package Noviforum::Adminalert::Check::DNS;

use strict;
use warnings;

use Net::DNS;
use Scalar::Util qw(blessed);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check';

our $VERSION = 0.13;

=head1 NAME

DNS check implementation and basic DNS infrastructure.

=head1 METHODS

This class inherits all methods from L<Noviforum::Adminalert::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription("Checks remote DNS server for availability.");

	$self->cfgParamAdd(
		'nameserver',
		'127.0.0.1',
		'Hostname of DNS server which will be queried.',
		$self->validate_lcstr(1024),
	);
	$self->cfgParamAdd(
		'host',
		undef,
		'Query for specified host/zone.',
		$self->validate_lcstr(1024),
	);
	$self->cfgParamAdd(
		'type',
		'A',
		'Queries for specified type.',
		$self->validate_ucstr(4),
	);
	$self->cfgParamAdd(
		'class',
		'IN',
		'Query class.',
		$self->validate_ucstr(2),
	);
	$self->cfgParamAdd(
		'timeout',
		2,
		'DNS query timeout in seconds.',
		$self->validate_int(1),
	);
	$self->cfgParamAdd(
		'check_authority',
		0,
		'Check authority section.',
		$self->validate_bool(),
	);
	
	return 1;
}

sub check {
	my ($self) = @_;	
	unless (defined $self->{host} && length($self->{host}) > 0) {
		return $self->error("Query host is not set.");
	}

	# create resolver object
	my $res = $self->getResolver();
	return CHECK_ERR unless (defined $res);

	# send DNS packet to server...
	local $@;
	my $packet = eval { $res->send($self->{host}, $self->{type}, $self->{class}) };
	if ($@) {
		return $self->error("Exception sending packet: $@");
	}
	unless (defined $packet) {
		return $self->error("Unable to resolve: " . $res->errorstring());
	}
	
	# check the packet...
	my @answer = $packet->answer();
	my @authority = $packet->authority();
	my @additional = $packet->additional();

	# print answer section
	$self->bufApp("") if ($self->{debug});
	$self->bufApp("ANSWER section:");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp("    " . $_->string());
	} @answer;
	$self->bufApp("--- snip ---");

	# print authority section
	$self->bufApp("AUTHORITY section:");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp("    " . $_->string());
	} @authority;
	$self->bufApp("--- snip ---");
	
	# print additional section
	$self->bufApp("ADDITIONAL section:");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp("    " . $_->string());
	} @additional;
	$self->bufApp("--- snip ---");

	# any answers? this could be a problem :)
	unless (@answer) {
		if ($self->{check_authority}) {
			if (@authority) {
				$self->bufApp("");
				$self->bufApp("Answer section is empty, but authority section contains records.");
				return 1;
			} else {
				return $self->error("DNS query finished successfully, but ANSWER and AUTHORITY sections are both empty!");
			}
		}

		return $self->error("DNS query finished successfully, but no records were returned in ANSWERS dns packet section!");
	}

	# return success...
	return $self->success();
}

sub toString {
	my ($self) = @_;
	no warnings;
	return $self->{host} . '/' .
		$self->{type} . '/' .
		$self->{class} .
		' @' .
		$self->{nameserver};
}

=head2 getResolver

Prototype:

 my $resolver = $self->getResolver([$nameserver]);

Returns initialized L<Net::DNS::Resolver> object.

=cut
sub getResolver {
	my ($self, $nameserver) = @_;
	$nameserver = $self->{nameserver} unless (defined $nameserver && length($nameserver));
	$nameserver = '127.0.0.1' unless (defined $nameserver);

	# create resolver object
	my $res = eval {
		Net::DNS::Resolver->new(
			nameservers => [ $nameserver ],
			# debug => $self->{debug},
			tcp_timeout => $self->{timeout},
			udp_timeout => $self->{timeout},
		)
	};
	unless (defined $res) {
		$self->error("Unable to create DNS resolver object: $!/$@");
	}

	return $res;
}

=head2 zoneAXFR

 my $records = $self->zoneAXFR($name [, $resolver, $class = 'IN']);

Tries to perform zone $name zone transfer. Returns array reference of L<Net::DNS::RR> records
on success, otherwise undef.

=cut
sub zoneAXFR {
	my ($self, $zone, $res, $class) = @_;
	unless (defined $zone && length($zone)) {
		$self->error("Invalid/Undefined zone name.");
		return undef;
	}
	$res = $self->getResolver() unless (blessed($res) && $res->isa('Net::DNS::Resolver'));
	$class = 'IN' unless (defined $class && length($class));
	$class = uc($class);

	# prepare error message prefix
	my $ns_list = join(', ', $res->nameservers());
	my $err = 'Error transfering zone ' .
		$zone . ' from ' . $ns_list . ': ';

	my $result = [];
	local $@;
	@{$result} = eval { $res->axfr($zone, $class) };
	if ($@) {
		$self->error($err . "Exception: $@");
		return undef;
	}
	unless (@{$result}) {
		$self->error($err . $res->errorstring());
		return undef;
	}
	
	# first argument MUST be SOA
	my $soa = $result->[0];
	unless (blessed($soa) && $soa->isa('Net::DNS::RR::SOA')) {
		$self->error($err . "Zone is missing SOA record. This is extremely weird.");
		return undef;
	}

	if ($self->{debug}) {
		$self->bufApp(
			"DNS zone transfer of zone $zone from $ns_list returned " .
			($#{$result} + 1) . " record(s)."
		);
	}

	return $result;	
}

=head1 SEE ALSO

L<Noviforum::Adminalert::Check>, 
L<Net::DNS>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;