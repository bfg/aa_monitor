package P9::AA::Renderer::STORABLE;

use strict;
use warnings;

use Storable qw(nfreeze);

use base 'P9::AA::Renderer';

our $VERSION = 0.10;

=head1 NAME

L<Storable> output renderer.

=head1 DESCRIPTION

Output is rendered using L<nfreeze|Storable/MEMORY-STORE> function from L<Storable> package.
It can be decoded with B<thaw> Storable function.

=cut

sub render {
	my ($self, $data, $resp) = @_;
	$self->setHeader($resp, 'Content-Type', 'application/octet-stream');
	return nfreeze($data);
}

=head1 SEE ALSO

L<P9::AA::Renderer> L<Storable>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;
# EOF