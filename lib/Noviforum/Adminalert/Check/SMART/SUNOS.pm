package Noviforum::Adminalert::Check::SMART::SUNOS;

use strict;
use warnings;

use File::Glob qw(:glob);

use base 'Noviforum::Adminalert::Check::SMART';

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

L<Noviforum::Adminalert::Check::SMART>
L<Noviforum::Adminalert::Check>

=cut

1;