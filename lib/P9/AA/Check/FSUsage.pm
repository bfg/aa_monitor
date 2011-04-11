package P9::AA::Check::FSUsage;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';

use constant MB => 1024 * 1024;

our $VERSION = 0.22;

=head1 NAME

Mounted filesystem usage check.

=head1 IMPLEMENTATIONS

Base class is implemented for B<Linux> operating system. Support for other operating
systems can be easily added by extending this class.

See L<P9::AA::Check::FSUsage::BSD> and
L<P9::AA::Check::FSUsage::FREEBSD> for operating system specific
implementation details.

=head1 METHODS

=cut

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription(
		"Checks filesystem usage."
	);
	
	# add configuration parameters...
	$self->cfgParamAdd(
		'usage_threshold',
		90,
		'Filesystem usage threshold in %',
		$self->validate_int(1, 99),
	);
	$self->cfgParamAdd(
		'usage_threshold_warn',
		80,
		'Filesystem usage warning threshold in %',
		$self->validate_int(1, 99),
	);
	# add configuration parameters...
	$self->cfgParamAdd(
		'inode_threshold',
		90,
		'Filesystem inode usage threshold in %',
		$self->validate_int(1, 99),
	);
	# add configuration parameters...
	$self->cfgParamAdd(
		'inode_threshold_warn',
		75,
		'Filesystem inode usage warning threshold in %',
		$self->validate_int(1, 99),
	);
	$self->cfgParamAdd(
		'ignore_pseudofs',
		1,
		'Ignore pseudo filesystem mounts?',
		$self->validate_bool()
	);
	$self->cfgParamAdd(
		'ignore_remote',
		0,
		'Ignore network/remote filesystem mounts?',
		$self->validate_bool()
	);
	$self->cfgParamAdd(
		'thresholds',
		'',
		'Per mountpoint usage threshold settings. Syntax: <mountpoint>=<threshold>[,...] Example: /mnt=88,/var=90',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'thresholds_warn',
		'',
		'Per mountpoint usage threshold warning settings. Syntax: <mountpoint>=<threshold>[,...] Example: /mnt=88,/var=90',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'ithresholds',
		'',
		'Per mountpoint inode threshold settings. Syntax: <mountpoint>=<threshold>[,...] Example: /mnt=75,/var=67',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'ithresholds_warn',
		'',
		'Per mountpoint inode warning threshold settings. Syntax: <mountpoint>=<threshold>[,...] Example: /mnt=75,/var=67',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'ignored',
		'',
		'Ignore specified filesystem mounts. Syntax: <mountpoint>[, ...] Example: /var,/opt',
		$self->validate_str(1024),
	);

	return 1;
}

sub check {
	my ($self) = @_;

	# get data...
	my $data = $self->getUsageData();
	return 0 unless ($data);
	
	my $res = CHECK_OK;
	my $err = '';
	my $warn = '';
	
	# write nice summary of data to buf.
	$self->bufApp($self->usageDataAsStr($data));

	# check gathered data...
	foreach my $d (@{$data}) {
		my $dev = $d->{device};
		my $mntpoint = $d->{mntpoint};
		next unless (defined $mntpoint && length($mntpoint));
		
		# get usage threshold for this mountpoint
		my $t_usage = $self->getThreshold($mntpoint);
		my $t_usage_warn = $self->getThresholdWarn($mntpoint);
		my $t_inode = $self->getThresholdInode($mntpoint);
		my $t_inode_warn = $self->getThresholdInodeWarn($mntpoint);
		
		my $err_prefix = "Device $dev, directory $mntpoint: ";
		
		# check usage (bytes) threshold
		if ($t_usage_warn > 0 && exists($d->{kb_used_percent}) && $d->{kb_used_percent} > $t_usage_warn) {
			$warn .= $err_prefix .
					"Disk space usage of " .
					"$d->{kb_used_percent}% exceeds warning threshold of $t_usage_warn%.\n";
			$res = CHECK_WARN unless ($res == CHECK_ERR);
		}
		if ($t_usage > 0 && exists($d->{kb_used_percent}) && $d->{kb_used_percent} > $t_usage) {
			$err .= $err_prefix .
					"Disk space usage of " .
					"$d->{kb_used_percent}% exceeds threshold of $t_usage%.\n";
			$res = CHECK_ERR;
		}
		
		# check inode usage threshold
		if ($t_inode_warn > 0 && exists($d->{inode_used_percent}) && $d->{inode_used_percent} > $t_inode_warn) {
			$warn .= $err_prefix .
					"Inode usage of " .
					"$d->{inode_used_percent}% exceeds warning threshold of $t_inode_warn%.\n";
			$res = CHECK_WARN unless ($res == CHECK_ERR);
		}
		if ($t_inode > 0 && exists($d->{inode_used_percent}) && $d->{inode_used_percent} > $t_inode) {
			$err .= $err_prefix .
					"Inode usage of " .
					"$d->{inode_used_percent}% exceeds threshold of $t_inode%.\n";
			$res = CHECK_ERR;
		}
	}

	if (length $warn) {
		$warn =~ s/\s+$//gm;
		$self->warning($warn);
	}	
	if (length $err) {
		$err =~ s/\s+$//gm;
		$self->error($err);
	}
	return $res;
}

=head2 getThreshold ($mountpoint)

Returns disk space usage threshold in % for specified mounpoint.

=cut
sub getThreshold {
	my ($self, $mnt) = @_;
	return 0 unless (defined $mnt && length($mnt));
	
	# check per-mountpoint usage thresholds
	foreach my $e (split(/\s*[,;]+\s*/, $self->{thresholds})) {
		my ($dir, $t) = split(/\s*=+\s*/, $e, 2);
		$dir =~ s/^\s+//g;
		$dir =~ s/\s+$//g;
		# convert threshold to integer
		{ no warnings; $t = abs(int($t)); $t = 99 if ($t > 99) }
		
		return $t if ($dir eq $mnt);
	}
	
	# return default threshold
	return $self->{usage_threshold};
}

sub getThresholdWarn {
	my ($self, $mnt) = @_;
	return 0 unless (defined $mnt && length($mnt));
	
	# check per-mountpoint usage thresholds
	foreach my $e (split(/\s*[,;]+\s*/, $self->{thresholds_warn})) {
		my ($dir, $t) = split(/\s*=+\s*/, $e, 2);
		$dir =~ s/^\s+//g;
		$dir =~ s/\s+$//g;
		# convert threshold to integer
		{ no warnings; $t = abs(int($t)); $t = 99 if ($t > 99) }
		return $t if ($dir eq $mnt);
	}
	
	# return default threshold
	return $self->{usage_threshold_warn};
}

=head2 getThresholdInode ($mountpoint)

Returns inode usage threshold in % for specified mounpoint.

=cut
sub getThresholdInode {
	my ($self, $mnt) = @_;
	return 0 unless (defined $mnt && length($mnt));

	# check per-mountpoint usage thresholds
	foreach my $e (split(/\s*[,;]+\s*/, $self->{ithresholds})) {
		my ($dir, $t) = split(/\s*=+\s*/, $e, 2);
		$dir =~ s/^\s+//g;
		$dir =~ s/\s+$//g;
		# convert threshold to integer
		{ no warnings; $t = abs(int($t)); $t = 99 if ($t > 99) }
		
		return $t if ($dir eq $mnt);
	}

	# return default threshold
	return $self->{inode_threshold};
}

sub getThresholdInodeWarn {
	my ($self, $mnt) = @_;
	return 0 unless (defined $mnt && length($mnt));

	# check per-mountpoint usage thresholds
	foreach my $e (split(/\s*[,;]+\s*/, $self->{ithresholds_warn})) {
		my ($dir, $t) = split(/\s*=+\s*/, $e, 2);
		$dir =~ s/^\s+//g;
		$dir =~ s/\s+$//g;
		# convert threshold to integer
		{ no warnings; $t = abs(int($t)); $t = 99 if ($t > 99) }
		
		return $t if ($dir eq $mnt);
	}

	# return default threshold
	return $self->{inode_threshold_warn};
}

=head2 usageDataAsStr ($data)

Returns nice string representation of data returned by B<getUsageData()>
method.

=cut
sub usageDataAsStr {
	my ($self, $data) = @_;
	return '' unless (defined $data && ref($data) eq 'ARRAY');
	
	my $str = '';
	my $fmt = "%-30.30s%-30.30s%-6.6s%-6.6s%-15.15s%-15.15s%-15.15s%-15.15s\n";
	
	# header
	$str .= sprintf(
		$fmt,
		qw(
			device mountpoint
			use% iuse%
			capacityGB usedGB freeGB
			inodeFree
		)
	);

	# sort devices on their disk space usages
	foreach (sort { $b->{kb_used_percent} <=> $a->{kb_used_percent} } @{$data}) {
		no warnings;
		my $e = $_;
		my $dev = $e->{device};
		my $total_gb = sprintf("%-.1f", ($e->{kb_total} / MB));
		my $used_gb = sprintf("%-.1f", ($e->{kb_used} / MB));
		my $free_gb = sprintf("%-.1f", ($e->{kb_free} / MB));
		my $used_percent = sprintf("%-.1f", $e->{kb_used_percent});
		my $i_used_percent = sprintf("%-.1f", $e->{inode_used_percent});
		my $i_free = sprintf("%d", $e->{inode_free});

		$str .= sprintf(
			$fmt,
			$dev,
			$e->{mntpoint},
			$used_percent,
			$i_used_percent,
			$total_gb,
			$used_gb,
			$free_gb,
			$i_free,
		);
	}
	
	return $str;
}

=head2 getUsageData ()

Returns filesystem usage data (including inode usage) as array reference on success,
otherwise undef.

Example result:

 [
  {
  	'device' => '/dev/sda3',
    'inode_free' => '17942617',
    'inode_total' => '18219008',
    'inode_used' => '276391',
    'inode_used_percent' => '2',
    'kb_free' => '140320',
    'kb_total' => '280194',
    'kb_used' => '125642',
    'kb_used_percent' => '48',
    'mntpoint' => '/export'
  },
  {
  	'device' => '/dev/sda1',
    'inode_free' => '702883',
    'inode_total' => '983040',
    'inode_used' => '280157',
    'inode_used_percent' => '29',
    'kb_free' => '7031',
    'kb_total' => '15119',
    'kb_used' => '7321',
    'kb_used_percent' => '52',
    'mntpoint' => '/'
  },
 ]

=cut
sub getUsageData {
	my ($self) = @_;
	my $data_bytes = $self->getUsageInfo();
	return undef unless ($data_bytes);
	
	my $data_inode = $self->getInodeInfo();
	return undef unless ($data_bytes);
	
	# merge arrays
	my $result = [];
	
	foreach my $e (@{$data_bytes}) {
		my $mntpoint = $e->{mntpoint};
		my $dev = $e->{device};
		
		# find matching entry in inode data
		foreach my $i (@{$data_inode}) {
			if (exists($i->{mntpoint}) && $i->{mntpoint} eq $mntpoint) {
				# copy inode_* keys from inode data...
				foreach (keys %{$i}) {
					next unless ($_ =~ m/^inode_/);
					$e->{$_} = $i->{$_};
				}
				last;
			}
		}
		
		push(@{$result}, $e);
	}
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN COMPLETE USAGE DATA ---");
		$self->bufApp($self->dumpVar($result));
		$self->bufApp("--- END COMPLETE USAGE DATA ---");
	}
	
	return $result;
}

=head2 getInodeInfo ()

Returns array reference containing inode data on success, otherwise undef. This
method honours all 'ignore*' configuration properties and returns only non-ignored
filesystem/device objects.

Sample output:

 [
    # data for device: /dev/sda1
    {
      'device' => '/dev/sda1',
      'inodes_free' => '25854',
      'inodes_num' => '25896',
      'inodes_used' => '42',
      'inodes_used_percent' => '1',
      'mntpoint' => '/boot',
    },
 
    # data for device: /dev/sda3
    '/dev/sda3' => {
      'device' => '/dev/sda3',
      'inodes_free' => '25854',
      'inodes_num' => '25896',
      'inodes_used' => '42',
      'inodes_used_percent' => '1',
      'mntpoint' => '/var/tmp',
    },
 ]

=cut
sub getInodeInfo {
	my ($self) = @_;
	my $cmd = $self->getInodeInfoCmd();
	return undef unless ($cmd);
	
	my ($data, $exit_code) = $self->qx2($cmd);
	unless (defined $data && ref($data) eq 'ARRAY' && defined $exit_code && $exit_code == 0) {
		return undef;
	}

	my $result = $self->_parseInodeInfo($data);
	return undef unless ($result);
	
	my $r = [];
	
	# remove ignored storage devices
	foreach my $e (@{$result}) {
		my $dev = $e->{device};
		if ($self->{ignore_pseudofs} && $self->isPseudoFs($dev)) {
			next
		}
		elsif ($self->{ignore_remote} && $self->isRemoteFs($dev)) {
			next;
		}
		push(@{$r}, $e);
	}
	
	@{$result} = @{$r};
	$r = [];
	
	# remove ignored filesystem mounts
	foreach my $e (@{$result}) {
		my $mntpoint = $e->{mntpoint};
		next if ($self->isIgnoredFs($mntpoint));
		push(@{$r}, $e);
	}
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN INODE DATA ---");
		$self->bufApp($self->dumpVar($r));
		$self->bufApp("--- END INODE DATA ---");
	}
	
	return $r;
}

=head2 getUsageInfo ()

Returns arry reference containing usage (in megabytes) data on success, otherwise undef. This
method honours all 'ignore*' configuration properties and returns only non-ignored
filesystem/device objects.

Sample output:

 [
  {
  	'device' => '/dev/sda3',
    'mb_free' => '140320',
    'mb_total' => '280194',
    'mb_used' => '125641',
    'mb_used_percent' => '48',
    'mntpoint' => '/export'
  },
  {
  	'device' => '/dev/sda1',
    'mb_free' => '7031',
    'mb_total' => '15119',
    'mb_used' => '7321',
    'mb_used_percent' => '52',
    'mntpoint' => '/'
  }
 ]
=cut
sub getUsageInfo {
	my ($self) = @_;

	my $cmd = $self->getUsageInfoCmd();
	return undef unless ($cmd);
	
	my ($data, $exit_code) = $self->qx2($cmd);
	unless (defined $data && ref($data) eq 'ARRAY' && defined $exit_code && $exit_code == 0) {
		return undef;
	}

	my $result = $self->_parseUsageInfo($data);
	return undef unless ($result);
	
	my $r = [];
	
	# remove ignored storage devices
	foreach my $e (@{$result}) {
		my $dev = $e->{device};
		if ($self->{ignore_pseudofs} && $self->isPseudoFs($dev)) {
			next
		}
		elsif ($self->{ignore_remote} && $self->isRemoteFs($dev)) {
			next
		}
		push(@{$r}, $e);
	}
	@{$result} = @{$r};
	$r = [];
	
	# remove ignored filesystem mounts
	foreach my $e (@{$result}) {
		my $mntpoint = $e->{mntpoint};
		next if ($self->isIgnoredFs($mntpoint));
		push(@{$r}, $e);
	}
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN STORAGE DATA ---");
		$self->bufApp($self->dumpVar($r));
		$self->bufApp("--- END STORAGE DATA ---");
	}
	
	return $r;
}

=head2 isRemoteFs ($device)

Returns 1 if specified device looks like remote filesystem
device, otherwise 0.

=cut
sub isRemoteFs {
	my ($self, $dev) = @_;
	return 0 unless (defined $dev && length($dev));
	
	# cifs mount: //host/share
	# nfs  mount: host.example.com:/path
	return 1 if ($dev =~ m/^\/\// || $dev =~ m/^[a-z].*:\//);

	# this is not remote filesystem...
	return 0;
}

=head2 isIgnoredFs ($mountpoint)

Returns 1 if check configuration marks specified mountpoint
as ignored.

=cut
sub isIgnoredFs {
	my ($self, $fs) = @_;
	return 0 unless (defined $fs && length($fs));
	return 0 unless (defined $self->{ignored} && length($self->{ignored}));
	
	foreach my $e (split(/\s*[;,]+\s*/, $self->{ignored})) {
		return 1 if ($fs eq $e);
	}
	
	return 0;
}

=head2 isPseudoFs ($device)

Returns 1 if specified device looks like pseudo filesystem
device, otherwise 0.

=cut
sub isPseudoFs {
	my ($self, $device) = @_;
	return 0;
}

=head2 getInodeInfoCmd ()

Returns command that should be run to gather mounted
filesystem inode usage.

=cut
sub getInodeInfoCmd {
	my $self = shift;
	die 'Not implemented in ' . ref($self) . ' class.';
}

=head2 getUsageInfoCmd ()

Returns command that should be run to gather mounted
filesystem diskspace usage.

=cut
sub getUsageInfoCmd {
	my $self = shift;
	die 'Not implemented in ' . ref($self) . ' class.';
}

sub VERSION {
	return $VERSION;
}

##################################################
#              PRIVATE METHODS                   #
##################################################

sub _parseInodeInfo {
	my ($self, $data) = @_;
	unless (defined $data && ref($data) eq 'ARRAY') {
		$self->error("Invalid data: not a arrayref.");
		return undef;
	}

	# remove header if necessary...
	if (@{$data} && $data->[0] =~ m/^\s*filesystem\s+/i) {
		shift(@{$data});
	}
	
	my $res = [];

	while (defined (my $line = shift(@{$data}))) {
		my ($dev, $inodes, $used, $free, $use_percent, @mnt) = split(/\s+/, $line);
		my $mntpoint = join(' ', @mnt);
		$use_percent =~ s/%+//g;
		
		# do it...
		push(
			@{$res},
			{
				device => $dev,
				mntpoint => $mntpoint,
				inode_total => $inodes,
				inode_used => $used,
				inode_free => $free,
				inode_used_percent => $use_percent,
			}
		);
	}
	
	return $res;
}

sub _parseUsageInfo {
	my ($self, $data) = @_;
	unless (defined $data && ref($data) eq 'ARRAY') {
		$self->error("Invalid data: not a arrayref.");
		return undef;
	}

	# remove header if necessary...
	if (@{$data} && $data->[0] =~ m/^\s*filesystem\s+/i) {
		shift(@{$data});
	}

	# parse content...
	my $res = [];
	while (defined (my $line = shift(@{$data}))) {
		my ($dev, $total, $used, $free, $used_percent, @mnt) = split(/\s+/, $line);
		my $mntpoint = join(' ', @mnt);
		next unless (defined $mntpoint && length($mntpoint));
		
		$used_percent =~ s/%+//g;
		push(
			@{$res},
			{
				device => $dev,
				mntpoint => $mntpoint,
				kb_total => $total,
				kb_used => $used,
				kb_free => $free,
				kb_used_percent => $used_percent,
			}
		);
	}
	
	return $res;
}

=head2 AUTHOR

Uros Golja, Brane F. Gracnar

=head2 SEE ALSO

L<P9::AA::Check::FSUsage>
L<P9::AA::Check::FSUsage::LINUX>
L<P9::AA::Check::FSUsage::BSD>
L<P9::AA::Check::FSUsage::FREEBSD>
L<P9::AA::Check::FSUsage::OPENBSD>
L<P9::AA::Check::FSUsage::NETBSD>
L<P9::AA::Check::FSUsage::SUNOS>

=cut

1;