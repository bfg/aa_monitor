package Noviforum::Adminalert::Check::IntelSensors::LINUX;

use strict;
use warnings;

use Noviforum::Adminalert::Util;

use base 'Noviforum::Adminalert::Check::IntelSensors';

our $VERSION = 0.10;

use constant PROGRAM_NAME => 'sensor';

sub getSensorData {
	my ($self) = @_;	
	my $array = [];

	# run sensor command...	
	my $u = Noviforum::Adminalert::Util->new();
	my ($out, $exit_value) = $u->qx2(PROGRAM_NAME . ' -s');
	unless (defined $out && ref($out) eq 'ARRAY') {
		$self->error("Error running sensor command: " . $u->error());
		return undef;
	}
	
	if ($self->{debug}) {
		$self->bufApp("##############################");
		$self->bufApp("# sensor(8) debugging output #");
		$self->bufApp("##############################");
		$self->bufApp();
	}
	
	# read output
	my $header_read = 0;
	foreach (@{$out}) {
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		
		$self->bufApp($_) if ($self->{debug});
		
		# skip header
		unless ($header_read) {
			if (/^-- BMC /) {
				$header_read = 1;
			}
			next;
		}
		next if (/^FRU|IPMB|SDR/);
		
		my @tmp = split(/\: | = |\s{3,}/, $_);
		map { $_ =~ s/\s+$//g; $_ =~ s/^\s+//g; $_ =~ s/^= //g; } @tmp;
		my $num = "";
		
		# post processing
		if ($tmp[1] =~ m/^num ([a-z0-9]+) (.+)/) {
			$num = $1;
			$tmp[1] = $2;
		}
		$tmp[2] =~ s/\*//g;
		my $value = 0;
		if ($tmp[3] && $tmp[3] =~ /^([\d\.]+) /) {
			$value = $1 + 0;
		}
		
		my $struct = {
			type => $tmp[0],
			num => $num,
			name => $tmp[1],
			status => $tmp[2],
			value => $tmp[3],
			value_num => $value
		};

		push(@{$array}, $struct);
	}

	if ($self->{debug}) {
		$self->bufApp("##############################");
		$self->bufApp();
	}
	
	return $array;
}

1;