package P9::AA::Check::Mount;

use strict;
use warnings;

use Cwd qw(abs_path);

use P9::AA::Constants;
use base 'P9::AA::Check';

our $VERSION = 0.10;

=head1 NAME

Mounted filesystems checking module.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check> module.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Checks if all filesystems are mounted."
	);
	
	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# get fstab data
	my $fstab = $self->getFstabData();
	return CHECK_ERR unless (defined $fstab);	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN FSTAB DATA ---");
		$self->bufApp($self->dumpVar($fstab));
		$self->bufApp("--- END FSTAB DATA ---");
	}
	
	# get mount data
	my $mounts = $self->getMountData();
	return CHECK_ERR unless (defined $mounts);
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN MOUNT DATA ---");
		$self->bufApp($self->dumpVar($mounts));
		$self->bufApp("--- END MOUNT DATA ---");
	}
	
	my $res = CHECK_OK;
	my $err = '';
	
	my $fmt = "%-50.50s%-50.50s%s\n";
	$self->bufApp(sprintf($fmt, "DEVICE", "MNTPOINT", "STATUS"));
	
	# check structures...
	foreach my $e (@{$fstab}) {
		my $dev = $e->[0];
		my $mntpoint = $e->[1];

		# try to resolve dev and mountpoint
		my $real_dev = abs_path($dev);
		my $real_mntpoint = abs_path($mntpoint);
		
		# search in mount data...
		my $ok = 0;
		foreach my $m (@{$mounts}) {
			my $m_dev = $m->[0];
			my $m_mntpoint = $m->[1];
			my $real_m_dev = abs_path($m_dev);
			my $real_m_mntpoint = abs_path($m_mntpoint);

			no warnings;
			if (
			($dev eq $m_dev || $dev eq $real_m_dev || $real_dev eq $m_dev || $real_dev eq $real_m_dev) &&
			($mntpoint eq $m_mntpoint || $mntpoint eq $real_m_mntpoint || $real_mntpoint eq $m_mntpoint || $real_mntpoint eq $real_m_mntpoint)
			) {
				$ok = 1;
				last;
			}
		}
		
		if ($ok) {
			$self->bufApp(sprintf($fmt, $dev, $mntpoint, "OK"));
		} else {
			$self->bufApp(sprintf($fmt, $dev, $mntpoint, "NOT MOUNTED"));
			$err .= "Device $dev is not mounted on $mntpoint\n";
			$res = CHECK_ERR;
		}
	}
	
	unless ($res == CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	return $res;
}

=head2 getFstabData

 my $fstab = $self->getFstabData();

Returns arrayref containing fstab data on success, otherwise undef. 

Example structure:

 [
  [
    '/dev/md2',
    '/'
  ],
  [
    '/dev/md0',
    '/boot'
  ]
 ]

=cut
sub getFstabData {
	my $self = shift;
	$self->error("Method getFstabData is not implemented on " . $self->getOs() . " OS.");
	return undef;
}

=head2 getMountCmd

 my $cmd = $self->getMountCmd();

Returns L<mount(8)> command name on success, otherwise undef.

=cut
sub getMountCmd {
	return 'mount';
}

=head2 getMountData

 my $mounted = $self->getMountData();

Returns arrayref containing info about currently mounted filesystems.

Example structure:

 [
  [
    '/dev/md2',
    '/'
  ],
  [
    '/dev/md0',
    '/boot'
  ]
 ]

=cut
sub getMountData {
	my $self = shift;
	$self->error("Method getMoundData is not implemented on " . $self->getOs() . " OS.");
	return undef;
}

=head2 parseMountData

 my $mounted = $self->parseMountData($raw_data);

Parses raw data returned from L<mount(8)> command and returns arrayref on success,
otherwise undef.

Example structure:

 [
  [
    '/dev/md2',
    '/'
  ],
  [
    '/dev/md0',
    '/boot'
  ]
 ]

=cut
sub parseMountData {
	my $self = shift;
	$self->error("Method parseMountData is not implemented on " . $self->getOs() . " OS.");
	return undef;
}

sub VERSION {
	return $VERSION;
}

=head1 SEE ALSO

L<P9::AA::Check::Mount::LINUX>
L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;