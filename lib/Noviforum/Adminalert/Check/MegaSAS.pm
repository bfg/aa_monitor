package Noviforum::Adminalert::Check::MegaSAS;

use strict;
use warnings;

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check';

our $VERSION = 0.15;

=head1 NAME

LSI Logic MegaSAS RAID adapter checking module.

=head1 METHODS

This class inherits all methods from L<Noviforum::Adminalert::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks MegaRAID SAS RAID array consistency."
	);
	
	$self->cfgParamAdd(
		'rebuild_state_is_ok',
		0,
		'Should rebuild state of logical volume be considered ok?',
		$self->validate_bool()
	);

	return 1;
}

sub check {
	my ($self) = @_;
	
	my $data = $self->getAdapterData($self->{adapter_number});
	return CHECK_ERR unless (defined $data);
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN MEGASAS DATA ---");
		$self->bufApp($self->dumpVar($data));
		$self->bufApp("--- END MEGASAS DATA ---");
	}
	
	# print nice volume summary...
	$self->bufApp($self->adapterDataToString($data));

	my $err = '';
	my $warn = '';
	my $result = CHECK_OK;
	foreach my $a (sort keys %{$data}) {
		my $adapter = $data->{$a};
	
		foreach my $v (sort keys %{$data}) {
			my $vol = $data->{$v};
			my $num = scalar(keys %{$vol}) - 1;
			my $vol_state = lc($vol->{state});
			if (length $vol_state && ($vol_state ne 'optimal' && $vol_state ne 'online')) {
				if (_is_rebuild($vol_state) && $self->{rebuild_state_is_ok}) {
					$err .= "Adapter $a, volume $v state is not optimal: $vol_state\n";
					$result = CHECK_WARN unless ($result == CHECK_ERR);
				} else {
					$err .= "Adapter $a, volume $v, state is not optimal: $vol_state\n";
					$result = CHECK_ERR;
				}
			}
	
			# check all disks...
			foreach my $d (sort keys %{$vol}) {
				next unless ($d =~ m/^disk_/);
				my $disk = $vol->{$d};
				my $name = $disk->{inquiry_data};
				$name =~ s/\s{2,}/ /g;
				my $size = $disk->{raw_size};
				my $disk_state = lc($disk->{state});
				
				if ($disk_state ne 'optimal' && $disk_state ne 'online') {
					if (_is_rebuild($disk_state) && $self->{rebuild_state_is_ok}) {
						$warn .= "Adapter $a, volume $v, disk $d [$name; size: $size] is not in optimal state: $disk_state\n";
						$result = CHECK_WARN unless ($result == CHECK_ERR);
					} else {
						$err .= "Adapter $a, volume $v, disk $d [$name; size: $size] is not in optimal state: $disk_state\n";
						$result = CHECK_ERR;
					}
				}
			}
		}
	}

	if (length $warn) {
		$warn =~ s/\s+$//g;
		$self->warning($warn);
	}
	if ($result != CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}

	return $result;
}

=head2 getAdapterData

 my $data = $self->getAdapterData();

Returns hash reference containing adapter data on success, otherwise undef.

Example:

 {
  # adapter 0
  '0' => {
  	  # volume 0
	  '0' => {
	  	# disk 0
	    '0' => {
	      'coerced_size' => '68664MB [0x861c000 Sectors]',
	      'connected_port_number' => '0(path0)',
	      'device_id' => '8',
	      'enclosure_device_id' => '21',
	      'firmware_state' => 'Online',
	      'inquiry_data' => 'SEAGATE ST373455SS      00023LQ12TEW',
	      'last_predictive_failure_event_seq_number' => '0',
	      'media_error_count' => '0',
	      'non_coerced_size' => '69495MB [0x87bb998 Sectors]',
	      'other_error_count' => '0',
	      'physical_disk' => '0',
	      'predictive_failure_count' => '0',
	      'raw_size' => '70007MB [0x88bb998 Sectors]',
	      'sas_address(0)' => '0x5000c50004960719',
	      'sas_address(1)' => '0x0',
	      'sequence_number' => '2',
	      'slot_number' => '0',
	      'state' => 'online'
	    },
	    # disk 1
	    '1' => {
	      'coerced_size' => '68664MB [0x861c000 Sectors]',
	      'connected_port_number' => '0(path0)',
	      'device_id' => '9',
	      'enclosure_device_id' => '21',
	      'firmware_state' => 'Online',
	      'inquiry_data' => 'SEAGATE ST373455SS      00023LQ12TBA',
	      'last_predictive_failure_event_seq_number' => '0',
	      'media_error_count' => '0',
	      'non_coerced_size' => '69495MB [0x87bb998 Sectors]',
	      'other_error_count' => '0',
	      'physical_disk' => '1',
	      'predictive_failure_count' => '0',
	      'raw_size' => '70007MB [0x88bb998 Sectors]',
	      'sas_address(0)' => '0x5000c50004960515',
	      'sas_address(1)' => '0x0',
	      'sequence_number' => '2',
	      'slot_number' => '1',
	      'state' => 'online'
	    },
	    'state' => 'optimal'
	  },
   },
 }

=cut
sub getAdapterData {
	my ($self) = @_;
	$self->error("This method is not implemented on " . $self->getOs() . " operating system.");
	return undef;
}

=head2 parseAdapterData

Raw => parsed data method. Should be implemented by the actual
implementation.

=cut
sub parseAdapterData {
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
	foreach my $a (sort keys %{$data}) {
		my $adapter = $data->{$a};
		$buf .= "ADAPTER: $a\n";
		foreach my $v (sort keys %{$adapter}) {
			my $vol = $adapter->{$v};
			my $num = scalar(keys %{$vol}) - 1;
			$buf .= "  VOLUME $v [$vol->{state}; $num disks]\n";
			foreach my $d (sort keys %{$vol}) {
				next if ($d eq 'state');
				#next unless ($d =~ m/^disk_/);
				my $disk = $vol->{$d};
				my $name = $disk->{inquiry_data};
				$name =~ s/\s{2,}/ /g;
				my $size = $disk->{raw_size};
				$buf .= "    DISK $d [$name; size: $size]: $disk->{state}\n\n";
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

=head1 AUTHOR

Brane F. Gracnar

=cut
1;