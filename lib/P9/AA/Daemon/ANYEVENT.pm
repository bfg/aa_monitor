package P9::AA::Daemon::ANYEVENT;

use strict;
use warnings;

use AnyEvent;

use P9::AA::Daemon;
use P9::AA::Log;
use P9::AA::Config;

use Data::Dumper;
use Scalar::Util qw(refaddr blessed);

use P9::AA::PodRenderer;

use P9::AA::Daemon::ANYEVENT::Request;
use P9::AA::Daemon::ANYEVENT::Connection;

use constant MAX_CLIENTS => 50;

use constant CONN => 'P9::AA::Daemon::ANYEVENT::Connection';

use base 'P9::AA::Daemon';

our $VERSION = 0.10;
my $log = P9::AA::Log->new();
my $cfg = P9::AA::Config->new();

sub run {
	my $self = shift;

	# check ssl...
	return 0 unless ($self->_checkSSL());

	$log->info("Daemon [" . ref($self) . "] startup.");

	#$cfg->set()
	return $self->SUPER::run(@_);
}

sub shutdown {
	my ($self) = @_;
	$log->info("Shutdown.");

	# destroy listeners
	$self->_listenersDestroy();

	# kill all clients
	my $i = 0;
	$log->debug("Destroyed $i client connections.");

	# send condition variable (this is the end of run())
	if (defined $self->{_cv}) {
		$self->{_cv}->send();
	}

	# this is it folx!
	return 1;
}

sub _listenersCreate {
	my ($self, $str, $port) = @_;
	$log->debug("_listenersCreate(): addrs = '$str' ; port = '$port'");
	my $res = [];

	my $num_clients = 0;

	# parse portz string
	my @desc = split(/\s*[;,]+\s*/, $str);
	foreach my $e (@desc) {
		if ($e eq '*') {
			$e = ($^O eq 'linux') ? '::' : '0.0.0.0';
		}

		# create http daemon...
		my $httpd = eval {
			MyHTTPD->new(
				max_clients      => $cfg->get('max_clients'),
				host             => $e,
				port             => $port,
				request_class    => 'P9::AA::Daemon::ANYEVENT::Request',
				connection_class => 'P9::AA::Daemon::ANYEVENT::Connection',
			);
		};
		if ($@ || !defined $httpd) {
			$self->{_error} =
			  "Error creating listening socket [$e]:$port : $@/$!";
			return undef;
		}

		# create callbacks...
		$httpd->reg_cb(
			'/doc'     => \&_process_doc,
			'/perldoc' => \&_process_doc,

			# check...
			'/rest/1/check' => \&_process_check,

			# return 404 for everything else...
			'' => sub { $_[1]->badResponse(404) },

			# decrement number of clients
		);

		# $log->info("Created httpd: $httpd");
		push(@{$res}, $httpd);
	}

	return $res;
}

sub _listenersDestroy {
	my ($self) = @_;
	my $i = 0;
	return $i
	  unless (defined $self->{_listeners}
		&& ref($self->{_listeners}) eq 'ARRAY');
	map { undef $_; $i++ } @{$self->{_listeners}};
	$self->{_listeners} = [];
	return $i;
}

sub _sighInstall {
	my ($self) = @_;
	$self->SUPER::_sighInstall();

	# don't install chld handler...
	$SIG{CHLD} = 'DEFAULT';
}

sub _acceptLoop {
	my ($self, $max_clients) = @_;
	$self->{_cv} = AnyEvent->condvar();
	$self->{_cv}->recv();
}

sub _process_doc {
	my ($daemon, $req) = @_;
	my $path = $req->url()->path();

	$path =~ s/^\/?(?:perl)?doc\/*//g;
	my $pkg = $path;
	$pkg =~ s/\/+/::/g;
	$pkg = 'P9::README_AA' unless (length $pkg);
	
	my $r   = P9::AA::PodRenderer->new();
	my $buf = $r->render($pkg);

	if (defined $buf && length $buf) {
		$req->header('Content-Type', 'text/html; charset=utf-8');
		$req->sendResponse(200, $buf);
	}
	else {
		$req->badResponse(404);
	}
}

sub _process_check {
	my ($self, $req) = @_;

	my $uri = $req->url();
	my $path = $uri->path();
	my $qs = $uri->query();
	
	use P9::AA::Protocol::_HTTPCommon;
	my $x = P9::AA::Protocol::_HTTPCommon->new();

	# what is client requesting us to do?
	my $ci = $x->checkParamsFromReq($req);
	unless (defined $ci) {
		$log->error($x->error());
		return $req->badResponse(400, $x->error());
	}

	# remove weird stuff from module name...
	my $module = $ci->{module};
	$module =~ s/[^\w]+//g if (defined $module);

	# what kind of output type should we
	# create?
	my $output_type = $x->getCheckOutputType($req);

	# create output renderer
	my $renderer = $x->getRenderer($output_type);
	unless (defined $renderer) {
		return $req->badResponse(500, $x->error());
	}
	
	use P9::AA::Check;
	my $data = P9::AA::Check->factory($module)->getResultDataStruct();

	# render the data
	my $h = {};
	my $body = $renderer->render($data, $h);
	unless (defined $body) {
		$self->error($renderer->error());
		return $req->badResponse(500, $renderer->error());
	}
	#$resp->content($body);

	# set http response code
	if (defined $module && length($module)) {
		no warnings;
		if (! $data->{data}->{check}->{success} && $data->{data}->{check}->{error_message} =~ m/^Unable to load driver module/i) {
			$req->code(503);
		} else {
			$req->code(200);
		}
	} else {
		$req->code(404);
	}
	
	# send output
	$req->sendResponse(200, $body, $h);
}

sub _checkSSL {
	my ($self) = @_;
	my $proto = $cfg->get('protocol');
	return 1 unless (defined $proto && length $proto && lc($proto) eq 'https');

	# do we have SSL support?
	unless (CONN->hasSSL()) {
		$self->error(
			"SSL support is not available. Please install Net::SSLeay perl module."
		);
		return 0;
	}

	# can we get TLS context?
	local $@;
	my $ctx = eval { CONN->getTLSctx() };
	if ($@) {
		my $err = $@;
		$err =~ s/\s+at\s+.+//g;
		$err =~ s/\s+$//g;
		$self->error("Error creating TLS context: $err");
		return 0;
	}

	# everything seems ok...
	return 1;
}

# inlined stuff...
package MyHTTPD;

use strict;
use warnings;

use Data::Dumper;

use P9::AA::Log;
use AnyEvent::HTTPD::Util;
use Scalar::Util qw(refaddr weaken);

use base 'AnyEvent::HTTPD';

sub new {
	my $this  = shift;
	my $class = ref($this) || $this;
	my %o = @_;
	my $max_clients = delete($o{max_clients}) || 100;
	my $self  = $class->SUPER::new(
		request_class => "AnyEvent::HTTPD::Request",
		%o
	);
	
	my $num_clients = 0;
	
	$self->reg_cb(
		# Taken from AnyEvent::HTTPD
		connect => sub {
			my ($self, $con) = @_;
			
			# MAX CONNECTIONS?
			if ($num_clients >= $max_clients) {
				# no more clients!!!
				P9::AA::Log->new()->warn(
					"Limit of $max_clients concurrently connected clients reached; dropping connection."
				);
				return $con->do_disconnect();
			}
			
			# increase number of connected clients...
			$num_clients++;

			$self->{conns}->{$con} = $con->reg_cb (
            request => sub {
               my ($con, $meth, $url, $hdr, $cont) = @_;
               #print "REQUEST: $meth, $url, [$cont] " . join (',', %$hdr) . "\n";
               
               $url = URI->new($url, 'http');
               #if ($meth eq 'GET') {
               #  $cont = parse_urlencoded ($url->query);
               #}
               if ($meth eq 'GET' or $meth eq 'POST') {
                  weaken $con;
                  $self->handle_app_req (
                     $meth, $url, $hdr, $cont, $con->{host}, $con->{port},
                     sub { $con->response (@_) if $con; }
                  );
               } else {
                  $con->response (400, "Bad Request");
               }
            }
			);
			
		},
		# Taken from AnyEvent::HTTPD
		disconnect => sub {
			my ($self, $con) = @_;
			$num_clients-- if ($num_clients > 0);
			$con->unreg_cb (delete $self->{conns}->{$con});
			$self->event (client_disconnected => $con->{host}, $con->{port});
		}
	);

	return $self;
}

1;