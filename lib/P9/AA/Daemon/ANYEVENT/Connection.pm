package P9::AA::Daemon::ANYEVENT::Connection;

use strict;
use warnings;

use AnyEvent::Handle;
use AnyEvent::Socket;

use AnyEvent::HTTPD::Request;

use P9::AA::Config;

use base 'AnyEvent::HTTPD::HTTPConnection';

# do we have SSL support?
my $_has_ssl = undef;
my $cfg = P9::AA::Config->new();
my $log = P9::AA::Log->new();

# SSL context
my $_tls_ctx = undef;

sub new {
	my $this  = shift;
	my $class = ref($this) || $this;
	my $self  = {@_};
	bless $self, $class;

	$self->{request_timeout} = 5 unless defined $self->{request_timeout};
	
	my $proto = $cfg->get('protocol');
	my $tls = (defined $proto && lc($proto) eq 'https') ? 1 : 0;
	my $ctx = ($tls) ? $self->getTLSctx() : undef;

	$self->{hdl} = AnyEvent::Handle->new(
		fh       => $self->{fh},
		on_eof   => sub { $self->do_disconnect() },
		on_error => sub { $self->do_disconnect() },
		tls => ($tls) ? 'accept' : undef,
		tls_ctx => $ctx,
		on_starttls => ($tls) ? sub { _on_starttls($self, @_) } : undef,
	);

	$self->push_header_line;

	return $self;
}

sub _on_starttls {
	my ($self, $handle, $success, $err) = @_;
	unless ($success) {
		my $addr = '[' .
			((exists $self->{host} && defined $self->{host}) ? $self->{host} : 'unknown_peer') .
			']:' .
			(($self->{port} && defined ($self->{port})) ? $self->{port} : '0')
			;
		$log->error("Client $addr TLS error: $err");
		$self->do_disconnect();
	}
}

sub hasSSL {
	return $_has_ssl if (defined $_has_ssl);
	# try to load TLS support class
	local $@;
	eval "use AnyEvent::TLS; 1";
	$_has_ssl = ($@) ? 0 : 1;
	return $_has_ssl;
}

sub getTLSctx {
	my ($self) = @_;
	return $_tls_ctx if (defined $_tls_ctx);
	
	my $ctx = $self->createTLSctx(
		ssl_cert_file => $cfg->get('ssl_cert_file'),
		ssl_key_file => $cfg->get('ssl_key_file'),
		ssl_ca_file => $cfg->get('ssl_ca_file'),
		ssl_ca_path => $cfg->get('ssl_ca_path'),
		ssl_verify_mode => $cfg->get('ssl_verify_mode'),
		ssl_crl_file => $cfg->get('ssl_crl_file'),
	);

	$_tls_ctx = $ctx;
	return $_tls_ctx;
}

sub createTLSctx {
	my ($self, %opt) = @_;

	return undef unless ($self->hasSSL());

	my $cert = delete $opt{'ssl_cert_file'};
	my $key = delete $opt{'ssl_key_file'};
	my $ca_file = delete $opt{'ssl_ca_file'};
	my $ca_path = delete $opt{'ssl_ca_path'};
	my $verify_mode = delete $opt{'ssl_verify_mode'};
	my $crl_file = delete $opt{'ssl_crl_file'};

	# try to create context...
	my $ctx = AnyEvent::TLS->new(
		method => 'any',
		sslv2 => 0,
		verify => ($verify_mode > 0) ? 1 : 0,
		verify_require_client_cert => ($verify_mode > 1) ? 1 : 0,
		verify_peername => ($verify_mode > 0) ? 'http' : undef,
		verify_client_once => ($verify_mode >= 4) ? 1 : 0,
		ca_file => $ca_file,
		ca_path => $ca_path,
		check_crl => (defined $crl_file) ? $crl_file : undef,
		#cipher_list => 'HIGH',
		
		# my cert
		key_file => $key,
		cert_file => $cert,
	);

	return $ctx
}

1;