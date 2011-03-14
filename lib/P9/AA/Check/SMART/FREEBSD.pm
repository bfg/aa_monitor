package P9::AA::Check::SMART::FREEBSD;

use strict;
use warnings;

use base 'P9::AA::Check::SMART';

=head1 NAME

Generic *BSD implementation of SMART disk health check monitoring module.

=cut

sub getDeviceGlobPatterns {
	return [ '/dev/{ad,da}?' ];
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<P9::AA::Check::SMART>
L<P9::AA::Check>

=cut

1;