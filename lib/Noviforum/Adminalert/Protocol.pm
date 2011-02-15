package Noviforum::Adminalert::Protocol;

use strict;
use warnings;

use Time::HiRes qw(time);
use Scalar::Util qw(blessed);

use Noviforum::Adminalert::Constants qw(:all);
use base 'Noviforum::Adminalert::Base';

=head1 NAME

Abstract protocol implementation.

=head1 DESCRIPTION

L<Noviforum::Adminalert::Protocol> is abstract communication protocol class which inherits all
methods from L<Noviforum::Adminalert::Base>.

=head1 METHODS

=head2 process

 $protocol->process($input, $output [, $start_time = time()]);

B<WARNING>: This is abstract method which B<MUST> be implemented by
the actual protocol implementation

=cut
sub process {
	my ($self, $input, $output, $ts) = @_;
	$self->error("Method process() is not implemented by " . ref($self) . " class.");
	return 0;
}

=head2 peeraddr

 my $remote_addr_port = $protocol->peeraddr($tcp_socket);
 my $unix_socket_path = $protocol->peeraddr($unix_domain_socket);
 my $fh_fileno = $protocol->peeraddr($fh);

Returns string representation of "connected" client. Returns non-empty string
if client can be identified somehow, otherwise empty string.

=cut
sub peeraddr {
	my ($self, $fd) = @_;

	my $r = '';
	if (blessed($fd)) {
		if ($fd->isa('IO::Socket::UNIX')) {
			$r = $fd->hostpath();
		}
		elsif ($fd->isa('IO::Socket')) {
			$r = '[' . $fd->peerhost() . ']:' . $fd->peerport();
		}
	}
	else {
		$r = '';
		eval { no warnings; $r = fileno($fd) };
	}

	return $r;
}

=head2 getRenderer

 my $html_renderer = $protocol->getRenderer('HTML');
 my $json_renderer = $protocol->getRenderer('JSON');

Returns initialized L<Noviforum::Adminalert::Renderer> object on success, otherwise undef.

=cut
sub getRenderer {
	my ($self, $type) = @_;
	#$type = 'PLAIN' unless (defined $type && length($type) > 0);
	#$type = 'PLAIN' if (lc($type) eq 'text');
	$type = uc($type) if (defined $type);
	
	# try to load renderer class
	local $@;
	eval "use " . CLASS_RENDERER . "; 1";
	die $@ if ($@);

	# try to create renderer
	my $obj = CLASS_RENDERER->factory($type);
	unless (defined $obj) {
		$self->error(
			"Unable to create renderer $type: " .
			CLASS_RENDERER->error()
		);
	}

	return $obj;
}

=head1 SEE ALSO

=over 4

=item *

L<Noviforum::Adminalert::Protocol::HTTP> HTTP protocol implementation

=item *

L<Noviforum::Adminalert::Protocol::HTTPS> HTTP protocol implementation

=item *

L<Noviforum::Adminalert::Protocol::FCGI> FastCGI protocol implementation

=item *

L<Noviforum::Adminalert::Protocol::CGI> CGI protocol implementation

=item *

L<Noviforum::Adminalert::Protocol::CMDL> Command line "protocol" implementation

=item *

L<Noviforum::Adminalert::Protocol::Renderer> Abstract data renderer

=back


=head1 AUTHOR

Brane F. Gracnar

=cut

1;

# EOF