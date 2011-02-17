package P9::AA::Protocol::_HTTPCommon;

# $Id: _HTTPCommon.pm 2349 2011-02-14 19:07:45Z bfg $
# $Date: 2011-02-14 20:07:45 +0100 (Mon, 14 Feb 2011) $
# $Author: bfg $
# $Revision: 2349 $
# $LastChangedRevision: 2349 $
# $LastChangedBy: bfg $
# $LastChangedDate: 2011-02-14 20:07:45 +0100 (Mon, 14 Feb 2011) $
# $URL: https://svn.interseek.com/repositories/admin/aa_monitor/trunk/lib/Noviforum/Adminalert/Protocol/_HTTPCommon.pm $

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

sub getCheckOutputType {
	my ($self, $req) = @_;
	my $type = undef;
	
	# Accept request header
	my $accept = undef;
	if ($req->can('header')) {
		$accept = $req->header('Accept');
		# ignore stupid accept headers...
		$accept = undef if (defined $accept && $accept eq '*/*');
	}
	
	my $method = undef;
	if ($req->can('method')) {
		$method = $req->method();
	}
	elsif ($req->can('request_method')) {
		$method = $req->request_method();
	}
	$method = lc ($method) if (defined $method);
	
	# output_type query param
	my $ot = undef;
	if ($req->can('uri')) {
		my $path = $req->uri()->path();
		my @px = split(/\s*\/+\s*/, $path);
		#shift(@px);
		$path = pop(@px);
		$ot = $req->uri()->query_param('output_type');
		if (! (defined $ot && length($ot)) && defined $path && $path =~ m/\.(\w{3,})$/) {
			$ot = $1;
		}
	}
	elsif ($req->can('param')) {
		$ot = $req->param('output_type');
	}

	# query string parameter output_type?
	if (defined $ot && length($ot) > 0) {
		$type = $ot;
	}
	# Accept: request header?
	elsif (defined $accept && length($accept)) {
		if ($accept =~ m/\/([\w\-]+)$/) {
			$type = $1;
		}
	}
	# post/put method and Content-Type header?
	elsif (defined $method && ($method eq 'post' || $method eq 'put')) {
		my $ct = ($req->can('header')) ? $req->header('Content-Type') : undef;
		if (defined $ct && length($ct)) {
			$ct =~ s/\s*;.*$//g;
			$ct =~ s/^[^\/]+\///g;
			$type = $ct if (length($ct) > 0);
		}
	}

	# select default renderer just if
	# nothing appropriate was detected...
	unless (defined $type) {
		my $ua = undef;
		if ($req->can('user_agent')) {
			$ua = $req->user_agent();
		}
		elsif ($req->can('header')) {
			$ua = $req->header('User-Agent');
		}
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
	
	# urldecode URI
	$uri = urldecode($uri);
	
	# TODO: this should be implemented
	# in a better and CONFIGURABLE WAY!
	$uri =~ s/^.+check\/+//g;
	$uri = '/' . $uri;

	# split URI by slashes
	my @uri = split(/\//, $uri);
	
	# first one is always undefined...
	shift(@uri) if (@uri);
	
	# urldecode query string
	my %qs = ();
	if (defined $qs) {
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
		$module = shift(@uri);
		
		# /<MODULE>.<output_type> ?
		if ($module =~ m/^(\w+)\./) {
			$module = $1
		}
	}
	if (exists($qs{module})) {
		$module = $qs{module};
		delete($qs{module});
	}
	
	# try to be restful: get parameters from uri
	map {
		my ($k, $v) = split(/\s*=\s*/, $_);
		if (defined $k && length($k) > 0 && defined $v) {
			$params->{$k} = $v;
		}
	} @uri;

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
	
	# get content-length
	my $cl = ($req->can('content_length')) ? $req->content_length() : undef;
	$cl = (! defined $cl && $req->can('header')) ? $req->header('Content-Length') : $cl;
	$cl = 0 unless (defined $cl);

	unless (defined $ct && length($ct) > 0) {
		$self->error("Missing Content-Type header.");
		return undef;
	}
	unless (defined $cl && length($cl) > 0) {
		$self->error("Missing Content-Length header.");
		return undef;
	}
	
	# don't bother with empty bodies
	return $data if ($cl < 1);
	
	$log->debug("HTTP request content-type: $ct; content-length: $cl");
	
	# post data...
	my $p = undef;
	
	# JSON?
	if ($ct =~ m/^(?:text|application)\/json/i) {
		$p = $self->parseJSON(\ $req->decoded_content());
		return undef unless (defined $p);
	}
	# XML?
	elsif ($ct =~ m/^(?:text|application)\/xml/i) {
		$p = $self->parseXML($req->decoded_content());
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

	# render package
	return P9::AA::PodRenderer->new()->render($pkg);
	#my $r = P9::AA::PodRenderer->new();
	#return $r->render($pkg);
}

1;