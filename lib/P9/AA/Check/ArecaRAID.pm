package P9::AA::Check::ArecaRAID;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';

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
	
	# detailed view
	$self->cfgParamAdd(
		'detailed',
		0,
		'Turn detailed mode on or off. Detailed mode prints out more data.',
		$self->validate_bool()
	);
	
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;

	my $failed_vs = $self->_getFailedVolumeSets($self->{adapter});
	return undef unless (defined $failed_vs);

	# are there any failed VolumeSets?
	if (@{$failed_vs}) {
		# do the summary
		$self->error(
			scalar @$failed_vs . 
			" VolumeSet(s) have errors: " . 
			join(', ', map { $_->{'Name'}; } @$failed_vs)
		);

		# output the failed RAIDSets if the detailed mode is enabled
		if ($self->{detailed}) {
			# check for failed RAIDSets
			my @failed_rs = $self->_getFailedRAIDSets($self->{adapter});
			unless (@failed_rs) {
				$self->bufApp("ERROR: Unable to get any RAIDSetData for adapter $self->{adapter}.");
				}
			}
	}
	else {
		# output some more stuff if the detailed mode is enabled
		if ($self->{detailed}) {

			# dump all VolumeSets
			my $vs = $self->getVolumeSetData($self->{adapter});
			if (defined $vs) {
				$self->bufApp("INFO: all VolumeSet details: " . $self->dumpVar($vs));
			}
			else {
				$self->bufApp("ERROR: Unable to get any VolumeSetData for adapter $self->{adapter}.");
			}

			# dump all RAIDSets
			my $rs = $self->getRAIDSetData($self->{adapter});
			if (defined $rs) {
				$self->bufApp("INFO: all RAIDSet details " . $self->dumpVar($rs));
			}
			else {
				$self->bufApp("ERROR: Unable to get any RAIDSetData for adapter $self->{adapter}.");
			}
		}
	}

	# do some more *common* additional output if detailed mode is enabled
	if ($self->{detailed}) {
		# print out Disk data
		my $dd = $self->getDiskData($self->{adapter});
		if (defined $dd) {
			$self->bufApp("INFO: all Disk details: " . $self->dumpVar($dd));
		}
		else {
			$self->bufApp("ERROR: Unable to get any DiskData for adapter $self->{adapter}.");
		}

		# print out Adapter data
		my $ad = $self->getAdapterData($self->{adapter});
		if (defined $ad) {
			$self->bufApp("INFO: all Adapter details: " . $self->dumpVar($ad));
		}
		else {
			$self->bufApp("ERROR: Unable to get any AdapterData for adapter $self->{adapter}.");
		}
	}

	scalar @$failed_vs ? return 0 : return 1;
}

# describes check, optional.
sub toString {
	my ($self) = @_;
	no warnings;

	my $str = $self->{string_uppercase} . '/' . $self->{param_bool} . '/' . $self->{param_int};	
	return $str
}

=head1 PROTECTED METHODS

=head2 _getFailedRAIDSets

 my $failed_rs = $self->_getFailedRAIDSets($adapter);

Get a listref of failed RAIDSets. $failed_rs contains an empty list if
everything is OK, or an undef if an error happened.

=cut
sub _getFailedRAIDSets {
	my ($self, $adapter) = @_;

	my $rsd = $self->getRAIDSetData($adapter);
	unless (defined $rsd) {
		$self->bufApp("ERROR: Unable to get any RAIDSet data for adapter $adapter.");
		return undef;
	}

	# build a list of failed RAIDSets
	my $failed_rs = [];
	foreach my $rs (@$rsd) {
		unless (exists $rs->{State} and $rs->{State} eq 'Normal') {
			push(@$failed_rs, $rs);
			$self->bufApp("ERROR: RAIDSet named '$rs->{Name}' is out of order. Details of the RAIDSet: " . $self->dumpVar($rs));
		}
	}
	
	return $failed_rs;
}


# my $failed_rs = $self->_getFailedVolumeSets($adapter);
#
#Get a listref of failed VolumeSets. $failed_rs contains an empty list if
#everything is OK, or an undef if an error happened.
sub _getFailedVolumeSets {
	my ($self, $adapter) = @_;

	# get VolumeSet data
	my $vsd = $self->getVolumeSetData($adapter);
	unless (defined $vsd) {
		$self->bufApp("ERROR: Unable to get any VolumeSet data for adapter $adapter.");
		return undef;
	}

	# build a list of failed VolumeSets
	my $failed_vs = [];
	foreach my $vs (@$vsd) {
		unless (exists $vs->{State} and $vs->{State} eq 'Normal') {
			push(@$failed_vs, $vs);
			$self->bufApp("ERROR: VolumeSet named '$vs->{Name}' is out of order. Details of the VolumeSet: " . $self->dumpVar($vs));
		}
	}

	return $failed_vs;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Uros Golja

=cut

1;
