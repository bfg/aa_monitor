package Noviforum::Adminalert::Check::Rsync;

use strict;
use warnings;

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::_Socket';

our $VERSION = 0.12;

##################################################
#              PUBLIC  METHODS                   #
##################################################

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks remote RSYNC server availability."
	);
	
	$self->cfgParamAdd(
		'host',
		'localhost',
		'Rsync server hostname.',
		$self->validate_str(1024)
	);
	$self->cfgParamAdd(
		'port',
		873,
		'Rsync server port.',
		$self->validate_int(1, 65535)
	);
	
	return 1;
}

sub check {
	my ($self) = @_;
	my $c = $self->sockConnect(
		$self->{host},
		PeerPort => $self->{port},
		Timeout => $self->{timeout}
	);
	return CHECK_ERR unless ($c);

	my $c_result = undef;
	unless (($c_result = <$c>) =~ /^\@RSYNCD/) {
		return $self->error("Wrong server response! What is running there?");
	}
	$c_result =~ s/\s+$//g;

	$self->bufApp("Server response: '$c_result'") if ($self->{debug});
	return CHECK_OK;
}

1;