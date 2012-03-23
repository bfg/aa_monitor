package P9::AA::Protocol::HTTP;

# $Id: HTTP.pm 2349 2011-02-14 19:07:45Z bfg $
# $Date: 2011-02-14 20:07:45 +0100 (Mon, 14 Feb 2011) $
# $Author: bfg $
# $Revision: 2349 $
# $LastChangedRevision: 2349 $
# $LastChangedBy: bfg $
# $LastChangedDate: 2011-02-14 20:07:45 +0100 (Mon, 14 Feb 2011) $
# $URL: https://svn.interseek.com/repositories/admin/aa_monitor/trunk/lib/Noviforum/Adminalert/Protocol/HTTP.pm $

use strict;
use warnings;

use HTTP::Request;
use HTTP::Response;
use Scalar::Util qw(blessed);

use P9::AA::Log;
use P9::AA::Config;
use P9::AA::Constants qw(:all);
use P9::AA::Protocol::_HTTPCommon;

use base 'P9::AA::Protocol::_HTTPCommon';

our $VERSION = 0.12;
my $log = P9::AA::Log->new();
my $cfg = P9::AA::Config->singleton();

=head1 NAME

HTTP protocol implementation.

=head1 DESCRIPTION

L<P9::AA::Protocol::HTTP> is limited HTTP/1.1 implementation of 
L<P9::AA::Protocol> interface.


=head1 METHODS

L<P9::AA::Protocol::HTTP> inherits all methods from 
L<P9::AA::Protocol> and implements the following methods:

=head1 process

 $protocol->process($socket, undef [, $start_time = time()])

Processes connection

=cut
sub process {
	my ($self, $sock, undef, $ts) = @_;
	# check socket...
	unless (defined $sock && blessed($sock) && $sock->isa('IO::Socket')) {
		$self->error("Invalid socket object.");
		return 0;
	}
	$ts = time() unless (defined $ts);
	
	# create response (bad by default)
	my $resp = $self->response();
	
	# read request...
	my $req = $self->parse($sock);
	unless (defined $req) {
		$log->error($self->error());
		return $self->badResponse($sock, 400, $self->error());
	}
	
	if ($log->is_debug()) {
		$log->debug("HTTP request: " . $req->as_string());
	}
	
	# EXPERIMENTAL DOCUMENTATION SUPPORT
	my $path = $req->uri()->path();
	$path = '/' unless (defined $path && length $path);
	$path = $self->urldecode($path);
	if (defined $path && length($path)) {
		# /favicon.ico?
		if ($path =~ m/^\/+favicon\.ico/i) {
			$log->debug("Will return 404 status for favicon.ico request.");
			$self->badResponse($sock, 404);
			return 1;
		}
		# /doc => documentation?
		if ($cfg->get('enable_doc') && $path =~ m/(.*)\/+doc\/?(.*)/) {
			my $prefix = $1;
			my $what = $2;
			$what = 'P9/README_AA' unless (defined $what && length($what));
			$what =~ s/\/+/::/g;
			$log->debug("Will render documentation: $what");
			$self->_renderDoc($what, $resp, $prefix);
			$self->sendResponse($sock, $resp);
			return 1;
		}
	}

	# what is client requesting us to do?
	my $ci = $self->checkParamsFromReq($req);
	unless (defined $ci) {
		$log->error($self->error());
		return $self->badResponse($sock, 400, $self->error());
	}
	
	my $module = $ci->{module};
	
	my $harness = CLASS_HARNESS->new();
	
	# remove weird stuff from module name...
	$module =~ s/[^\w]+//g if (defined $module);

	# what kind of output type should we
	# create?
	my $output_type = $self->getCheckOutputType($req);

	# create output renderer
	my $renderer = $self->getRenderer($output_type);
	unless (defined $renderer) {
		return $self->badResponse($sock, 500, $self->error());
	}
	
	# perform the service check...
	my $data = eval { $harness->check($module, $ci->{params}, $ts) };
	if ($@) {
		$log->error("Exception: $@");
		return $self->badResponse(
			$sock,
			500,
			"Exception while running check. See logs for details."
		);
	}
	unless (defined $data) {
		return $self->badResponse(
			$sock,
			503,
			"Client " . $self->str_addr($sock) . " module $module error: " .
			$harness->error()
		);
	}
	
	# render the data
	$renderer->uri($req->uri());
	my $body = $renderer->render($data, $resp);
	unless (defined $body) {
		$self->error($renderer->error());
		return $self->badResponse($sock, 500, $renderer->error());
	}
	$resp->content($body);

	# set http response code
	if (defined $module && length($module)) {
		no warnings;
		if (! $data->{data}->{check}->{success} && $data->{data}->{check}->{error_message} =~ m/^Unable to load driver module/i) {
			$resp->code(503);
		} else {
			$resp->code(200);
		}
	} else {
		$resp->code(404);
	}
	
	# send output
	$self->sendResponse($sock, $resp);

	return 1;
}

sub parse {
	my ($self, $fd) = @_;
	$self->{_error} = '';
	
	# request buffer
	my $buf = '';
	my $buf_len = 0;

	my $do_read = 1;
	# request should be read in 2 seconds...
	local $SIG{ALRM} = sub {
		die "Timeout reading HTTP request from client.\n";
		$do_read = 0;
		#$log->warn("Client request read timeout.");
		#exit 0;
		#CORE::exit(0);
	};
	alarm(2);

	my $last = '';		# last line
	my $i = 0;			# 100 lines of http headers? enough!
	while ($do_read && $i < 100) {
		$i++;
		my $line = <$fd>;
		last unless (defined $line);

		# append buffer...
		$buf .= $line;
		$last = $line;
		
		if ($line eq "\r\n" && $last eq "\r\n") {
			last;
		}
	}
	
	my $err = 'Error parsing HTTP request: ';
	
	# construct request object
	my $req = HTTP::Request->parse($buf);
	unless (defined $req) {
		$self->error($err. "Unknown error.");
		$req = undef;
		goto outta_parse;
	}
	
	my $method = $req->method();
	unless (defined $method && length($method) > 0) {
		$self->error(
			$err .
			"No request method specified."
		);
		$req = undef;
		goto outta_parse;
	}
	
	# POST/PUT methods also contain
	# request body
	$method = lc($method);
	if ($method eq 'post' || $method eq 'put') {
		my $cl = $req->header('Content-Length');
	
		unless (defined $cl && length($cl) > 0) {
			$self->error(
				$err .
				"Request method " . uc($method) .
				"Requires Content-Length header."
			);
			
			$req = undef;
			goto outta_parse;
		}
		
		# has client sent Expect request header?
		if (defined(my $e = $req->header('Expect'))) {
		  $e = lc($e);
		  if ($e =~ m/^\s*100-continue/i) {
		    print $fd "HTTP/1.1 100 Continue\r\n\r\n";
		  }
		}

		# try to convert it into int
		{ no warnings; $cl += 0 }

		# read content body
		if ($do_read && $cl > 0) {
		  # too big request body?
		  if ($cl > 1024 * 1024) {
		    $self->error("Request entity too big (413).");
        return undef;
		  }

			my $buf = '';
			my $r = read($fd, $buf, $cl);
			unless (defined $r) {
				$self->error($err . "Error reading content body: $!");
				$req = undef;
				goto outta_parse;			
			}
			$req->content($buf);
		}
	}
	
	outta_parse:

	# destroy alarm
	alarm(0);
	
	return $req;
}

sub response {
	my ($self, $req) = @_;

	my $resp = HTTP::Response->new(400);
	$resp->protocol('HTTP/1.1');
	eval { no warnings; $resp->header('Server', sprintf("%s/%s", main->name(), main->VERSION())) };
	$resp->date(CORE::time());
	$resp->header('Cache-Control', 'no-cache, max-age=0');
	$resp->header('Connection', 'close');
	$resp->content_type('text/plain; charset=utf8');
	
	$resp->content($self->code2str($resp->code()));	
	return $resp;
}

sub badResponse {
	my ($self, $fd, $code, $body) = @_;
	$body = $self->code2str($code) unless (defined $body);
	# prepare bad response
	my $resp = $self->response();
	$resp->code($code);
	$resp->content('Error ' . $code . "\n\n" . $body);
	
	$self->error($body);
	
	$self->sendResponse($fd, $resp);
	return 0;
}

sub sendResponse {
	my ($self, $fd, $resp) = @_;
	my $e = 'Unable to send http response: ';

	# check fd
	unless (defined $fd && fileno($fd) > 0) {
		$log->error($e . "Invalid output filehandle.");
		return 0;
	}

	# write response
	if (defined $resp && blessed($resp) && $resp->isa('HTTP::Response')) {
		no warnings;
		my $n = print $fd $resp->as_string();
		unless ($n) {
			$log->error($e . "Error writing HTTP response: $!");
		}
	}
	
	# does fd look like socket?
	if (blessed($fd) && $fd->isa('IO::Socket') && $fd->connected()) {
		shutdown($fd, 2);
	}

	# close fd
	close($fd);
	return 1;
}

sub _renderDoc {
	my ($self, $pkg, $resp, $prefix) = @_;
	$prefix = '/' unless (defined $prefix && length $prefix);
	my $c = $self->renderDoc($pkg, $prefix);
	if (defined $c) {
		$resp->code(200);
		$resp->content($c);
		$resp->content_type('text/html; charset=utf8');		
	} else {
		$resp->code(404);
		$resp->content("Not found");
		$resp->content_type('text/plain; charset=utf8');		
	}
}

=head1 SEE ALSO

This protocol implementation is based on L<HTTP::Request> and L<HTTP::Response> packages
found in L<LWP> (libwww-perl).

=head1 AUTHORS

=over 4

=item *

Brane F. Gracnar

=back

=cut
1;