package Noviforum::Adminalert::CheckHarness::AnyEvent;

use strict;
use warnings;

use AnyEvent;

use base 'Noviforum::Adminalert::CheckHarness';

=head1 NAME

Asynchronous L<Noviforum::Adminalert::CheckHarness> class implementation based on L<AnyEvent>.

=head1 METHODS

=head2 check

Performs acutual check.

 # perform asynchrounous check...
 $harness->check(
 	$module,
 	$params,
 	sub {
 		my ($result) = @_;
 		use Data::Dumper;
 		print "GOT result: ", Dumper($result);
 	}
 );

=cut
sub check {
	die "Currently unimplemented.";
}

=head1 SEE ALSO

L<Noviforum::Adminalert::CheckHarness>, L<AnyEvent>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;