package P9::AA::Check::Mount::LINUX;

use strict;
use warnings;

use IO::File;

use base 'P9::AA::Check::Mount';

=head1 NAME

Linux implementation of L<P9::AA::Check::Mount> checking module

=cut

sub getFstabData {
	my ($self) = @_;
	my $file = '/etc/fstab';
	my $fd = IO::File->new($file, 'r');
	unless (defined $fd) {
		$self->error("Unable to open file $file for reading: $!");
		return undef;
	}
	
	my $r = [];
	while (<$fd>) {
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		next if ($_ =~ m/^#/);
		next unless (length($_) > 0);
		my ($dev, $mntpoint, $type, $opt) = split(/\s+/, $_);
		next unless (defined $dev && defined $mntpoint);
		next if ($mntpoint eq 'swap');
		next if ($opt =~ m/noauto/);
		push(@{$r}, [ $dev, $mntpoint ]);
	}

	return $r;
}

sub getMountData {
	my ($self) = @_;
	my $cmd = $self->getMountCmd();
	return undef unless (defined $cmd);
	
	# run command
	my ($buf, $exit_status) = $self->qx2($cmd);
	return $self->parseMountData($buf);
}

sub parseMountData {
	my ($self, $in) = @_;
	my $ref = ref($in);
	unless (defined $in && ($ref eq 'SCALAR' || $ref eq 'ARRAY')) {
		$self->error("Input data must be defined array or scalar reference.");
		return undef;
	}
	
	# get_lines sub
	my $get_lines = ($ref eq 'SCALAR') ?
		sub { split(/[\r\n]+/, ${$in}) }
		:
		sub { @{$in} };

	my $r = [];
	foreach my $line ($get_lines->()) {
		# fusectl on /sys/fs/fuse/connections type fusectl
		if ($line =~ m/^(.+)\s+on\s+(.+)\s+type\s+/i) {
			my $dev = $1;
			my $mntpoint = $2;
			push(@{$r}, [ $dev, $mntpoint ]);
		}
	}

	return $r;
}

=head1 AUTHOR

Brane F. Gracnar

=cut
1;