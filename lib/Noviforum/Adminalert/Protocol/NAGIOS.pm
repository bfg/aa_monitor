package Noviforum::Adminalert::Protocol::NAGIOS;

use strict;
use warnings;

use base 'Noviforum::Adminalert::Protocol::CMDL';

our $VERSION = 0.10;

=head1 NAME

Nagios command line "protocol" implementation.

=head1 METHODS

This class inherits all methods from L<Noviforum::Adminalert::Protocol::CMDL>.

=cut

sub getOutputType { 'NAGIOS' }

=head1 SEE ALSO

L<Noviforum::Adminalert::Protocol::CMDL>, 
L<Noviforum::Adminalert::Protocol>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;