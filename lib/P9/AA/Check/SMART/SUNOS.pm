package P9::AA::Check::SMART::SUNOS;

use strict;
use warnings;

use File::Glob qw(:glob);

use base 'P9::AA::Check::SMART';

our $VERSION = 0.10;

=head1 NAME

Solaris implementation of SMART disk health check monitoring module.

=cut

sub getDeviceGlobPatterns {
	return [ '/dev/rdsk/c?t?d?s?' ];
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<P9::AA::Check::SMART>
L<P9::AA::Check>

=cut

1;