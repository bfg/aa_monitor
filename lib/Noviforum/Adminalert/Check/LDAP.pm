package Noviforum::Adminalert::Check::LDAP;

use strict;
use warnings;

use Authen::SASL;
use List::Util qw(shuffle);
use Scalar::Util qw(blessed);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::_Socket';

our $VERSION = 0.20;

=head1 NAME

LDAP checking module and support methods.

=head1 METHODS

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription("Checks LDAP server availability.");

	$self->cfgParamAdd(
		'host',
		'localhost',
		'LDAP server hostname, ip address or LDAP URL',
		$self->validate_str(200)
	);
	$self->cfgParamAdd(
		'port',
		389,
		'LDAP server listening port',
		$self->validate_int(1, 65535)
	);
	$self->cfgParamAdd(
		'ldap_version',
		3,
		'LDAP protocol version',
		$self->validate_int(1, 3)
	);
	$self->cfgParamAdd(
		'tls',
		0,
		'Use TLS secured connection?',
		$self->validate_bool()
	);
	$self->cfgParamAdd(
		'tls_verify',
		'none',
		'TLS peer verification mode. See perldoc IO::Socket:SSL for details.',
		$self->validate_str(10)
	);
	$self->cfgParamAdd(
		'tls_sslversion',
		'tlsv1',
		'TLS SSL version. Possible values: tlsv1, sslv2, sslv3.',
		$self->validate_str(5),
	);
	$self->cfgParamAdd(
		'tls_ciphers',
		'HIGH',
		'TLS cipher list.',
		$self->validate_str(250)
	);
	$self->cfgParamAdd(
		'tls_clientcert',
		undef,
		'TLS client certificate file',
		$self->validate_str(250)
	);
	$self->cfgParamAdd(
		'tls_clientkey',
		undef,
		'TLS client key file',
		$self->validate_str(250),
	);
	$self->cfgParamAdd(
		'tls_capath',
		undef,
		'TLS SSL CA directory',
		$self->validate_str(250),
	);
	$self->cfgParamAdd(
		'tls_cafile',
		undef,
		'TLS SSL CA file',
		$self->validate_str(250)
	);

	$self->cfgParamAdd(
		'bind_dn',
		undef,
		'LDAP bind DN',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'bind_sasl',
		0,
		'Use SASL bind?',
		$self->validate_bool()
	);
	$self->cfgParamAdd(
		'bind_sasl_authzid',
		undef,
		'SASL bind authzid',
		$self->validate_str(250)
	);
	$self->cfgParamAdd(
		'bind_sasl_mech',
		'PLAIN',
		'SASL bind mechanism',
		$self->validate_str(20)
	);
	$self->cfgParamAdd(
		'bind_pw',
		undef,
		'LDAP bind password',
		$self->validate_str(250)
	);

	$self->cfgParamAdd(
		'search_base',
		'',
		'LDAP search base DN',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'search_filter',
		'(objectClass=*)',
		'LDAP search filter',
		$self->validate_str(1024)
	);
	$self->cfgParamAdd(
		'search_scope',
		'one',
		'LDAP search scope. Possible values: sub, one, none',
		$self->validate_str(4)
	);
	$self->cfgParamAdd(
		'search_deref',
		'never',
		'Dereference LDAP search results? Possible values: never, search, find, always',
		$self->validate_str(6),
	);

	$self->cfgParamAdd(
		'timeout',
		1,
		'LDAP operation timeout in seconds',
		$self->validate_int(1)
	);
	$self->cfgParamAdd(
		'debug_search',
		0,
		'Display/dump entries returned by LDAP search?',
		$self->validate_bool()
	);

	# remove parameters
	$self->cfgParamRemove('timeout_connect');

	return 1;
}

=head2 check ()

Checks LDAP service using current configuration.

=cut
sub check {
	my ($self) = @_;

	# PHASE I: connect                                            #
	my %opt = $self->_connectOpt();
	my $ldap = $self->ldapConnect(host => $self->{host}, %opt);
	return CHECK_ERR unless (defined $ldap);

	# PHASE II: LDAP bind
	return CHECK_ERR unless ($self->ldapBind($ldap, %opt));

	# PHASE III: LDAP search                                       #
	my $r = $self->ldapSearch($ldap, $self->_searchOpt());
	return CHECK_ERR unless (defined $r && ! $r->is_error());

	# PHASE IV: unbind and disconnect
	$ldap->unbind();
	$ldap->disconnect();
	undef $ldap;

	return CHECK_OK;
}

=head2 ldapConnect (host => "ldap.example.org", %opt)

Connects to LDAP service. Returns initialized Net::LDAP object on success, otherwise undef.

%opt must contain the same keys as this object configuration.

=cut
sub ldapConnect {
	my ($self, %opt) = @_;
	
	my $host = undef;
	my @ips = ();

	
	# is host LDAP URL or hostname?
	if ($opt{host} =~ m/^ldap(s|i)?:\//i) {
		$host = delete($opt{host});
	} else {

		# ipv6 stuff?
		my $no_ipv6 = 0;
		if ($opt{ipv6} ne 'off') {
			if ($opt{ipv6} eq 'force') {
				return 0 unless ($self->setForcedIPv6());
			}
			# other ipv6 cases are handled transparently...
		} else {
			$no_ipv6 = 1;
		}

		@ips = $self->resolveHost($opt{host}, $no_ipv6);
		return undef unless (@ips);
		$self->bufApp(
			"Host '" . $opt{host} .
			"' resolves to the following IP addresses: " .
			join(", ", @ips)
		);
		$host = \ @ips;
	}

	# try to create LDAP connection
	my $ldap = MyLDAP->new(
		$host,
		port    => $opt{port},
		timeout => $opt{timeout},
		version => $opt{ldap_version},
		__connect_obj => $self,
	);	
	return undef unless (defined $ldap);

	# start TLS?
	if ($self->{tls}) {
		my $r = $ldap->start_tls(
			verify     => $self->{tls_verify},
			sslversion => $self->{tls_sslversion},
			ciphers    => $self->{tls_ciphers},
			clientcert => $self->{tls_clientcert},
			clientkey  => $self->{tls_clientkey},
			capath     => $self->{tls_capath},
			cafile     => $self->{tls_cafile}
		);
		if ($r->is_error()) {
			$self->{error} =
			    "Unable to start secure transport: LDAP error code "
			  . $r->code() . ": "
			  . $r->error();
			return undef;
		}
	}

	return $ldap;
}

=head2 ldapBind ($ldap_obj, %opt)

Performs LDAP bind on $ldap_object (L<Net::LDAP>). Returns 1 on success, otherwise 0.

%opt must contain the same keys as this object configuration.

=cut
sub ldapBind {
	my ($self, $ldap, %opt) = @_;
	unless (blessed($ldap) && $ldap->isa('Net::LDAP')) {
		$self->error("Invalid LDAP object (bind).");
		return 0;
	}
	
	# no ldap bind dn?
	unless (defined $opt{bind_dn} && length($opt{bind_dn}) && defined $opt{bind_pw} && length($opt{bind_pw})) {
		return 1;
	}

	my $r = undef;
 
	if ($opt{bind_sasl}) {
		my $sasl = Authen::SASL->new(
			mechanism => $opt{bind_sasl_mech},
			callback  => {
				user => $opt{bind_sasl_authzid},
				pass => $opt{bind_pw}
			}
		);
		unless (defined $sasl) {
			$self->error("Unable to create SASL authentication object.");
			return 0;
		}

		# this is sooo stupid - sasl authzid must match $USER environment variable
		# (cyrus sasl requirement)
		my $user = $ENV{USER};
		$ENV{USER} = $opt{bind_sasl_authzid};
		$r = $ldap->bind($opt{bind_dn}, sasl => $sasl);
		$ENV{USER} = $user if (defined $user);
	
	} else {
		$r = $ldap->bind($opt{bind_dn}, password => $opt{bind_pw});
	}

	if ($r->is_error()) {
		$self->error(
			"Unable to bind ldap server: LDAP error code " .
			$r->code() . ": " .
			$r->error()
		);
		return 0;
	}

	return 1;
}

=head2 ldapSearch ($ldap_obj, %opt)

Performs LDAP search using $ldap_object (L<Net::LDAP>). Returns initialized L<Net::LDAP::Search> object on search success,
undef on fatal error. B<WARNING:> you must check for success using B<is_error()> method on returned object.

%opt must contain the same keys as method B<search> in L<Net::LDAP> class.

=cut
sub ldapSearch {
	my ($self, $ldap, %opt) = @_;
	unless (blessed($ldap) && $ldap->isa('Net::LDAP')) {
		$self->error("Invalid LDAP object (search).");
		return undef;
	}

	my $r = $ldap->search(
		base   => $opt{base},
		filter => $opt{filter},
		scope  => $opt{scope},
		deref  => $opt{deref}
	);

	if ($r->is_error()) {
		$self->error(
			"Unable to perform ldap search: LDAP error code " .
			$r->code() . ": " .
			$r->error()
		 );
	} else {
		$self->bufApp("LDAP search returned " . $r->count() . ' entries.');
		if ($self->{debug_search}) {
			$self->bufApp("--- BEGIN SEARCH ENTRIES ---");
			map {
				$self->bufApp($_->ldif());
			} $r->entries();
			$self->bufApp("--- END SEARCH ENTRIES ---");
		}
	}

	return $r;
}

sub _connectOpt {
	my ($self) = @_;
	my %opt = ();
	foreach (keys %{$self}) {
		next if ($_ =~ /^_/);
		$opt{$_} = $self->{$_};
	}
	return %opt;
}

sub _searchOpt {
	my ($self) = @_;
	my %opt = ();
	foreach (keys %{$self}) {
		next unless ($_ =~ /^search_(.+)$/);
		$opt{$1} = $self->{$_};
	}
	return %opt;	
}

=head1 SEE ALSO

L<Net::LDAP>
L<Noviforum::Adminalert::Check::_Socket>
L<Noviforum::Adminalert::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut

# inline Net::LDAP subclass...
package MyLDAP;

use Net::LDAP;

use vars qw(@ISA);
@ISA = qw(Net::LDAP);

sub connect_ldap {
	my ($ldap, $host, $arg) = @_;
	my $port = $arg->{port} || 389;
	$arg->{port} = $port;

	# separate port from host overwriting given/default port
	$host =~ s/^([^:]+|\[.*\]):(\d+)$/$1/ and $port = $2;

	my $sock = __connect($host, $arg);
	return undef unless (defined $sock);

	$ldap->{net_ldap_socket} = $sock;
	$ldap->{net_ldap_host}   = $host;
	$ldap->{net_ldap_port}   = $port;
}

sub connect_ldaps {
	my ($ldap, $host, $arg) = @_;
	my $port = $arg->{port} || 636;
	$arg->{port} = $port;

	# separate port from host overwriting given/default port
	$host =~ s/^([^:]+|\[.*\]):(\d+)$/$1/ and $port = $2;

	my $sock = __connect($host, $arg, 1);
	return undef unless (defined $sock);

	$ldap->{net_ldap_socket} = $sock;
	$ldap->{net_ldap_host} = $host;
	$ldap->{net_ldap_port} = $port;
}

sub __connect {
	my ($host, $arg, $ssl) = @_;
	$ssl = 0 unless (defined $ssl);
	my $port = $arg->{port} || 389;

	# separate port from host overwriting given/default port
	$host =~ s/^([^:]+|\[.*\]):(\d+)$/$1/ and $port = $2;
	
	my $connector = delete($arg->{__connect_obj});
	my $method = ($ssl) ? 'sockSSLConnect' : 'sockConnect';
	# no connector object?
	unless (defined $connector) {
		$connector = ($arg->{inet6}) ? 'IO::Socket::INET6' : 'IO::Socket::INET';
		$method = 'new';
	}

	# create socket...
	my $sock = eval {
		$connector->$method(
			$host,
			PeerPort   => $port,
			LocalAddr  => $arg->{localaddr} || undef,
			Proto      => 'tcp',
			MultiHomed => $arg->{multihomed},
			Timeout    => defined $arg->{timeout} ? $arg->{timeout} : 120,
		)
	};
	
	return $sock;
}

1;