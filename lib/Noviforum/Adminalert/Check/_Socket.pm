package Noviforum::Adminalert::Check::_Socket;

use strict;
use warnings;

use Scalar::Util qw(blessed);

use constant CLASS_UNIX => 'IO::Socket::UNIX';
use constant CLASS_INET => 'IO::Socket::INET';
use constant CLASS_INET4 => 'IO::Socket::INET4';
use constant CLASS_INET6 => 'IO::Socket::INET6';
use constant CLASS_SSL => 'IO::Socket::SSL';
use constant CLASS_GLUE => 'Net::INET6Glue';

use base 'Noviforum::Adminalert::Check';

our $VERSION = 0.10;

my $_has_ipv6 = undef;
my $_has_ssl = undef;
my $_is_patched = 0;

# ipv6 behaviour
my $_ipv6 = {
	off => 1,
	any => 1,
	prefer => 1,
	force => 1,
};

=head1 NAME

Low-level TCP/UNIX domain socket support methods.

=head1 METHODS

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->cfgParamAdd(
		'ipv6',
		'prefer',
		'IPv6 behaviour. Possible values: off (use IPv4), force (force IPv6 usage), prefer (try IPv6 first, then try IPv4), any (connect using IPv4 or IPv6).',
		$self->validate_str(
			10,
			'prefer',
			qw(off force any prefer)
		),
	);

	$self->cfgParamAdd(
		'timeout_connect',
		1,
		'Connect timeout in seconds.',
		$self->validate_int()
	);

	$self->cfgParamAdd(
		'debug_socket',
		0,
		'Display socket debugging messages.',
		$self->validate_bool()
	);

	return 1;
}

=head2 hasIPv6

Returns 1 if ipv6 support modules are available.

=cut
sub hasIPv6 {
	my ($self) = @_;
	unless (defined $_has_ipv6) {
		$_has_ipv6 = eval 'use ' . CLASS_INET6 . '; 1';
	}
	
	if (! $_has_ipv6) {
		$self->error("IPv6 support is not available; missing " . CLASS_INET6 . " module.");
	}

	return $_has_ipv6;
}

=head2 hasSSL

Returns 1 if SSL support modules are available.

=cut
sub hasSSL {
	my ($self) = @_;
	unless (defined $_has_ssl) {
		$_has_ssl = eval 'use ' . CLASS_SSL . '; 1';
	}
	
	if (! $_has_ssl) {
		$self->error("SSL support is not available; missing " . CLASS_SSL . " module.");
	}

	return $_has_ssl;
}

=head2 sockConnect

Prototype:

 my $conn = $self->sockConnect($host [, %opt]);

Connects to specified host or unix domain socket. IPv6 is handled transparently. Supported options for B<%opt>:

=over

=item B<PeerPort> (integer, default: undef)

Remote port number. 

=item B<ipv6> (string, default: configuration parameter B<ipv6> or "any"):

IPv6 connection method. Possible values: prefer, any, off, force

=back

See L<IO::Socket::INET>, L<IO::Socket::UNIX> for description of B<%opt>.

Returns socket on success, otherwise undef.

=cut
sub sockConnect {
	my ($self, $host, %opt) = @_;
	unless (defined $host && length($host)) {
		#$self->error("No host/address or unix socket path was specified.");
		$self->log_debug("No host/address or unix socket path was specified.");
		#return undef;
	}
		
	# ipv6 connection method
	my $v6 = delete($opt{ipv6});
	$v6 = $self->{ipv6} unless (defined $v6);
	$v6 = 'prefer' unless (defined $v6);
	$v6 = lc($v6);
	
	# fix %opt
	unless (exists($opt{Timeout})) {
		my $to = $self->{timeout_connect};
		$to = (defined $to) ? $to : $self->{timeout};
		{ no warnings; $to += 0 };
		$to = 5 unless (defined $to);
		$opt{Timeout} = $to;
	}
	
	no warnings;
	my $pfx = "CONNECT [$host]: ";
	
	# get connection class
	my $class = $self->_getConnClass($host, $v6);
	return undef unless (defined $class);
	$self->bufApp($pfx, "Will use connection class $class.") if ($self->{debug_socket});

	# unix domain socket?
	if ($class =~ m/::unix$/i) {
		$opt{Peer} = $host;
		$self->bufApp($pfx, "Connecting to UNIX domain socket.") if ($self->{debug_socket});
		my $conn = $class->new(%opt);
		unless ($conn) {
			$self->error("Error connecting to UNIX domain socket [$host]: $!");
		}
		return $conn;
	}
	
	# no proto?
	my $proto = $opt{Proto};
	$proto = 'tcp' unless (defined $proto && length($proto));
	$opt{Proto} = $proto;
	
	# no port?
	my $port = $opt{PeerPort};
	unless (defined $port) {
		$self->error("No connection port was set.");
		return undef;
	}
	$pfx = "CONNECT [$host]:$port [$opt{Proto}]: ";
	
	# apply remote address
	$opt{PeerAddr} = $host;

	# do we prefer ipv6 connectivity?
	if ($v6 eq 'prefer') {
		# we need two options...
		# one for ipv6:
		my %opt_v6 = %opt;
		$opt_v6{Domain} = eval "$class->AF_INET6";
		
		# and one for ipv4
		$opt{Domain} = eval "$class->AF_INET";
		
		# now try to connect
		$self->bufApp($pfx, "Trying to create IPv6 connection.") if ($self->{debug_socket});
		my $sock6 = $class->new(%opt_v6);
		if (defined $sock6) {
			$self->bufApp($pfx, "IPv6 connection succeeded!") if ($self->{debug_socket});
			return $sock6;
		}
		my $err_6 = "$!";
		$self->bufApp($pfx, "Trying to create IPv4 connection.") if ($self->{debug_socket});
		my $sock = $class->new(%opt);
		if (defined $sock) {
			$self->bufApp($pfx, "IPv4 connection succeeded!") if ($self->{debug_socket});
			return $sock;
		}
		my $err_4 = "$!";
		
		$self->error(
			"Error connecting to [$host]:$port: IPv6 error: $err_6; IPv4 error: $err_4"
		);
		return undef;
	}

	if ($v6 eq 'force') {
		$opt{Domain} = eval "$class->AF_INET6";
	}
	elsif ($v6 eq 'off') {
		$opt{Domain} = eval "$class->AF_INET";
	}
	else {
		$opt{MultiHomed} = 1;
	}

	# try to connect
	$self->bufApp($pfx, "Connecting with IPv6 mode '$v6'.") if ($self->{debug_socket});
	my $conn = $class->new(%opt);
	unless ($conn) {
		$self->error("Error connecting to [$host]: $!");
	}
	
	return $conn;
}

=head2 sockSSLConnect

Prototype:

 my $sslconn = $self->sockSSLConnect($host [, %opt]);

Connects to specified host or unix domain socket and tries to establish SSL/TLS secured session.
IPv6 is handled transparently. Supported options for B<%opt>:

=over

=item B<PeerPort> (integer, default: undef)

Remote port number. 

=item B<ipv6> (string, default: configuration parameter B<ipv6> or "any"):

IPv6 connection method. Possible values: prefer, any, off, force

=back

See L<IO::Socket::INET>, L<IO::Socket::UNIX> and L<IO::Socket::SSL> for description of B<%opt>.

Returns socket on success, otherwise undef.

=cut
sub sockSSLConnect {
	my ($self, $host, %opt) = @_;

	# do we have SSL support?
	return undef unless ($self->hasSSL());

	# try to connect...
	my $sock = $self->sockConnect($host, %opt);
	return undef unless (defined $sock);
	
	# try to establish SSL secured session...
	return $self->sslify($sock, %opt);
}

=head2 sslify

Prototype:

 my $ssl_socket = $self->sslify($plain_sock, %opt);

SSLifies (starts SSL/TLS session) already established socket. Returns
sslified socket object on success, otherwise undef.

See L<IO::Socket::SSL> for description of B<%opt>.

=cut
sub sslify {
	my ($self, $sock, %opt) = @_;
	unless (blessed($sock) && $sock->isa('IO::Socket')) {
		$self->error("Invalid socket.");
		return undef;
	}
	unless ($sock->connected()) {
		$self->error("Socket is not connected.");
		return undef;
	}

	# try to establish SSL secured session...
	$self->bufApp("Trying to establish SSL/TLS secured connection.") if ($self->{debug_socket});
	my $ssl_sock = IO::Socket::SSL->start_SSL($sock, %opt);
	unless (defined $ssl_sock) {
		$self->error(
			"Error establishing SSL/TLS session on already connected socket: " .
			IO::Socket::SSL::errstr()
		);
		return undef;
	}

	return $ssl_sock;
}

=head2 resolveHost

 my $r = $self->resolveHost($hostname [, $no_ipv6 = 0])

Resolves hostname $hostname and returns all resolved ip addresses. Result list
also contains IPv6 addresses if IPv6 support is available.

=cut
sub resolveHost {
	my ($self, $name, $no_ipv6) = @_;
	$no_ipv6 = 0 unless (defined $no_ipv6);
	return () unless (defined $name);
	
	# now to the stuff...
	my @res = ();	
	if (! $no_ipv6 && $self->hasIPv6()) {
		my @r = Socket6::getaddrinfo($name, 1, Socket->AF_UNSPEC, Socket->SOCK_STREAM);
		return () unless (@r);
		while (@r) {
			my $family = shift(@r);
			my $socktype = shift(@r);
			my $proto = shift(@r);
			my $saddr = shift(@r);
			my $canonname = shift(@r);
			next unless (defined $saddr);

			my ($host, undef) = Socket6::getnameinfo($saddr, Socket6->NI_NUMERICHOST | Socket6->NI_NUMERICSERV);
			push(@res, $host) if (defined $host);
		}		
	} else {
		my @addrs = gethostbyname($name);
		@res = map { Socket::inet_ntoa($_); } @addrs[4 .. $#addrs];
	}
	
	# assign system error code...
	$! = 99 unless (@res);
	
	return @res;
}

=head2 patchSocketImpl

Tries to patch L<IO::Socket> implementation by loading L<Net::INET6Glue>
module.

Returns 1 on success, otherwise 0.

=cut
sub patchSocketImpl {
	my ($self) = @_;
	return 1 if ($_is_patched);
	
	# try to load ipv6 support
	return 0 unless ($self->hasIPv6());

	# try to patch
	eval 'use ' . CLASS_GLUE . '; 1';
	unless ($@) {
		$_is_patched = 1;
		return 1;
	}

	$self->error("Error loading class '" . CLASS_GLUE . "': $@");
	return 0;
}

=head2 isPatched

Returns 1 if socket implementation was patched using B<patchSocketImpl> method,
otherwise 0.

=cut
sub isPatched {
	return $_is_patched;
}

=head2 setForcedIPv6

This method runs L<patchSocketImpl> that replaces L<IO::Socket::INET>
methods with ones defined in L<IO::Socket::INET6>. However this implementation
tries to connect to desired host using IPv6 first, if connect() fails it tries
to connect using IPv4.

Sometimes you want to connect strictly using IPv6 only. This method
hot-patches socket implementation classes that usage of Domain => AF_INET6
and MultiHomed => 0 are enforced.

After successful invocation of this method all modules using
L<IO::Socket::INET> use only (and really ONLY) IPv6.

Returns 1 on success, otherwise 0.

=cut
sub setForcedIPv6 {
	my ($self) = @_;
	return 0 unless ($self->patchSocketImpl());
	
	# we're going to defefine some subs now,
	# disable warning reporting.
	no warnings 'redefine';
	no strict;
	
	# redefine subs, save existing ones...
	*{IO::Socket::INET6::configure_orig} = \ &IO::Socket::INET6::configure;
	#*{IO::Socket::INET6::configure} = \ &{Noviforum::Adminalert::Check::_Socket::_cfg};
	*IO::Socket::INET6::configure = \ &{Noviforum::Adminalert::Check::_Socket::_cfg}; 
	*{IO::Socket::INET::configure_orig} = \ &IO::Socket::INET::configure;
	# *{IO::Socket::INET::configure} = \ &{Noviforum::Adminalert::Check::_Socket::_cfg};
	*IO::Socket::INET::configure = \ &{Noviforum::Adminalert::Check::_Socket::_cfg};

	return 1;
}

=head2 v6Sock

 # prefer ipv6 connections
 $self->v6Sock('prefer');
 
 # force ipv6 connections
 $self->v6Sock('force')
 
 # disable ipv6
 $self->v6Sock('off');

Automatically select/patch IPv6/IPv4 socket implementation. Returns 1 on success,
otherwise 0.

=cut
sub v6Sock {
	my ($self, $v6) = @_;
	$v6 = $self->{ipv6} unless (defined $v6);
	$v6 = 'prefer' unless (defined $v6);

	if ($v6 ne 'off') {
		if ($v6 eq 'force') {
			return 0 unless ($self->setForcedIPv6());
		}
		
		# try to patch socket implementation (ignore result)
		return $self->patchSocketImpl();
	}

	return 1;
}

sub _cfg {
	my($sock, $arg) = @_;
	if (ref($arg) eq 'HASH') {
		# we want to force AF_INET6 family!
		$arg->{Domain} = eval '$sock->AF_INET6';
		# this socket should not be multihomed
		$arg->{MultiHomed} = 0;
	}

	# is this ipv6 socket?
	if (blessed($sock) && $sock->isa('IO::Socket::INET6')) {
		return IO::Socket::INET6::configure_orig($sock, $arg);
	}

	# looks like usual ipv4 socket implementation...
	return IO::Socket::INET::configure_orig($sock, $arg);
}

sub _getConnClass {
	my ($self, $host, $v6) = @_;
	$v6 = 'prefer' unless (defined $v6);
	$v6 = lc($v6);
	
	unless (defined $host && length($host)) {
		return ($v6 ne 'off') ? CLASS_INET6 : CLASS_INET;
	}

	my @classes = (CLASS_INET);

	# does it look like unix domain socket?
	if ($host =~ m/\/+/) {
		@classes = (CLASS_UNIX);
	}
	elsif ($v6 eq 'force') {
		return undef unless ($self->hasIPv6());
		@classes = (CLASS_INET6);
	}
	elsif ($v6 eq 'prefer' || $v6 eq 'any') {
		unshift(@classes, CLASS_INET6);
	}
	elsif ($v6 eq 'off' && $self->isPatched()) {
		@classes = (CLASS_INET4);
	}
	
	# try to load classes...
	my $class = undef;
	foreach my $c (@classes) {
		eval "require $c";
		unless ($@) {
			$class = $c;
			last;
		}
	}

	unless (defined $class) {
		$self->error(
			"No suitable connection classes were loaded to handle connection " . 
			"to [$host] using IPv6 connection method '$v6'."
		);
	}

	return $class;
}

=head1 SEE ALSO

L<IO::Socket::INET>
L<IO::Socket::UNIX>
L<IO::Socket::INET6>
L<Net::INET6Glue>
L<IO::Socket::SSL>

=head1 AUTHOR

Brane F. Gracnar 

=cut

1;