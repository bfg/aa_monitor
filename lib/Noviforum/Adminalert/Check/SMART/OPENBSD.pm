package Noviforum::Adminalert::Check::SMART::OPENBSD;

use strict;
use warnings;

use base 'Noviforum::Adminalert::Check::SMART';

=head1 NAME

OpenBSD implementation of SMART disk health check monitoring module.

=cut

sub getDeviceGlobPatterns {
	return [ '/dev/{wd,sd,st}d?' ];
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<Noviforum::Adminalert::Check::SMART>
L<Noviforum::Adminalert::Check>

=cut

1;