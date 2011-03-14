package P9::AA::Check::SMART::OPENBSD;

use strict;
use warnings;

use base 'P9::AA::Check::SMART';

=head1 NAME

OpenBSD implementation of SMART disk health check monitoring module.

=cut

sub getDeviceGlobPatterns {
	return [ '/dev/{w,s,st}d?' ];
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<P9::AA::Check::SMART>
L<P9::AA::Check>

=cut

1;