package Noviforum::Adminalert::Check::DNSZoneConsistency;

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use Scalar::Util qw(blessed);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::DNSZone';

our $VERSION = 0.11;

=head1 NAME

This module checks DNS zone consistency on two nameservers (using AXFR).

=head1 METHODS

This module inherits all methods from L<Noviforum::Adminalert::Check::DNSZone>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription(
		"Checks for zone data consistency on two nameservers."
	);
	
	$self->cfgParamAdd(
		'peer_nameserver',
		undef,
		'Compare specified zone from \'nameserver\' with zone from this nameserver.',
		$self->validate_str(500),
	);
	
	return 1;
}

sub toString {
	my $self = shift;
	no warnings;
	return $self->{zone} .
		' ' . $self->{nameserver} .
		' <=> ' . $self->{peer_nameserver} .
		' / ' . $self->{class};
}

sub check {
	my ($self) = @_;	
	unless (defined $self->{zone} && length($self->{zone}) > 0) {
		return $self->error("DNS zone is not set");
	}
	unless (defined $self->{peer_nameserver} && length($self->{peer_nameserver})) {
		return $self->error("Peer DNS nameserver host is not set.");
	}
	
	# get resolvers...
	my $res_ref = $self->getResolver($self->{nameserver});
	return CHECK_ERR unless ($res_ref);
	my $res_cmp = $self->getResolver($self->{peer_nameserver});
	return CHECK_ERR unless ($res_cmp);

	# get zones...
	my $z_ref = $self->zoneAXFR($self->{zone}, $res_ref, $self->{class});
	return CHECK_ERR unless ($z_ref);
	my $soa_ref = $z_ref->[0];

	my $z_cmp = $self->zoneAXFR($self->{zone}, $res_cmp, $self->{class});
	return CHECK_ERR unless ($z_cmp);
	my $soa_cmp = $z_cmp->[0];
	
	#####################
	
	$self->bufApp("Referential SOA:");
	$self->bufApp($soa_ref->string());
	$self->bufApp();
	$self->bufApp("Comparing SOA:");
	$self->bufApp($soa_cmp->string());

	# compare zone data
	return CHECK_ERR unless ($self->compareZone($z_ref, $z_cmp));
	return CHECK_OK;
}

=head2 compareSOA

 my $r = $self->compareSOA($reference, $comparing);

Returns 1 if specified L<Net::DNS::RR::SOA> records are
equal, otherwise 0.

=cut
sub compareSOA {
	my ($self, $ref, $cmp) = @_;
	unless (blessed($ref) && $ref->isa('Net::DNS::RR::SOA')) {
		$self->error('Invalid referential SOA record: ' . ref($ref));
		return 0;
	}
	unless (blessed($cmp) && $cmp->isa('Net::DNS::RR::SOA')) {
		$self->error('Invalid comparing SOA record: ' . ref($cmp));
		return 0;
	}
	
	# get domain name...
	my $name_ref = $ref->name();
	my $name_cmp = $cmp->name();
	unless ($name_ref eq $name_cmp) {
		$self->error("Domain name between zones differ: reference: $name_ref, comparing: $name_cmp");
		return 0;
	}

	# error prefix
	my $err = "SOA record validation failed: ";

	if ($ref->mname() ne $cmp->mname()) {
		$self->error($err . "Primary domain name servers differ.");
	}
	elsif ($ref->rname() ne $cmp->rname()) {
		$self->error($err . "Mailbox addresses differ.");
	}
	elsif ($ref->serial() ne $cmp->serial()) {
		$self->error($err . "Serial numbers differ.");
	}
	elsif ($ref->refresh() ne $cmp->refresh()) {
		$self->error($err . "Refresh values differ.");
	}
	elsif ($ref->retry() ne $cmp->retry()) {
		$self->error($err . "Retry values differ.");
	}
	elsif ($ref->expire() ne $cmp->expire()) {
		$self->error($err . "Expire values differ.");
	}
	elsif ($ref->minimum() ne $cmp->minimum()) {
		$self->error($err . "Minimum values differ.");
	}
	else {
		return 1;
	}
	
	return 0;
}

=head2 compareZone

 my $r = $self->compareZone($reference, $comparing);

Compares two arrayrefs of L<Net::DNS::RR> records. Returns 1 if array contain
equal zone data, otherwise 0.

=cut
sub compareZone {
	my ($self, $ref, $cmp) = @_;
	unless (defined $ref && ref($ref) eq 'ARRAY') {
		$self->error('Invalid referential zone argument: ' . ref($ref));
		return 0;
	}
	unless (ref($cmp) && ref($cmp) eq 'ARRAY') {
		$self->error('Invalid comparing zone argument ' . ref($cmp));
		return 0;
	}
	
	# compare SOA records...
	my $soa_ref = $ref->[0];
	my $soa_cmp = $cmp->[0];
	return 0 unless ($self->compareSOA($soa_ref, $soa_cmp));

	# now compare data records
	my @s_ref = ();
	for (my $i = 1; $i < $#{$ref}; $i++) {
		my $e = $ref->[$i];
		next unless (blessed($e) && $e->isa('Net::DNS::RR'));
		push(@s_ref, $e->string());
	}
	my $buf_ref = join("\n", sort(@s_ref));

	my @s_cmp = ();
	for (my $i = 1; $i < $#{$cmp}; $i++) {
		my $e = $cmp->[$i];
		next unless (blessed($e) && $e->isa('Net::DNS::RR'));
		push(@s_cmp, $e->string());
	}
	my $buf_cmp = join("\n", sort(@s_cmp));
	
	if ($self->{debug}) {
		$self->bufApp('--- BEGIN REFERENTIAL ZONE ---');
		$self->bufApp($buf_ref);
		$self->bufApp('--- END REFERENTIAL ZONE ---');
		$self->bufApp();
		$self->bufApp('--- BEGIN COMPARING ZONE ---');
		$self->bufApp($buf_cmp);
		$self->bufApp('--- END COMPARING ZONE ---');
	}
	
	# create digests.
	my $digest_ref = md5_hex($buf_ref);
	my $digest_cmp = md5_hex($buf_cmp);

	# compare digests.
	unless ($digest_ref eq $digest_cmp) {
		$self->error("Zone data checksums differ between referential and compared nameserver.");
		return 0;
	}
	
	# we survived, zones are ok!
	return 1;
}

=head1 SEE ALSO

L<Noviforum::Adminalert::Check::DNSZone>, 
L<Noviforum::Adminalert::Check>, 
L<Net::DNS>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;