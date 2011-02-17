package P9::AA::Daemon::ANYEVENT::Request;

use strict;
use warnings;

use AnyEvent::HTTPD::Request;

use base 'AnyEvent::HTTPD::Request';

# The following is stoled from HTTP::Status
my %StatusCode = (
	100 => 'Continue',
	101 => 'Switching Protocols',
	102 => 'Processing',                      # RFC 2518 (WebDAV)
	200 => 'OK',
	201 => 'Created',
	202 => 'Accepted',
	203 => 'Non-Authoritative Information',
	204 => 'No Content',
	205 => 'Reset Content',
	206 => 'Partial Content',
	207 => 'Multi-Status',                    # RFC 2518 (WebDAV)
	300 => 'Multiple Choices',
	301 => 'Moved Permanently',
	302 => 'Found',
	303 => 'See Other',
	304 => 'Not Modified',
	305 => 'Use Proxy',
	307 => 'Temporary Redirect',
	400 => 'Bad Request',
	401 => 'Unauthorized',
	402 => 'Payment Required',
	403 => 'Forbidden',
	404 => 'Not Found',
	405 => 'Method Not Allowed',
	406 => 'Not Acceptable',
	407 => 'Proxy Authentication Required',
	408 => 'Request Timeout',
	409 => 'Conflict',
	410 => 'Gone',
	411 => 'Length Required',
	412 => 'Precondition Failed',
	413 => 'Request Entity Too Large',
	414 => 'Request-URI Too Large',
	415 => 'Unsupported Media Type',
	416 => 'Request Range Not Satisfiable',
	417 => 'Expectation Failed',
	422 => 'Unprocessable Entity',            # RFC 2518 (WebDAV)
	423 => 'Locked',                          # RFC 2518 (WebDAV)
	424 => 'Failed Dependency',               # RFC 2518 (WebDAV)
	425 => 'No code',                         # WebDAV Advanced Collections
	426 => 'Upgrade Required',                # RFC 2817
	449 => 'Retry with',                      # unofficial Microsoft
	500 => 'Internal Server Error',
	501 => 'Not Implemented',
	502 => 'Bad Gateway',
	503 => 'Service Unavailable',
	504 => 'Gateway Timeout',
	505 => 'HTTP Version Not Supported',
	506 => 'Variant Also Negotiates',         # RFC 2295
	507 => 'Insufficient Storage',            # RFC 2518 (WebDAV)
	509 => 'Bandwidth Limit Exceeded',        # unofficial
	510 => 'Not Extended',                    # RFC 2774
);


sub new {
	my $this  = shift;
	my $class = ref($this) || $this;
	my $self  = $class->SUPER::new(@_);

	$self->{_code} = 400;
	$self->{_msg}  = 'Bad Request';

	bless $self, $class;
}

sub header {
	my $self = shift;
	my $name = shift;
	return undef unless (defined $name && length($name));
	$name = lc($name);

	# set header?!
	if (@_) {
		$self->{hdr}->{$name} = join('', @_);
		return 1;
	}

	# return header
	return (exists($self->{hdr}->{$name})) ? $self->{hdr}->{$name} : undef;
}

sub uri { shift->url(@_) }

sub url {
	my ($self) = @_;
	unless ($self->{__host_port_fixed}) {
		my ($host, $port) = split(/\s*:\s*/, $self->{hdr}->{host});
		$self->{url}->host($host) if (defined $host);
		$self->{url}->port($port) if (defined $port);
		$self->{url}->scheme('http');
		$self->{__host_port_fixed} = 1;
	}
	return $self->{url};
}

sub code {
	my ($self, $code) = @_;
	if (defined $code && $code >= 100 && $code < 600) {
		$self->{_code} = $code;
	}

	return $self->{_code};
}

sub req_content {
	my $self = shift;
	return $self->{content};
}

sub decoded_content {
	my $self = shift;
	return $self->{content};
}

my $_server_str = undef;

sub sendResponse {
	my ($self, $code, $body, $headers) = @_;
	# fix status
	$code = 501 unless (defined $code && $code >= 0 && $code <= 512);
	my $status = exists($StatusCode{$code}) ? $StatusCode{$code} : 'Not implemented';
	$body = $code . ' ' . $status unless (defined $body);

	# fix headers
	$headers = {} unless (defined $headers && ref($headers) eq 'HASH');
	unless (exists $headers->{Server} && defined $headers->{Server}) {
		unless (defined $_server_str) {
			$_server_str = main->name() . '/' . main->VERSION();
		}
		$headers->{Server} = $_server_str;
	}
	
	$self->respond([ $code, $status, $headers, $body ]);
}

sub badResponse {
	my ($self, $code, $body) = @_;
	$code = 500 unless (defined $code && $code >= 0 && $code <= 512);
	$self->sendResponse($code, $body);
}

1;