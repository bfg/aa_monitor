package P9::AA::Protocol::NAGIOS;

use strict;
use warnings;

use base 'P9::AA::Protocol::CMDL';

our $VERSION = 0.10;

=head1 NAME

Nagios command line "protocol" implementation.

=head1 METHODS

This class inherits all methods from L<P9::AA::Protocol::CMDL>.

=cut

sub getOutputType { 'NAGIOS' }

=head1 SEE ALSO

L<P9::AA::Protocol::CMDL>, 
L<P9::AA::Protocol>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;