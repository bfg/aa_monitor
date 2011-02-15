package Noviforum::Adminalert::Check::HPRAID::LINUX;

use strict;
use warnings;

use POSIX qw(getcwd);

use base 'Noviforum::Adminalert::Check::HPRAID::_acucli';

=head1 NAME

Linux implementation of L<Noviforum::Adminalert::Check::HPRAID> module

=head1 DESCRIPTION

This module is based on L<Noviforum::Adminalert::Check::HPRAID::_acucli>, which 
requires L<hpacucli(8)> command.

=head1 SEE ALSO

L<Noviforum::Adminalert::Check::HPRAID>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;