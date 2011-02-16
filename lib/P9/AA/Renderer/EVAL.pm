package P9::AA::Renderer::EVAL;

use strict;
use warnings;

use P9::AA::Util;

use base 'P9::AA::Renderer';

our $VERSION = 0.10;

=head1 NAME

Perl eval output renderer.

=cut

sub render {
	my ($self, $data, $resp) = @_;
	
	my $u = P9::AA::Util->new();

	# set headers
	$self->setHeader($resp, 'Content-Type', 'text/plain; charset=utf-8');
	
	return $u->dumpVar($data);
}

=head1 SEE ALSO

L<P9::AA::Renderer>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;
# EOF