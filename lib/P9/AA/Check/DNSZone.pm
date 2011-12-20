package P9::AA::Check::DNSZone;

use strict;
use warnings;

use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::DNS';

our $VERSION = 0.21;

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
		'Comma separated list of one or more zone names. Example: example.org,example2.org',
		$self->validate_str(16 * 1024),
	);

	$self->cfgParamRemove('host');
	$self->cfgParamRemove('type');
	$self->cfgParamRemove('check_authority');
	
	return 1;
}

sub toString {
	my $self = shift;
	no warnings;
	return 
	 join(",", $self->_peer_list($self->{zone})) . '@' . $self->{nameserver};
}

sub check {
  my ($self) = @_;	
  unless (defined $self->{zone} && length($self->{zone}) > 0) {
    return $self->error("DNS zone is not set.");
  }
	
  # get zones...
  my @zones = $self->_peer_list($self->{zone});
  unless (@zones) {
    no warnings;
    return $self->error("No DNS zone names can be parsed from string '$self->{zone}'");
  }

  # create resolver object
  my $res = $self->getResolver();
  return CHECK_ERR unless (defined $res);
	
  my $r = CHECK_OK;
  my $err = '';
  my $warn = '';
	
  # check all zones...
  my $i = 0;
  foreach my $zone (@zones) {
    $i++;    

    # get zone data...
    my $z = $self->zoneAXFR($zone, undef, $self->{class});
    unless (defined $z) {
      $err .= $self->error() . "\n";
      $r = CHECK_ERR;
      next;
    }

    # get soa
    my $soa = $z->[0];
    $self->bufApp("Zone $zone [" . ($#{$z} + 1) . " record(s)]:");
    $self->bufApp($soa->string());
    $self->bufApp();
  }
  
  if ($r != CHECK_OK) {
    $err =~ s/\s+$//g;
    $warn =~ s/\s+$//g;
    $self->warning($warn);
    $self->error($err);
  }

  return $r;
}

=head1 SEE ALSO

L<P9::AA::Check::DNS>, 
L<P9::AA::Check>, 
L<Net::DNS>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;