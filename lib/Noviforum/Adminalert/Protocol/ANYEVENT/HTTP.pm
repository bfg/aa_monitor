package Noviforum::Adminalert::Protocol::ANYEVENT::HTTP;

use strict;
use warnings;

use Noviforum::Adminalert::Protocol;

use base 'Noviforum::Adminalert::Protocol';

sub process {
	my ($self, $req, undef, $ts) = @_;
	
	# check socket...
	unless (defined $req && blessed($req)) {
		$self->error("Invalid HTTP request object.");
		return 0;
	}
	$ts = time() unless (defined $ts);

=pod
	my $harness = Noviforum::Adminalert::CheckHarness->new();
	
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

	# what is client requesting us to do?
	my $ci = $self->checkParamsFromReq($req);
	unless (defined $ci) {
		$log->error($self->error());
		return $self->badResponse($sock, 400, $self->error());
	}
	
	my $module = $ci->{module};
	
	if (defined $module && $module =~ m/favicon\.ico/i) {
		$self->badResponse($sock, 404);
		return 1;
	}
	
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
	my $data = $harness->check($module, $ci->{params}, $ts);
	unless (defined $data) {
		return $self->badResponse(
			$sock,
			503,
			"Client " . $self->str_addr($sock) . " module $module error: " .
			$harness->error()
		);
	}
	
	# render the data
	my $body = $renderer->render($data, $resp);
	unless (defined $body) {
		$self->error($renderer->error());
		return $self->badResponse($sock, 500, $renderer->error());
	}
	$resp->content($body);
	
	# set code
	$resp->code(200);
	
	# send output
	$self->sendResponse($sock, $resp);
=cut
	return 1;
}

1;