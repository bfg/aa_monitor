package P9::AA::Check::IntelSensors;

use strict;
use warnings;

use File::Spec;
use POSIX qw(:sys_wait_h);

use P9::AA::Constants;
use base 'P9::AA::Check';

our $VERSION = 0.11;

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription(
		"Checks Intel BMC sensors data."
	);

	$self->cfgParamAdd(
		'status_ok',
		'Warn-lo, BelowCrit, OK',
		'Comma separated list of statuses considered as successful.',
		$self->validate_lcstr(100),
	);
	$self->cfgParamAdd(
		'frontpanel_max_temp',
		29,
		'Maximum frontpanel temperature',
		$self->validate_int(1),
	);

	return 1;
}

sub check {
	my ($self) = @_;
	
	my $data = $self->getSensorData();
	unless (defined $data) {
		return CHECK_ERR;
	}

	# select success statuses
	my @ok = split(/\s*[;,]+\s*/, lc($self->{status_ok}));

	my $result = CHECK_OK;
	my $err = '';

	no warnings;
	foreach my $sensor (@{$data}) {
		my $status = $sensor->{status};
		if ($sensor->{name} eq 'FntPnl Amb Temp') {
			if ($sensor->{value_num} > $self->{frontpanel_max_temp}) {
				my $str = "Frontpanel temperature is too high (" . $sensor->{value} .").";
				$self->bufApp($str);
				$err .= $str . "\n";
				$result = CHECK_ERR;
			}
		}
		elsif (length($status) > 0) {
			my $lc_status = lc($status);
			if (grep(/^$lc_status$/, @ok) < 1) {
				my $str = sprintf(
					"Sensor \"%s\", number \"%s\" : value \"%s\", status: \"%s\"",
					$sensor->{name},
					$sensor->{num},
					$sensor->{value},
					$sensor->{status}
				);
	
				$self->bufApp($str);
				$err .= $str . "\n";
				$result = CHECK_ERR;
			}
		}
	}
	
	if ($result != CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	
	return $result;
}

sub getSensorData {
	my ($self) = @_;
	$self->error("This method is not implemented on " . $self->getOs() . " operating system.");
	return undef;
}

1;