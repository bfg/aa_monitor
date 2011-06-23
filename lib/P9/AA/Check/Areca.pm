package P9::AA::Check::Areca;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';
use Data::Dumper;

# version MUST be set
our $VERSION = 0.01;

=head1 NAME

Areca RAID adapter checking module.

=head1 METHODS

This class inherits all methods from L<P9::AA::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Checks Areca RAID array for consistency."
	);

	# Adapter index
	$self->cfgParamAdd(
		'adapter',
		1,	
		'Adapter index.',
		$self->validate_int(1, 8)
	);
	
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;

	my @failed_vs = $self->_getFailedVolumeSets($self->{adapter});
	if (scalar @failed_vs) {
		$self->error(
			scalar @failed_vs . 
			" error(s) found. The following VolumeSets have errors: " . 
			join(', ', map { $_->{'Name'}; } @failed_vs)
		);
		return 0;
	}
	else {
		return 1;
	}
}

# describes check, optional.
sub toString {
	my ($self) = @_;
	no warnings;

	my $str = $self->{string_uppercase} . '/' . $self->{param_bool} . '/' . $self->{param_int};	
	return $str
}

sub _getFailedVolumeSets {
	my ($self, $adapter) = @_;

	# get VolumeSet data
	my $vsd = $self->getVolumeSetData($adapter);
	unless (defined $vsd) {
		$self->bufApp("ERROR: Unable to get any VolumeSet data for adapter $adapter.");
		return undef;
	}

	# build a list of failed VolumeSets
	my @failed_vs;
	foreach my $vs (@$vsd) {
		unless (exists $vs->{State} and $vs->{State} eq 'Normal') {
			push(@failed_vs, $vs);
		}
	}

	# check to see if any VolumeSets are out of order
	if (scalar @failed_vs) {

		# some VolumeSets are definitely bad, get underlying RaidSet data
		my $rsd = $self->getRAIDSetData($adapter);
		unless (defined $rsd) {
			$self->bufApp("ERROR: Unable to get any RAIDSet data for adapter $adapter.");
			return undef;
		}

		# go through all failed VolumeSets and print out their associated RaidSets
		foreach my $vs (@failed_vs) {
			$self->bufApp("ERROR: VolumeSet named '$vs->{Name}' is out of order. Details of the VolumeSet: " . Dumper $vs);
			foreach my $rs (@$rsd) {
				next if ($rs->{Name} ne $vs->{'Raid Name'});
				$self->bufApp("INFO: Details of the underlying RAIDSet named '$rs->{Name}' ('x' marks the spot!): " . Dumper $rs);
			}
		}

		# print out Disk data
		my $dd = $self->getDiskData($adapter);
		unless (defined $dd) {
			$self->bufApp("ERROR: Unable to get any DiskData for adapter $adapter.");
			return undef;
		}
		$self->bufApp("INFO: all disk details: " . Dumper $dd);

		# print out Adapter data
		my $ad = $self->getAdapterData($adapter);
		unless (defined $ad) {
			$self->bufApp("ERROR: Unable to get any AdapterData for adapter $adapter.");
			return undef;
		}
		$self->bufApp("INFO: adapter details: " . Dumper $ad);
	}

	return @failed_vs;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Uros Golja

=cut
1;
