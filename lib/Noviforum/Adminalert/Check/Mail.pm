package Noviforum::Adminalert::Check::Mail;

use strict;
use warnings;

use IO::File;
use Net::SMTP;
use IO::Socket;
use Sys::Hostname;
use POSIX qw(strftime);

use vars qw(@ISA);
@ISA = qw(Noviforum::Adminalert::Check);

our $VERSION = 0.13;
die "This module is completely broken: TODO: split it to SMTP, IMAP and POP3";

my $DOMAIN = _get_domain();
my $HOSTNAME = hostname();
my $FQDN = $HOSTNAME . "." . $DOMAIN;

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	eval { require IO::Socket::SSL; };
	$self->{_has_io_ssl} = (($@) ? 0 : 1);
	
	$self->setDescription(
		"Performs SMTP/IMAP/POP3 server checks."
	);
	
	# SMTP settings
	$self->{smtp_check} = 0;
	$self->{smtp_host} = "localhost";
	$self->{smtp_helo} = hostname() . "." . _get_domain();
	$self->{smtp_from} = 'admalrt.test@interseek.si';
	$self->{smtp_to} = "";
	$self->{smtp_success_delivery_sleep} = 2;

	# IMAP settings
	$self->{imap_check} = 0;
	$self->{imap_use_ssl} = 0;
	$self->{imap_host} = "localhost";
	$self->{imap_port} = 143;
	$self->{imap_user} = "user";
	$self->{imap_pass} = "";
	$self->{imap_check_smtp_delivery} = 0;
	$self->{imap_remove_sent_message} = 1;
	
	# TLS/SSL settings
	$self->{tls} = 0;
	$self->{tls_version} = "tlsv1";
	$self->{tls_ciphers} = "HIGH";
	$self->{tls_cert_file} = "";
	$self->{tls_key_file} =  "";
	$self->{tls_ca_file} = "";
	$self->{tls_ca_path} = "";
	$self->{tls_verify} = 0x00;

	$self->{imap_remove_all_messages} = 0;
	
	# POP3 settingsRemoving
	$self->{pop3_check} = 0;

	$self->{delivery_time} = 2;
	$self->{socket_timeout} = 1;
	$self->{debug} = 0;
}

sub check {
	my ($self) = @_;
	$self->{imap_remove_sent_message} = 0 if ($self->{imap_remove_all_messages});
	return ($self->_smtpCheck() && $self->_imapCheck() && $self->_pop3Check());
}


##################################################
#               SMTP METHODS                     #
##################################################

sub _smtpCheck {
	my ($self) = @_;
	unless ($self->{smtp_check}) {
		$self->bufApp("SMTP check is disabled, returning success.");
		return 1;
	}
	
	$self->bufApp("SMTP check starting.");

	$self->{_msgid} = "";
	my $smtp = Net::SMTP->new(
		$self->{smtp_host},
		timeout => $self->{socket_timeout},
		Hello => $self->{smtp_helo},
		Debug => $self->{debug},
	);
	
	unless (defined $smtp) {
		$self->{error} = "Unable to connect to SMTP server '" . $self->{smtp_host} . "': $!";
		return 0;
	}
	
	unless ($smtp->ok()) {
		$self->{error} = "SMTP server returned negative response: " . $smtp->message();
		return 0;
	}
	
	# mail from:
	unless ($smtp->mail($self->{smtp_from})) {
		$self->{error} = "SMTP server dislikes sender address '" . $self->{smtp_from} . "': " . $smtp->message();
		return 0;
	}
	
	# rcpt to:
	unless ($smtp->recipient($self->{smtp_to})) {
		$self->{error} = "SMTP server dislikes recipient address '" . $self->{smtp_to} . "': " . $smtp->message();
		return 0;
	}
	
	my $msg = $self->_smtpGetMessageData();
	
	unless ($smtp->data($msg)) {
		$self->{error} = "SMTP server is not willing to accept DATA command: " . $smtp->message();
		return 0;
	}
	unless ($smtp->dataend()) {
		$self->{error} = "SMTP server is not willing to accept message: " . $smtp->message();
		return 0;
	}
	
	$smtp->quit();
	$smtp = undef;
	
	$self->bufApp("Email message was successfuly sent.") if ($self->{debug});
	sleep($self->{smtp_success_delivery_sleep});
	return 1;
}

sub _smtpGetMessageData {
	my ($self) = @_;
	my $id = time() . "." . rand() . "." . rand() . '@' . $FQDN;
	$self->{_msgid} = $id;
	my $msg = "Message-Id: <$id>\n";
	$msg .= "Date: " . strftime("%a, %d %b %Y %H:%M:%S %z (%Z)", localtime(time())) . "\n";
	$msg .= "From: AdminAlert Mailing list monitor <" . $self->{smtp_from} . ">\n";
	$msg .= "To: Mailing list test system <" . $self->{smtp_to} . ">\n";
	$msg .= "Subject: AdminAlert Ping module test message\n";
	$msg .= "\n";
	$msg .= "This is a test message: " . rand() . "." . rand();

	return $msg;
}

##################################################
#               IMAP METHODS                     #
##################################################

sub _imapCheck {
	my ($self) = @_;
	unless ($self->{imap_check}) {
		$self->bufApp("IMAP check is disabled, returning success.");
		return 1;
	}

	$self->bufApp("IMAP check starting.");

	# connect
	return 0 unless ($self->_imapConnect());
	
	# authenticate
	return 0 unless ($self->_imapAuth());
	
	# select inbox
	return 0 unless ($self->_imapSelectMbox("INBOX"));

	# check messages
	return 0 unless ($self->_imapCheckMessages());

	# disconnect
	$self->_imapDisconnect();

	return 1;
}

sub _imapAuth {
	my ($self) = @_;
	return $self->_imapCommand("LOGIN " . $self->{imap_user} . " " . $self->{imap_pass});
}

sub _imapSelectMbox {
	my ($self, $mbox) = @_;
	return 0 unless ($self->_imapCommand("SELECT " . $mbox));
	
	my $num = 0;
	
	# ok, check for messages
	if ($self->{_imap_ctrl} =~ m/\s+(\d+)\s+EXISTS/mi) {
		$self->{_imap_nmsgs} = $1;
	}
	
	$self->bufApp("  Mailbox '$mbox' contains " . $self->{_imap_nmsgs} . " messages.") if ($self->{debug});

	return 1;
}

sub _imapCheckMessages {
	my ($self) = @_;
	my $msg_no = -1;

	if ($self->{imap_check_smtp_delivery}) {
		unless ($self->{smtp_check}) {
			$self->{error} = "Property smtp_check must be set to value '1' in order to enable property imap_check_smtp_delivery.";
			return 0;
		}
		unless ($self->{_imap_nmsgs}) {
			$self->{error} = "No messages were delivered to mailbox.";
			return 0;
		}
		
		# fetch all messages, try to find message with message id we've sent...
		my $i = 1;
		my $res = 0;
		while ($i <= $self->{_imap_nmsgs}) {
			return 0 unless ($self->_imapCommand("FETCH $i BODY[HEADER]"));
			
			my $id = $self->{_msgid};
			if ($self->{_imap_body} =~ m/^Message-Id:\s+<$id>/m) {
				$res = 1;
				$self->bufApp("    Found test message sent via SMTP with message id '$id'. IMAP mailbox index number $i.");
				$msg_no = $i;
				last;
			}
			$i++;
		}

		unless ($res) {
			$self->{error} = "Mailbox doesn't contain message that was sent by SMTP.";
			return 0;
		}
	}

	# remove test message from inbox?
	if ($self->{imap_remove_sent_message} && $self->{_imap_nmsgs}) {
		$self->bufApp("    Removing test message sent from mailbox.");# if ($self->{debug});

		# mark found message as deleted
		if ($msg_no > 0) {
			return 0 unless ($self->_imapCommand("STORE $msg_no:$msg_no" . ' +FLAGS (\Deleted)'));
		}
	}
	# remove all messages from inbox?
	if ($self->{imap_remove_all_messages} && $self->{_imap_nmsgs}) {
		$self->bufApp("    Removing all messages from mailbox.");# if ($self->{debug});

		# mark all messages as deleted
		return 0 unless ($self->_imapCommand("STORE 1:" . $self->{_imap_nmsgs} . ' +FLAGS (\Deleted)'));
	}

	# expunge mailbox
	unless ($self->_imapCommand("EXPUNGE")) {
		$self->bufApp("WARNING: Unable to expunge mailbox: " . $self->{error});
	}
	
	return 1;
}

sub _imapConnect {
	my ($self) = @_;
	$self->{_imap} = undef;
	if ($self->{tls} && ! $self->{_has_io_ssl}) {
		$self->{error} = "TLS/SSL secured connection was requested, but module IO::Socket::SSL is not available.";
		return 0;
	}

	# SSL?
	my $ssl = 0;
	if (lc(substr($self->{tls_version}, 0, 3)) eq 'ssl') {
		$ssl = 1;
		$self->{_imap} = IO::Socket::SSL->new(
			PeerHost => $self->{imap_host},
			PeerPort => $self->{imap_port},
			Proto => 'tcp',
			Reuse => 1,
			Timeout => $self->{socket_timeout},
			$self->_getTlsHash()
		);
	} else {
		$self->{_imap} = IO::Socket::INET->new(
			PeerHost => $self->{imap_host},
			PeerPort => $self->{imap_port},
			Proto => 'tcp',
			Reuse => 1,
			Timeout => $self->{socket_timeout}
		);
	}

	unless (defined $self->{_imap}) {
		$self->{error} = "Unable to connect to IMAP server '" . $self->{imap_host} . "': $!";
		return 0;
	}

	$self->{_imap_idx} = 0;
	$self->{_imap_ctrl} = "";
	$self->{_imap_status} = "";
	$self->{_imap_body} = "";
	$self->{_imap_nmsgs} = 0;

	return 0 unless ($self->_imapCommand("CAPABILITY"));
	
	# if client requested TLS, we need to upgrade socket
	if ($self->{tls} && ! $ssl) {
		# send starttls command
		return 0 unless ($self->_imapCommand("STARTTLS"));
		
		# start secured session
		my $r = IO::Socket::SSL->start_SSL(
			$self->{_imap},
			$self->_getTlsHash()
		);
		
		unless ($r) {
			$self->{error} = "Unable to start TLS secured session: " . $self->{_imap}->errstr();
			$self->{_imap} = undef;
			return 0;
		}

		$self->bufApp("    Successfully started TLS secured session.");
	}
	
	return 1;
}

sub _imapCommand {
	my ($self, $cmd) = @_;
	$self->{_imap_idx}++;
	my $idx = $self->{_imap_idx};
	$cmd = $idx . " " . $cmd;
	$self->{_imap_body} = "";

	# are we connected?
	unless (defined $self->{_imap} && $self->{_imap}->connected()) {
		$self->{error} = "IMAP socket is not in connected state.";
		$self->{_imap} = undef;
		return 0;
	}

	# send command
	if ($self->{debug}) {
		$self->bufApp();
		$self->bufApp("    IMAP command: $cmd") if ($self->{debug});
	}
	my $x = print {$self->{_imap}} $cmd, "\r\n";
	unless ($x) {
		$self->{error} = "Error sending IMAP command: $!";
		return undef;
	}

	# read output
	my $done = 0;
	my $result = 0;
	my $msg_ctrl = "";
	my $msg_status = "";
	my $msg = "";
	my $no_read = 0;
	my $line = undef;
	while (! $done) {
		unless ($self->{_imap}->connected()) {
			$self->{error} = "Error reading IMAP command response: Socket is no longer connected.";
			$done = 1;
			last;
		}
		$line = $self->{_imap}->getline();
		unless (defined $line) {
			$done = 1;
			last;
		}
		$no_read++;

		if ($self->{debug}) {
			my $str = $line;
			$str =~ s/\s+$//g;
			$self->bufApp("    IMAP response: $str");
		}
		# do we have status line?
		if ($line =~ m/^$idx\s+(OK|NO|BAD)\s+(.+)/) {
			$result = (lc($1) eq 'ok') ? 1 : 0;
			$msg_status = $2;
			unless ($result) {
				$self->{error} = "Error running IMAP command '$cmd': " . $msg_status;
			}
			$done = 1;
		}
		# do we have control line?
		if ($line =~ m/^\*\s+(.+)/) {
			$msg_ctrl .= $1;
		}
		# we have regular line
		else {
			$msg .= $line
		}
	}
	
	if ($self->{debug}) {
		$self->bufApp("    IMAP command ended " . (($result) ? "SUCCESSFULLY" : "UNSUCCESSFULLY"));
	}

	if ($no_read < 1) {
		$self->{error} = "IMAP server did not reply to IMAP command.";
		return 0;
	}
	
	$self->{_imap_ctrl} = $msg_ctrl;
	$self->{_imap_status} = $msg_status;
	$self->{_imap_body} = $msg;
	
	if (! $result && ! length($self->{error})) {
		$self->bufApp();
		$self->bufApp("# Whole read message:");
		$self->bufApp($msg) if (defined $msg);
		$self->bufApp();
		$self->bufApp("# Last read line:");
		$self->bufApp($line) if (defined $line);
		$self->{error} = "Undefined error message. This should never happen.";
	}

	return $result;
}

sub _imapDisconnect {
	my ($self) = @_;
	$self->_imapCommand("LOGOUT");
	$self->{_imap} = undef;
	return 1;
}

##################################################
#               POP3 METHODS                     #
##################################################

sub _pop3Check {
	my ($self) = @_;
	$self->bufApp("POP3 check is not yet implemented.");
	return 1;
}

##################################################
#            GENERAL PURPOSE METHODS             #
##################################################
sub _getTlsHash {
	my ($self) = @_;

	my %h = (
		SSL_version => $self->{tls_version},
		SSL_chiper_list =>  $self->{tls_ciphers},
		SSL_use_cert => (defined $self->{tls_cert_file} && length($self->{tls_cert_file}) > 0) ? 1 : 0,
		SSL_cert_file => $self->{tls_cert_file},
		SSL_key_file => $self->{tls_key_file},
		SSL_ca_file => $self->{tls_ca_file},
		SSL_ca_path => $self->{tls_ca_path},
		SSL_verify_mode => $self->{tls_verify},
	);

	return %h;
}

sub _get_domain {
	my $res = "";
	my $file = "/etc/resolv.conf";
	my $fd = IO::File->new($file, 'r');
	return "" unless defined ($fd);
	my $i = 0;
	while ($i < 30 && defined(my $line = <$fd>)) {
		$i++;
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		if ($line =~ m/^(?:search|domain)\s+([^\s]+)/) {
			$res = $1;
			last;
		}
	}
	$fd = undef;

	return $res;
}

1;
