package Noviforum::Adminalert::Check::MegaSAS::SUNOS;

use strict;
use warnings;

use File::Spec;
use POSIX qw(getcwd);

use base 'Noviforum::Adminalert::Check::MegaSAS::_megacli';

=head1 NAME

Solaris implementation of L<Noviforum::Adminalert::Check::MegaSAS::_megacli> module.

=head1 DESCRIPTION

NOTE: This module requires MegaCli command line utility.

=head1 SEE ALSO

L<Noviforum::Adminalert::Check::MegaSAS::_megacli>, 
L<Noviforum::Adminalert::Check::MegaSAS>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;