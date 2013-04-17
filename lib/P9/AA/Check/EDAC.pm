package P9::AA::Check::EDAC;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';

=head1 NAME

ECC memory test module

=cut

our $VERSION = 0.20;

##################################################
#              PUBLIC  METHODS                   #
##################################################

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription(
		"Checks for ECC memory errors and PCI parity errors. Operates only on Linux OS."
	);
	
	$self->cfgParamAdd(
		'ue_threshold',
		0,
		'Uncorrectable errors threshold.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'ce_threshold',
		0,
		'Correctable errors threshold.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'pci_threshold',
		0,
		'PCI errors threshold.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'reset_counters',
		0,
		'Reset EDAC counters?',
		$self->validate_bool(),
	);

	return 1;
}

sub check {
	my ($self) = @_;
	my $struct = $self->edac_data();
	return CHECK_ERR unless (defined $struct);

	my $result = CHECK_OK;
	$self->bufApp("");
	$self->bufApp("### EDAC test: ###");
	
	# check for validity
	$self->bufApp("Got struct: " . $self->dumpVar($struct)) if ($self->{debug});
	unless (exists($struct->{mem}) && keys(%{$struct->{mem}}) > 0) {
		$self->bufApp("Unable to read EDAC statistics: EDAC enabled hardware is not available on the system.");
		return CHECK_OK;
	}

	# check edac structure
	$self->bufApp();
	$self->bufApp("Checking EDAC structures: ");

	foreach my $c (sort keys %{$struct->{mem}}) {
		foreach my $m (sort keys %{$struct->{mem}->{$c}}) {
			my $ue = int($struct->{mem}->{$c}->{$m}->{ue_count});
			my $ce = int($struct->{mem}->{$c}->{$m}->{ce_count});
			my $r = "OK";
			
			if ($ue > $self->{ue_threshold} || $ce > $self->{ce_threshold}) {
				$self->error("ECC errors detected (UE: $ue, CE: $ce) on controller '$c', slot '$m'.");
				$result = CHECK_ERR;
				$r = "FAILURE";
			}

			$self->bufApp("    Controller $c, slot $m: $r");
		}
	}

	# Check for PCI errors...
	if (exists($struct->{pci})) {
		$self->bufApp();
		my $str = "Checking EDAC structures for PCI parity errors: ";
		if ($struct->{pci}->{err_count} > $self->{pci_threshold}) {
			$self->error($struct->{pci}->{err_count} . " parity errors detected on PCI bus.");
			$str .= "FAILURE";
			$result = CHECK_ERR;
		} else {
			$str .= "OK";
		}
		$self->bufApp($str);
	}

	return $result;
}

=head1 METHODS

This module inherits all methods from L<P9::AA::Check> and implements the following ones:

=head2 edac_data

  my $struct = $chk->edac_data();

Returns edac data hash

=cut
sub edac_data {
  my $self = shift;
  $self->error("This method is not implemented in class " . ref($self));
  return undef;
}

=head2 edac_reset

  $chk->edac_reset($memory_controller);

Resets edac counters

=cut
sub edac_reset {
  my $self = shift;
  $self->error("This method is not implemented in class " . ref($self));
  return undef;  
}

=head1 SEE ALSO

=over

=item * L<P9::AA::Check::EDAC::LINUX>

=back

=head1 AUTHOR

Brane F. Gracnar

=cut

1;