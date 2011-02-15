package Noviforum::Adminalert::Check::MemcachedRepl;

use strict;
use warnings;

use Time::HiRes qw(sleep);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::Memcached';

our $VERSION = 0.12;

##################################################
#              PUBLIC  METHODS                   #
##################################################

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Memcached replication health checking module."
	);
	
	$self->cfgParamAdd(
		'peer_host',
		'localhost:21211',
		'Replication peer host.',
		$self->validate_str(250),
	);
	$self->cfgParamAdd(
		'replication_delay_msec',
		100,
		'Maximum replication delay in milliseconds.',
		$self->validate_int(1),
	);
	
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;

	# return value is success by default...
	my $r = CHECK_OK;
	
	# try to connect to both memcached backends
	my $conn_a = $self->mcConnect($self->{host});
	return 0 unless (defined $conn_a);
	my $conn_b = $self->mcConnect($self->{peer_host});
	return 0 unless (defined $conn_b);

	# compute data
	my $key = "aa_monitor_" . rand();
	my $val = rand();
	$self->bufApp("TX KEY: '$key'; VALUE: '$val'");

	# write data to first backend
	unless ($self->mcSet($conn_a, $key, $val)) {
		$self->error(
			"Unable to write data to first backend: " .
			$self->error()
		);
		$r = CHECK_ERR;
		goto outta_ping;
	}
	
	$self->bufApp("Sleeping $self->{replication_delay_msec} milliseconds before trying to fetch data from replicated backend.");
	if ($self->{replication_delay_msec} > 0) {
		my $sleep_interval = $self->{replication_delay_msec} / 1000;
		sleep($sleep_interval);
	}

	# read data from first backend
	my $val_a = $self->mcGet($conn_a, $key);
	unless (defined $val_a) {
		$self->error(
			"Unable to read data from first backend: " .
			$self->error()
		);
		$r = CHECK_ERR;
		goto outta_ping;
	}
	$self->bufApp("RX [A] KEY: '$key'; VALUE: '$val_a'");

	# read data from second backend
	my $val_b = $self->mcGet($conn_b, $key);
	unless (defined $val_b) {
		$self->error(
			"Unable to read data from replication peer backend: " .
			$self->error()
		);
		$r = CHECK_ERR;
		goto outta_ping;
	}
	$self->bufApp("RX [B] KEY: '$key'; VALUE: '$val_b'");
	
	# validate read data...
	unless ($val eq $val_a && $val_a eq $val_b) {
		my $err = "Replication doesn't work correctly. ";
		$err .= "Wrote value '$val', backend A replied '$val_a', ";
		$err .= "replication peer replied with '$val_b'.";
		$self->error($err);
		$r = CHECK_ERR;
		goto outta_ping;
	}
	
	# fire exit door :)
	outta_ping:

	# remove stuff from both backends and
	# don't check for results and create
	# copy of last error message in case of
	# error.
	my $err = undef;
	$err = $self->error() unless ($r);
	$self->mcRemove($conn_a, $key) if (defined $conn_a);
	$self->mcRemove($conn_b, $key) if (defined $conn_b);
	$self->error($err) if (defined $err);

	return $r;
}

sub toString {
	my $self = shift;
	no warnings;
	my $str = $self->{host};
	if ($self->{host} !~ /:\d+$/) {
		$str .= ':' . $self->{port};
	}
	
	$str .= " <=> " . $self->{peer_host};
	if ($self->{peer_host} !~ /:\d+$/) {
		$str .= ':' . $self->{port};
	}

	return $str;
}

1;