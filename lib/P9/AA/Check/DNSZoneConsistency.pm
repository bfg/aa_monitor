package P9::AA::Check::DNSZoneConsistency;

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::DNSZone';

our $VERSION = 0.12;

=head1 NAME

This module checks DNS zone consistency on two nameservers (using AXFR).

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::DNSZone>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription(
		"Checks for zone data consistency on two nameservers."
	);
	
	$self->cfgParamAdd(
		'nameserver_peers',
		undef,
		'Comma separated list of peer nameservers. Zone will be transferred from all nameservers and compared to referential nameserver.',
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
	unless (defined $self->{nameserver_peers} && length($self->{nameserver_peers})) {
		return $self->error("DNS nameserver peer hosts are not set.");
	}
	
	# get referential zone...
	my $zone_ref = $self->zoneTransfer($self->{zone}, $self->{nameserver});
	return CHECK_ERR unless (defined $zone_ref);
	
	# compare nameserver results...
	my $cmp = {};
	
	# transfer zones from all nameserver peers
	foreach my $ns (split(/\s*[;,]+\s*/, $self->{nameserver_peers})) {
		$ns =~ s/^\s+//g;
		$ns =~ s/\s+$//g;
		next unless (length $ns);
		my $z = $self->zoneTransfer($self->{zone}, $ns);
		$cmp->{$ns} = [ $z, $self->error() ];
	}
	
	my $warn = '';
	my $err = '';
	my $result = CHECK_OK;
	
	foreach my $ns (keys %{$cmp}) {
		my $z = $cmp->{$ns}->[0];
		my $e = $cmp->{$ns}->[1];
		# no zone, no fun...
		unless (defined $z) {
			$err = "Nameserver $ns: " . $e . "\n";
			$result = CHECK_ERR;
			next;
		}
		
		$self->bufApp("Nameserver $ns: zone contains " . ($#{$z} + 1) . " records.");
		
		# compare zone data
		unless ($self->compareZone($zone_ref, $z)) {
			$err = $self->error() . "\n";
			$result = CHECK_ERR;
			next;
		}
	}
	
	unless ($result == CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	
	return $result;
}

sub zoneTransfer {
	my ($self, $zone, $nameserver) = @_;

	# create resolver...
	my $res = $self->getResolver($nameserver);
	return undef unless ($res);

	# transfer zone...
	return $self->zoneAXFR($zone, $res, $self->{class});
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

L<P9::AA::Check::DNSZone>, 
L<P9::AA::Check>, 
L<Net::DNS>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;