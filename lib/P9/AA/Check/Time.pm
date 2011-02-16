package P9::AA::Check::Time;

use strict;
use warnings;

use Time::HiRes;

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

use constant NTP_ADJ => 2208988800;

our $VERSION = 0.24;

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription(
		"Checks difference between localtime on running host and reference time server(s)."
	);
	
	$self->cfgParamAdd(
		'time_diff_threshold',
		60,
		'Maximum allowed time difference between local clock and NTP server\'s clock in milliseconds.',
		$self->validate_int(0, 30000),
	);
	$self->cfgParamAdd(
		'ntp_hosts',
		'ntp.server.com',
		'Comma separated list of NTP servers.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'ntp_port',
		123,
		'NTP server port.',
		$self->validate_int(1, 65535),
	);	
	$self->cfgParamAdd(
		'timeout',
		2,
		'NTP query timeout in seconds.',
		$self->validate_int(1)
	);
	$self->cfgParamAdd(
		'min_ok_responses',
		1,
		'Minimum number of successfull checks.',
		$self->validate_int(1)
	);
	
	$self->cfgParamRemove('timeout_connect');
	
	return 1;
}

sub check {
	my ($self) = @_;

	my @results = (); 	
	foreach my $host (split(/\s*[,;]+\s*/, $self->{ntp_hosts})) {
		$host =~ s/^\s+//g;
		$host =~ s/\s+$//g;
		my $port = $self->{ntp_port};
		if ($host =~ m/^([a-z0-9\-\.]+):(\d+)$/) {
			$host = $1;
			$port = $2;
		}
		push(@results, $self->_checkNTPServer($host, $port));
	}
	
	my $no_ok = grep(/^1$/, @results);
	if ($no_ok < $self->{min_ok_responses}) {
		return $self->error(
			"To few successfull responses from NTP servers (REQUIRED: " .
			$self->{min_ok_responses} . "; OK: $no_ok; FAILED: " .
			($#{results} + 1 - $no_ok) . ")."
		);
	}
	return CHECK_OK;
}

sub _checkNTPServer {
	my ($self, $host, $port) = @_;
	my $result = 1;

	$self->bufApp("### Checking NTP server '$host:$port'.");
	my $t = Time::HiRes::time();
	my $data = undef;
	eval {
		$data = $self->_getNTPData($host, $port);
	};
	
	if ($@) {
		$self->{error} = "Error retrieving time data: " . $@;
		return 0;
	}

	unless (defined $data) {
		$self->{error} = "Error checking NTP server: " . $self->{error};
		$self->bufApp($self->{error});
		return 0;
	}

	$self->bufApp(sprintf("%-25.25s %-20.20s %10.10s", "Timestamp", "Difference", "Status"));
	for my $f ("Receive", "Transmit", "Originate") {
		my $key = $f . " Timestamp";
		unless (defined $data->{$key}) {
			$self->{error} = "NTP structure property \"$key\" is not defined.";
			$result = 0;
			next;
		}
		my $val = $data->{$key};
		my $diff = ($val - $t);
		my $str = "";

		if (abs($diff) > $self->{time_diff_threshold}) {
			$str = "[FAILURE: clock skew too big]";
			$result = 0;
		} else {
			$str .= " [OK]";
		}
		$self->bufApp(sprintf("%-25.25s %-.3f ms. %35.35s", $f, $diff, $str));
	}
	$self->bufApp();
	return $result;
}

#
# This function is taken from Net::NTP module and lightly altered.
#
# Copyright 2004 by James G. Willmore
#
# This library is free software; you can redistribute it and/or modify
# it under the same terms as Perl itself.
# 
sub _getNTPData {
	my ($self, $host, $port) = @_;

	my %MODE = (
		'0' => 'reserved',
		'1' => 'symmetric active',
		'2' => 'symmetric passive',
		'3' => 'client',
		'4' => 'server',
		'5' => 'broadcast',
		'6' => 'reserved for NTP control message',
		'7' => 'reserved for private use'
	);

	my %STRATUM = (
		'0' => 'unspecified or unavailable',
		'1' => 'primary reference (e.g., radio clock)',
	);

	for (2 .. 15) {
		$STRATUM{$_} = 'secondary reference (via NTP or SNTP)';
	}

	for(16 .. 255) {
		$STRATUM{$_} = 'reserved';
	}

	my %STRATUM_ONE_TEXT = (
		'LOCL'=> 'uncalibrated local clock used as a primary reference for a subnet without external means of synchronization',
		'PPS' => 'atomic clock or other pulse-per-second source individually calibrated to national standards',
		'ACTS'  => 'NIST dialup modem service',
		'USNO'  => 'USNO modem service',
		'PTB'   => 'PTB (Germany) modem service',
		'TDF'   => 'Allouis (France) Radio 164 kHz',
		'DCF'   => 'Mainflingen (Germany) Radio 77.5 kHz',
		'MSF'   => 'Rugby (UK) Radio 60 kHz',
		'WWV'   => 'Ft. Collins (US) Radio 2.5, 5, 10, 15, 20 MHz',
		'WWVB'  => 'Boulder (US) Radio 60 kHz',
		'WWVH'  => 'Kaui Hawaii (US) Radio 2.5, 5, 10, 15 MHz',
		'CHU'   => 'Ottawa (Canada) Radio 3330, 7335, 14670 kHz',
		'LORC'  => 'LORAN-C radionavigation system',
		'OMEG'  => 'OMEGA radionavigation system',
		'GPS'   => 'Global Positioning Service',
		'GOES'  => 'Geostationary Orbit Environment Satellite',
	);

	my %LEAP_INDICATOR = (
		'0'=> 'no warning',
		'1'=> 'last minute has 61 seconds',
		'2'=> 'last minute has 59 seconds)',
		'3'=> 'alarm condition (clock not synchronized)'
	);

	my @ntp_packet_fields = (
		'Leap Indicator',
		'Version Number',
		'Mode',
		'Stratum',
		'Poll Interval',
		'Precision',
		'Root Delay',
		'Root Dispersion',
		'Reference Clock Identifier',
		'Reference Timestamp',
		'Originate Timestamp',
		'Receive Timestamp',
		'Transmit Timestamp',
	);

	my $frac2bin = sub {
		my $bin= '';
		my $frac = shift;
		while (length($bin) < 32) {
			$bin= $bin . int($frac * 2);
			$frac = ($frac * 2) - (int($frac * 2));
		}
		return $bin;
	};

	my $bin2frac = sub {
		my $str = shift;
		return 0 unless (defined $str);
		my @bin = split '', $str;
		my $frac = 0;
		while (@bin) {
			$frac = ($frac + pop @bin) / 2;
		}
		return $frac;
	};

	my $percision = sub {
		my $number = shift;
		if ($number > 127) {
			$number -= 255;
		}
		return sprintf("%1.4e", 2**$number);
	};

	my $unpack_ip = sub {
		my $ip;
		my $stratum = shift;
		my $tmp_ip = shift;
		if ($stratum < 2) {
			$ip = unpack("A4", pack("H8", $tmp_ip));
		} else {
			$ip = sprintf("%d.%d.%d.%d", unpack("C4", pack("H8", $tmp_ip)));
		}
		return $ip;
	};

	# try to connect
	#my $sock = IO::Socket::INET->new(
	my $sock = $self->sockConnect(
		$host,
		Proto => 'udp',
		PeerPort => $port,
		Timeout => $self->{timeout}
	);
	
	unless (defined $sock) {
		$self->{error} = "Unable to connect to NTP server: $@";
		return undef;
	}
	
	# remove possible default die() handler
	local $SIG{__DIE__} = 'DEFAULT';
	local $SIG{ALRM} = sub {
		die "Operation timed out.";
	};

	my %tmp_pkt;
	my %packet;
	my $data;

	my $client_localtime = time();
	my $client_adj_localtime = $client_localtime + NTP_ADJ;
	my $client_frac_localtime = $frac2bin->($client_adj_localtime);

	my $ntp_msg = pack( "B8 C3 N10 B32", '00011011', (0) x 12, int($client_localtime), $client_frac_localtime);

	alarm($self->{timeout});
	eval { 	$sock->send($ntp_msg); };
	alarm(0);

	if ($@) {
		$self->{error} = "Error talking to NTP server: $@";
		return undef;
	}

	alarm($self->{timeout});
	eval{ $sock->recv($data, 960); };
	alarm(0);

	if ($@) {
		$self->{error} = "Error talking to NTP server: $@";
		return undef;
	}
	elsif (length($data) < 1) {
		$self->{error} = "No data received from NTP server.";
		return undef;
	}

	my @ntp_fields = qw/byte1 stratum poll precision/;
	push @ntp_fields, qw/delay delay_fb disp disp_fb ident/;
	push @ntp_fields, qw/ref_time ref_time_fb/;
	push @ntp_fields, qw/org_time org_time_fb/;
	push @ntp_fields, qw/recv_time recv_time_fb/;
	push @ntp_fields, qw/trans_time trans_time_fb/;

	@tmp_pkt{@ntp_fields} = unpack("a C3 n B16 n B16 H8 N B32 N B32 N B32 N B32", $data);

	@packet{@ntp_packet_fields} = (
		(unpack( "C", $tmp_pkt{byte1} & "\xC0" ) >> 6),
		(unpack( "C", $tmp_pkt{byte1} & "\x38" ) >> 3),
		(unpack( "C", $tmp_pkt{byte1} & "\x07" )),
		$tmp_pkt{stratum},
		(sprintf("%0.4f", $tmp_pkt{poll})),
		$tmp_pkt{precision} - 255,
		($bin2frac->($tmp_pkt{delay_fb})),
		(sprintf("%0.4f", $tmp_pkt{disp})),
		$unpack_ip->($tmp_pkt{stratum}, $tmp_pkt{ident}),
		(($tmp_pkt{ref_time} += $bin2frac->($tmp_pkt{ref_time_fb})) -= NTP_ADJ),
		(($tmp_pkt{org_time} += $bin2frac->($tmp_pkt{org_time_fb})) ),
		(($tmp_pkt{recv_time} += $bin2frac->($tmp_pkt{recv_time_fb})) -= NTP_ADJ),
		(($tmp_pkt{trans_time} += $bin2frac->($tmp_pkt{trans_time_fb})) -= NTP_ADJ)
	);

	return \ %packet;
}

=head1 SEE ALSO

L<P9::AA::Check>, 
L<Net::NTP>

=head1 AUTHOR

Brane F. Gracnar

B<WARNING>: This module includes slightly altered code from L<Net::NTP>
written by James G. Willmore.

=cut
1;