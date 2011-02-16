package P9::AA::Check::IMAP;

use strict;
use warnings;

use POSIX qw(strftime);
use Scalar::Util qw(refaddr blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

our $VERSION = 0.10;

=head1 NAME

IMAP server checking module and basic imap methods.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::_Socket>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"IMAP server check."
	);

	# define additional configuration variables...
	$self->cfgParamAdd(
		'imap_host',
		'localhost',
		'IMAP server hostname or ip-address.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'imap_port',
		143,
		'IMAP server listening port.',
		$self->validate_int(1, 65535),
	);
	$self->cfgParamAdd(
		'imap_user',
		undef,
		'IMAP server auth username.',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'imap_pass',
		undef,
		'IMAP server auth password.',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'imap_ssl',
		0,
		'SSL connection to IMAP server?.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'imap_tls',
		0,
		'Try to establish TLS secured session after successful connect to IMAP server?.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'imap_folder',
		'INBOX',
		'Try to select specified folder after successful connection.',
		$self->validate_str(1024),
	);

	# $self->cfgParamRemove('timeout_connect');
	
	# imap stuff
	$self->{_imap} = {};
	
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# CONNECT
	my $sock = $self->imapConnect();
	return CHECK_ERR unless ($sock);
	$self->bufApp("Successfully established connection with IMAP server.");
	
	# select inbox
	return CHECK_ERR unless ($self->imapSelectMbox($sock, $self->{imap_folder}));

	# disconnect
	$self->imapDisconnect($sock);

	return $self->success();
}

=head2 imapConnect

Connects to IMAP server, establish SSL/TLS, try to login. Returns socket
on success, otherwise undef.

All options of L<P9::AA::Check::_Socket/sockConnect> are supported.

=cut
sub imapConnect {
	my ($self, %opt) = @_;

	return undef unless ($self->v6Sock($self->{ipv6}));
	my $o = $self->_getConnectOpt(%opt);
	
	my $user = delete($o->{imap_user});
	my $pass = delete($o->{imap_pass});

	my $host = delete($o->{imap_host});
	my $port = delete($o->{imap_port}) || 25;
	my $ssl = delete($o->{imap_ssl});
	my $tls = delete($o->{imap_tls});

	# can't use SSL and TLS at the same time.
	$ssl = 0 if ($ssl && $tls);

	my $method = ($ssl) ? 'sockSSLConnect' : 'sockConnect';
	local $@;
	my $sock = eval { $self->$method($host, PeerPort => $port, %{$o}) };
	if ($@) {
		$self->error("Exception: $@");
		return undef;
	}
	return undef unless (defined $sock);
	
	my $id = refaddr($sock);
	$self->{_imap}->{$id} = {
		imap_idx => 0,
		imap_ctrl => '',
		imap_status => '',
		imap_body => '',
		imap_nmsgs => 0,
	};

	return undef unless ($self->imapCmd($sock, "CAPABILITY"));

	# if client requested TLS, we need to upgrade socket
	if ($tls) {
		# send starttls command
		return undef unless ($self->imapCmd($sock, "STARTTLS"));
		
		# start secured session
		$sock = $self->sslify($sock);
		unless (defined $sock) {
			my $err = $self->error;
			$self->imapQuit($sock);
			$self->error($err);
			return undef;
		}
	}
	
	# try to login...
	if (defined $user && length $user && defined $pass) {
		unless ($self->imapCmd($sock, 'LOGIN ' . $user . ' ' . $pass)) {
			my $err = $self->error;
			$self->imapQuit($sock);
			$self->error($err);
			return undef;			
		}
		$self->bufApp("Successfully authenticated as $user.");
	}

	return $sock;
}

=head2 imapCmd

 my $r = $self->imapCmd($sock, $cmd)

Returns 1 on success, otherwise 0.

=cut
sub imapCmd {
	my ($self, $sock, $cmd) = @_;
	unless (defined $sock && blessed($sock) && $sock->isa('IO::Socket') && $sock->connected()) {
		$self->error("Invalid provided socket.");
		return 0;
	}

	my $id = refaddr($sock);
	my $i = $self->{_imap}->{$id};
	unless (defined $i) {
		$self->error("Untracked socket.");
		return 0;
	} 

	$i->{imap_idx}++;
	my $idx = $i->{imap_idx};
	$cmd = $idx . ' ' . $cmd;
	$i->{imap_body} = '';

	# send command
	if ($self->{debug}) {
		$self->bufApp();
		$self->bufApp("TX IMAP command: $cmd") if ($self->{debug});
	}
	my $x = print $sock $cmd, "\r\n";
	unless ($x) {
		$self->error("Error sending IMAP command: $!");
		return 0;
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
		unless ($sock->connected()) {
			$self->error("Error reading IMAP command response: Socket is no longer connected.");
			$done = 1;
			last;
		}
		$line = $sock->getline();
		unless (defined $line) {
			$done = 1;
			last;
		}
		$no_read++;

		if ($self->{debug}) {
			my $str = $line;
			$str =~ s/\s+$//g;
			$self->bufApp("RX IMAP response: $str");
		}
		# do we have status line?
		if ($line =~ m/^$idx\s+(OK|NO|BAD)\s+(.+)/) {
			$result = (lc($1) eq 'ok') ? 1 : 0;
			$msg_status = $2;
			unless ($result) {
				$self->error("Error running IMAP command '$cmd': " . $msg_status);
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
		$self->bufApp(" IMAP command ended " . (($result) ? "SUCCESSFULLY" : "UNSUCCESSFULLY"));
	}

	if ($no_read < 1) {
		$self->error("IMAP server did not reply to IMAP command.");
		return 0;
	}
	
	$i->{imap_ctrl} = $msg_ctrl;
	$i->{imap_status} = $msg_status;
	$i->{imap_body} = $msg;
	
#	if (! $result && ! length($self->{error})) {
#		$self->bufApp();
#		$self->bufApp("# Whole read message:");
#		$self->bufApp($msg) if (defined $msg);
#		$self->bufApp();
#		$self->bufApp("# Last read line:");
#		$self->bufApp($line) if (defined $line);
#		$self->{error} = "Undefined error message. This should never happen.";
#	}

	return $result;
}

=head2 imapSelectMbox

 my $r = $self->imapSelectMbox($sock, 'INBOX');

=cut
sub imapSelectMbox {
	my ($self, $sock, $mbox) = @_;
	return 0 unless ($self->imapCmd("SELECT " . $mbox));
	
	my $num = 0;
	my $id = refadd($sock);
	my $i = $self->{_imap}->{$id};
	
	# ok, check for messages
	if ($i->{imap_ctrl} =~ m/\s+(\d+)\s+EXISTS/mi) {
		$i->{imap_nmsgs} = $1;
	}
	
	$self->bufApp("  Mailbox '$mbox' contains " . $i->{imap_nmsgs} . " messages.") if ($self->{debug});

	return 1;
}

=head2 imapDisconnect

 $self->imapDisconnect($sock);

Ends IMAP session and closes socket. Always returns 0.

=cut
sub imapDisconnect {
	my ($self, $sock) = @_;
	$self->imapCommand($sock, "LOGOUT");
	close($sock);
	return 1;
}

sub _getConnectOpt {
	my ($self, %opt) = @_;
	my $r = {};
	
	foreach (qw(imap_host imap_port imap_user imap_pass imap_helo imap_tls imap_ssl)) {
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