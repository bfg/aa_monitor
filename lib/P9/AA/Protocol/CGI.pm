package P9::AA::Protocol::CGI;

# $Id: CGI.pm 2322 2011-02-10 19:12:03Z bfg $
# $Date: 2011-02-10 20:12:03 +0100 (Thu, 10 Feb 2011) $
# $Author: bfg $
# $Revision: 2322 $
# $LastChangedRevision: 2322 $
# $LastChangedBy: bfg $
# $LastChangedDate: 2011-02-10 20:12:03 +0100 (Thu, 10 Feb 2011) $
# $URL: https://svn.interseek.com/repositories/admin/aa_monitor/trunk/lib/Noviforum/Adminalert/Protocol/CGI.pm $

use strict;
use warnings;

use CGI qw(:standard);
use Time::HiRes qw(time);
use Scalar::Util qw(blessed);

use P9::AA::Log;
use P9::AA::Protocol::_HTTPCommon;

use vars qw(@ISA);
@ISA = qw(P9::AA::Protocol::_HTTPCommon);

our $VERSION = 0.10;
my $log = P9::AA::Log->new();

sub getReqMethod {
	my ($self, $cgi) = @_;
	unless (defined $cgi && blessed($cgi) && $cgi->isa('CGI')) {
		$self->error("Invalid CGI object.");
		return undef;
	}

	return $cgi->request_method();
}

sub process {
	my ($self, $stdin, $stdout, $ts) = @_;
	$ts = time() unless (defined $ts);

	my $cgi = CGI->new();

	my $headers = $self->_cgiHeaders();
	my $harness = P9::AA::CheckHarness->new();

	my $path = $cgi->path_info();
	$path = $self->urldecode($path) if (defined $path);
	if (defined $path && length($path)) {
		# /favicon.ico?
		if ($path =~ m/^\/+favicon\.ico/i) {
			$log->debug("Will return 404 status for favicon.ico request.");
			$self->badResponse($stdout, 404);
			return 1;
		}
		# /doc => documentation?
		if ($path =~ m/\/+doc\/?(.*)/) {
			my $what = $1;
			$what = 'P9/README_AA' unless (defined $what && length($what));
			$what =~ s/\/+/::/g;
			$log->debug("Will render documentation: $what");
			my $body = $self->renderDoc($what);
			unless (defined $body && length $body) {
				$self->badResponse($stdout, 404);
				return 1;
			}
			$headers->{'Content-Type'} = 'text/html; charset=utf-8';
			$headers->{-status} = 200;
			$self->sendResponse($stdout, $headers, \ $body);
			return 1;
		}
	}

	# what is client requesting us to do?
	my $ci = $self->checkParamsFromReq($cgi);
	unless (defined $ci) {
		return $self->badResponse($stdout, 400, $self->error());
	}

	# get check module and check parameters
	my $module = $ci->{module};
	if (defined $module) {
		# 404 for favicon requests
		if ($module =~ m/^favicon(\.ico)?/i) {
			$self->badResponse($stdout, 404);
			return 1;
		}
	}

	my $params = $ci->{params};

	# remove weird stuff from module name...
	$module =~ s/[^\w]+//g if (defined $module);

	# what kind of output type should we
	# create?
	my $output_type = $self->getCheckOutputType($cgi);

	# create output renderer
	my $renderer = $self->getRenderer($output_type);
	unless (defined $renderer) {
		return $self->badResponse($stdout, 500, $self->error());
	}
	
	# perform the service check...
	my $data = eval { $harness->check($module, $params, $ts) };
	if ($@) {
		$log->error("Exception: $@");
		return $self->badResponse(
			$stdout,
			500,
			"Exception while running check. See logs for details."
		);
	}
	unless (defined $data) {
		return $self->badResponse(
			$stdout,
			503,
			"Client " . $self->str_addr($cgi) . " module $module error: " .
			$harness->error()
		);
	}
	
	# render the data
	my $body = $renderer->render($data, $headers);
	unless (defined $body) {
		return $self->badResponse($stdout, 500, $renderer->error());
	}
	
	# set successfull status...
	$headers->{'-status'} = '200 OK';

	# this is it!
	$self->sendResponse($stdout, $headers, \ $body);

	return 1;
}

sub sendResponse {
	my ($self, $fd, $headers, $body) = @_;
	# validate output fd
	return 0 unless (defined $fd && fileno($fd));

	my $cgi = CGI->new();

	# write header
	print $fd $cgi->header(%{$headers});
	
	# write body
	print $fd ${$body} if (defined $body && ref($body) eq 'SCALAR');
	
	return 1;
}

sub badResponse {
	my ($self, $fd, $code, $body) = @_;
	my $headers = $self->_cgiHeaders();
	$headers->{'-status'} = $self->code2CgiStatus($code);
	$body = $self->code2str($code) unless (defined $body);
	$self->sendResponse($fd, $headers, \ $body);
	return 0;
}

sub _cgiHeaders {
	my $self = shift;
	return {
		-status => $self->code2CgiStatus(400),
		-expires => 'now',
		-charset => 'utf8',
		'-X-Server' => eval { no warnings; sprintf("%s/%-.2f", main->name(), main->VERSION()) },
		'-Cache-Control' => 'no-cache, max-age=0',
		-type => 'text/plain',
	};
}

1;