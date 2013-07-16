package P9::AA::Check::URL;

use strict;
use warnings;

use URI;
use MIME::Base64;
use HTTP::Request;
use LWP::UserAgent;
use POSIX qw(strftime);
use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

our $VERSION = 0.19;

=head1 NAME

HTTP service checking module and infrastructure.

=head1 METHODS

=cut

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Performs HTTP URL check."
	);

	$self->cfgParamAdd(
		'url',
		'http://localhost/',
		'Full URL address.',
		$self->validate_str(16 * 1024),
	);
	$self->cfgParamAdd(
		'redirects',
		0,
		'Maximum number of allowed redirects.',
		$self->validate_int(0, 10),
	);
	$self->cfgParamAdd(
		qr/^header[\w\-]+/,
		'',
		'[REGEX PARAMETER] Arbitrary http request header. Example: headerHost=www.example.org; headerContent-Type=text/plain.',
		$self->validate_str(4 * 1024)
	);
	$self->cfgParamAdd(
		'username',
		undef,
		'Basic HTTP auth username.',
		$self->validate_str(300),
	);
	$self->cfgParamAdd(
		'password',
		undef,
		'Basic HTTP auth password.',
		$self->validate_str(300),
	);
	$self->cfgParamAdd(
		'user_agent',
		'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.2.13) Gecko/20101203 SUSE/3.6.13-3.1 Firefox/3.6.13',
		'User-Agent definition',
		$self->validate_str(150),
	);
	$self->cfgParamAdd(
		'request_method',
		'GET',
		'HTTP request method.',
		$self->validate_ucstr(6),
	);
	$self->cfgParamAdd(
		'request_body',
		undef,
		'HTTP request body for PUT/POST request methods. HTTP request body is limited to 1MB.',
		$self->validate_str(1024 * 1024),
	);
	$self->cfgParamAdd(
		'timeout',
		2,
		'HTTP request timeout in seconds.',
		$self->validate_int(1),
	);
	$self->cfgParamAdd(
		'proxy_url',
		undef,
		'Proxy address URL',
		$self->validate_str(150),
	);
	$self->cfgParamAdd(
		'content_pattern',
		undef,
		'Apply specified regex pattern on returned response. Syntax: /PATTERN/flags',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'content_pattern_match',
		1,
		'Specifies if regex defined in content_pattern should or should not match',
		$self->validate_bool()
	);
	$self->cfgParamAdd(
		'host_header',
		undef,
		'Specifies custom Host: request header',
		$self->validate_str(100),
	);
	$self->cfgParamAdd(
		'debug_response',
		0,
		'Display response content.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'ssl_verify',
		0,
		'Verify peer\'s SSL certificate',
		$self->validate_bool(),
	);
	
	# remove socket-specific stuff...
	$self->cfgParamRemove('debug_socket');
	$self->cfgParamRemove('timeout_connect');
	
	return 1;
}

sub setParams {
	my $self = shift;
	my $r = $self->SUPER::setParams(@_);

	# be strict about ipv6 usage
	$self->v6Sock($self->{ipv6});

	return $r;
}

sub toString {
	my $self = shift;
	no warnings;
	my $str = $self->{request_method};
	$str .= ' ' . $self->{url};
	my $hh = $self->{host_header} || $self->{headerHost} || undef;
	if (defined $hh && length $hh) {
		$str .= ' host: ' . $hh;
	}

	return $str;
}

sub check {
	my ($self) = @_;

	# create content regex
	my $re = undef;
	if (defined $self->{content_pattern}) {
		my $v = $self->validate_regex();
		$re = $v->($self->{content_pattern});
		unless (defined $re) {
			my $e = $@;
			$e =~ s/\s+at\s+(.*)$//g;
			return $self->error("Error compiling regex: $self->{content_pattern}: $e");
		}
	}
	
	# get request...
	my $req = $self->prepareRequest();
	return CHECK_ERR unless ($req);

	# perform request...
	my $r = $self->httpRequest($req);
	return CHECK_ERR unless (defined $r);

	# HTTP response must be 200-300
	unless($r->is_success()) {
		return $self->error("Bad HTTP response: " . $r->status_line());
	}

	# inspect content?
	if (defined $re) {
		if ($self->{content_pattern_match}) {
			# content should match pattern
			if ($r->decoded_content() !~ $re) {
				return $self->error("Returned content doesn't match regex $re.");
			}
		} else {
			# content shouldn't match pattern
			if ($r->decoded_content() =~ $re) {
				return $self->error("Returned content matches regex $re, but it shouldn't.");
			}
		}		
	}

	return CHECK_OK;
}

=head2 getUa ([$timeout, $proxy_url])

Returns initialized and prepared L<LWP::UserAgent> object on success, otherwise undef.

=cut
sub getUa {
	my ($self, $timeout, $proxy_url) = @_;
	$timeout = $self->{timeout} unless (defined $timeout);
	$timeout = 30 unless (defined $timeout);
	
	# do we need ipv6?
	my $v6 = $self->{ipv6};
	$v6 = 'prefer' unless (defined $v6);
	$v6 = lc($v6);

	if ($v6 ne 'off') {
		if ($v6 eq 'force') {
			return undef unless ($self->setForcedIPv6());
		}
		
		# try to patch socket implementation (ignore result)
		$self->patchSocketImpl();
	}
	
	my $lwp = LWP::UserAgent->new(timeout => $timeout);
	
	# proxy, anyone?
	$proxy_url = $self->{proxy_url} unless (defined $proxy_url && length($proxy_url));

	# ssl hostname validation
	my $ssl_verify = ($self->{ssl_verify}) ? 1 : 0;
	if ($lwp->can('ssl_opts')) {
		$lwp->ssl_opts(verify_hostname => $ssl_verify);
	} else {
		$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = $ssl_verify;
	}

	if (defined $proxy_url && length($proxy_url) > 0) {
		$self->bufApp("Using proxy URL: $proxy_url");
		$lwp->proxy(
			[ 'http', 'https', 'ftp' ],
			$proxy_url
		);
	}
	
	# set max max redirects?
	if (defined $self->{redirects} && $self->{redirects} >= 0) {
		$lwp->max_redirect($self->{redirects});
	}

	return $lwp;
}

=head2 prepareRequest

 # prepare request
 my $req = $self->prepareRequest([ %opt ]);
 unless (defined $req) {
 	print "Error: ", $self->error(), "\n";
 }
 
 # execute request...
 my $res = $self->httpRequest($req);

Returns L<HTTP::Request> object based on object configuration,  otherwise undef. Optional
B<%opt> parameters keys are the same as object configuration.

B<CUSTOM EXAMPLE:>

 my $req = $self->prepareRequest(
 	url => 'http://www.example.com/something',
 	request_method => 'POST',
 	headerHost => 'www.evilhost.com',
 	username => 'user',
 	password => 's3cret',
 );
 
=cut
sub prepareRequest {
	my ($self, %opt)= @_;
	my $o = $self->_getRequestOpt(%opt);
	
	# create uri object just to check URL address validity...
	local $@;
	my $uri = eval { URI->new($o->{url}) };
	if ($@) {
		$self->error("Error creating URI object: $@");
		return undef;
	}
	elsif (! defined $uri) {
		$self->error("Undefined/invalid URL.");
		return undef;
	}
	elsif (blessed($uri) && ! $uri->isa('URI::http')) {
		$self->error("Not a HTTP URL '$o->{url}': " . ref($uri));
		return undef;
	}

	# create new request object...
	my $req = HTTP::Request->new(uc($o->{request_method}), $o->{url});
	
	my $m = lc($req->method());
	
	# apply custom headers...
	foreach my $k (keys %{$o}) {
		if ($k =~ m/^header([\w+\-]+)/) {
			$req->header($1, $o->{$k});
		}
	}

	# add custom Host: header
	if (defined $o->{host_header} && length($o->{host_header})) {
		$req->header("Host", $o->{host_header});
	}

	# set some browser options if necessary
	if (defined $o->{user_agent}) {
		$req->header("User-Agent", $o->{user_agent});
	}

	# authenticated session?
	if (defined $o->{username} && defined $o->{password}) {
		$req->header(
			"Authorization",
			"Basic " . encode_base64($o->{username} . ":" . $o->{password}, ''),
		);
	}
	
	# content-body?
	if ($m eq 'post' || $m eq 'put') {
		if (defined $o->{request_body}) {
			use bytes;
			my $len = length($o->{request_body});
			$req->content($o->{request_body});
			$req->header('Content-Length', $len);
		}
	}
	
	return $req;
}

=head2 httpRequest ($request [, $ua], [ other LWP::UserAgent->request() arguments ])

Performs HTTP request described in $request (must be initialized L<HTTP::Request> object)
using L<LWP::UserAgent>. If $ua is omitted, it will be autocreated.

Returns initialized L<HTTP::Response> object in sending request succeeded, otherwise undef.

B<WARNING:> You still need to inspect returned object to query http response status. 

=cut
sub httpRequest {
	my $self = shift;
	my $req = shift;
	my $ua = shift;
	#my ($self, $req, $ua) = @_;
	unless (blessed($req) && $req->isa('HTTP::Request')) {
		$self->error("Invalid request object");
		return undef;
	}
	unless (blessed($ua) && $ua->isa('LWP::UserAgent')) {
		$ua = $self->getUa();
		return undef unless (defined $ua);
	}
	
	# HTTPS url? Check for availability of IO::Socket::SSL module
	my $url = $req->uri();
	if (defined $url && $url =~ m/^https:\/\//) {
		return undef unless ($self->hasSSL());
	}

	if ($self->{debug}) {
		$self->bufApp("--- BEGIN REQUEST ---");
		$self->bufApp($req->as_string());
		$self->bufApp("--- BEGIN REQUEST ---");
	}
	
	# do the HTTP request...
	my $r = $ua->request($req, @_);

	if ($self->{debug_response}) {
		$self->bufApp();
		$self->bufApp("--- BEGIN RESPONSE ---");
		$self->bufApp($r->as_string());
		$self->bufApp("--- END RESPONSE ---");
	}
	elsif ($self->{debug}) {
		my $hdrs = $r->headers();
		if (defined $hdrs) {
			print "--- BEGIN RESPONSE HEADERS ---";
			print $hdrs->as_string();
			print "---  END RESPONSE HEADERS  ---";
		}
	}

	return $r;
}

=head2 httpGet ($url, ...)

Performs simple GET using default user agent. Returns L<HTTP::Response> object on success,
otherwise undef.

=cut
sub httpGet {
	my ($self, $url, %opt) = @_;
	
	# create request...
	my $req = $self->prepareRequest(
		%opt,
		url => $url,
		request_method => 'GET',
	);
	return undef unless (defined $req);
	return $self->httpRequest($req);
}

sub _getRequestOpt {
	my ($self, %opt) = @_;
	my $r = {};

	foreach (
		'url', 'request_method', 'timeout',
		'request_body', 'username', 'password',
		'host_header', 'user_agent',
	) {
		$r->{$_} = $self->{$_};
		$r->{$_} = $opt{$_} if (exists($opt{$_}));
	}
	
	# custom headers
	foreach (keys %{$self}, %opt) {
		next unless (defined $_ && $_ =~ m/^header.+/);
		$r->{$_} = $self->{$_};
		$r->{$_} = $opt{$_} if (exists($opt{$_}));		
	}

	unless (defined $r->{request_method}) {
		$r->{request_method} = 'GET';
	}

	return $r;
}

=head1 SEE ALSO

L<P9::AA::Check>
L<P9::AA::Check::_Socket>
L<HTTP::Request>
L<HTTP::Response>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;
