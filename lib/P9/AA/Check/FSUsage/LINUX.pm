package P9::AA::Check::FSUsage::LINUX;

use strict;
use warnings;

use base 'P9::AA::Check::FSUsage';

=head1 NAME

Linux implementation of L<P9::AA::Check::FSUsage> checking module

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