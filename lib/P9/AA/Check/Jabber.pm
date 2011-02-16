package P9::AA::Check::Jabber;

use strict;
use warnings;

use Net::Jabber;

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

our $VERSION = 0.11;

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription(
		"Checks Jabber server availability."
	);
	
	$self->cfgParamAdd(
		'hostname',
		'localhost',
		'Jabber server hostname.',
		$self->validate_lcstr(1024),
	);
	$self->cfgParamAdd(
		'port',
		5222,
		'Jabber server listening port.',
		$self->validate_int(1, 65535),
	);
	$self->cfgParamAdd(
		'username',
		undef,
		'Connect username.',
		$self->validate_str(100),
	);
	$self->cfgParamAdd(
		'password',
		undef,
		'Connect password.',
		$self->validate_str(100),
	);
	$self->cfgParamAdd(
		'resource',
		'Jping',
		'Jabber resource',
		$self->validate_str(100),
	);
	$self->cfgParamAdd(
		'tls',
		0,
		'Use TLS?',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'timeout',
		2,
		'Timeout for operations',
		$self->validate_int(1),
	);
	
	$self->cfgParamRemove('debug_socket');
	$self->cfgParamRemove('timeout_connect');

	return 1;
}

sub check {
	my ($self) = @_;
	
	# ipv6 stuff...
	unless ($self->{ipv6} eq 'off') {
		if ($self->{ipv6} eq 'force') {
			return 0 unless ($self->setForcedIPv6());
		}
		$self->patchSocketImpl();
	}

	my $conn = Net::Jabber::Client->new();
	
	my $r = $conn->Connect(
		hostname => $self->{hostname},
		port => $self->{port},
		tls => $self->{tls},
		timeout => $self->{timeout}
	);
	
	unless (defined $r && $conn->Connected()) {
		no warnings;
		$self->error("Unable to connect to jabber server: $@");
		return CHECK_ERR;
	}

	my @connection_status = $conn->AuthSend(
		username => $self->{username},
		password => $self->{password},
		resource => $self->{resource},
		processtimeout => $self->{timeout}
	);

	unless (@connection_status) {
		$self->error("No connection status. Authentication failed or Net::Jabber::Client bug.");
		return CHECK_ERR;
	}

	if ($connection_status[0] ne "ok") {
		$self->error($connection_status[1]);
		return CHECK_ERR;
	}

	return CHECK_OK;
}

1;