package P9::AA::Check::RTSP;

use strict;
use warnings;

use URI;

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

our $VERSION = 0.13;

=head1 NAME

RTSP video/audio stream checking module.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::_Socket>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"RTSP service check."
	);

	$self->cfgParamAdd(
		'url',
		'rtsp://host.example.com::554/public/stream.sdp',
		'RTSP resource URL address.',
		$self->validate_str(8192),
	);
	$self->cfgParamAdd(
		'timeout_playback',
		1,
		'Timeout for waiting for RTSP playback stream data in seconds.',
		$self->validate_int(1),
	);
	$self->cfgParamAdd(
		'playback_bytes',
		2048,
		'How many bytes to read from playback stream?',
		$self->validate_int(1),
	);

	return 1;
}

sub _rtspSetup {
	my ($self, $e) = @_;
	my $cb = $e->{content_base};
	my $tid = $e->{track_id};
	my $type = $e->{type};
	unless (defined $cb) {
		$self->error("Undefined key: content_base");
		return undef;
	}
	unless (defined $tid) {
		$self->error("Undefined key: track_id");
		return undef;
	}
	unless (defined $type) {
		$self->error("Undefined key: type");
		return undef;
	}

	my $perr = "[id: $tid, type: $type] ";
	
	my $err = '';
	my $result = {
		udp => undef,
		play_url => undef,
		content_base => $e->{content_base},
		track_id => $e->{track_id},
		type => $e->{type},
	};

	my $play_url = $cb . 'trackID=' . $tid;
	$self->bufApp("SETUP [content-base: $cb; type: $type]:");
	$self->bufApp("  PLAY URL: $play_url");
		
	# create UDP listening socket
	$result->{udp} = $self->_udpListenerCreate();
	unless ($result->{udp}) {
		$self->error(
			$perr . "Unable to create udp listening socket: " .
			$self->error() . "\n"
		);
		return undef;
	}
		
	# get listening port number
	my $udp_port = $result->{udp}->sockport();
	$self->bufApp("  Created UDP listening socket on port $udp_port");

	# create another RTSP connection...
	my $conn = $self->rtspConnect($self->{url});
	unless ($conn) {
		$self->error(
			$perr . "Unable to create additional connection: " .
			$self->error() . "\n"
		);
		return undef;
	}

	# create client_port=header property
	my $cp_str = $udp_port . '-' . ($udp_port + 1);
		
	# SETUP
	$self->bufApp("  SETUP $play_url; client_port=$cp_str");
	my ($ok, $setup) = $conn->command("SETUP $play_url", 'Transport' => 'RTP/AVP;unicast;client_port=' . $cp_str);
	unless ($ok) {
		$self->error(
			$perr . "Error setting up playback: " . $conn->error() . "\n"
		);
		return undef;
	}

	# get session id
	my $session = $setup->{headers}->{session};
	unless (defined $session && length $session) {
		$self->error(
			$perr .
			"Error setting up playback: No session id in SETUP response\n"
		);
		return undef;
	}
	$session = (split(/[;,]+/, $session))[0];
	$self->bufApp("  Session ID: $session");
	$result->{session} = $session;

	return $result;
}

sub _rtspPlay {
	my ($self, $e) = @_;
	my $perr = "[id: $e->{track_id}, type: $e->{type}] ";

	$self->bufApp();
	$self->bufApp("Playing $perr");
	# create another RTSP connection...
	my $conn = $self->rtspConnect($self->{url});
	unless ($conn) {
		$self->error(
			$perr . "Unable to create additional connection: " .
			$self->error() . "\n"
		);
		return undef;
	}
	
	# start playback!
	my ($okp, $play) = $conn->command("PLAY $self->{url}", Session => $e->{session});
	unless ($okp) {
		$self->error($perr . "Error starting playback: $play->{status}");
		return 0;
	}
		
	# try to read played stream...
	local $@;
	my $buf = eval { $self->_udpRead($e->{udp}) };
	if ($@) {
		$@ =~ s/\s+at\s+.+//g;
		$@ =~ s/\s+$//g;
		$self->error($perr . "Error reading UDP playback stream: $@");
		return 0;
	}
	unless (defined $buf && length($buf) > 0) {
		$self->error($perr . "No data read from UDP playback stream: $@");
		return 0;
	}
	my $read_len = length $buf;
	$self->bufApp("  Read $read_len bytes of UDP playback stream.");
		
	# we should teardown the session right now.
	# but we want. too lazy to code that...
	$self->bufApp("  Stream id $e->{track_id} [$e->{type}] looks healthy.");

	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	my $describe = $self->getDescribe($self->{url});
	return CHECK_ERR unless (defined $describe);

	my $err = '';
	my $result = CHECK_OK;
	
	# do setups first!
	my @setups = ();
	foreach my $e (@{$describe}) {
		$self->bufApp();
		my $x = $self->_rtspSetup($e);
		unless (defined $x) {
			$err .= $self->error() . "\n";
			next;
		}
		push(@setups, $x);
	}
	unless (@setups) {
		$self->error("No SETUP commands finished successfully!");
		return CHECK_ERR;
	}
	
	# now try to play streams...
	foreach my $e (@setups) {
		unless ($self->_rtspPlay($e)) {
			$err .= $self->error() . "\n";
			$result = CHECK_ERR;
		}
	}
	
	# validate check...
	unless ($result == CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	return $result;
}

# describes check, optional.
sub toString {
	my ($self) = @_;
	return $self->{url};
}

=head2 getDescribe

 my $desc = $self->getDescribe('rtsp://host.example.org:554/something.sdp'));

Returns parsed describe structure as arrayref on success, otherwise undef.

Example structure:

 [
  {
    'content_base' => 'rtsp://host.example.org:554/public/live/tv.sdp/',
    'track_id' => '3',
    'type' => 'audio 0 RTP/AVP 96'
  },
  {
    'content_base' => 'rtsp://host.example.org:554/public/live/tv.sdp/',
    'track_id' => '4',
    'type' => 'video 0 RTP/AVP 97'
  }
 ]

=cut
sub getDescribe {
	my ($self, $url) = @_;
	$self->error('');
	my $perr = 'Unable to get RTSP stream description: ';

	# try to connect...
	my $rtsp = $self->rtspConnect($url);
	unless ($rtsp) {
		$self->error($perr . $self->error());
		return undef;
	}
	
	# get rtsp info about url...
	my $describe = $rtsp->describe();
	unless ($describe && ref($describe) eq 'ARRAY') {
		$self->error($perr . $rtsp->error());
		return undef;
	}
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN RTSP URL DESCRIBE DATA ---");
		$self->bufApp($self->dumpVar($describe));
		$self->bufApp("--- BEGIN RTSP URL DESCRIBE DATA ---");
	}

	return $describe;
}

=head2 rtspConnect

 my $conn = $self->rtspConnect('rtsp://host.example.org:554/something.sdp');

Returns initialized MyRTSP object on success, otherwise undef.

=cut
sub rtspConnect {
	my ($self, $url) = @_;
	my $u = URI->new($url);
	my $hp = $u->host_port();
    # anything in cache?
	if (exists($self->{_cache}->{$hp})) {
	  return $self->{_cache}->{$hp};
	}

	my $rtsp = MyRTSP->new(connector => $self, debug => $self->{debug});
	unless ($rtsp->connect_url($url)) {
		$self->error("Unable to connect: " . $rtsp->error());
		return undef;
		#$rtsp = undef;
	}
		
	# send OPTIONS command first...
	my $r = $rtsp->command("OPTIONS *");

	$self->{_cache}->{$hp} = $rtsp;
	return $rtsp;
}

sub _udpListenerCreate {
	my ($self) = @_;
	my $sock = undef;
	for (1 .. 10) {
		my $port = int(rand(20000)) + 10000;
		# create UDP listening port...
		$sock = $self->sockConnect(
			Proto => 'udp',
			LocalPort => $port,
			Reuse => 1,
		);
		last if (defined $sock);
	}

	return $sock;
}

sub _udpRead {
	my ($self, $sock) = @_;
	my $buf = '';
	local $SIG{ALRM} = sub { die "Timeout waiting for UDP playback data packet." };
	alarm($self->{timeout_playback}) if ($self->{timeout_playback});
	read($sock, $buf, $self->{playback_bytes});
	alarm(0);
	return $buf;
}

=head1 SEE ALSO

L<P9::AA::Check::_Socket>,
L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut

package MyRTSP;

use strict;
use warnings;

use URI;
use Scalar::Util qw(blessed);
use constant CRLF => "\r\n";
use Data::Dumper;

our $VERSION = 0.10;
my $Error = '';

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my %opt = @_;
	
	my $self = {
		_socket => undef,
		_error => '',
		_seq => 0,
		_session => undef,
		_uri => undef,
		_host => undef,
		_port => 0,
		_connector => undef,
	};
	# connector object?
	my $c = delete($opt{connector}) || undef;
	if (blessed($c) && $c->can('sockConnect')) {
		$self->{_connector} = $c;
	}
	if ($opt{debug}) {
		$self->{_debug} = 1;
	}

	bless($self, $class);
}

sub error {
	my $self = shift;
	return (ref($self)) ? $self->{_error} : $Error;
}

sub _error {
	my $self = shift;
	if (ref($self)) {
		$self->{_error} = join('', @_);
	} else {
		$Error = join('', @_);
	}
}

sub connect_url {
	my ($self, $url) = @_;
	return 1 if (defined $self->{_socket} && $self->{_socket}->connected());
	local $@;
	my $uri = eval { URI->new($url) };
	if ($@) {
		$self->_error("Exception while constructing URI object: $@");
		return 0;
	}
	unless ($uri->isa('URI::rtsp')) {
		$self->_error("Non-RTSP URL: $url");
		return 0;
	}
	
	my $host = $uri->host();
	my $port = $uri->port();
	unless ($port) {
		$port = 554;
		$uri->port($port);
	}
	
	my $sock = $self->_connect($host, $port);
	return 0 unless ($sock);

	$self->{_uri} = $uri;
	$self->{_socket} = $sock;
	return 1;
}

sub _connect {
	my ($self, $host, $port) = @_;
	my $connector = ($self->{_connector}) ? $self->{_connector} : 'IO::Socket::INET';
	my $method = (blessed($connector)) ? 'sockConnect' : 'new';
	
	my $sock = eval { $connector->$method(PeerAddr => $host, PeerPort => $port, proto => 'tcp') };
	
	unless ($sock) {
		$self->_error("Unable to connect: " . $connector->error());
	}

	return $sock;
}

sub command {
	my ($self, $cmd, %headers) = @_;
	unless (defined $cmd && length $cmd) {
		$self->_error("Undefined command.");
	}
	
	my $s = $self->{_socket};
	unless (defined $s && $s->connected()) {
		$self->_error("Not connected.");
		return undef;
	}
	
	$self->{_seq}++;
	print "" if ($self->{_debug});
	
	$self->{_last_cmd} = $cmd;

	my $buf = $cmd . " RTSP/1.0" . CRLF;
	$buf .= "CSeq: $self->{_seq}" . CRLF;
	$buf .= "User-Agent: " . ref($self) . "/" . sprintf("%-2.2f", $VERSION) . CRLF;
	map { $buf .= "$_: $headers{$_}" . CRLF } sort keys %headers;
	$buf .= CRLF;
	
	$self->_print_s($s, $buf);

	# read response
	return $self->_response($s);
}

sub _print_s {
	my ($self, $s, $data) = @_;
	print "  >> $data" if ($self->{_debug});
	print $s $data;
}

sub _response {
	my ($self, $s) = @_;

	my $buf = '';
	my $header_read = 0;
	my $resp = undef;
	my $code = 0;

	my $data = {
		code => 0,
		status => '',
		headers => {},
		body => '',
	};

	# read headers
	while (1) {
		my $line = <$s>;
		last unless (defined $line);
		$line =~ s/[\r\n]+$//g;
		last unless (length $line);
		print "  << $line\n" if ($self->{_debug});
		unless (defined $resp) {
			# RTSP/1.0 200 OK..
			if ($line =~ m/^(RTSP\/+\d+\.\d+)\s+(\d+)\s+(.+)/i) {
				$code = $2;
				$data->{code} = $code;
				$data->{status} = $1 . ' ' . $3;
				$resp = 1;
			}
			next;
		}
		
		# headers
		my ($h, $v) = split(/\s*:\s*/, $line, 2);
		$h = lc($h);
		next unless (defined $h && defined $v);
		if (exists($data->{headers}->{$h})) {
			$data->{headers}->{$h} = "; " . $v;
		} else {
			$data->{headers}->{$h} = $v;
		}
	}
	
	my $ok = (defined $code && $code >= 200 && $code < 400) ? 1 : 0;
	
	# should we read some body?
	my $ct = $data->{headers}->{'content-length'};
	if (defined $ct) {
		no warnings;
		$ct = int($ct);
	} else {
		$ct = 0;
	}
	# read body...
	read($s, $data->{body}, $ct) if ($ct > 0);
	unless ($ok) {
	    my $sock_connected = (defined $s && blessed($s) && $s->can('connected') && $s->connected()) ? 1 : 0;
		unless (defined $data->{code} && $data->{code} >= 200 && $data->{code} < 400) {
		  $data->{code} = 595;
		  $data->{status} = "Unable to parse RTSP response, read " . length($data->{body}) . " bytes.";
		}
		$self->_error("Bad RTSP response (connected: $sock_connected) [cmd: $self->{_last_cmd}]: $data->{code} $data->{status}");
	}
	
	return ($ok, $data);
}

sub describe {
	my ($self, $uri) = @_;
	unless (blessed($uri) && $uri->isa('URI::rtsp')) {
		$uri = $self->{_uri};
	}
	unless (defined $uri) {
		$self->_error("Bad URI");
		return undef;
	}

	# Send describe command...
	my ($ok, $res) = $self->command("DESCRIBE $uri");
	return undef unless ($ok);
	
	# parse body...
	my $r = _parse_desc($res->{body}, $res->{headers});
	
	unless (@{$r}) {
		$self->_error("No tracks were parsed from DESCRIBE response body.");
		return undef;
	}
	
	return $r;
}

sub _parse_desc {
	my ($str, $headers) = @_;
	
	# content base?
	my $cb = (exists $headers->{'content-base'}) ? $headers->{'content-base'} : undef;
	$cb = undef unless (defined $cb && length $cb);

	my $r = [];
	my $last_m = undef;
	foreach (split(/[\r\n]+/, $str)) {
		if ($_ =~ m/^m=(.+)/i) {
			$last_m = $1;
		}
		# get track id
		elsif ($_ =~ m/^a=control:trackID=(.+)/) {
			my $e = { type => $last_m, track_id => $1};
			$e->{content_base} = $cb if ($cb);
			push(@{$r}, $e);
			$last_m = undef;
		}
	}

	return $r;
}

1;