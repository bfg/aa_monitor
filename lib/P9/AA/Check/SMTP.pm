package P9::AA::Check::SMTP;

use strict;
use warnings;

use Sys::Hostname;
use POSIX qw(strftime);
use Scalar::Util qw(blessed);
use MIME::Base64 qw(encode_base64);

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

our $VERSION = 0.10;

=head1 NAME

SMTP server checking module and basic smtp methods.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::_Socket>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"SMTP server check."
	);

	# define additional configuration variables...
	$self->cfgParamAdd(
		'smtp_host',
		'localhost',
		'SMTP server hostname or ip-address.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'smtp_port',
		25,
		'SMTP server listening port.',
		$self->validate_int(1, 65535),
	);
	$self->cfgParamAdd(
		'smtp_user',
		undef,
		'SMTP server auth username.',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'smtp_pass',
		undef,
		'SMTP server auth password.',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'smtp_helo',
		hostname(),
		'HELO greeting.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'smtp_ssl',
		0,
		'SSL connection to SMTP server?.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'smtp_tls',
		0,
		'Try to establish TLS secured session after successful connect to SMTP server?.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'smtp_from',
		undef,
		'Send test message with specified from address.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'smtp_to',
		undef,
		'Send test message to specified comma separated list of recipient addresses.',
		$self->validate_str(1024),
	);

	# $self->cfgParamRemove('timeout_connect');
	
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;	
	my $sock = $self->smtpConnect();
	return CHECK_ERR unless ($sock);
	$self->bufApp("Successfully established connection with SMTP server.");

	if (defined $self->{smtp_from} && length $self->{smtp_from}) {
		my @recips = split(/\s*[;,]+\s*/, $self->{smtp_to});
		unless (@recips) {
			return $self->error("No recipients specified.");
		}
		
		# try to send test message
		unless ($self->_sendTestMsg($sock, $self->{smtp_from}, @recips)) {
			my $err = $self->error();
			$self->smtpQuit($sock);
			return $self->error($err);
		}
		$self->bufApp("Successfully sent test message.");
	}
	
	$self->smtpQuit($sock);
	return $self->success();
}

# describes check, optional.
sub toString {
	my ($self) = @_;
	no warnings;
	my $str = '';
	$str .= $self->{smtp_user} . '@' if (defined $self->{smtp_user});
	$str .= $self->{smtp_host} . '/' . $self->{smtp_port};	
	if ($self->{smtp_tls}) {
		$str .= '/TLS'
	}
	elsif ($self->{smtp_ssl}) {
		$str .= '/SSL'		
	}

	return $str
}

=head2 smtpConnect

 my $smtp = $self->smtpConnect(
 	smtp_host => $host,
 	smtp_port => 25,
 	smtp_user => 'dummy',
 	smtp_pass => 's3cret',
 	smtp_helo => 'client.example.com',
 	smtp_ssl => 0,
 	smtp_tls => 1,
 	%{opt},
 );

Tries to connect to specified smtp host. If connection succeeds EHLO command
is sent, TLS/SSL connection will be tried before SMTP auth. Returns initialized
socket object on success, otherwise undef.

NOTE: This method supports all options supporder by L<P9::AA::Check::_Socket/sockConnect>.

=cut
sub smtpConnect {
	my ($self, %opt) = @_;
	return undef unless ($self->v6Sock($self->{ipv6}));
	my $o = $self->_getConnectOpt(%opt);
	
	my $user = delete($o->{smtp_user});
	my $pass = delete($o->{smtp_pass});

	my $host = delete($o->{smtp_host});
	my $port = delete($o->{smtp_port}) || 25;
	my $ssl = delete($o->{smtp_ssl});
	my $tls = delete($o->{smtp_tls});

	# can't use SSL and TLS at the same time.
	$ssl = 0 if ($ssl && $tls);

	my $helo = delete($o->{smtp_helo}) || hostname();
	
	my $method = ($ssl) ? 'sockSSLConnect' : 'sockConnect';
	local $@;
	my $sock = eval { $self->$method($host, PeerPort => $port, %{$o}) };
	if ($@) {
		$self->error("Exception: $@");
		return undef;
	}
	return undef unless (defined $sock);
	
	$sock->autoflush(1);
	
	# read initial response
	my ($c, $buf) = $self->_readResponse($sock);
	unless (defined $c && ($c >= 200 && $c <= 300)) {
		no warnings;
		$self->error("Invalid SMTP server greeting: '$buf'");
		return undef;
	}
	
	# send helo
	return undef unless ($self->smtpCmd($sock, "EHLO " . $helo));

	# SMTP TLS?
	if ($tls) {
		return undef unless ($self->smtpCmd($sock, "STARTTLS"));
		$sock = $self->sslify($sock);
		unless (defined $sock) {
			my $err = $self->error;
			$self->smtpQuit($sock);
			$self->error($err);
			return undef;
		}
	}
	
	# SMTP AUTH?
	if (defined $user && length $user && defined $pass) {
		unless ($self->smtpCmd($sock, "AUTH PLAIN " . encode_base64("\0" . $user . "\0" . $pass))) {
			my $err = $self->error;
			$self->smtpQuit($sock);
			$self->error($err);
			return undef;
		}
		$self->bufApp("Successfully authenticated as $user.");
	}

	return $sock;
}

=head2 smtpSend

 my $r = $self->smtpSend(
 	$sock,
 	$from,
 	\ @recipients,
 	$message
 );

Tries to send message over already esablished socket connection. Message $message
argument can be string or L<MIME::Lite> object.

Returns 1 on success, otherwise 0.

=cut
sub smtpSend {
	my ($self, $sock, $from, $to, $msg) = @_;
	unless (defined $from && length $from) {
		$self->error("No sender.");
		return 0;
	}
	unless (defined $to && ref($to) eq 'ARRAY' && @{$to}) {
		$self->error("No recipients.");
		return 0;
	}
	if (! defined $msg) {
		$self->error("Undefined message.");
		return 0;
	}
	unless (ref($msg) eq '' || (blessed($msg) && $msg->isa('MIME::Lite'))) {
		$self->error("Message must be string or MIME::Lite object.");
		return 0;
	}
	
	# let's do it...

	# mail from:
	return 0 unless ($self->smtpCmd($sock, 'MAIL FROM: <' . $from . '>'));
	
	# rcpt to:
	foreach my $r (@{$to}) {
		return 0 unless ($self->smtpCmd($sock, 'RCPT TO: <' . $r . '>'));
	}
	
	# data:
	return 0 unless ($self->smtpCmd($sock, 'DATA'));
	my $raw = (blessed $msg) ? $msg->as_string() : $msg;
	return 0 unless ($self->smtpCmd($sock, $raw . "\r\n."));
	
	# send it!
	return 1;
}

=head2 smtpCmd

 $self->smtpCmd($sock, "HELP")

Sends SMTP command. Returns 1 on success, otherwise 0.

=cut
sub smtpCmd {
	my $self = shift;
	my $sock = shift;
	unless (blessed($sock) && $sock->isa('IO::Socket') && $sock->connected()) {
		$self->error("Socket is not connected.");
		return 0;
	}
	my $cmd = join('', @_);
	$cmd =~ s/[\r\n]+$//g;
	unless (length $cmd) {
		return undef;
	}
	$self->log_debug("Sending SMTP command: $cmd");
	$cmd .= "\r\n";
	
	# send command...
	print $sock $cmd;
	
	my ($code, $buf) = $self->_readResponse($sock);
	{ no warnings; $self->log_debug("Response code: '$code', buf: '$buf'") }
	unless (defined $code && ($code >= 200 && $code <= 400)) {
		no warnings;
		$self->error("Bad response [$code]: $buf");
		$self->log_debug("Bad response [$code]: $buf");
		return 0;
	}
	
	return 1;
}

=head2 smtpQuit

 $self->smtpQuit($sock)

Quits SMTP session and closes socket. Always returns 1.

=cut
sub smtpQuit {
	my ($self, $sock) = @_;
	$self->smtpCmd($sock, 'QUIT');
	close($sock);
	return 1;
}

sub _date {
	my ($self, $t) = @_;
	$t = time() unless ($t);
	# Date: Wed, 16 Feb 2011 08:01:46 +0100
	return strftime(
		"%a, %d %b %Y %H:%M:%S %z",
		localtime($t)
	);
}

sub _sendTestMsg {
	my $self = shift;
	my $sock = shift;
	my ($from, @to) = @_;
	
	my $msg_id = int(rand(999999)) . int(rand(999999)) . '@' . hostname();
	my $id = sprintf("%x", rand(0xffffffff)); 
	
	my $msg = "From: <$from>\r\n";
	$msg .= "To: undisclosed-recipients <>\r\n";
	$msg .= "Message-Id: <$msg_id>\r\n";
	$msg .= "Date: " . $self->_date() . "\r\n";
	$msg .= "Subject: Test message [$id]\r\n";
	$msg .= "\r\n";
	$msg .= "This is " . ref($self) . " test message.\r\n";
	$msg .= "\r\n";
	$msg .= "ID: $id\r\n";
	$msg .= "\r\n";
	
	return undef unless ($self->smtpSend($sock, $from, \ @to, $msg));
	return $msg_id;
}

sub _readResponse {
	my ($self, $sock) = @_;
	unless (defined $sock && $sock->connected()) {
		$self->error("Undefined or not connected socket.");
		return undef;
	}

	my $code = undef;
	my $buf = '';
	
	local $SIG{ALRM} = sub {
		my $msg = "Timeout reading SMTP server response.";
		$self->error($msg);
		die $msg . "\n";
	};
	alarm(5);

	my $in_msg = 0;
	while (1) {
		my $line = $sock->getline();
		last unless (defined $line);
		$line =~ s/\s+$//g;
		if ($line =~ m/^(\d{3})\s+(.+)/) {
			$buf .= $2 . "\n";
			$code = $1;
			last;
		}
		if ($line =~ m/^(\d{3})-(.+)/) {
			$buf .= $2 . "\n";
		}
	}
	alarm(0);
	return ($code, $buf);
}

sub _getConnectOpt {
	my ($self, %opt) = @_;
	my $r = {};
	
	foreach (qw(smtp_host smtp_port smtp_user smtp_pass smtp_helo smtp_tls smtp_ssl)) {
		$r->{$_} = $self->{$_};
		$r->{$_} = $opt{$_} if (exists($opt{$_}));
	}
	
	foreach (keys %{opt}) {
		next if (exists $r->{$_});
		$r->{$_} = $opt{$_};
	}
	
	return $r;
}

=head1 SEE ALSO

L<P9::AA::Check::_Socket>, 
L<P9::AA::Check>, 

=head1 AUTHOR

Brane F. Gracnar

=cut
1;