package P9::AA::Check::FSUsage::SUNOS;

use strict;
use warnings;

use base 'P9::AA::Check::FSUsage';

=head1 NAME

Solaris implementation of L<P9::AA::Check::FSUsage> checking module

=cut

sub getInodeInfoCmd {
	return 'df -o i';
}

sub getUsageInfoCmd {
	return 'df -k';
}

sub _parseUsageInfo {
	my ($self, $data) = @_;
	unless (defined $data && ref($data) eq 'ARRAY') {
		$self->error("Invalid data: not a arrayref.");
		return undef;
	}

	# remove header if necessary...
	if ($data->[0] =~ m/^\s*filesystem\s+/i) {
		shift(@{$data});
	}

# $ df -k
# Filesystem            kbytes    used   avail capacity  Mounted on
# /                    1572864000 1157381041 415482959    74%    /
# /dev                 1572864000 1157381041 415482959    74%    /dev
# /lib                 302549886 22039481 277484907     8%    /lib

	my $res = {};
	while (defined (my $line = shift(@{$data}))) {
		my ($dev, $total, $used, undef, undef, @mnt) =
			split(/\s+/, $line);
		my $mntpoint = join(' ', @mnt);
		next unless (defined $mntpoint && length($mntpoint));
		
		# compute missing stuff...
		next unless ($total > 0);
		my $used_percent = int(($used / $total) * 100);
		my $free = $total - $used;
		
		# do it...
		$res->{$dev} = {
			mntpoint => $mntpoint,
			kb_total => $total,
			kb_used => $used,
			kb_free => $free,
			kb_used_percent => $used_percent,
		};
	}
	
	return $res;
}

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

# Filesystem             iused   ifree  %iused  Mounted on
# /dev/md/dsk/d0        481649 13399951     3%   /

	my $res = {};
	while (defined (my $line = shift(@{$data}))) {
		my ($dev, $used, $free, $used_percent, @mnt) = split(/\s+/, $line);
		my $mntpoint = join(' ', @mnt);
		next unless (defined $mntpoint && length($mntpoint));
		my $total = $used + $free;

		# do it...
		$res->{$dev} = {
			mntpoint => $mntpoint,
			inode_total => $total,
			inode_used => $used,
			inode_free => $free,
			inode_used_percent => $used_percent,
		};
	}
	
	return $res;
}

=head1 AUTHOR

Brane F. Gracnar

=cut
1;