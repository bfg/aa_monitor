package P9::AA::Check::Memory::FREEBSD;

use strict;
use warnings;

use base 'P9::AA::Check::Memory';

use constant MB => 1024 * 1024;

our $VERSION = 0.11;

=head1 NAME

FreeBSD implementation of L<P9::AA::Check::Memory> module.

=head1 METHODS

This module inherits all method from L<P9::AA::Check::Memory>.

=cut

sub getMemoryUsageCmd {
	return '/sbin/sysctl -a';
}

sub getSwapUsageCmd {
	return 'swapinfo -m';
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
	my $res = {
		total => 0,
		used => 0,
		free => 0,
		shared => 0,
		buffers => 0,
		cached => 0,
	};

	my $sysctl = {};
	# parse
	my $i = 0;
	foreach my $line ($get_lines->()) {
		$i++;
		last if ($i > 4000);
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length $line);
		#print "LINE: '$line'";
		
		# parse sysctl value...
		my ($k, $v) = split(/\s*:\s*/, $line, 2);
		next unless (defined $k && defined $v);
		
		if ($k =~ m/^vm\.stats\.vm/ || $k =~ m/^hw\./ || $k =~ m/\.swap/) {
			$sysctl->{$k} = $v;
		}
	}

	my $mem_hw        = _mem_rounded($sysctl->{"hw.physmem"});
	my $mem_phys      = $sysctl->{"hw.physmem"};
	my $mem_all       = $sysctl->{"vm.stats.vm.v_page_count"}      * $sysctl->{"hw.pagesize"};
	my $mem_wire      = $sysctl->{"vm.stats.vm.v_wire_count"}      * $sysctl->{"hw.pagesize"};
	my $mem_active    = $sysctl->{"vm.stats.vm.v_active_count"}    * $sysctl->{"hw.pagesize"};
	my $mem_inactive  = $sysctl->{"vm.stats.vm.v_inactive_count"}  * $sysctl->{"hw.pagesize"};
	my $mem_cache     = $sysctl->{"vm.stats.vm.v_cache_count"}     * $sysctl->{"hw.pagesize"};
	my $mem_free      = $sysctl->{"vm.stats.vm.v_free_count"}      * $sysctl->{"hw.pagesize"};
	
	#   determine logical summary information
	my $mem_total = $mem_hw;
	my $mem_avail = $mem_inactive + $mem_cache + $mem_free;
	my $mem_used  = $mem_total - $mem_avail;

	my $ps = $sysctl->{'hw.pagesize'};
	$res->{total} = int($mem_total / MB);
	$res->{used} = int($mem_used / MB);
	$res->{free} = int($mem_free / MB);
	$res->{shared} = 0;
	$res->{buffers} = 0;
	$res->{cached} = int($mem_cache / MB);

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
	my $total = 0;
	my $used = 0;
	my $free = 0;
	foreach my $line ($get_lines->()) {
		if ($line =~ m/%\s*$/) {
			my (undef, $t, $u, $f) = split(/\s+/, $line);
			$total += $t;
			$used += $u;
			$free += $f;
		}
	}
	
	$res->{total} = $total;
	$res->{used} = $used;
	$res->{free} = $free;
	
	return $res;	
}

sub _mem_rounded {
	my ($mem_size) = @_;
	my $chip_size  = 1;
	my $chip_guess = ($mem_size / 8) - 1;
	while ($chip_guess != 0) {
		$chip_guess >>= 1;
		$chip_size  <<= 1;	
	}
	return 0 unless ($chip_size != 0);
	return (int($mem_size / $chip_size) + 1) * $chip_size;
}

=head1 SEE ALSO

L<P9::AA::Check::Memory>, 
L<P9::AA::Check::Memory::LINUX>,
 
=head1 AUTHOR

Brane F. Gracnar

Module is based on B<freebsd-memory.pl> by Ralf S. Engelschall L<mailto:rse@engelschall.com>,
for more info see: L<http://www.cyberciti.biz/faq/freebsd-command-to-get-ram-information/>

=cut
1;