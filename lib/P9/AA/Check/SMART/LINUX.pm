package P9::AA::Check::SMART::LINUX;

use strict;
use warnings;

use base 'P9::AA::Check::SMART';

=head1 NAME

Linux implementation of SMART disk health check monitoring module.

=cut

sub getDeviceGlobPatterns {
	return [ '/dev/[hs]d?' ];
}

=head1 AUTHOR

Uros Golja, Brane F. Gracnar

=head1 SEE ALSO

L<P9::AA::Check::SMART>
L<P9::AA::Check>

=cut

1;