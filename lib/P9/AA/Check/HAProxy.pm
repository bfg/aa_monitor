package P9::AA::Check::HAProxy;

use strict;
use warnings;

use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::URL';

our $VERSION = 0.20;

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
  'UNK' => 'Unknown state',
  'UP' => 'Backend is fully up and running',
  'OPEN' => 'Frontend is accepting connections',
  'NO CHECK' => 'Health checking is disabled',
  'INI' => 'Initializing',
  'SOCKERR' => 'Socket error',
  'L4OK' => 'Check passed on layer 4, no upper layers testing enabled',
  'L4TOUT' => 'Layer 1-4 timeout',
  'L4CON' => 'Layer 1-4 connection problem, for example "Connection refused" (tcp rst) or "No route to host" (icmp)',
  'L6OK' => 'Check passed on layer 6',
  'L6TOUT' => 'Layer 6 (SSL) timeout',
  'L6RSP' => 'Layer 6 invalid response - protocol error',
  'L7OK' => 'Check passed on layer 7',
  'L7OKC' => 'Check conditionally passed on layer 7, for example 404 with disable-on-404',
  'L7TOUT' => 'Layer 7 (HTTP/SMTP) timeout',
  'L7RSP' => 'Layer 7 invalid response - protocol error',
  'L7STS' => 'Layer 7 response error, for example HTTP 5xx',
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
		sub {
			my $validator = $self->validate_str(1024);
			my $r = $validator->(@_);
			unless ($r =~ m/\?/ && $r =~ m/\/$/) {
				$r .= '/';
			}
			return $r;
		}
	);

	$self->cfgParamAdd(
		'ignore_backends',
		undef,
		'Regular expression matching backends you want to ignore. Syntax: /PATTERN/flags',
		$self->validate_regex(),
	);
	$self->cfgParamAdd(
		'only_backends',
		undef,
		'Regular expression matching backends which will be the only ones inspected. Syntax: /PATTERN/flags',
		$self->validate_regex(),
	);
	$self->cfgParamAdd(
		'ignore_frontends',
		undef,
		'Regular expression matching frontends you want to ignore. Syntax: /PATTERN/flags',
		$self->validate_regex(),
	);
	$self->cfgParamAdd(
		'only_frontends',
		undef,
		'Regular expression matching frontends which will be the only ones inspected. Syntax: /PATTERN/flags',
		$self->validate_regex(),
	);
	$self->cfgParamAdd(
		'min_up',
		50,
		'Minimum percents of active servers of active servers per backend. Syntax: /PATTERN/flags',
		$self->validate_int(1, 99),
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
	$self->bufApp();
	
	my $res = CHECK_OK;
	my $err = '';
	my $warn = '';
	
	# inspect backends...
	foreach my $bck_name (sort keys %{$data->{backends}}) {
	  my $bck = $data->{backends}->{$bck_name};

      # not part of check group?
      if (! $self->_isInOnlyBe($bck_name)) {
        $self->bufApp("Backend $bck_name is ignored.");
        next;
      }
      
      my $ignore_farm = $self->_isIgnoredBe($bck_name);
	  
	  # inspect backend servers
	  my $num_srvs = 0;
	  my $num_up = 0;
	  foreach my $srv_name (sort keys %{$bck->{nodes}}) {
	    my $srv = $bck->{nodes}->{$srv_name};

        next unless (ref($srv) eq 'HASH' && exists($srv->{status}) && defined($srv->{status}));
        my $status = uc($srv->{status});

        # haproxy 1.5.x stats interfaces can also contain
        # frontend data in "backend" sections; just ignore it...
        next if ($status eq 'OPEN');
        $num_srvs++;
        
        # is this backend in maintenance mode?
        if ($status eq 'MAINT') {
          $warn .= "BACKEND $bck_name/$srv_name is in maintenance mode.\n";
          $res = CHECK_WARN unless ($res == CHECK_ERR);
          next;
        }
        
        # should we just ignore any errors?
        if ($status eq 'UP' || $status eq 'NO CHECK') {
          $num_up++;
        } else {
          my $str = "BACKEND $bck_name/$srv_name is not in OK state: $status";
          if (defined $srv->{check_status}) {
            $str .= " [check $srv->{check_status}";
            $str .= " in $srv->{check_duration} msec:" if (defined $srv->{check_duration});
            $str .= " " . $srv->{check_status_str} if (defined $srv->{check_status_str});
            $str .= "]";
          }
          
          if ($ignore_farm) {
            $warn .= $str . "\n";
            $res = CHECK_WARN unless ($res == CHECK_ERR);
          } else {
            $err .= $str . "\n";
            $res = CHECK_ERR;
          }
        }
	    # $self->bufApp("$bck_name/$srv_name: " . $self->dumpVar($srv));
	  }
	  
	  # check entire backend/farm...
	  my $bck_total = $bck->{total};
	  if (ref($bck_total) eq 'HASH') {
	    my $st = $bck_total->{status};
	    unless ($st eq 'UP') {
	      my $str = "BACKEND $bck_name is in state $st.";

          if ($ignore_farm) {
            $warn .= $str . "\n";
            $res = CHECK_WARN unless ($res == CHECK_ERR);
          } else {
            $err .= $str . "\n";
            $res = CHECK_ERR;
          }	      
	    }
	  }
	  
	  # less than % are up?
	  if ($num_srvs) {
        my $pct_up = int(($num_up * 100) / $num_srvs);
        unless ($pct_up >= $self->{min_up}) {
          my $str = "BACKEND $bck_name has only $pct_up% active backends.";
          if ($ignore_farm) {
            $warn .= $str . "\n";
            $res = CHECK_WARN unless ($res == CHECK_ERR);
          } else {
            $err .= $str . "\n";
            $res = CHECK_ERR;
          }          
        }
	  }
	}
	
	# inspect frontends...
	foreach my $fe_name (sort keys %{$data->{frontends}}) {
	  my $fe = $data->{frontends}->{$fe_name}->{total};
	  my $st = $fe->{status};
	  
	  my $ignore_fe = $self->_isIgnoredFe($fe_name);
	  
	  # not in checking group?
	  next unless ($self->_isInOnlyFe($fe_name));
	  
	  unless (defined $st && $st eq 'OPEN') {
	    no warnings;
	    my $str = "FRONTEND $fe_name is in state '$st'";
	    $str .= " [$fe->{status_str}]" if (defined $fe->{status_str});

        if ($ignore_fe) {
          $warn .= $str . "\n";
          $res = CHECK_WARN unless ($res == CHECK_ERR);
        } else {
          $err .= $str . "\n";
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
	
	# parse and return data
	return $self->_parse_stats(\ $raw_data);
	
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

sub _parse_stats {
    my $self = undef;
	$self = shift if ($_[0] eq __PACKAGE__ || blessed($_[0]));
	my $ref = (ref($_[0]) eq 'SCALAR') ? $_[0] : \ $_[0];
	
	# should we bother?
	unless (defined $ref && length($$ref) > 0) {
	  $self->error("Unable to parse zero-length data.") if (defined $self && blessed($self));
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
	foreach (reverse(split(/[\r\n]+/, $$ref))) {
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
			if (defined $i && length($i) > 0) {
				# does the value look like na number?
				$i += 0 if ($i =~ m/^(?:\-|\+)?[\d\.]+$/);
				$tdata->{$_} = $i;
				
				# status?
				if ($_ eq 'status') {
					$tdata->{status_str} = _check_status_str($i);
				}
				elsif ($_ eq 'check_status') {
					$tdata->{check_status_str} = _check_status_str($i);
				}
			}
		} @_order;
		
		# svname and pxname must be defined
		my $svname = delete($tdata->{svname});
		my $pxname = delete($tdata->{pxname});
		next unless (defined $svname && length($svname) > 0);
		next unless (defined $pxname && length($pxname) > 0);
		
		if ($svname eq 'FRONTEND') {
			$last_fe = $pxname;
			$last_be = undef;
			%{$res->{frontends}->{$last_fe}->{total}} = %{$tdata};
		}
		elsif ($svname eq 'BACKEND') {
			$last_fe = undef;
			$last_be = $pxname;
			%{$res->{backends}->{$last_be}->{total}} = %{$tdata};
		} else {
			%{$res->{backends}->{$last_be}->{nodes}->{$svname}} = %{$tdata};
		}

	}
	
	return $res;
}

sub _statsSummary {
	my ($self, $data) = @_;
	return '' unless (defined $data && ref($data) eq 'HASH');
	my $no_farms = scalar(keys %{$data->{backends}});
	my $no_frontends = scalar(keys %{$data->{frontends}});
	my $no_real_backends = 0;
	# count real servers
	map {
		$no_real_backends += scalar(keys %{$data->{backends}->{$_}->{nodes}})
	} keys %{$data->{backends}};
	
	return	"  FRONTENDS:     $no_frontends\n" .
			"  BACKEND FARMS: $no_farms\n" .
			"  REAL BACKENDS: $no_real_backends";
}

sub _isInOnlyFe {
  my ($self, $name) = @_;
  return 1 unless (defined $name && length($name) > 0);
  return 1 unless (defined $self->{only_frontends});
  return ($name =~ $self->{only_frontends}) ? 1 : 0;
}

sub _isInOnlyBe {
  my ($self, $name) = @_;
  return 1 unless (defined $name && length($name) > 0);
  return 1 unless (defined $self->{only_backends});
  return ($name =~ $self->{only_backends}) ? 1 : 0;
}

sub _isIgnoredFe {
  my ($self, $name) = @_;
  return 0 unless (defined $name && length($name) > 0);
  return 0 unless (defined $self->{ignore_frontends});
  return ($name =~ $self->{ignore_frontends}) ? 1 : 0;
}

sub _isIgnoredBe {
  my ($self, $name) = @_;
  return 0 unless (defined $name && length($name) > 0);
  return 0 unless (defined $self->{ignore_backends});
  return ($name =~ $self->{ignore_backends}) ? 1 : 0;
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


sub _check_status_str {
	shift if ($_[0] eq __PACKAGE__ || blessed($_[0]));
	my $str = shift;

	$str = 'unk' unless (defined $str && length($str) > 0);
	$str = uc($str);
	$str = 'UNK' unless (exists($_check_status->{$str}));
	return $_check_status->{$str};
}

=head1 SEE ALSO

=over

=item L<P9::AA::Check>

=item L<P9::AA::Check::URL>

=item L<P9::AA::Check::_Socket>

=item L<http://code.google.com/p/haproxy-docs/wiki/StatisticsMonitoring#CSV_format>

=back

=head1 AUTHOR

Brane F. Gracnar

=cut
1;