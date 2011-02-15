package Noviforum::Adminalert::Check::FSUsage::LINUX;

use strict;
use warnings;

use base 'Noviforum::Adminalert::Check::FSUsage';

=head1 NAME

Linux implementation of L<Noviforum::Adminalert::Check::FSUsage> checking module

=cut

sub getInodeInfoCmd {
	return 'df -Pi';
}

sub getUsageInfoCmd {
	return 'df -Pk';
}

=head1 AUTHOR

Brane F. Gracnar

=cut
1;