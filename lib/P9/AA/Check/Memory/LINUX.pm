package P9::AA::Check::Memory::LINUX;

use strict;
use warnings;

use base 'P9::AA::Check::Memory';

sub getMemoryUsageCmd {
	return 'free -m';
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
		memory => {
			total => 0,
			used => 0,
			free => 0,
			shared => 0,
			buffers => 0,
			cached => 0,
		},
		swap => {
			total => 0,
			used => 0,
			free => 0,
		}
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
			$res->{memory}->{total} = shift(@tmp);
			$res->{memory}->{used} = shift(@tmp);
			$res->{memory}->{free} = shift(@tmp);
			$res->{memory}->{shared} = shift(@tmp);
			$res->{memory}->{buffers} = shift(@tmp);
			$res->{memory}->{cached} = shift(@tmp);
		}
		# swap?
		elsif ($line =~ m/^swap:/i) {
			my @tmp = split(/\s+/, $line);
			shift(@tmp);
			$res->{swap}->{total} = shift(@tmp);
			$res->{swap}->{used} = shift(@tmp);
			$res->{swap}->{free} = shift(@tmp);			
		}
	}

	return $res;
}

1;