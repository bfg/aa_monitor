package P9::AA::Check::FSUsage::BSD;

use strict;
use warnings;

use base 'P9::AA::Check::FSUsage';

=head1 NAME

*BSD (including Mac OS X) implementation of L<P9::AA::Check::FSUsage> checking
module.

=cut

sub getInodeInfoCmd {
	return 'df -i';
}

sub getUsageInfoCmd {
	return 'df -k';
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
	
	my $res = {};

	while (defined (my $line = shift(@{$data}))) {
		# OSX has " " chars in device names? insane!
		next if ($line =~ m/^\s*map\s+/);

		my (
			$dev, undef, undef, undef, undef,
			$used, $free, $used_percent,
			@mnt,
		) = split(/\s+/, $line);

		# remove % chars
		$used_percent =~ s/%+//g;
		my $mntpoint = join(' ', @mnt);
		next unless (defined $mntpoint && length($mntpoint));
		
		# do it...
		$res->{$dev} = {
			mntpoint => $mntpoint,
			inode_total => ($free + $used),
			inode_used => $used,
			inode_free => $free,
			inode_used_percent => $used_percent,
		};
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
	if ($data->[0] =~ m/^\s*filesystem\s+/i) {
		shift(@{$data});
	}
	
	my $res = {};

	while (defined (my $line = shift(@{$data}))) {
		# OSX has " " chars in device names? insane!
		next if ($line =~ m/^\s*map\s+/);
		
		my ($dev, $total, $used, $free, $used_percent, @mnt) =
			split(/\s+/, $line);
		my $mntpoint = join(' ', @mnt);
		next unless (defined $mntpoint && length($mntpoint));
		

		# remove % chars
		$used_percent =~ s/%+//g;
		
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

=head1 AUTHOR

Brane F. Gracnar

=cut
1;