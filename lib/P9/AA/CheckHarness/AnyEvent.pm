package P9::AA::CheckHarness::AnyEvent;

use strict;
use warnings;

use AnyEvent;

use base 'P9::AA::CheckHarness';

=head1 NAME

Asynchronous L<P9::AA::CheckHarness> class implementation based on L<AnyEvent>.

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

L<P9::AA::CheckHarness>, L<AnyEvent>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;