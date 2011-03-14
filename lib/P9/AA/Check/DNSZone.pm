package P9::AA::Check::DNSZone;

use strict;
use warnings;

use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::DNS';

our $VERSION = 0.20;

=head1 NAME

DNS AXFR zone transfer checking module.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::DNS>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription("Tries to perform DNS AXFR zone transfer from specified DNS server.");
	
	$self->cfgParamAdd(
		'zone',
		undef,
		'Zone name. Example: example.org',
		$self->validate_str(500),
	);

	$self->cfgParamRemove('host');
	$self->cfgParamRemove('type');
	$self->cfgParamRemove('check_authority');
	
	return 1;
}

sub toString {
	my $self = shift;
	no warnings;
	return $self->{zone} . '@' . $self->{nameserver};
}

sub check {
	my ($self) = @_;	
	unless (defined $self->{zone} && length($self->{zone}) > 0) {
		return $self->error("DNS zone is not set.");
	}

	# create resolver object
	my $res = $self->getResolver();
	return CHECK_ERR unless (defined $res);
	
	# get zone data...
	my $z = $self->zoneAXFR($self->{zone}, undef, $self->{class});
	return CHECK_ERR unless (defined $z);
	
	# get soa
	my $soa = $z->[0];
	$self->bufApp("Zone $self->{zone} SOA:");
	$self->bufApp($soa->string());
	$self->bufApp("Zone contains " . ($#{$z} + 1) . " records.");

	# return success...
	return CHECK_OK;
}

=head1 SEE ALSO

L<P9::AA::Check::DNS>, 
L<P9::AA::Check>, 
L<Net::DNS>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;