package Noviforum::Adminalert::Check::DNSCompare;

use strict;
use warnings;

use Scalar::Util qw(blessed);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::DNS';

our $VERSION = 0.10;

=head1 NAME

This module checks single DNS record on multiple DNS server(s).

=head1 METHODS

This class inherits all methods from L<Noviforum::Adminalert::Check::DNS>.

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
	# compute peers...
	my @peer_hosts = ();
	{
		no warnings;
		map {
			if (defined $_ && length $_) {
				push(@peer_hosts, $_);
			}
		} split(/\s*[,;]+\s*/, $self->{nameserver_peers});
	}
	unless (@peer_hosts) {
		return $self->error("No peer nameservers defined.");
	}

	# create referential resolver object
	my $resolver_ref = $self->getResolver();
	unless (defined $resolver_ref) {
		return $self->error("Error creating referential resolver: " . $self->error());
	}

	# create peer resolvers
	my @peers = ();
	foreach (@peer_hosts) {
		my $r = $self->getResolver($_);
		unless (defined $r) {
			return $self->error("Error creating comparing resolver $_: ", $self->error());
		}
	}

=pod
	# send DNS packet to server...
	local $@;
	my $packet = eval { $res->send($self->{host}, $self->{type}, $self->{class}) };
	if ($@) {
		return $self->error("Exception sending packet: $@");
	}
	unless (defined $packet) {
		return $self->error("Unable to resolve: " . $res->errorstring());
	}
	
	# check the packet...
	my @answer = $packet->answer();
	my @authority = $packet->authority();
	my @additional = $packet->additional();

	# print answer section
	$self->bufApp("") if ($self->{debug});
	$self->bufApp("ANSWER section:");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp("    " . $_->string());
	} @answer;
	$self->bufApp("--- snip ---");

	# print authority section
	$self->bufApp("AUTHORITY section:");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp("    " . $_->string());
	} @authority;
	$self->bufApp("--- snip ---");
	
	# print additional section
	$self->bufApp("ADDITIONAL section:");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp("    " . $_->string());
	} @additional;
	$self->bufApp("--- snip ---");

	# any answers? this could be a problem :)
	unless (@answer) {
		if ($self->{check_authority}) {
			if (@authority) {
				$self->bufApp("");
				$self->bufApp("Answer section is empty, but authority section contains records.");
				return 1;
			} else {
				return $self->error("DNS query finished successfully, but ANSWER and AUTHORITY sections are both empty!");
			}
		}

		return $self->error("DNS query finished successfully, but no records were returned in ANSWERS dns packet section!");
	}
=cut

	# return success...
	return $self->success();
}

sub toString {
	my ($self) = @_;
	no warnings;
	return $self->{host} . '/' .
		$self->{type} . '/' .
		$self->{class} .
		' [' .
		$self->{nameserver} . ' <=> ' . $self->{nameserver_peers}. ']';
}


=head1 SEE ALSO

L<Noviforum::Adminalert::Check::DNS>, 
L<Noviforum::Adminalert::Check>, 
L<Net::DNS>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;