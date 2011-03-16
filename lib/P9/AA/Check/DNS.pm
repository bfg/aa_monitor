package P9::AA::Check::DNS;

use strict;
use warnings;

use Net::DNS;
use Digest::MD5 qw(md5_hex);
use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check';

our $VERSION = 0.14;

=head1 NAME

DNS check implementation and basic DNS infrastructure.

=head1 METHODS

This class inherits all methods from L<P9::AA::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription("Checks remote DNS server for availability.");

	$self->cfgParamAdd(
		'nameserver',
		$self->_getDefaultNs(),
		'Hostname of DNS server which will be queried.',
		$self->validate_lcstr(1024),
	);
	$self->cfgParamAdd(
		'host',
		undef,
		'Query for specified host/zone.',
		$self->validate_lcstr(1024),
	);
	$self->cfgParamAdd(
		'type',
		'A',
		'Queries for specified type.',
		$self->validate_ucstr(4),
	);
	$self->cfgParamAdd(
		'class',
		'IN',
		'Query class.',
		$self->validate_ucstr(2),
	);
	$self->cfgParamAdd(
		'timeout',
		2,
		'DNS query timeout in seconds.',
		$self->validate_int(1),
	);
	$self->cfgParamAdd(
		'check_authority',
		0,
		'Check authority section for NS records in case of empty answer section.',
		$self->validate_bool(),
	);
	
	return 1;
}

sub check {
	my ($self) = @_;	
	unless (defined $self->{host} && length($self->{host}) > 0) {
		return $self->error("Query host is not set.");
	}

	# create resolver object
	my $res = $self->getResolver();
	return CHECK_ERR unless (defined $res);

	# get data...
	my $data = $self->resolve($self->{host}, $self->{type}, $self->{class});
	return CHECK_ERR unless (defined $data);
	
	# check the packet...
	my $answer = $data->{answer};
	my $authority = $data->{authority};
	my $additional = $data->{additional};

	# print answer section
	$self->bufApp("") if ($self->{debug});
	$self->bufApp("ANSWER section:");
	$self->bufApp("--- snip ---");
	my $types = 0;
	map {
		$self->bufApp("    " . $_->string());
		$types++ if ($_->isa('Net::DNS::RR::' . uc($self->{type})))
	} @${answer};
	
	$self->bufApp("--- snip ---");

	# print authority section
	$self->bufApp("AUTHORITY section:");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp("    " . $_->string());
	} @{$authority};
	$self->bufApp("--- snip ---");
	
	# print additional section
	$self->bufApp("ADDITIONAL section:");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp("    " . $_->string());
	} @{$additional};
	$self->bufApp("--- snip ---");

	# any answers? this could be a problem :)
	if (@{$answer}) {
		# count type matches...
		my $type_matches = 0;
		map { $type_matches++ if ($_->isa('Net::DNS::RR::' . uc($self->{type}))) } @{$answer};
		unless ($type_matches > 0) {
			return $self->error("Answer section doesn't contain any records of type $self->{type}.");
		}
		$self->bufApp("Answer section contains $type_matches $self->{type} type records.");
	} else {
		if ($self->{check_authority}) {
			if (@{$authority}) {
				# autority section should contain at least one NS record...
				my $ns = 0;
				map { $ns++ if ($_->isa('Net::DNS::RR::NS')) } @{$authority};
				unless ($ns > 0) {
					return $self->error("Answer section is empty and authority section doesn't contain any NS records.");
				}
				$self->bufApp("");
				$self->bufApp("Answer section is empty, but authority section contains $ns NS record(s).");
				return CHECK_OK;
			} else {
				return $self->error("DNS query finished successfully, but ANSWER and AUTHORITY sections are both empty!");
			}
		}

		return $self->error("DNS query finished successfully, but no records were returned in ANSWER dns packet section!");
	}

	# return success...
	return $self->success();
}

sub toString {
	my ($self) = @_;
	no warnings;
	return $self->{host} . '/' .
		$self->{type} . '/' .
		$self->{class} .
		' @' .
		$self->{nameserver};
}

=head2 getResolver

Prototype:

 my $resolver = $self->getResolver([$nameserver]);

Returns initialized L<Net::DNS::Resolver> object.

=cut
sub getResolver {
	my ($self, $nameserver) = @_;
	$nameserver = $self->{nameserver} unless (defined $nameserver && length($nameserver));
	$nameserver = '127.0.0.1' unless (defined $nameserver);

	# create resolver object
	my $res = eval {
		Net::DNS::Resolver->new(
			nameservers => [ $nameserver ],
			# debug => $self->{debug},
			tcp_timeout => $self->{timeout},
			udp_timeout => $self->{timeout},
		)
	};
	unless (defined $res) {
		$self->error("Unable to create DNS resolver object: $!/$@");
	}

	return $res;
}

=head2 resolve

 my $res = $self->resolve('host.example.com' [$type = 'A', $class = 'IN', $resolver])

Returns hash reference containing answer, additional and authority keys containing
arrayrefs of L<Net::DNS::RR> objects on success, otherwise undef. Optional resolver
argument can be hostname or initialized L<Net::DNS::Resolver> object.

=cut
sub resolve {
	my ($self, $host, $type, $class, $res) = @_;
	$type = 'A' unless (defined $type);
	$class = 'IN' unless (defined $class);
	
	if (defined $res) {
		unless (blessed($res) && $res->isa('Net::DNS::Resolver')) {
			$res = $self->getResolver($res);
		}
	} else {
		$res = $self->getResolver();
	}
	
	unless (defined $res) {
		$self->error("Invalid resolver.");
		return undef;
	}

	# send DNS packet to server...
	local $@;
	my $packet = eval { $res->send($host, $type, $class) };
	if ($@) {
		$self->error("Exception sending packet: $@");
		return undef;
	}
	unless (defined $packet) {
		$self->error("Unable to resolve: " . $res->errorstring());
		return undef;
	}
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN RETURNED PACKET ---");
		$self->bufApp($packet->string());
		$self->bufApp("--- END RETURNED PACKET ---");
		$self->bufApp();
	}
	
	# check for bad queries...
	my $err = $res->errorstring();
	if (lc($err) ne 'noerror') {
		$self->error(
			"Resolver(s) " . join(", ", $res->nameservers()) .
			" error [host: $host, type: $type, class: $class]: $err"
		);
		return undef;
	}

	my $result = {
		answer => [ $packet->answer() ],
		authority => [ $packet->authority() ],
		additional => [ $packet->additional() ],
	};
	
	# basic checks...
	unless (@{$result->{answer}} || @{$result->{authority}}) {
		$self->error("Nothing was resolved: " . $err);
		return undef;
	}

	return $result;
}

=head2 zoneAXFR

 my $records = $self->zoneAXFR($name [, $resolver, $class = 'IN']);

Tries to perform zone $name zone transfer. Returns array reference of L<Net::DNS::RR> records
on success, otherwise undef. Optional $resolver argument can be hostname or L<Net::DNS::Resolver>
object.

=cut
sub zoneAXFR {
	my ($self, $zone, $res, $class) = @_;
	unless (defined $zone && length($zone)) {
		$self->error("Invalid/Undefined zone name.");
		return undef;
	}
	$class = 'IN' unless (defined $class && length($class));
	$class = uc($class);

	if (defined $res) {
		unless (blessed($res) && $res->isa('Net::DNS::Resolver')) {
			$res = $self->getResolver($res);
		}
	} else {
		$res = $self->getResolver();
	}
	unless (defined $res) {
		$self->error("Invalid resolver.");
		return undef;
	}

	# prepare error message prefix
	my $ns_list = join(', ', $res->nameservers());
	my $err = 'Error transfering zone ' .
		$zone . ' from ' . $ns_list . ': ';

	my $result = [];
	local $@;
	@{$result} = eval { $res->axfr($zone, $class) };
	if ($@) {
		$self->error($err . "Exception: $@");
		return undef;
	}
	unless (@{$result}) {
		$self->error($err . $res->errorstring());
		return undef;
	}
	
	# first argument MUST be SOA
	my $soa = $result->[0];
	unless (blessed($soa) && $soa->isa('Net::DNS::RR::SOA')) {
		$self->error($err . "Zone is missing SOA record. This is extremely weird.");
		return undef;
	}

	if ($self->{debug}) {
		$self->bufApp(
			"DNS zone transfer of zone $zone from $ns_list returned " .
			($#{$result} + 1) . " record(s)."
		);
	}

	return $result;	
}

=head2 dnsPacketToStr

 my $str = $self->dnsPacketToStr($packet);

Returns nice string representation of $packet. $packet can be L<Net::DNS::Packet> object
or hash reference returned by L</resolve> method.

=cut
sub dnsPacketToStr {
	my ($self, $packet) = @_;
	my $buf = '';
	
	my @answer = ();
	my @authority = ();
	my @additional = ();
	
	if (blessed($packet) && $packet->isa('Net::DNS::Packet')) {
		@answer = $packet->answer();
		@authority = $packet->authority();
		@additional = $packet->additional();
	}
	elsif (ref($packet) eq 'HASH') {
		@answer = @{$packet->{answer}};
		@authority = @{$packet->{authority}};
		@additional = @{$packet->{additional}};
	}
	
	$buf .= "--- ANSWER ---\n";
	map { $buf .= $_->string . "\n" } @answer;
	$buf .= "--- AUTHORITY\n";
	map { $buf .= $_->string . "\n" } @authority;
	$buf .= "--- ADDITIONAL\n";
	map { $buf .= $_->string . "\n" } @additional;

	return $buf;
}

sub _compareRecords {
	my ($self, $ref, $cmp) = @_;
	unless (ref($ref) eq 'ARRAY' && ref($cmp) eq 'ARRAY') {
		$self->error("Reference and comparision arguments must both be array refs.");
		return 0;
	}

	my @r = ();
	my @cmp = ();
	foreach (@{$ref}) {
		next unless (blessed($_) && $_->isa('Net::DNS::RR'));
		push(@r, $_->string());
	}
	foreach (@{$cmp}) {
		next unless (blessed($_) && $_->isa('Net::DNS::RR'));
		push(@cmp, $_->string());
	}
	
	# create string buffers...
	my $buf_ref = join("\n", sort(@r));
	my $buf_cmp = join("\n", sort(@cmp));
	
	# create digests.
	my $digest_ref = md5_hex($buf_ref);
	my $digest_cmp = md5_hex($buf_cmp);
	
	if ($digest_ref ne $digest_cmp) {
		$self->error("\nRef:\n" . $buf_ref . "\nvs.\nCmp:\t" . $buf_cmp . "\n");
		return 0;
	}
	
	return 1;
}

sub _peer_list {
	my ($self, $str) = @_;
	my @res = ();
	return @res unless (defined $str && length($str));
	foreach (split(/\s*[;,]+\s*/, $str)) {
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		next unless (length $_);
		push(@res, $_);
	}

	return sort @res;
}

sub _getDefaultNs {
	my ($self) = @_;
	my $ns = '127.0.0.1';
	
	my $fd = IO::File->new('/etc/resolv.conf', 'r');
	return $ns unless (defined $fd);
	my $i = 0;
	while ($i < 100 && defined (my $line = <$fd>)) {
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length $line);
		next if ($line =~ m/^#/);
		
		if ($line =~ m/^nameserver\s+([0-9\.:a-f]+)/) {
			$ns = $1;
			last;
		}
	}
	
	return $ns;
}

=head1 SEE ALSO

L<P9::AA::Check>, 
L<Net::DNS>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;