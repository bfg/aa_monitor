package Noviforum::Adminalert::Daemon::ANYEVENT;

use strict;
use warnings;

use AnyEvent;
use AnyEvent::HTTPD;

use Noviforum::Adminalert::Daemon;
use Noviforum::Adminalert::Log;
use Noviforum::Adminalert::Config;

use Noviforum::Adminalert::Daemon::ANYEVENT::HTTPRequest;

use constant MAX_CLIENTS => 50;

use base 'Noviforum::Adminalert::Daemon';

our $VERSION = 0.10;
my $log = Noviforum::Adminalert::Log->new();
my $cfg = Noviforum::Adminalert::Config->new();

sub run {
	my $self = shift;
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
	
	# parse portz string
	my @desc = split(/\s*[;,]+\s*/, $str);
	foreach my $e (@desc) {
		if ($e eq '*') {
			$e = ($^O eq 'linux') ? '::' : '0.0.0.0';
		}
		# create http daemon...
		my $httpd = eval { AnyEvent::HTTPD->new(
			host => $e,
			port => $port,
			request_class => 'Noviforum::Adminalert::Daemon::ANYEVENT::HTTPRequest',
		)};
		if ($@ || ! defined $httpd) {
			$self->{_error} = "Error creating listening socket [$e]:$port : $@/$!";
			return undef;
		}
		
		# create callbacks...
		$httpd->reg_cb(
			# any url?
			'' => sub {
				my ($daemon, $req) = @_;
				use Data::Dumper;
				
				$req->respond ({ content => ['text/plain; charset=utf8',
					Dumper($req)
					]}
				);
			},
		);

		$log->info("Created httpd: $httpd");
		push(@{$res}, $httpd);
	}
	
	return $res;
}

sub _listenersDestroy {
	my ($self) = @_;
	my $i = 0;
	return $i unless (defined $self->{_listeners} && ref($self->{_listeners}) eq 'ARRAY');
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

1;