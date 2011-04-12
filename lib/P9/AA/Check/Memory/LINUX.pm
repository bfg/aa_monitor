package P9::AA::Check::Memory::LINUX;

use strict;
use warnings;

use base 'P9::AA::Check::Memory';

our $VERSION = 0.14;

=head1 NAME

Linux implementation of L<P9::AA::Check::Memory> module.

=cut
sub getMemoryUsageCmd {
	return 'free -m';
}

sub getSwapUsageCmd {
	return shift->getMemoryUsageCmd();
}

sub getMemoryUsage {
	my ($self) = @_;
	# memory...
	my ($buf, $s) = $self->qx2($self->getMemoryUsageCmd());
	return undef unless ($buf);

	# parse it...
	my $memory = $self->parseMemoryUsage($buf);
	return undef unless (defined $memory);

	# swap
	my $swap = $self->parseSwapUsage($buf);
	return undef unless (defined $swap);
	
	return { memory => $memory, swap => $swap };	
}

sub parseMemoryUsage {
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

	# result structure...
	my $result = {};

#             total       used       free     shared    buffers     cached
#Mem:          3949       3855         94          0        190       1792
#-/+ buffers/cache:       1871       2077
#Swap:         5711          0       5711

	my $res = {
		total => 0,
		used => 0,
		free => 0,
		shared => 0,
		buffers => 0,
		cached => 0,
	};

	# parse
	my $i = 0;
	foreach my $line ($get_lines->()) {
		$i++;
		last if ($i > 100);
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length $line);
		# memory?
		if ($line =~ m/^mem:/i) {
			my @tmp = split(/\s+/, $line);
			shift(@tmp);
			$res->{total} = shift(@tmp);
			$res->{used} = shift(@tmp);
			$res->{free} = shift(@tmp);
			$res->{shared} = shift(@tmp);
			$res->{buffers} = shift(@tmp);
			$res->{cached} = shift(@tmp);
			last;
		}
	}

	return $res;
}

sub parseSwapUsage {
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

	# result structure...
	my $res = {
		total => 0,
		used => 0,
		free => 0,
	};

	# parse
	my $i = 0;
	foreach my $line ($get_lines->()) {
		$i++;
		if ($line =~ m/^swap:/i) {
			my @tmp = split(/\s+/, $line);
			shift(@tmp);
			$res->{total} = shift(@tmp);
			$res->{used} = shift(@tmp);
			$res->{free} = shift(@tmp);
			last;			
		}
	}
	
	return $res;
}

=head1 AUTHOR

Brane F. Gracnar

=cut

1;