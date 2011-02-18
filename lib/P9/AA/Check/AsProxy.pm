package P9::AA::Check::AsProxy;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::JSON';

our $VERSION = 0.10;

=head1 NAME

Proxy checking module - Perform arbitrary check on another agent.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::JSON>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Execute check on another agent."
	);

	$self->cfgParamRemove(qr/^header[\w\-]+/);
	$self->cfgParamRemove('debug_json');
	$self->cfgParamRemove('host_header');
	$self->cfgParamRemove('user_agent');
	$self->cfgParamRemove('username');
	$self->cfgParamRemove('password');
	$self->cfgParamRemove('proxy_url');
	$self->cfgParamRemove('request_method');
	$self->cfgParamRemove('request_body');
	$self->cfgParamRemove('strict');
	$self->cfgParamRemove('url');
	$self->cfgParamRemove('user_agent');
	$self->cfgParamRemove('ipv6');
	$self->cfgParamRemove('debug_response');
	$self->cfgParamRemove('ignore_http_status');
	$self->cfgParamRemove('timeout');	

	$self->cfgParamAdd(
		qr/.+/,
		undef,
		'Arbitrary configuration parameter.',
		$self->validate_str(16 * 1024),
	);

	$self->cfgParamAdd(
		'REAL_HOSTPORT',
		'host.example.com:1552',
		'Real agent host:port',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'REAL_MODULE',
		undef,
		'Real agent check module name',
		$self->validate_str(100),
	);
	$self->cfgParamAdd(
		'USE_SSL',
		1,
		'Use SSL for connection to real agent.',
		$self->validate_bool(),
	);
	

	return 1;
}

sub check {
	my ($self) = @_;
	
	my $data = $self->getRemoteCheckData();
	return CHECK_ERR unless (defined $data);
	
	# behave like normal checking module...
	my $check = $data->{data}->{check};
	unless (defined $check && ref($check) eq 'HASH') {
		return $self->error("Invalid JSON response: no check data returned.");
	}
	# check result
	my $res = $check->{result_code};
	# messages
	#$self->bufClear();
	$self->bufApp($check->{messages});
	
	# error and warning
	$self->warning($check->{warning_message});
	$self->error($check->{error_message});

	return $res;
}

sub toString {
	my ($self) = @_;
	no warnings;
	return $self->{REAL_MODULE} . '@' . $self->{REAL_HOSTPORT};	
}

sub getRemoteCheckData {
	my $self = shift;
	
	my $module = $self->{REAL_MODULE};
	my $host_port = $self->{REAL_HOSTPORT};
	{
		no warnings;
		$module =~ s/[^\w]+//g;
		unless (defined $module && length $module) {
			$self->error("Undefined remote agent checking module name. Define REAL_MODULE configuration property.");
			return undef;
		}
		# check host_port
		unless (defined $host_port) {
			$self->error("Undefined remote agent host:port. Define REAL_HOSTPORT configuration property.");
			return undef;
		}
		if ($host_port !~ m/^\[?[\w\-\.\:]+\]?:\d+$/) {
			$self->error("Invalid remote agent host_port declaration: '$host_port'.");
			return undef;
		}
	}
	
	# compute url
	my $url =
		(($self->{REAL_SSL}) ? 'https://' : 'http://') .
		$host_port . '/' .
		$module . '/';
	
	# compute options
	
	# prepare proxy check parameters
	my $params = {};
	foreach (keys %{$self}) {
		next if ($_ =~ m/^_/);
		next if ($_ =~ m/^REAL_/);
		$params->{$_} = $self->{$_};
	}
	
	$self->log_debug("Will query agent on URL: $url") if ($self->{debug});
	
	# json parser
	my $p = $self->getJSONParser();
	
	# get the fucking json...
	return $self->getJSON(
		url => $url,
		request_method => 'POST',
		user_agent => ref($self) . '/' . $self->VERSION(),
		headerAccept => 'application/json',
		'headerAccept-Encoding' => 'gzip',
		'headerContent-Type' => 'application/json; charset=utf-8',
		request_body => $p->encode($params),
	);
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;