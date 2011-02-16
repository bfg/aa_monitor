package P9::AA::Check::HPRAID::SUNOS;

use strict;
use warnings;

use POSIX qw(getcwd);

use base 'P9::AA::Check::HPRAID::_acucli';

=head1 NAME

Solaris implementation of L<P9::AA::Check::HPRAID> module

=head1 DESCRIPTION

This module is based on L<P9::AA::Check::HPRAID::_acucli>, which 
requires L<hpacucli(8)> command.

=head1 SEE ALSO

L<P9::AA::Check::HPRAID>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;