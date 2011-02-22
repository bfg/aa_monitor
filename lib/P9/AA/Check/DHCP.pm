package P9::AA::Check::DHCP;

use strict;
use warnings;

use bytes;
use Sys::Hostname;
use Net::DHCP::Packet;
use Net::DHCP::Constants;
use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

use constant BUF_LEN => 1024;

our $VERSION = 0.22;

my $_has_net_arp = undef;

=head1 NAME

DHCP server checking module.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::_Socket>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks if remote DHCP (IPv4) server delivers DHCP lease."
	);
	
	$self->cfgParamAdd(
		'interface',
		'eth0',
		'Use specified network interface.',
		$self->validate_str(10),
	);
	$self->cfgParamAdd(
		'ether_addr',
		undef,
		'Interface ethernet (MAC) address. It will be automatically discovered if not specified and module Net::ARP is available.',
		$self->validate_str(17),
	);
	$self->cfgParamAdd(
		'dhcp_server',
		undef,
		'DHCP server hostname or IP address. Leave it undefined if don\'t care which DHCP server sends response.',
		$self->validate_str(250),
	);
	$self->cfgParamAdd(
		'dhcp_server_aliases',
		'',
		'Comma separated list of DHCP server aliases. This option will be only evaluated if \'dhcp_server\' option is set.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'expected_addr',
		undef,
		'Expected client\'s IP address in DHCP server response. Check will fail if it is set and if DHCP server responds with different proposed address.',
		$self->validate_str(250),
	);
	$self->cfgParamAdd(
		'hostname',
		hostname(),
		'Send specified hostname in DHCP request packet',
		$self->validate_str(250),
	);
	$self->cfgParamAdd(
		'timeout',
		3,
		'DHCP operation timeout',
		$self->validate_int(1),
	);
	$self->cfgParamAdd(
		'debug_dhcp',
		0,
		'Display sent/received DHCP packets?',
		$self->validate_bool(),
	);
	
	# fix common _socket stuff. We don't want IPv6!
	$self->cfgParamRemove('timeout_connect');
	$self->cfgParamRemove('debug_socket');
	$self->cfgParamRemove('ipv6');
	$self->{ipv6} = 'off';

	return 1;
}

sub check {
	my ($self) = @_;
	
	# we must be t00r to perform this check...
	unless ($> == 0) {
		return $self->error("This module requires process to be running with r00t privileges.");
	}
	
	my $ds = $self->{debug_socket};
	$self->{debug_socket} = $self->{debug};

	return CHECK_ERR unless ($self->_initCheck());

	# obtain exclusive lock...
	return CHECK_ERR unless ($self->_exclusiveLock());

	# remove any ':' chars from ethernet address
	my $ether_addr = $self->{ether_addr};
	$ether_addr =~ s/://g;
	
	# use broadcast address if dhcp server is not set.
	my $dhcp_server = $self->{dhcp_server};
	if (defined $dhcp_server) {
		$dhcp_server =~ s/[^\w\-\.]+//g;
		$dhcp_server = undef unless (length($dhcp_server));
	}

	# generate transaction id
	my $xid = $self->_xid();
	
	# create request dhcp packet...
	my $request = Net::DHCP::Packet->new(
		DHO_DHCP_MESSAGE_TYPE() => DHCPDISCOVER(),
		Xid => $xid,
		Chaddr => $ether_addr,
		Hostname => $self->{hostname}
	);

	# we want broadcast answer if no dhcp server was set
	#unless (defined $dhcp_server && length($dhcp_server)) {
		$request->flags(0x8000);
	#}

	# prepare listening socket...
	my $sock_in = $self->dhcpPrepareListeningSocket();
	return CHECK_ERR unless (defined $sock_in);

	# send dhcp packet
	return CHECK_ERR unless ($self->dhcpSend($request, $dhcp_server));

	# receive response
	my $response = $self->dhcpRecv($sock_in, $self->{timeout});
	return CHECK_ERR unless (defined $response);
	
	# validate received DHCP packet
	my $r = $self->validateDHCPResponse(
		$response,
		$request,
		$self->_getOpt()
	);
	
	return ($r) ? CHECK_OK : CHECK_ERR;
}

sub toString {
	my $self = shift;
	no warnings;
	my $str = 'srv=' . $self->{dhcp_server};
	$str .= ', mac=' . $self->{ether_addr};
	$str .= ', expected_addr=' . $self->{expected_addr};
	
	return $str;
}

sub _initCheck {
	my ($self) = @_;
	
	if (! (defined $self->{interface} || defined $self->{ether_addr})) {
		$self->error("Interface is not set, neighter is ethernet address.");
		return 0;
	}

	# no ethernet/mac address?
	unless (defined $self->{ether_addr} && length($self->{ether_addr})) {
		unless ($self->hasNetArp()) {
			$self->error(
				"Argument ether_addr is not set and module Net::ARP is not available. " .
				"Unable to determine interface ethernet address."
			);
			return 0;
		}
		
		# try to get interface ethernet address
		$self->bufApp("PREPARE: Argument ether_addr is not set,") if ($self->{debug});
		$self->bufApp("PREPARE: trying to discover ethernet address for device " . $self->{interface} . " using module Net::ARP.") if ($self->{debug});
		my $mac = "";
		eval {
			$mac = Net::ARP::get_mac($self->{interface});
			$mac = uc($mac) if (defined $mac);
		};
		if ($@) {
			$self->error("Unable to obtain interface '" . $self->{interface} . "' MAC address: $@");
			return 0;
		}
		elsif (length($mac) < 1) {
			$self->error("Unable to obtain interface '" . $self->{interface} . "' MAC address: unknown error $!");
			return 0;
		}
		else {
			$self->bufApp("Discovered ethernet address for interface $self->{interface}: $mac");
			$self->{ether_addr} = $mac;
		}
	}

	return 1;
}

=head2 dhcpPrepareListeningSocket

Prepares DHCP listening socket ready to receive DHCP responses. Returns
initialized socket object on success, otherwise undef.

=cut
sub dhcpPrepareListeningSocket {
	my ($self) = @_;
	$self->bufApp("Creating UDP listening socket for receiving DHCP server responses...") if ($self->{debug});

	my %opts = (
		Proto => 'udp',
		PeerPort => 67,
		LocalPort => 68,
		Reuse => 1,
		Broadcast => 1,
		Timeout => $self->{timeout},
		Broadcast => 1,
		ipv6 => 'off',
	);
	
	return $self->sockConnect(undef, %opts);
}

=head2 dhcpSend

 my $r = $self->dhcpSend($packet [, $destination = '255.255.255.255']);

Sends $packet (L<Net::DHCP::Packet>) object to specified destination.
Returns 1 on success, otherwise 0.

=cut
sub dhcpSend {
	my ($self, $packet, $dst) = @_;
	unless (blessed($packet) && $packet->isa('Net::DHCP::Packet')) {
		$self->error("Invalid DHCP packet argument.");
		return 0;
	}
	
	my $err = 'Unable to send DHCP packet: ';
	
	# no destination? it must be a broadcast then...
	my $bc = 0;
	unless (defined $dst && length($dst)) {
		$bc = 1;
		$dst = '255.255.255.255';
	}
	
	# create sending socket
	my %opt = (
		Proto => 'udp',
		PeerPort => 67,
		LocalPort => 68,
		Reuse => 1,
		Timeout => $self->{timeout},
		Broadcast => $bc,
		PeerAddr => $dst,
		ipv6 => 'off',
	);
	my $sock = $self->sockConnect($dst, %opt);
	unless ($sock) {
		$self->error($err . $self->error());
		return 0;
	}
	
	use bytes;
	my $pkg_len = length($packet->serialize());

	if ($self->{debug_dhcp} && ref($packet)) {
		my $str = $packet->toString();
		my @tmp = split(/[\r\n]+/, $str);
		$self->bufApp("[DHCP_SEND]: --- BEGIN PACKET TO BE SENT---");
		map { $self->bufApp('    ' . $_) } @tmp;
		$self->bufApp("[DHCP_SEND]: --- END PACKET TO BE SENT ---");
	}

	# send the goddamn packet
	my $len = eval { $sock->send($packet->serialize()) };
	if ($@) {
		$self->error($err . $@);
		return 0;
	}
	elsif ($len < $pkg_len) {
		$self->error("Entire packet was not sent (only $len of $pkg_len bytes were sent): $!");
		return 0;
	}

	$self->bufApp("[DHCP SEND]: DHCP packet sent [$len bytes].") if ($self->{debug});
	return 1;
}

=head2 dhcpRecv

 my $obj = $self->dhcpRecv($sock [, $timeout]);

Tries to receive DHCP response on socket $sock. Returns initialized
L<Net::DHCP::Packet> object on success, otherwise undef.

=cut
sub dhcpRecv {
	my ($self, $sock, $timeout) = @_;
	unless (blessed($sock) && $sock->isa('IO::Socket')) {
		$self->error("Invalid receiving UDP socket.");
		return undef;
	}

	my $err = 'Error receiving DHCP packet: ';

	# try to receive packet	
	$self->bufApp("[DHCP_RECV]: Waiting for DHCP packet...") if ($self->{debug});
	my $buf = '';
	local $@;
	local $SIG{ALRM} = sub { die "Timeout.\n" };
	alarm($timeout) if (defined $timeout && $timeout > 0);
	eval { $sock->recv($buf, BUF_LEN) };
	alarm(0);
	if ($@) {
		$self->error($err . $@);
		return undef;
	}
	my $len = length($buf);
	unless ($len > 0) {
		$self->error($err . "No bytes received: $!");
		return undef;
	}
	$self->bufApp("[DHCP_RECV]: Received $len bytes of data.") if ($self->{debug});


	my $packet = Net::DHCP::Packet->new();
	eval { $packet->marshall($buf)	};
	if ($@) {
		$self->error("Error constructing DHCP packet from receivd data: $@");
		return undef
	}
	
	if ($self->{debug_dhcp} && ref($packet)) {
		my $str = $packet->toString();
		my @tmp = split(/[\r\n]+/, $str);
		$self->bufApp("[DHCP_RECV]: --- BEGIN RECEIVED PACKET ---");
		map { $self->bufApp('    ' . $_) } @tmp;
		$self->bufApp("[DHCP_RECV]: --- END RECEIVED PACKET ---");
	}

	return $packet;
}

=head2 hasNetArp

Returns 1 if L<Net::ARP> module is available, otherwise 0.

=cut
sub hasNetArp {
	unless (defined $_has_net_arp) {
		$_has_net_arp = eval 'use Net::ARP; 1';
	}
	return $_has_net_arp;
}

=head2 validateDHCPResponse

 my $r = $self->validateDHCPResponse($response [, $request, %opt]);

Validates DHCP response packet. Returns 1 on success, otherwise 0.

=cut
sub validateDHCPResponse {
	my ($self, $response, $request, %opt) = @_;

	# check response...
	unless ($self->_validatePacket($response)) {
		$self->error(
			"Invalid response packet: " .
			$self->error()
		);
		return 0;
	}

	# now validate just received packet...
	unless ($response->isDhcp()) {
		$self->error("Response is not a DHCP response packet.");
		return 0;
	}

	# do we have request packet?
	if (defined $request) {
		# check validity...
		unless ($self->_validatePacket($request)) {
			$self->error(
				"Invalid request packet: " .
				$self->error()
			);
			return 0;
		}

		# transaction xids must match
		if ($request->xid() != $response->xid()) {
			$self->error(
				"DHCP transaction ids differ. " .
				"[request: " . $request->xid() .
				", response: " . $response->xid() .
				"]"
			);
			return 0;
		}
	}

	# get DHCP type as string of response packet...
	my $type = $response->getOptionValue(DHO_DHCP_MESSAGE_TYPE());
	my $type_str = $self->_type2str($type);
	return 0 unless (defined $type_str);

	# DHCP type should be DHCPOFFER or DHCPACK
	if ($type == DHCPOFFER()) {
		return $self->validateDHCPOffer($response, %opt);
	}
	elsif ($type == DHCPACK()) {
		return $self->validateDHCPack($response, %opt);
	}
	else {
		$self->error("Invalid or unsupported DHCP server response: $type_str.");
		return 0;
	}
}

=head2 validateDHCPOffer ($packet, %opt)

=cut
sub validateDHCPOffer {
	my ($self, $packet, %opt) = @_;
	return 0 unless ($self->_validatePacket($packet));
	
	my $err = 'Invalid DHCP OFFER packet: ';

	# fetch important stuff from packet...

	my $client_addr = $packet->yiaddr();
	unless (defined $client_addr && length($client_addr)) {
		$self->error($err . 'Empty offered IP address.');
		return 0;
	}

	my $subnet_mask = $packet->getOptionValue(DHO_SUBNET_MASK());
	unless (defined $subnet_mask && length($subnet_mask)) {
		$self->error($err . 'Empty subnet mask.');
		return 0;
	}

	my $renew_time = $packet->getOptionValue(DHO_DHCP_RENEWAL_TIME());
	my $lease_time = $packet->getOptionValue(DHO_DHCP_LEASE_TIME());

	my $dhcp_server = $packet->getOptionValue(DHO_DHCP_SERVER_IDENTIFIER());
	unless (defined $dhcp_server && length($dhcp_server)) {
		$self->error($err . 'Undefined DHCP server address.');
		return 0;
	}

	# write something to msgbuf
	{
		my $str = 'DHCP OFFER: ';
		$str .= "server: $dhcp_server, ";
		$str .= "client_address: $client_addr, ";
		$str .= "subnet_mask: $subnet_mask, ";
		$str .= "lease_time: $lease_time, ";
		$str .= "renew_time: $renew_time";
		
		$self->bufApp($str);
	}
	
	# additional check: offered IP address
	return 0 unless ($self->_checkExpectedAddr($packet, $opt{expected_addr}));

	# additional check: check if response came from the same
	# server that we have sent packet to.
	return 0 unless ($self->_checkExpectedServer($packet, $opt{dhcp_server}, $opt{dhcp_server_aliases}));

	return 1;
}

=head2 validateDHCPack ($packet, %opt)

=cut
sub validateDHCPack {
	my ($self, $packet, %opt) = @_;
	return 0 unless ($self->_validatePacket($packet));	
	$self->error("DHCP pack validation is not yet implemented.");
	return 0;
}

sub _validatePacket {
	my ($self, $packet) = @_;
	unless (defined $packet && blessed($packet) && $packet->isa('Net::DHCP::Packet')) {
		$self->error("Invalid DHCP packet: " . ref($packet));
		return 0;
	}

	return 1;
}

sub _checkExpectedAddr {
	my ($self, $packet, $requested_addr) =  @_;
	return 0 unless ($self->_validatePacket($packet));

	# no expected address? ok then...
	return 1 unless (defined $requested_addr && length($requested_addr));

	my $client_addr = $packet->yiaddr();
	unless (defined $client_addr && length($client_addr)) {
		$self->error("No client IP address specified in DHCP packet; this is weird.");
		return 0;
	}

	if ($requested_addr ne $client_addr) {
		$self->error(
			"Invalid DHCP response: " .
			"Expected client's IP address $requested_addr, DHCP server offered $client_addr."
		);
		return 0;
	}

	return 1;
}

sub _checkExpectedServer {
	my ($self, $packet, $server, $server_aliases) = @_;
	return 0 unless ($self->_validatePacket($packet));

	# no expected server?
	return 1 unless (defined $server && length($server));

	# resolve dhcp server and it's aliases
	my @addrs = $self->resolveHost($server, 1);
		
	# do we have aliases?
	if (defined $server_aliases) {
		foreach my $e (split(/\s*[;,]+\s*/, $server_aliases)) {
			next unless (defined $e && length($e) > 0);
			push(@addrs, $self->resolveHost($e, 1));
		}
	}

	my $dhcp_server = $packet->getOptionValue(DHO_DHCP_SERVER_IDENTIFIER());
	unless (defined $dhcp_server && length($dhcp_server)) {
		$self->error("No DHCP server specified in DHCP packet; this is weird.");
		return 0;
	}

	# check packet
	my $found = 0;
	foreach my $addr (@addrs) {
		next unless (defined $addr);
		if ($addr eq $dhcp_server) {
			$found = 1;
			last;
		}
	}
		
	unless ($found) {
		$self->error(
			"Invalid DHCP server response: " .
			"DHCP packet didn't come from DHCP server $server. " .
			"Resolved address(es): " . join(', ', @addrs)
		);
		return 0;
	}

	return 1;
}

# converts DHCP type to string
sub _type2str {
	my ($self, $type) = @_;
	# this is ugly and completely undocumented
	my $type_str = undef;
	if (defined $type && exists($Net::DHCP::Packet::REV_DHCP_MESSAGE{$type})) {
		$type_str = $Net::DHCP::Packet::REV_DHCP_MESSAGE{$type};
	}
	
	unless (defined $type_str) {
		no warnings;
		$self->error("Unknown DHCP message type: $type");
		return undef;
	}

	return uc($type_str);
}

sub _xid {
	return int(rand(0xFFFFFFFF));
}

sub _getOpt {
	my $self = shift;
	my %opt = ();
	foreach (keys %{$self}) {
		next unless (defined $_ && length($_));
		next if ($_ =~ m/^_/);
		$opt{$_} = $self->{$_};
	}
	return %opt;
}

sub _exclusiveLock {
	my $self = shift;
	return 1;
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<Net::DHCP::Packet>
L<Net::ARP>
L<P9::AA::Check>

=cut

1;