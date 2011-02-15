package Noviforum::Adminalert::Renderer::EVAL;

use strict;
use warnings;

use Noviforum::Adminalert::Util;

use base 'Noviforum::Adminalert::Renderer';

our $VERSION = 0.10;

=head1 NAME

Perl eval output renderer.

=cut

sub render {
	my ($self, $data, $resp) = @_;
	
	my $u = Noviforum::Adminalert::Util->new();

	# set headers
	$self->setHeader($resp, 'Content-Type', 'text/plain; charset=utf-8');
	
	return $u->dumpVar($data);
}

=head1 SEE ALSO

L<Noviforum::Adminalert::Renderer>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;
# EOF