package P9::AA::Check::MongoDB;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::JSON';

our $VERSION = 0.10;

=head1 NAME

MongoDB L<http://www.mongodb.org/> server validating module.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::JSON>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks MongoDB server status. Check uses MongoDB HTTP rest interface."
	);

	$self->cfgParamAdd(
		'mongo',
		'localhost:28017',
		'MongoDB HTTP rest interface <host>:<port>',
		$self->validate_str(1000),
	);
	
	$self->cfgParamRemove('content_pattern');
	$self->cfgParamRemove('content_pattern_match');
	$self->cfgParamRemove('host_header');
	$self->cfgParamRemove('request_body');
	$self->cfgParamRemove('request_method');
	$self->cfgParamRemove('user_agent');
	$self->cfgParamRemove('url');
	$self->cfgParamRemove(qr/^header[\w\-]+/);
	
	return 1;
}

sub toString {
	my $self = shift;
	no warnings;
	return $self->{mongo};
}

# actually performs ping
sub check {
	my ($self) = @_;

	# check for server status
	my $d = $self->getServerStatus($self->{mongo});
	if (defined $d) {
		$self->bufApp("MongoDB seems to be up and running on $self->{mongo}");
		return CHECK_OK;
	}

	return CHECK_ERR;
}

=head2 getServerStatus

 my $data = $self->getServerStatus($host_port);

Returns hash reference containing data about MongoDB running at $host_port
on success, otherwise undef.

Note that mongod B<MUST> have web interface enabled.

=cut
sub getServerStatus {
	my ($self, $host) = @_;

	# compute REST url
	my $url = 'http://' . $host . '/serverStatus?text';
	
	# get json
	my $data = $self->getJSON(url => $url);
	unless (defined $data) {
		$self->error("Unable to get MongoDB server status: " . $self->error());
		return undef;
	}
	
	return $data;
}

=head2 getReplicaSetStatus

 my $data = $self->getReplicaSetStatus($host_port);

Returns hash reference containing data about MongoDB replica set for
mongod running at $host_port on success, otherwise undef.

=cut
sub getReplicaSetStatus {
	my ($self, $host) = @_;

	# compute REST url
	my $url = 'http://' . $host . '/replSetGetStatus?text';
	
	# get json
	my $data = $self->getJSON(url => $url);
	unless (defined $data) {
		$self->error("Unable to get replica set status: " . $self->error());
		return undef;
	}
	
	return $data;
}

=head2 getReplicaSetMembers

 my $members = $self->getReplicaSetMembers($host_port);

Returns array reference containing list of MongoDB replica set members for
mongod running at $host_port on success, otherwise undef.

=cut
sub getReplicaSetMembers {
	my ($self, $host) = @_;
	# compute url
	my $url = 'http://' . $host . '/local/system.replset/?html=0';
	
	# get json
	my $data = $self->getJSON(url => $url);
	unless (defined $data) {
		$self->error("Unable to get list of replica set members: " . $self->error());
		return undef;
	}
	
	# filter json...
	unless (exists($data->{rows})) {
		$self->error("Replica set members JSON doesn't contain rows attribute.");
		return undef;
	}
	
	return $data->{rows};
}

##################################################
#              PRIVATE METHODS                   #
##################################################

sub _preprocessRawJSON {
	my ($self, $json) = @_;	
	# Date( "Wed Oct 27 14:26:09 2010" )
	${$json} =~ s/Date\s*\((.+)\)/$1/gm;

	return 1;
}


=head1 SEE ALSO

L<P9::AA::Check::JSON>,
L<P9::AA::Check::URL>,  
L<P9::AA::Check>  

=head1 AUTHOR

Brane F. Gracnar

=cut

1;
# EOF