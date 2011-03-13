package P9::AA::Protocol::_HTTPCommon;

use strict;
use warnings;

use URI;
use URI::QueryParam;

use HTTP::Status;
use Scalar::Util qw(blessed);

use P9::AA::CheckHarness;
use base 'P9::AA::Protocol';

our $VERSION = 0.10;

my $log = P9::AA::Log->new();

my $_has_json = undef;
my $_has_xml = undef;

sub hasJSON {
	unless (defined $_has_json) {
		$_has_json = eval { require JSON };
	}
	return $_has_json;
}

sub hasXML {
	unless (defined $_has_xml) {
		$_has_xml = eval { require XML::Simple };
	}
	return $_has_xml;
}

sub urldecode {
	shift if ($_[0] eq __PACKAGE__ || (blessed($_[0]) && $_[0]->isa(__PACKAGE__)));
	my ($str) = @_;
	return '' unless (defined $str && length $str);
	$str =~ s/\+/ /g;
	$str =~ s/%([0-9a-hA-H]{2})/pack('C',hex($1))/ge;
	return $str;
}

sub parseJSON {
	my ($self, $data_ref) = @_;
	unless ($self->hasJSON()) {
		$self->error("JSON support is not available.");
		return undef;
	}
	unless (ref($data_ref) eq 'SCALAR') {
		$self->error("JSON string must be passed as scalar reference.");
		return undef;
	}
	
	# create parser...
	my $p = JSON->new();
	$p->utf8(1);
	$p->relaxed(1);

	# decode string...
	my $d = eval { $p->decode(${$data_ref}) };

	if ($@) {
		$self->error("Error parsing JSON input: syntax errror.");
		return undef;
	}
	elsif (ref($d) ne 'HASH') {
		$self->error("Error parsing JSON input: not a hash reference.");
		return undef;
	}

	return $d;	
}

sub parseXML {
	my ($self, $data_ref) = @_;
	unless ($self->hasXML()) {
		$self->error("XML support is not available.");
		return undef;
	}
	
	# create parser object...
	my $p = XML::Simple->new(
	);

	# try to parse
	my $d = eval { $p->parse_string($data_ref) };
	if ($@) {
		$self->error("Error parsing XML: syntax error.");
		return undef;
	}
	elsif (! defined $d || ref($d) ne 'HASH') {
		$self->error("Error parsing XML: parser returned invalid structure.");
		return undef;
	}
	
	
	# TODO: improve xml parsing and figure out correct structure.
	#use Data::Dumper;
	#print "XML: ", Dumper($d), "\n";

	return $d;
}

sub code2CgiStatus {
	my ($self, $code) = @_;
	my $s = status_message($code);
	unless (defined $s && length($s)) {
		$code = 500;
		$s = 'Internal Server Error';
	}
	return $code . ' ' . $s;
}

sub code2str {
	my ($self, $code) = @_;
	my $s = status_message($code);
	unless (defined $s && length($s)) {
		$s = 'Internal Server Error';
	}
	return $s;
}

sub getCheckParams {
	my ($self, $req) = @_;
	$self->error('');

	# we support only few request methods...
	my $method = $req->getReqMethod();
	return undef unless ($self->isSupportedMethod($method));
	
	# always check parameters as if request method
	# would be GET
	my $data = $self->_getCheckParamsGet($req);
	return undef unless (defined $data);
	
	# POST request method is special case
	if ($method eq 'POST') {
		$data = $self->_getCheckParamsPost($req, $data);
	}

	# print "RETURNED STRUCT: ", Dumper($data), "\n";
	
	return $data;
}

sub getReqMethod {
	my ($self, $req) = @_;

	unless (defined $req && blessed($req) && $req->can('method')) {
		$self->error("Invalid request object.");
		return undef;
	}
	
	return uc($req->method());
}

sub isSupportedMethod {
	my ($self, $method) = @_;
	unless (defined $method && length($method)) {
		$self->error("Undefined HTTP request method.");
		return 0;
	}
	$method = lc($method);
	return 1 if ($method eq 'get' || $method eq 'post');

	$self->error("Unsupported request method: $method");
	return 0;
}

sub isBrowser {
	my ($self, $ua) = @_;
	return 0 unless (defined $ua && length($ua));
	return ($ua =~ m/(?:mozilla|opera|msie|konqueror|epiphany|gecko)/i) ? 1 : 0;
}

sub getRequestPath {
	my ($self, $req) = @_;
	return undef unless (defined $req && blessed($req));
	
	my $path = undef;
	if ($req->can('path_info')) {
		$path = $req->path_info();
	}
	elsif ($req->can('uri')) {
		$path = $req->uri()->path();
	}
	
	$path = urldecode($path) if (defined $path);
	return $path;
}

sub getCheckOutputType {
	my ($self, $req) = @_;
	my $type = undef;
	
	# request method
	my $method = $self->_getRequestMethod($req);
	$method = lc($method);
	unless (defined $method) {
		$self->error("Undefined request method");
		return undef;
	}
	
	# Accept: request header
	my $accept = $self->_getRequestHeader($req, 'Accept');
	$accept = undef if (defined $accept && $accept =~ m/\*/);

	# Content-Type: request header
	my $ct = ($req->can('content_type')) ? $req->content_type() : undef;
	$ct = (defined $ct) ? $ct : $self->_getRequestHeader($req, 'Content-Type');

	# output_type URI parameter
	my $ot = $self->_getQueryParam($req, 'output_type');

	my $ua = $self->_getRequestHeader($req, 'User-Agent');
	# $log->info("method: '$method', accept: '$accept', ct: '$ct', output_type: '$ot', ua: '$ua'");
	
	# query parameter has the highest priority
	$type = (defined $ot && length $ot) ? $ot : undef;

	# module suffix...
	my $path = $self->getRequestPath($req);
	if ($path =~ m/\.(\w+)$/) {
		$type = $1;
	}

	# do we have Accept?
	unless (defined $type) {
		if (defined $accept && length $accept) {
			if ($accept =~ m/\/+(.+)$/i) {
				$type = $1;
			}
		}
	}
	
	# POST and Content-Type?
	if (($method eq 'post' || $method eq 'put') && defined $ct) {
		if ($ct =~ /\/(.+)$/) {
			$type = $1;
		}
	}

	# select default renderer just if
	# nothing appropriate was detected...
	unless (defined $type) {
		$type = "HTML" if ($self->isBrowser($ua));	
		$type = 'PLAIN' unless (defined $type);
	}

	$type = uc($type) if (defined $type);
	return $type;
}

# this method translates HTTP::Request object
# to check hashref
sub checkParamsFromReq {
	my ($self, $req) = @_;
	$self->error('');
	unless (defined $req && blessed($req)) {
		$self->error("Invalid request object.");
		return undef;
	}
	
	# we only support GET and POST
	# request methods...
	my $method = $self->getReqMethod($req);
	return undef unless ($self->isSupportedMethod($method));
	
	# always check parameters as if request method
	# would be GET
	my $data = $self->_getCheckParamsGet($req);
	
	# POST request method is special case
	if ($method eq 'POST') {
		$data = $self->_getCheckParamsPost($req, $data);
	}
	
	return $data;
}

sub _getCheckParamsGet {
	my ($self, $req) = @_;

	# get URI and query string...
	my ($uri, $qs) = (undef, undef);
	if ($req->can('uri')) {
		$uri = $req->uri()->path();
		$qs = $req->uri()->query();
	}
	elsif ($req->can('path_info')) {
		$uri = $req->path_info();
		if ($req->can('query_string')) {
			$qs = $req->query_string();
			$qs =~ s/;/&/g if (defined $qs);
		}
	}
	
	# urldecode URI
	$uri = '/' unless (defined $uri && length($uri));
	$uri = urldecode($uri);
	$uri = '/' . $uri unless ($uri =~ m/^\//);

	# split URI by slashes
	my @uri = split(/\/+/, $uri);
	
	# urldecode query string
	my %qs = ();
	if (defined $qs && length $qs) {
		%qs = ();
		# urldecode parameters
		map {
			my ($key, $val) = split(/\s*=\s*/, $_, 2);
			if (defined $key && defined $val) {
				$key = urldecode($key);
				$val = urldecode($val);
				$qs{$key} = $val;
			}
		} split(/&/, $qs);
	}

	my $module = undef;
	my $params = {};
	
	# select check module...
	if (@uri) {
		$module = pop(@uri);		
		# /<MODULE>.<output_type> ?
		if ($module =~ m/^(\w+)\./) {
			$module = $1
		}
	}
	if (exists($qs{module})) {
		$module = $qs{module};
		delete($qs{module});
	}

	# replace params from query string
	map { $params->{$_} = $qs{$_} } keys %qs;

	# result structure
	return {
		module => $module,
		params => $params,
	};
}

sub _getCheckParamsPost {
	my ($self, $req, $data) = @_;
	
	# get content-type
	my $ct = ($req->can('content_type')) ? $req->content_type() : undef;
	$ct = (! defined $ct && $req->can('header')) ? $req->header('Content-Type') : $ct;
	$ct = '' unless (defined $ct);
	
	unless (defined $ct && length($ct) > 0) {
		$self->error("Missing Content-Type request header.");
		return undef;
	}

	# get request body content
	my $content = undef;
	if ($req->can('decoded_content')) {
		$content = $req->decoded_content();
	}
	elsif ($req->can('param')) {
		# remove POSTDATA if req is CGI
		delete($data->{POSTDATA}) if ($req->isa('CGI'));
		$content = $req->param('POSTDATA');
		$content = $self->urldecode($content);
	}
	
	# post data...
	my $p = undef;
	
	# JSON?
	if ($ct =~ m/^(?:text|application)\/json/i) {
		$p = $self->parseJSON(\ $content);
		return undef unless (defined $p);
	}
	# XML?
	elsif ($ct =~ m/^(?:text|application)\/xml/i) {
		$p = $self->parseXML($content);
		return undef unless (defined $p);
	}
	# other content_type?
	else {
		$self->error("Invalid/unsupported POST content-type: $ct");
		return undef;
	}

	# merge post data with current data...
	$self->mergeReqParams($data, $p);

	return $data;
}

sub mergeReqParams {
	my ($self, $dst, $src) = @_;

	return undef unless (defined $dst && ref($dst) eq 'HASH');
	return undef unless (defined $src && ref($src) eq 'HASH');

	# module selection...
	#if (exists($src->{module}) && defined $src->{module} && ref($src->{params}) eq '') {
	#	$dst->{module} = $src->{module}
	#}

	# copy params
	if (ref($src) eq 'HASH') {
		map {
			$dst->{params}->{$_} = $src->{$_};
		} keys %{$src};
	}

	return $dst;
}

sub str_addr {
	my ($self, $sock) = @_;
	
	if (defined $sock && blessed($sock)) {
		# socket?
		if ($sock->isa('IO::Socket')) {
			# unix domain socket
			if ($sock->can('hostpath')) {
				return $sock->hostpath();
			} else {
				return '[' . $sock->peerhost() . ']:' . $sock->peerport();
			}
		}
		# CGI?
		elsif ($sock->isa('CGI')) {
			my $s = '[' . $sock->remote_addr() . ']';
			$s .= ':' . $ENV{REMOTE_PORT} if (exists($ENV{REMOTE_PORT}));
			return $s;
		}
	}
	
	return '';
}

sub renderDoc {
	my ($self, $pkg) = @_;
	# load renderer class
	eval { require P9::AA::PodRenderer };
	return undef if ($@);

	# render package documentation
	return P9::AA::PodRenderer->new()->render($pkg);
}

sub _getRequestMethod {
	my ($self, $req) = @_;
	return undef unless (defined $req && blessed $req);
	my $m = undef;
	if ($req->can('method')) {
		$m = $req->method();
	}
	elsif ($req->can('request_method')) {
		$m = $req->request_method();
	}

	return $m;
}

sub _getRequestHeader {
	my ($self, $req, $name) = @_;
	return undef unless (defined $req && blessed($req) && defined $name);
	my $v = undef;

	if ($req->isa('CGI') && $req->can('http')) {
		$log->info("Getting CGI req header: $name ; ct='$ENV{HTTP_CONTENT_TYPE}'");
		$v = $req->http($name);
	}
	elsif ($req->can('header')) {
		$v = $req->header($name);
	}
	return $v;
}

sub _getQueryParam {
	my ($self, $req, $name) = @_;
	return undef unless (defined $req && blessed($req) && defined $name);
	my $v = undef;
	if ($req->can('url_param')) {
		$v = $req->url_param($name);
	}
	elsif ($req->can('uri')) {
		$v = $req->uri()->query_param($name);
	}
	return $v;
}

1;