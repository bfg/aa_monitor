package P9::AA::Check::Mount::LINUX;

use strict;
use warnings;

use IO::File;

use base 'P9::AA::Check::Mount';

use constant PROC_MOUNTS => '/proc/mounts';

=head1 NAME

Linux implementation of L<P9::AA::Check::Mount> checking module

=cut

sub getFstabData {
	my ($self) = @_;
	return $self->_parseFstab('/etc/fstab');
}

sub getMountData {
	my ($self) = @_;
	
	# is /proc available?
	#if (-f PROC_MOUNTS && -r PROC_MOUNTS) {
	#	$self->bufApp("Using proc(5) interface [" . PROC_MOUNTS . "].");
	#	return $self->_parseFstab(PROC_MOUNTS);
	#}

	# nope, we should run mount command...
	my $cmd = $self->getMountCmd();
	return undef unless (defined $cmd);	
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

sub _parseFstab {
	my ($self, $file) = @_;
	if ($self->{debug}) {
		$self->bufApp("Parsing fstab file: $file");
	}
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
		next if ($mntpoint eq 'swap' || $mntpoint eq 'none');
		next if ($dev eq 'devpts');
		next if ($opt =~ m/noauto/);
		
		# LABEL/UUID support...
		if ($dev =~ m/^((UUID|LABEL)=[^\s]+)$/i) {
			my $real_dev = $self->qx2("findfs $dev")->[0];
			if (defined $real_dev && length $real_dev > 0) {
				$real_dev =~ s/\s+$//g;
				$self->log_debug("LABEL/UUID '$dev' resolved to '$real_dev'.");
				# rename "dev"
				$dev = $real_dev;
			}
		}
		
		push(@{$r}, [ $dev, $mntpoint ]);
	}

	return $r;
}

=head1 AUTHOR

Brane F. Gracnar

=cut
1;