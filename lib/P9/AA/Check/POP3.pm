package P9::AA::Check::POP3;

use strict;
use warnings;

use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

our $VERSION = 0.10;

=head1 NAME

POP3 server checking module and basic pop3 methods.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::_Socket>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"POP3 server check."
	);

	# define additional configuration variables...
	$self->cfgParamAdd(
		'pop3_host',
		'localhost',
		'POP3 server hostname or ip-address.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'pop3_port',
		110,
		'POP3 server listening port.',
		$self->validate_int(1, 65535),
	);
	$self->cfgParamAdd(
		'pop3_user',
		undef,
		'POP3 server auth username.',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'pop3_pass',
		undef,
		'POP3 server auth password.',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'pop3_ssl',
		0,
		'SSL connection to POP server?.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'pop3_tls',
		1,
		'Try to establish TLS secured session after successful connect to POP3 server?.',
		$self->validate_bool(),
	);

	# $self->cfgParamRemove('timeout_connect');
	
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# CONNECT
	my $sock = $self->pop3Connect();
	return CHECK_ERR unless ($sock);
	$self->bufApp("Successfully established connection with POP3 server.");
	
	# get message list
	my $msgs = $self->pop3MsgList($sock);
	return CHECK_ERR unless ($msgs);
	$self->bufApp("Mailbox contains " . (scalar @{$msgs}) . " messages.");

	# disconnect
	$self->pop3Quit($sock);

	return $self->success();
}

# describes check, optional.
sub toString {
	my ($self) = @_;
	no warnings;
	my $str = '';
	$str .= $self->{pop3_user} . '@' if (defined $self->{pop3_user});
	$str .= $self->{pop3_host} . '/' . $self->{pop3_port};
	if ($self->{pop3_tls}) {
		$str .= '/TLS'
	}
	elsif ($self->{pop3_ssl}) {
		$str .= '/SSL'		
	}
	return $str
}

=head2 pop3Connect

 my $sock = $self->imapConnect(
 	pop3_host => 'host.example.org',
 	pop3_port => 143,
 	pop3_tls => 1,
 	pop3_ssl => 0,
 	pop3_user => 'user',
 	pop3_pass => 'passwd',
 );

Connects to POP3 server, establish SSL/TLS, try to login. Returns socket
on success, otherwise undef.

All options of L<P9::AA::Check::_Socket/sockConnect> are supported.

=cut
sub pop3Connect {
	my ($self, %opt) = @_;

	return undef unless ($self->v6Sock($self->{ipv6}));
	my $o = $self->_getConnectOpt(%opt);
	
	my $user = delete($o->{pop3_user});
	my $pass = delete($o->{pop3_pass});

	my $host = delete($o->{pop3_host});
	my $port = delete($o->{pop3_port}) || 25;
	my $ssl = delete($o->{pop3_ssl});
	my $tls = delete($o->{pop3_tls});

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
	
	$sock->autoflush(1);
	
	# read initial response
	my ($c, $buf) = $self->_readResponse($sock);
	unless ($c) {
		no warnings;
		$self->error("Invalid POP3 server greeting: '$buf'");
		return undef;
	}
	
	# if client requested TLS, we need to upgrade socket
	if ($tls) {
		# send starttls command
		return undef unless ($self->pop3Cmd($sock, 'STLS'));
		
		# start secured session
		$sock = $self->sslify($sock);
		unless (defined $sock) {
#			my $err = $self->error;
#			$self->error($err);
			return undef;
		}
	}
	
	# try to login...
	my $err = 'Unable to login to POP3 server: ';
	unless ($self->pop3Cmd($sock, 'USER ' . $user)) {
		$self->error($err . $self->error());
		return undef;
	}
	unless ($self->pop3Cmd($sock, 'PASS ' . $pass)) {
		$self->error($err . $self->error());
		return undef;
	}
	$self->bufApp("Successfully authenticated as $user.");

	return $sock;
}

=head2 pop3Cmd

 my $r = $self->pop3Cmd($sock, $cmd)

Sends specified POP3 command to socket connection and waits for response.

Returns 1 on success, otherwise 0.

=cut
sub pop3Cmd {
	my $self = shift;
	my $sock = shift;
	unless (blessed($sock) && $sock->isa('IO::Socket') && $sock->connected()) {
		$self->error("Unable to run command @_: Invalid provided socket.");
		return wantarray ? (0, undef) : undef;
	}

	my $cmd = join('', @_);
	$cmd =~ s/[\r\n]+//g;
	#$self->bufApp("TX: $cmd") if ($self->{debug});
	
	# send command
	print $sock $cmd, "\r\n";
	
	# read response
	my ($s, $buf) = $self->_readResponse($sock);
	unless ($s) {
		no warnings;
		$self->error("Invalid server response: '$buf'");
	}

	return wantarray ? ($s, $buf) : $s;
}

=head2 pop3MsgList

 my $list = $self->pop3MsgList($sock)

Retrieves arrayref of arrayrefs [ id, size ] message list on success,
otherwise undef.

=cut
sub pop3MsgList {
	my ($self, $sock) = @_;
	my ($c, $buf) = $self->pop3Cmd($sock, 'LIST');
	unless ($c) {
		$self->error("Unable to list mailbox: " . $self->error());
		return undef;
	}
	
	my $r = [];
	foreach my $line (split(/[\r\n]+/, $buf)) {
		next unless (defined $line && length $line);
		my ($id, $size) = split(/\s+/, $line, 2);
		next unless (defined $id && defined $size);
		push(@{$r}, [ $id, $size]);
	}
	
	return $r;
}

=head2 pop3MsgRetr

 my $msg = $self->pop3MsgRetr($id);

Retrieves message with specified id as string on success,
otherwise undef.

=cut
sub pop3MsgRetr {
	my ($self, $sock, $id) = @_;
	my ($c, $buf) = $self->pop3Cmd($sock, 'RETR ' . $id);
	unless ($c) {
		$self->error("Unable to retrieve message: " . $self->error());
		return undef;
	}
	return $buf;
}

=head2 pop3Quit

 $self->pop3Quit($sock);

Ends POP3 session and closes socket. Always returns 1.

=cut
sub pop3Quit {
	my ($self, $sock) = @_;
	$self->pop3Cmd($sock, 'QUIT');
	$self->error('');
	close($sock);
	undef $sock;
	return 1;
}

sub _readResponse {
	my ($self, $sock) = @_;
	unless (blessed($sock) && $sock->connected()) {
		$self->error("Invalid, undefined or not connected socket.");
		return undef;
	}
	
	local $SIG{ALRM} = sub {
		my $msg = "Timeout reading POP3 server response.";
		$self->error($msg);
		die $msg . "\n";
	};
	alarm(5);

	# parse input
	my $status = 0;
	my $buf = '';
	while (1) {
		my $line = $sock->getline();
		last unless (defined $line);
		$line =~ s/\s+$//g;
		#print "parsing: $line\n";
		
		# normal command?
		if ($line =~ m/^(\-|\+)([\w]+)\s*(.*)/) {
			$status = ($1 eq '+') ? 1 : 0;
			no warnings;
			$buf = $2 . ' ' . $3;
			last unless ($line =~ m/:$/);
		}
		# end of list?
		if ($line eq '.') {
			last;
		}
		# normal stuff...
		else {
			$buf .= $line . "\n";
		}
	}
	alarm(0);

	return wantarray ? ($status, $buf) : $status;
}

sub _getConnectOpt {
	my ($self, %opt) = @_;
	my $r = {};
	
	foreach (qw(pop3_host pop3_port pop3_user pop3_pass pop3_helo pop3_tls pop3_ssl)) {
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