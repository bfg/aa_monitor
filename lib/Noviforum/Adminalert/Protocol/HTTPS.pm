package Noviforum::Adminalert::Protocol::HTTPS;

# $Id: HTTPS.pm 2326 2011-02-11 20:56:42Z bfg $
# $Date: 2011-02-11 21:56:42 +0100 (Fri, 11 Feb 2011) $
# $Author: bfg $
# $Revision: 2326 $
# $LastChangedRevision: 2326 $
# $LastChangedBy: bfg $
# $LastChangedDate: 2011-02-11 21:56:42 +0100 (Fri, 11 Feb 2011) $
# $URL: https://svn.interseek.com/repositories/admin/aa_monitor/trunk/lib/Noviforum/Adminalert/Protocol/HTTPS.pm $

use strict;
use warnings;

use IO::Socket::SSL;

use Noviforum::Adminalert::Protocol::HTTP;

use vars qw(@ISA);
@ISA = qw(Noviforum::Adminalert::Protocol::HTTP);

my $log = Noviforum::Adminalert::Log->new();

=head1 NAME

HTTP protocol implementation.

=head1 DESCRIPTION

L<Noviforum::Adminalert::Protocol::HTTPS> is limited HTTP/1.1 SSL (SSLv3/TLSv1) implementation of 
L<Noviforum::Adminalert::Protocol> interface.

=head1 METHODS

L<Noviforum::Adminalert::Protocol::HTTPS> inherits all methods from 
L<Noviforum::Adminalert::Protocol::HTTP> and implements the following methods:

=head1 process

 $protocol->process($socket, undef [, $start_time = time()])

Processes connection.

=cut
sub process {
	my $self = shift;
	my $sock = shift;
	
	# get configuration singleton
	my $cfg = Noviforum::Adminalert::Config->new();

	$log->debug('Upgrading plain socket to SSL socket.');
	my $s = IO::Socket::SSL->start_SSL(
		$sock,
		SSL_server => 1,
		SSL_version => 'tlsv1',
		SSL_cipher_list => 'HIGH',
		SSL_cert_file => $cfg->get('ssl_cert_file'),
		SSL_key_file => $cfg->get('ssl_key_file'),
		SSL_ca_file => $cfg->get('ssl_ca_file'),
		SL_ca_path => $cfg->get('ssl_ca_path'),
		SSL_verify_mode => $cfg->get('ssl_verify_mode'),
		SSL_crl_file => $cfg->get('ssl_crl_file'),
		SSL_check_crl => (defined($cfg->get('ssl_crl_file')) && length($cfg->get('ssl_crl_file')) > 0) ? 1 : 0,
	);

	# SSL handshake failed?
	unless ($s) {
		# send bad response...
		$self->badResponse(
			$sock,
			400,
			'This site requires SSL/TLS encrypted session; ' .
			'Piss off :P'			
		);
		$self->error("Error sslifying plain socket: " . IO::Socket::SSL::errstr());
		return 0;
	}
	$log->debug(
		"Successfully sslfied plain socket; " .
		"used cipher: " . $s->get_cipher()
	);
	
	# normally process connection as it would be a plain
	# connection
	return $self->SUPER::process($s, @_);
}

sub parse {
	my ($self, $fd) = @_;
	my $req = $self->SUPER::parse($fd);
	
	# inject SSL headers
	if (defined $req) {
		$req->header('X-SSL', 'on');
		$req->header('X-SSL-Cipher', $fd->get_cipher());

		# client certificate info
		foreach (qw(cn subject issuer)) {
			my $v = $fd->peer_certificate($_);
			next unless (defined $v && length($v) > 0);
			$req->header('X-SSL-Peer-' . ucfirst($_), $v);
		}
	}
	return $req;
}

=head1 SEE ALSO

This protocol implementation is based on L<Noviforum::Adminalert::Protocol::HTTP> and L<IO::Socket::SSL>.

=head1 AUTHOR

Brane F. Gracnar

=cut

1;