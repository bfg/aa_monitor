package P9::AA::Check::DNSCompare;

use strict;
use warnings;

use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::DNS';

our $VERSION = 0.11;

=head1 NAME

This module checks single DNS record on multiple DNS server(s).

=head1 METHODS

This class inherits all methods from L<P9::AA::Check::DNS>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription("Checks single DNS record on multiple DNS server(s).");

	$self->cfgParamAdd(
		'nameserver_peers',
		undef,
		'Comma separated list of peer nameservers.',
		$self->validate_lcstr(1024),
	);
	
	return 1;
}

sub check {
	my ($self) = @_;	
	unless (defined $self->{host} && length($self->{host}) > 0) {
		return $self->error("Query host is not set.");
	}
	
	my @peers = $self->_peer_list($self->{nameserver_peers});
	unless (@peers) {
		return $self->error("DNS nameserver peer hosts are not set.");
	}
	
	# get referential data
	my $data_ref = $self->resolve($self->{host}, $self->{type}, $self->{class}, $self->{nameserver});
	unless (defined $data_ref) {
		return $self->error("Error resolving referential data: " . $self->error());
	}
	
	$self->bufApp("--- BEGIN REFERENTIAL DATA ---");
	$self->bufApp($self->dnsPacketToStr($data_ref));
	$self->bufApp("--- END REFERENTIAL DATA ---");
	$self->bufApp();

	my $cmp = {};

	# get records from peer nameservers...
	foreach my $ns (@peers) {
		my $d = $self->resolve($self->{host}, $self->{type}, $self->{class}, $ns);
		$cmp->{$ns} = [ $d, $self->error() ];
	}
	
	my $res = CHECK_OK;
	my $err = '';
	
	# check peers
	foreach my $ns (keys %{$cmp}) {
		my $d = $cmp->{$ns}->[0];
		my $e = $cmp->{$ns}->[1];
		unless (defined $d) {
			$err = "Nameserver $ns: " . $e . "\n";
			$res = CHECK_ERR;
			next;
		}
		
		$self->bufApp("--- BEGIN $ns ---");
		$self->bufApp($self->dnsPacketToStr($d));
		$self->bufApp("--- END $ns ---");
		$self->bufApp();
		
		# compare data with referential one...
		unless ($self->_compare($data_ref, $d)) {
			$err .= "Nameserver $ns: " . $self->error() . "\n";
			$res = CHECK_ERR;
			next;
		}
	}

	unless ($res == CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	return $res;
}

sub toString {
	my ($self) = @_;
	no warnings;
	return $self->{host} . '/' .
		$self->{type} . '/' .
		$self->{class} .
		' [' .
		$self->{nameserver} . ' <=> ' .
		join(",", $self->_peer_list($self->{nameserver_peers})) .
		']';
}

sub _compare {
	my ($self, $ref, $cmp) = @_;
	unless (defined $ref && ref($ref) eq 'HASH') {
		$self->error("Invalid referential structure.");
		return 0;
	}
	unless (defined $cmp && ref($cmp) eq 'HASH') {
		$self->error("Invalid comparing structure.");
		return 0;
	}

	# answer
	unless ($self->_compareRecords($ref->{answer}, $cmp->{answer})) {
		$self->error("Answer section differs: " . $self->error());
		return 0;
	}
	# additional
	unless ($self->_compareRecords($ref->{additional}, $cmp->{additional})) {
		$self->error("Additional section differs: " . $self->error());
		return 0;
	}
	# authority
	unless ($self->_compareRecords($ref->{authority}, $cmp->{authority})) {
		$self->error("Authority section differs: " . $self->error());
		return 0;
	}

	return 1;
}

=head1 SEE ALSO

L<P9::AA::Check::DNS>, 
L<P9::AA::Check>, 
L<Net::DNS>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;