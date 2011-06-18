package P9::AA::Check::HAProxy;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::URL';

our $VERSION = 0.10;

# haproxy CSV stats item order...
my @_order = qw(
	pxname svname qcur qmax scur smax slim stot bin bout dreq dresp ereq
	econ eresp wretr wredis status weight act bck chkfail chkdown lastchg
	downtime qlimit pid iid sid throttle lbtot tracked type rate rate_lim
	rate_max check_status check_code check_duration hrsp_1xx hrsp_2xx hrsp_3xx
	hrsp_4xx hrsp_5xx hrsp_other hanafail req_rate req_rate_max req_tot cli_abrt srv_abrt 
);

# haproxy check status descriptions
my $_check_status = {
	UNK => 'unknown',
	INI => 'initializing',
	SOCKERR => 'socket error',
	L4OK => 'check passed on layer 4, no upper layers testing enabled',
	L4TOUT => 'layer 1-4 timeout',
	L4CON => 'layer 1-4 connection problem, for example "Connection refused" (tcp rst) or "No route to host" (icmp)',
	L6OK => 'check passed on layer 6',
	L6TOUT => 'layer 6 (SSL) timeout',
	L6RSP => 'layer 6 invalid response - protocol error',
	L7OK => 'check passed on layer 7',
	L7OKC => 'check conditionally passed on layer 7, for example 404 with disable-on-404',
	L7TOUT => 'layer 7 (HTTP/SMTP) timeout',
	L7RSP => 'layer 7 invalid response - protocol error',
	L7STS => 'layer 7 response error, for example HTTP 5xx',
};

=head1 NAME

HaProxy checking module

=head1 DESCRIPTION

This module checks HaProxy status via HTTP or UNIX domain socket statistics interface.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::URL>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Check Haproxy availability and backends."
	);
	
	$self->cfgParamAdd(
		'haproxy_url',
		'http://localhost:8089/',
		'HaProxy web interface URL or UNIX domain statistcs socket path.',
		$self->validate_str(1024),
	);

	$self->cfgParamAdd(
		'ignore_backends',
		'',
		'Comma separated list of ignored backends',
		$self->validate_str(1024 * 8),
	);
	$self->cfgParamAdd(
		'ignore_frontends',
		'',
		'Comma separated list of ignored frontends',
		$self->validate_str(1024 * 8),
	);

	$self->cfgParamRemove(qr/^header[\w\-]+/);
	$self->cfgParamRemove('content_pattern');
	$self->cfgParamRemove('content_pattern_match');
	$self->cfgParamRemove('host_header');
	$self->cfgParamRemove('request_method');
	$self->cfgParamRemove('request_body');
	$self->cfgParamRemove('strict');
	$self->cfgParamRemove('url');
	$self->cfgParamRemove('user_agent');
	$self->cfgParamRemove('redirects');
	$self->cfgParamRemove('debug_response');
	$self->cfgParamRemove('ignore_http_status');
	
	return 1;
}

sub check {
	my ($self) = @_;
	
	# try to get haproxy data
	my $info = $self->getHaproxyInfo();
	if (defined $info) {
		$self->bufApp("HAProxy: " . $self->dumpVar($info));
		$self->bufApp();
	} else {
		$self->bufApp("WARNING: Error fetching HAProxy info: " . $self->error());
	}
	
	# fetch data
	my $data = $self->getHaproxyStats();
	return CHECK_ERR unless (defined $data);
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN HAPROXY DATA ---");
		$self->bufApp($self->dumpVar($data));
		$self->bufApp("--- END HAPROXY DATA ---");
	}
	
	# print some nice summary
	$self->bufApp("HAProxy summary:");
	$self->bufApp($self->_statsSummary($data));
	
	my $res = CHECK_OK;
	my $err = '';
	my $warn = '';
	
	# inspect backends...
	foreach my $name (sort keys %{$data->{backend}}) {
		my $be = $data->{backend}->{$name};
		
		# check all backend nodes
		foreach my $node (sort keys %{$be->{nodes}}) {
			my $n = $be->{nodes}->{$node};
			my $status = uc($n->{status});
			unless ($status eq 'UP') {
				my $str = "BACKEND $name, NODE $node is not in OK state: $status";
				# check problem?
				my $cs = uc($n->{check_status});
				if (length($cs) > 0) {
					my $cs_str = $_check_status->{$cs} || 'UNKNOWN';
					$str .= " [check status $cs: $cs_str]\n";
				}
				if ($self->_isIgnoredBe($name)) {
					$warn .= $str;
					$res = CHECK_WARN if ($res != CHECK_ERR);
				} else {
					$err .= $str;
					$res = CHECK_ERR;
				}
			}
		}
		
		# check total backend stats
		my $be_status = $be->{total}->{status};
		$be_status = uc($be_status) if (defined $be_status);
		if (defined $be_status && $be_status ne 'UP') {
			if ($self->_isIgnoredBe($name)) {
				$warn .= "BACKEND $name is in state '$be_status'\n";
				$res = CHECK_WARN if ($res != CHECK_ERR);				
			} else {
				$err .= "BACKEND $name is in state '$be_status'\n";
				$res = CHECK_ERR;
			}
		}
	}
	
	# inspect frontends
	foreach my $name (sort keys %{$data->{frontend}}) {
		my $fe = $data->{frontend}->{$name}->{total};
		my $status = uc($fe->{status});
		if ($status ne 'OPEN') {
			my $str = "FRONTEND $name is in state '$status'\n";
			if ($self->_isIgnoredFe($name)) {
				$warn .= $str;
				$res = CHECK_WARN if ($res != CHECK_ERR);
			} else {
				$err .= $str;
				$res = CHECK_ERR;
			}
		}
	}
	
	if ($res == CHECK_ERR) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	elsif ($res == CHECK_WARN) {
		$warn =~ s/\s+$//g;
		$self->warning($warn);		
	}
	return $res;
}

sub toString {
	my ($self) = @_;
	no warnings;
	return $self->{haproxy_url};	
}

=head2 getHaproxyStats

 my $data = $self->getHaproxyStats($url);
 my $data = $self->getHaproxyStats($unix_socket_path);

Returns hash reference containing haproxy stats interface data on success, otherwise undef.

=cut
sub getHaproxyStats {
	my ($self, $url, %opt) = @_;
	$url = $self->{haproxy_url} unless (defined $url);
	
	my $raw_data = undef;

	# fetch data using HTTP or unix domain socket?
	if ($url =~ m/^http(?:s)?:\/\//) {
		# append csv query string if necessary.
		$url .= ';csv' unless ($url =~ m/\;csv$/);
		$raw_data = $self->_fetchDataHttp($url, %opt); 
	}
	elsif ($self->{haproxy_url} =~ m/^\//) {
		# unix domain socket...
		$raw_data = $self->_fetchDataUnix($url);
	}
	else {
		$self->error("Invalid haproxy statistics URL: $self->{haproxy_url}");
		return undef;
	}

	# no raw data?
	return undef unless (defined $raw_data);
	
	# try to parse raw data...
	return $self->_parseHaproxy(\ $raw_data);
}

=head2 getHaproxyInfo

 my $info = $self->getHaproxyInfo($url);
 my $info = $self->getHaproxyInfo($unix_socket_path);

Returns HAProxy information as hash reference on success, otherwise undef.

=cut
sub getHaproxyInfo {
	my ($self, $url, %opt) = @_;
	$url = $self->{haproxy_url} unless (defined $url);
	my $is_unix = $self->_isUnixUrl($url);
	return undef if ($is_unix < 0);
	return ($is_unix) ? $self->_fetchInfoUnix($url) : $self->_fetchInfoHttp($url, %opt);
}

sub _fetchDataHttp {
	my ($self, $url, %opt) = @_;
	# perform http request...
	my $resp = $self->httpGet($url, %opt);
	unless ($resp->is_success()) {
		$self->error("Invalid HTTP response: " . $resp->status_line());
		return undef;
	}

	# correct content-type?
	my $ct = $resp->header('Content-Type');
	unless (defined $ct && $ct =~ m/text\/plain/i) {
		no warnings;
		$self->error("Invalid response content-type: '$ct'");
		return undef;
	}
	
	# return content
	return $resp->decoded_content();
}

sub _fetchDataUnix {
	my ($self, $path) = @_;
	# connect
	my $sock = $self->sockConnect($path);
	return undef unless (defined $sock);
	
	# send stats command
	print $sock "show stat\r\n";
	
	# read response
	my $buf = '';
	while (<$sock>) {
		$buf .= $_;
	}
	
	return $buf;
}

sub _fetchInfoHttp {
	my ($self, $url, %opt) = @_;
	$url = $self->{haproxy_url} unless (defined $url);
	
	# strip possible CSV suffix
	$url =~ s/;csv\s*$//g;
	
	# perform http request...
	my $resp = $self->httpGet($url, %opt);
	unless ($resp->is_success()) {
		$self->error("Invalid HTTP response: " . $resp->status_line());
		return undef;
	}

	# correct content-type?
	my $ct = $resp->header('Content-Type');
	unless (defined $ct && $ct =~ m/text\/html/i) {
		no warnings;
		$self->error("Invalid response content-type: '$ct'");
		return undef;
	}

	# parse html buffer
	my $s = {};
	foreach (split(/[\r\n]+/, $resp->decoded_content, 100)) {
		# HAProxy version 1.4.15, released 2011/04/08</a></h1>  
		if (m/HAProxy\s+version\s+(.+),\s+released\s+([^<]+)/i) {
			$s->{name} = 'HAProxy';
			$s->{version} = $1;
			$s->{released} = $2;
		}
		elsif (m/Report\s+for\s+pid\s+(\d+)/i) {
			$s->{pid} = $1;
		}
		# <p><b>pid = </b> 15525 (process #1, nbproc = 1)<br>  
		elsif (m/\s+\d+\s+\(process\s+#(\d+),\s+nbproc\s+=\s+(\d+)\)<br>/i) {
			$s->{process_num} = $1;
			$s->{nbproc} = $2;
		}
		# <b>uptime = </b> 3d 18h52m26s<br> 
		elsif (m/uptime\s+=\s+<\/b>\s+([^<]+)<br>/i) {
			$s->{uptime} = $1;
			$s->{uptime_sec} = $self->_uptime_sec($s->{uptime});
		}
		# <b>system limits:</b> memmax = unlimited; ulimit-n = 2500136<br>
		elsif (m/system\s+limits:<\/b>\s+memmax\s+=\s+([^;]+);\s+ulimit-n\s+=\s+(\d+)/i) {
			$s->{memmax_mb} = ($1 eq 'unlimited') ? 0 : $1;
			$s->{'ulimit-n'} = $2;
		}
		# <b>maxsock = </b> 2500136; <b>maxconn = </b> 1000000; <b>maxpipes = </b> 250000<br>
		elsif (m/maxsock\s*=\s*<\/b>\s*(\d+);.*maxconn\s*=.*<\/b>\s*(\d+);.*maxpipes\s*=.*<\/b>\s*(\d+)/i) {
			$s->{maxsock} = $1;
			$s->{maxconn} = $2;
			$s->{maxpipes} = $3;
		}
		# current conns = 2229; current pipes = 38/38<br> 
		elsif (m/current\s+conns\s*=\s*(\d+);\s*current\s+pipes\s*=\s*(\d+)\/(\d+)/) {
			$s->{curconns} = $1;
			$s->{pipesfree} = $3;
			$s->{pipesused} = $2;
		}
		# Running tasks: 1/2298<br> 
		elsif (m/running\s+tasks:\s+(\d+)\/(\d+)/i) {
			$s->{run_queue} = $1;
			$s->{tasks} = $2;
			last;
		}
	}
	
	unless (%{$s}) {
		$self->error("HTML response doesn't contain HAProxy info data");
		return undef;
	}
	
	return $s;
}

sub _fetchInfoUnix {
	my ($self, $path) = @_;
	# connect
	my $sock = $self->sockConnect($path);
	return undef unless (defined $sock);
	
	# send stats command
	print $sock "show info\r\n";

	# read response
	my $s = {};
	while (<$sock>) {
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		next unless (length($_) > 0);
		my ($k, $v) = split(/\s*:+\s*/, $_, 2);
		next unless (defined $k && length $k > 0);
		$s->{lc($k)} = $v;
	}

	return $s;
}

sub _isUnixUrl {
	my ($self, $url) = @_;
	return -1 unless ($self->_checkUrl($url));

	if ($url =~ m/^http(?:s)?:\/\//) {
		return 0;
	}
	elsif ($url =~ m/^\//) {
		return 1;
	}
	else {
		$self->error("Invalid haproxy statistics URL: $self->{haproxy_url}");
		return -1;
	}
}

sub _checkUrl {
	my ($self, $url) = @_;
	unless (defined $url && length($url) > 0) {
		$self->error("Undefined HaProxy stats URL.");
		return 0;
	}
	return 1;
}

sub _parseHaproxy {
	my ($self, $str) = @_;
	unless (defined $str && ref($str) eq 'SCALAR') {
		$self->{_error} = "Data argument must be scalar reference.";
		return undef;
	}
	
	# result structure
	my $res = {};

	my $last_fe = undef;
	my $last_be = undef;

	# split into line chunks and reverse order
	#
	# it's easier to parse haproxy stats output
	# in reverse order
	foreach (reverse(split(/[\r\n]+/, $$str))) {
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		next if ($_ =~ m/^#/);
		next unless (length $_ > 0);
		
		# split line
		my @tmp = split(/\s*,\s*/, $_);
		
		# build hash...
		my $tdata = {};
		map {
			my $i = shift(@tmp);
			$tdata->{$_} = lc($i) if (defined $i && length($i) > 0);
		} @_order;
		
		# svname and pxname must be defined
		my $svname = delete($tdata->{svname});
		my $pxname = delete($tdata->{pxname});
		next unless (defined $svname && length($svname) > 0);
		next unless (defined $pxname && length($pxname) > 0);
				
		my $is_backend_member = 0;
		
		if ($svname eq 'backend') {
			$last_fe = undef;
			$last_be = $pxname;			
		}
		elsif ($svname eq 'frontend') {
			$last_fe = $pxname
		} else {
			$is_backend_member = 1;
			%{$res->{backend}->{$last_be}->{nodes}->{$svname}} = %{$tdata};
		}
		
		unless ($is_backend_member) {
			%{$res->{$svname}->{$pxname}->{total}} = %{$tdata};
		}
	}
	
	return $res;
}

sub _statsSummary {
	my ($self, $data) = @_;
	return '' unless (defined $data && ref($data) eq 'HASH');
	my $no_farms = scalar(keys %{$data->{backend}});
	my $no_frontends = scalar(keys %{$data->{frontend}});
	my $no_real_backends = 0;
	# count real servers
	map {
		$no_real_backends += scalar(keys %{$data->{backend}->{$_}->{nodes}})
	} keys %{$data->{backend}};
	
	return	"  FRONTENDS:     $no_frontends\n" .
			"  BACKEND FARMS: $no_farms\n" .
			"  REAL BACKENDS: $no_real_backends";
}

sub _isIgnoredFe {
	my ($self, $name) = @_;
	return 0 unless (defined $name && length($name) > 0);
	my @ignored = split(/\s*,\s*/, $self->{ignore_frontends});
	return (grep({ $_ eq $name } @ignored) > 0) ? 1 : 0;
}

sub _isIgnoredBe {
	my ($self, $name) = @_;
	return 0 unless (defined $name && length($name) > 0);
	my @ignored = split(/\s*,\s*/, $self->{ignore_backends});
	return (grep({ $_ eq $name } @ignored) > 0) ? 1 : 0;
}

sub _uptime_sec {
	my ($self, $s) = @_;
	#3d 18h52m26s
	if ($s =~ m/(\d+d)?\s*(\d+h)?(\d+m)?(\d+s)/i) {
		my $days = (defined $1) ? $1 : 0;
		my $hours = (defined $2) ? $2 : 0;
		my $minutes = (defined $3) ? $3 : 0;
		my $seconds = (defined $4) ? $4 : 0;
		
		map { $_ =~ s/[^\d]+//g } $days, $hours, $minutes, $seconds;
		
		return ($days * 86400 + $hours * 3600 + $minutes * 60 + $seconds);
	}
	return 0;
}

=head1 SEE ALSO

L<P9::AA::Check>, L<P9::AA::Check::URL>, L<P9::AA::Check::_Socket>, L<http://code.google.com/p/haproxy-docs/wiki/StatisticsMonitoring#CSV_format>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;