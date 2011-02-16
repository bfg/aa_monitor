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
		1,
		'Try to establish TLS secured session after successful connect to IMAP server?.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'imap_mailbox',
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
	return CHECK_ERR unless ($self->imapSelectMbox($sock, $self->{imap_mailbox}));
	$self->bufApp("Successfully opened mailbox $self->{imap_mailbox}.");

	# disconnect
	$self->imapDisconnect($sock);

	return $self->success();
}

=head2 imapConnect

 my $sock = $self->imapConnect(
 	imap_host => 'host.example.org',
 	imap_port => 143,
 	imap_tls => 1,
 	imap_ssl => 0,
 	imap_user => 'user',
 	imap_pass => 'passwd',
 );

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

	unless (defined $user && length $user && defined $pass) {
		$self->error("No username/password provided.");
		return undef;
	}

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
	} else {
		$self->error("Connection to IMAP server succeeded, but there were no provided credentials.");
		return undef;
	}

	return $sock;
}

=head2 imapCmd

 my $r = $self->imapCmd($sock, $imap_cmd)

Performs single IMAP command and waits for results. Returns 1 on success, otherwise 0.

=cut
sub imapCmd {
	my ($self, $sock, $cmd) = @_;
	unless (defined $sock && blessed($sock) && $sock->isa('IO::Socket') && $sock->connected()) {
		$self->error("Invalid provided socket.");
		return 0;
	}

	my $i = $self->imapSockMeta($sock);
	return 0 unless ($i);

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

	return $result;
}

=head2 imapSelectMbox

 my $r = $self->imapSelectMbox($sock, 'INBOX');

Selects specified mailbox on established socket. Returns 1 on success, otherwise 0.

=cut
sub imapSelectMbox {
	my ($self, $sock, $mbox) = @_;
	unless ($self->imapCmd($sock, "SELECT " . $mbox)) {
		$self->error("Unable to select folder: " . $self->error());
		return 0;
	}
	
	my $i = $self->imapSockMeta($sock);
	return 0 unless ($i);

	my $num = 0;
	
	# ok, check for messages
	if ($i->{imap_ctrl} =~ m/\s+(\d+)\s+EXISTS/mi) {
		$i->{imap_nmsgs} = $1;
	}
	
	$self->bufApp(" Mailbox '$mbox' contains " . $i->{imap_nmsgs} . " messages.") if ($self->{debug});

	return 1;
}

=head2 imapDisconnect

 $self->imapDisconnect($sock);

Ends IMAP session and closes socket. Always returns 1.

=cut
sub imapDisconnect {
	my ($self, $sock) = @_;
	# perform logout
	$self->imapCmd($sock, "LOGOUT");

	# remove socket catalog...
	my $id = refaddr($sock);
	delete($self->{_imap}->{$id});

	# close socket
	close($sock);
	undef $sock;

	return 1;
}

=sub head2 imapSockMeta

 my $m = $self->imapSockMeta($sock);

Returns socket imap metadata on success, otherwise undef.

=cut
sub imapSockMeta {
	my ($self, $sock) = @_;
	unless (defined $sock && blessed($sock) && $sock->isa('IO::Socket')) {
		$self->error("Invalid socket.");
		return undef;
	}
	my $id = refaddr($sock);
	unless (exists $self->{_imap}->{$id}) {
		$self->error("Untracked socket.");
		return undef;
	}
	return $self->{_imap}->{$id};
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