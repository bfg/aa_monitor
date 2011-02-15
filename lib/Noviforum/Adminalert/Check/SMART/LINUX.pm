package Noviforum::Adminalert::Check::SMART::LINUX;

use strict;
use warnings;

use base 'Noviforum::Adminalert::Check::SMART';

=head1 NAME

Linux implementation of SMART disk health check monitoring module.

=cut

sub getDeviceGlobPatterns {
	return [ '/dev/[hs]d?' ];
}

=head1 AUTHOR

Uros Golja, Brane F. Gracnar

=head1 SEE ALSO

L<Noviforum::Adminalert::Check::SMART>
L<Noviforum::Adminalert::Check>

=cut

1;