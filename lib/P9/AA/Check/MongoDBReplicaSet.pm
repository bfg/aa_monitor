package P9::AA::Check::MongoDBReplicaSet;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::MongoDB';

our $VERSION = 0.12;

use constant DEFAULT_REST_PORT => 28017;

#
# See http://www.mongodb.org/display/DOCS/Replica+Set+Commands#ReplicaSetCommands-%5C
#
my $rs_states = {
		0 => 'Starting up, phase 1 (parsing configuration)',
		1 => 'Primary',
		2 => 'Secondary',
		3 => 'Recovering',
		3 => 'Fatal error',
		5 => 'Starting up, phase 2 (forking threads)',
		6 => 'Unknown state',
		7 => 'Arbiter',
		8 => 'Down',
		9 => 'Rollback',
};
my @rs_states_ok = qw(1 2 7);

=head1 NAME

MongoDB L<http://www.mongodb.org/> replica set status validating module.

=cut

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::MongoDB>.

=cut
# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks MongoDB replica set status. Check uses MongoDB HTTP REST interface."
	);

	return 1;
}

sub check {
	my ($self) = @_;
	
	# perform normal mongo check...
	return CHECK_ERR unless ($self->SUPER::check() == CHECK_OK);
	$self->bufApp();
	
	# get replica set members...
	my $rs_data = $self->getReplicaSetMembers($self->{mongo});
	return CHECK_ERR unless (defined $rs_data);
	
	# check each and every member
	my $err = '';
	my $res = CHECK_OK;
	
	foreach my $rs (@{$rs_data}) {
		my $rs_name = $rs->{_id};
		$self->bufApp("REPLICA SET: $rs_name");
		foreach my $member (@{$rs->{members}}) {
			my $host = $member->{host};
			my $port = DEFAULT_REST_PORT;
			if ($host =~ m/(.+):(\d+)$/) {
				$host = $1;
				$port = $2;
				$port += 1000;
				$host = $host . ":" . $port;
			} else {
				$host .= ":" . $port;
			}

			$self->bufApp("  Member: $host");
			my $data = $self->getReplicaSetStatus($host);
			unless (defined $data) {
				$err = "Unable to get replica set '$rs_name' member $host status: " . $self->error();
				$res = CHECK_ERR;
				next;
			}
		
			# validate data...
			my ($status, $buf) = $self->_validateRsData($data);
			$self->bufApp($buf);
			$self->bufApp();
			unless ($status) {
				$err = $self->error();
				$res = CHECK_ERR;
				next;
			}
		}
	}

	unless ($res == CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	return $res;
}

sub _validateRsData {
	my ($self, $data) = @_;
	my $set_name = $data->{set};
	my $mystate = $data->{myState};
	
	my $buf = '';
	my $res = 1;
	my $err = '';
	
	foreach my $member (@{$data->{members}}) {
		my $id = $member->{_id};
		my $host = $member->{name};
		
		# for more info, see: http://www.mongodb.org/display/DOCS/Replica+Set+Commands#ReplicaSetCommands-%5C
		my $health = $member->{health};
		unless (defined $health && $health eq '1') {
			$err .= "Replica set $set_name: Member $host is not healthy - status: '$health'\n";
			$res = 0;
		}
		
		# check state:
		my $state = $member->{state};
		unless (defined $state) {
			$err .= "Replica set $set_name: Member $host has undefined replica set state.\n";
			$res = 0;
		}
		my $state_str = (exists($rs_states->{$state})) ? $rs_states->{$state} : undef;
		
		{
			no warnings;
			$buf .= "    $host [id: $id, healthy: ";
			$buf .= (defined $health && $health eq '1') ? "yes" : "no";
			$buf .= ", state: $state_str]\n"; 
		}
		
		unless (defined $state_str) {
			$err .= "Replica set $set_name: Member $host has undefined replica set state '$state'.\n";
			$res = 0;
			next;
		}
		unless (grep { $_ eq $state } @rs_states_ok) {
			$err .= "Replica set $set_name: Member $host bad state: $state_str.\n";
			$res = 0;
			next;
		}
	}
	
	unless ($res) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	
	return (wantarray ? ($res, $buf) : $res);
}

=head1 SEE ALSO

L<P9::AA::Check::MongoDB>,
L<P9::AA::Check>  

=head1 AUTHOR

Brane F. Gracnar

=cut
1;
# EOF