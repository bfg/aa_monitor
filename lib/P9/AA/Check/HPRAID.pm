package P9::AA::Check::HPRAID;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';

our $VERSION = 0.10;

=head1 NAME

HP/Compaq RAID adapter checking module.

=head1 METHODS

This class inherits all methods from L<P9::AA::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks HP/Compaq RAID array consistency."
	);

	$self->cfgParamAdd(
		'rebuild_state_is_ok',
		0,
		'Consider rebuild state as normal, errorless state?',
		$self->validate_bool(),
	);

	return 1;
}

sub check {
	my ($self) = @_;
	
	# get list of all adapters...
	my $data = $self->getAdapterData();
	return CHECK_ERR unless (defined $data);
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN HPRAID DATA ---");
		$self->bufApp($self->dumpVar($data));
		$self->bufApp("--- END HPRAID DATA ---");
	}

	# print nice volume summary...
	$self->bufApp($self->adapterDataToString($data));

	my $res = CHECK_OK;
	my $err = '';
	my $warn = '';

	foreach my $s (sort keys %{$data}) {
		my $slot = $data->{$s};
		foreach my $v (sort keys %{$slot->{volumes}}) {
			my $vol = $slot->{volumes}->{$v};
			foreach my $e (@{$vol}) {
				my $s = lc($e->{status});
				next if ($s eq 'ok');

				no warnings;
				
				# rebuild maybe?
				if ($self->{rebuild_state_is_ok} && _is_rebuild($s)) {
					$warn .= "Adapter slot $s, volume $v, port $e->{port}, bay $e->{bay} [$e->{misc}]: $s\n";
					$res = CHECK_WARN unless ($res == CHECK_ERR);
				}
				# nop, plain error
				else {
					$err .= "Adapter slot $s, volume $v, port $e->{port}, bay $e->{bay} [$e->{misc}]: $s\n";
					$res = CHECK_ERR;					
				}
				
			}
		}
	}

	if (length $warn) {
		$warn =~ s/\s+$//g;
		$self->warning($warn);
	}
	if ($res != CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}

	return $res;
}

=head2 getAdapterData

 my $data = $self->getAdapterData();

Returns hash reference containing volume/disk info for B<all> adapters found on system on
success, otherwise undef.

Example output:

 {
  # controller slot 0
  '0' => {
    'name' => 'Smart Array P410i',
    'serial' => '5001438006AF9EA0',
    'volumes' => {
      'A' => [
        {
          'bay' => '1',
          'box' => '1',
          'misc' => 'SAS, 146 GB',
          'port' => '1I',
          'status' => 'ok'
        },
        {
          'bay' => '2',
          'box' => '1',
          'misc' => 'SAS, 146 GB',
          'port' => '1I',
          'status' => 'ok'
        }
      ]
    }
  }
 }

=cut
sub getAdapterData {
	my ($self, $adapter) = @_;
	$self->error("This method is not supported on " . $self->getOs() . " operating system.");
	return undef;
}

=head2 getAdapterList

 my $list = $self->getAdapterList();

Returns array reference of MegaRAID adapter numbers on success, otherwise undef.

Example return value:

 [
  {
    'name' => 'Smart Array P410i',
    'serial' => '5001438006AF9EA0',
    'slot' => 0
  }
 ]

=cut
sub getAdapterList {
	my ($self) = @_;
	$self->error("This method is not implemented on " . $self->getOs() . " operating system.");
	return undef;
}

=head2 adapterDataToString

 my $str = $self->adapterDataToString($data);

Formats data returned by L</getAdapterData> to nice string summary.

=cut
sub adapterDataToString {
	my ($self, $data) = @_;
	no warnings;
	my $buf = '';
	
	foreach my $s (sort keys %{$data}) {
		my $slot = $data->{$s};
		$buf .= "ADAPTER: $s [name: $slot->{name}, serial: $slot->{serial}]\n";
		foreach my $v (sort keys %{$slot->{volumes}}) {
			my $vol = $slot->{volumes}->{$v};
			$buf .= "  VOLUME: $v\n";
			foreach my $e (@{$vol}) {
				$buf .= "    port $e->{port} [bay: $e->{bay}, box: $e->{box}, $e->{misc}]: " .
						uc($e->{status}) . "\n";
			}
			$buf .= "\n";
		}
		$buf .= "\n";
	}
	
	return $buf;
}

sub _is_rebuild {
	my ($s) = @_;
	return 0 unless (defined $s && length $s);
	$s = lc($s);
	return ($s eq 'rbld' && $s eq 'rebuild' && $s eq 'rebuilding') ? 1 : 0;
}

=head1 SEE ALSO

L<P9::AA::Check::HPRAID::LINUX>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;