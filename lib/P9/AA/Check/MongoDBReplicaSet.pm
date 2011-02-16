package P9::AA::Check::MongoDBReplicaSet;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::MongoDB';

our $VERSION = 0.10;

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
		"Checks MongoDB replica set status. Check uses MongoDB HTTP rest interface."
	);

	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# check for server status
	my $d = $self->getServerStatus($self->{mongo});
	if (defined $d) {
		$self->bufApp("MongoDB seems to be up and running on $self->{mongo}");
		return CHECK_ERR;
	}

	return CHECK_OK;
}

=head1 SEE ALSO

L<P9::AA::Check::MongoDB>,
L<P9::AA::Check>  

=head1 AUTHOR

Brane F. Gracnar

=cut
1;
# EOF