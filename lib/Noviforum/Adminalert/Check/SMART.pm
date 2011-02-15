package Noviforum::Adminalert::Check::SMART;

use strict;
use warnings;

use File::Glob qw(:glob);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check';

use constant SMART_CMD => 'smartctl';
use constant HKEY => 'smart_data';

our $VERSION = 0.12;

my @smart_attrs = qw(
	Raw_Read_Error_Rate
	Spin_Up_Time
	Start_Stop_Count
	Reallocated_Sector_Ct
	Seek_Error_Rate
	Seek_Time_Performance
	Power_On_Hours
	Spin_Retry_Count
	Power_Cycle_Count
	G-Sense_Error_Rate
	Power-Off_Retract_Count
	Temperature_Celsius
	Hardware_ECC_Recovered
	Reallocated_Event_Count
	Current_Pending_Sector
	Offline_Uncorrectable
	UDMA_CRC_Error_Count
	Multi_Zone_Error_Rate
	Soft_Read_Error_Rate
	Load_Retry_Count
	Load_Cycle_Count
);

=head1 NAME

S.M.A.R.T. disk monitoring module based on L<smartctl(8)> provided by smartmontools project.

=head1 METHODS

=cut

##################################################
#              PUBLIC  METHODS                   #
##################################################

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"S.M.A.R.T. disk monitoring module. Requires smartctl(8) command from smartmontools package."
	);
	
	$self->cfgParamAdd(
		'use_history',
		1,
		'Remember and use SMART data.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'Max_Temperature_Celsius',
		45,
		'Maximum disk temperature in celsius',
		$self->validate_int(1),
	);
	$self->cfgParamAdd(
		'Max_Reallocated_Sector_Ct',
		100,
		'Maximum number of reallocated sectors',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'Max_Current_Pending_Sector',
		0,
		'Maximum number of currently unstable sectors (waiting for remapping).',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'Max_Offline_Uncorrectable',
		0,
		'Maximum number off offline uncorrectable errors.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'Max_Delta_Raw_Read_Error_Rate',
		10000,
		'Maximum delta of Raw_Read_Error_Rate property between two checks. Requires use_history=true.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'Max_Delta_UDMA_CRC_Error_Count',
		10000,
		'Maximum delta of UDMA_CRC_Error_Count propety between two checks. Requires use_history=true.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'debug_raw',
		0,
		'Display raw smartctl output.',
		$self->validate_bool(),
	);

	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# get data
	my $data = $self->getSmartData();
	return CHECK_ERR unless (defined $data);
	
	if ($self->{debug}) {
		$self->bufApp('--- BEGIN SMART DATA ---');
		$self->bufApp($self->dumpVar($data));
		$self->bufApp('--- END SMART DATA ---');
	}

	my $result = CHECK_OK;
	my $err = '';
	
	# get old data...
	my $data_old = ($self->{use_history}) ? $self->hoGet(HKEY) : undef;
	$data_old = undef unless (defined $data_old && ref($data_old) eq 'HASH');

	# inspect smart data
	foreach my $dev (keys %{$data}) {
		# is smart enabled?
		unless ($self->_isSmartEnabled($data->{$dev})) {
			$self->bufApp("SMART is not enabled/available for device $dev.");
			next;
		}
		
		my $ok = 1;
		
		# check device health
		if (! $self->_checkDeviceHealth($data->{$dev})) {
			$err .= "Device $dev:\n" . $self->error() . "\n";
			$result = CHECK_ERR;
			$ok = 0;
		}
		elsif (defined $data_old && exists($data_old->{$dev})) {
			unless ($self->_compareDeviceHealth($data_old->{$dev}, $data->{$dev})) {
				$err .= "Device $dev:\n" . $self->error() . "\n";
				$result = CHECK_ERR;
				$ok = 0;
			}
		}
		
		if ($ok) {
			$self->bufApp("Device $dev: looks healthy.");
		} else {
			$self->bufApp("Device $dev looks sick:\n" . $self->error());
		}
	}
	
	# save data to new history?
	if ($self->{use_history}) {
		$self->hnSet(HKEY, $data);
	}

	if ($result != CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	return $result;
}

=head2 discoverDevices ()

Returns array reference of discovered disk devices on success, otherwise undef.

=cut
sub discoverDevices {
	my ($self) = @_;
	my $patterns = $self->getDeviceGlobPatterns();
	return undef unless ($patterns);

	my $res = [];	
	foreach my $patt (@{$patterns}) {
		if (GLOB_ERROR != 0) {
			$self->error("Error discovering disk devices: $!");
			return undef;
		}	
		my @devs = bsd_glob($patt);

		# must be valid block device
		map { push(@{$res}, $_) if (-e $_ && -b $_) } @devs;
	}

	return $res;
}

=head2 getDeviceGlobPatterns



=cut
sub getDeviceGlobPatterns {
	my $self = shift;
	die "This method is not implemented in " . ref($self);
}

=head2 getDeviceData ($dev)

Returns device SMART data as hashref on success, otherwise undef.

Result structure looks like this:

 {
    'meta' => {
      'capacity' => '320072933376',
      'family' => 'Seagate Momentus 7200.4 series',
      'firmware' => '0003LVM1',
      'model' => 'ST9320423AS',
      'serial' => '5VH3FNL4',
      'smart_enabled' => 1,
      'smart_passed' => 1
    },
    'smart' => {
      'Current_Pending_Sector' => 0,
      'G-Sense_Error_Rate' => 54,
      'Hardware_ECC_Recovered' => 22016862,
      'Load_Cycle_Count' => 80733,
      'Offline_Uncorrectable' => 0,
      'Power-Off_Retract_Count' => 1,
      'Power_Cycle_Count' => 442,
      'Power_On_Hours' => '36670430775236',
      'Raw_Read_Error_Rate' => 22016862,
      'Reallocated_Event_Count' => 1874,
      'Reallocated_Sector_Ct' => 203,
      'Seek_Error_Rate' => 14466079,
      'Spin_Retry_Count' => 0,
      'Spin_Up_Time' => 0,
      'Start_Stop_Count' => 475,
      'Temperature_Celsius' => 34,
      'UDMA_CRC_Error_Count' => 0
    }
  }

=cut
sub getDeviceData {
	my ($self, $dev) = @_;
	unless (defined $dev && length($dev)) {
		$self->error("Undefined device.");
		return undef;
	}
	unless (-e $dev && -b $dev) {
		$self->error("Not valid block device: $dev");
		return undef;
	}
	
	# clear error
	$self->error('');
	
	# run command
	my ($out, $exit_code) = $self->qx2(SMART_CMD . ' -iHa ' . $dev);
	return undef unless (defined $out);
	
	if ($self->{debug_raw}) {
		$self->bufApp("--- BEGIN $dev RAW OUTPUT ---");
		map { $self->bufApp($_) } @{$out};
		$self->bufApp("--- END $dev RAW OUTPUT ---");
	}

	# parse data...
	return $self->_parseRawData($out);
}

=head2 getSmartData ()

Discovers devices and returns smart data as hashref on success, otherwise undef.

Example result:

 {
  '/dev/sda' => {
  	# structure returned by getDeviceData() method
  }
 } 

=cut
sub getSmartData {
	my ($self) = @_;
	my $devs = $self->discoverDevices();
	return undef unless (defined $devs);

	if ($self->{debug}) {
		$self->bufApp(
			"Discovered " . scalar(@{$devs}) . " device(s): " .
			join(", ", @{$devs})
		);
	}
	
	my $r = {};
	foreach my $dev (@{$devs}) {
		my $d = $self->getDeviceData($dev);
		return undef unless (defined $d);

		$r->{$dev} = $d;		
	}

	return $r;
}

sub VERSION {
	return $VERSION;
}

##################################################
#              PRIVATE METHODS                   #
##################################################

sub _parseRawData {
	my ($self, $out) = @_;
	my $data = $self->_getDataStructEmpty();

	foreach my $e (@{$out}) {
		# trim
		$e =~ s/^\s+//g;
		$e =~ s/\s+$//g;
		
		# basic info parsing...
		if ($e =~ m/^Device\s+Model:\s*(.+)/i) {
			$data->{meta}->{model} = $1;
		}
		elsif ($e =~ m/^Model\s+Family:\s*(.+)/i) {
			$data->{meta}->{family} = $1;
		}
		elsif ($e =~ m/^Serial\s+Number:\s*(.+)/i) {
			$data->{meta}->{serial} = $1;
		}
		elsif ($e =~ m/^Firmware\s+Version:\s*(.+)/i) {
			$data->{meta}->{firmware} = $1;
		}
		elsif ($e =~ m/^User\s+Capacity:\s*([\d,.]+)/i) {
			my $size = $1;
			$size =~ s/[,.]+//g;
			no warnings;
			$data->{meta}->{capacity} = int($size);
		}
		elsif ($e =~ m/^SMART\s+support\s+is:\s*enabled/i) {
			$data->{meta}->{smart_enabled} = 1;
		}
		elsif ($e =~ m/SMART\s+overall-health\s+self-assessment\s+test\s+result:\s+PASSED/i) {
			$data->{meta}->{smart_passed} = 1;
		}
		
		# smart attribute, maybe?
		map {
			my $attr = $_;
			if (! exists($data->{smart}->{$attr}) && $e =~ m/^\s*\d+\s+$attr/i) {
				my $val;
				if ($e =~ m/\s*([\w\-_]+\s*){10}/i) {
					$val = $1;
				}
				no warnings;
				$data->{smart}->{$attr} = int($val);
			}
		} @smart_attrs;
	}

	return $data;
}

sub _isSmartEnabled {
	my ($self, $data) = @_;
	unless (defined $data && ref($data) eq 'HASH') {
		$self->error("Invalid data structure.");
		return 0;
	}

	return ($data->{meta}->{smart_enabled}) ? 1 : 0;
}

sub _isSmartPassed {
	my ($self, $data) = @_;
	unless (defined $data && ref($data) eq 'HASH') {
		$self->error("Invalid data structure.");
		return 0;
	}

	return ($data->{meta}->{smart_passed}) ? 1 : 0;
}

sub _checkDeviceHealth {
	my ($self, $data) = @_;
	unless (defined $data && ref($data) eq 'HASH') {
		$self->error("Invalid data structure.");
		return 0;
	}

	# is smart support enabled?
	unless ($self->_isSmartEnabled($data)) {
		$self->error("\tSMART is not enabled for this device.");
		return 0;
	}

	my $err = '';
	my $errors = 0;

	# SMART status
	unless ($self->_isSmartPassed($data)) {
		$err .= "\tSMART status FAILED\n";
		$errors++;
	}

	# * Temperature_Celsius - lahko nastavljiv, s privzeto vrednostjo recimo
	# 45 stopinj. Pri tej temperatiri mora disk delovati brez tezav.
	if (exists $data->{smart}->{Temperature_Celsius} && $data->{smart}->{Temperature_Celsius} > $self->{Max_Temperature_Celsius}) {
		$err .= "\tTemperature_Celsius too high (value > treshold): $data->{smart}->{Temperature_Celsius} > $self->{Max_Temperature_Celsius}\n";
		$errors++;
	}

	# * Reallocated_Sector_Ct - pove nam, koliko sektorjev je disk realociral.
	# Ce se stevilka naglo povecuje je to zelo dober indikator odpovedovanja
	# diska. Povecevanje vrednosti zaradi ocitnoh razlogov tudi mocno vpliva
	# na hitrost delovanja samega diska. Glede na to, da je realociranje nekaj
	# malega sektorjev normalno, bi tudi tu lahko implementirali custom
	# treshold value z defaultno vrednostjo recimo 100.
	if (exists $data->{smart}->{Reallocated_Sector_Ct} && $data->{smart}->{Reallocated_Sector_Ct} > $self->{Max_Reallocated_Sector_Ct}) {
		$err .= "\tReallocated_Sector_Ct too high (value > treshold): $data->{smart}->{Reallocated_Sector_Ct} > $self->{Max_Reallocated_Sector_Ct}\n";
		$errors++;
	}

	# * Current_Pending_Sector - Stevilo sektorjev, ki cakajo na realokacijo.
	# Alert ce je vrednost razlicna od 0.
	if (exists $data->{smart}->{Current_Pending_Sector} && $data->{smart}->{Current_Pending_Sector} > $self->{Max_Current_Pending_Sector}) {
		$err .= "\tCurrent_Pending_Sector too high (value > treshold): $data->{smart}->{Current_Pending_Sector} > $self->{Max_Current_Pending_Sector}\n";
		$errors++;
	}

	# * Offline_Uncorrectable - Stevilo sektorjev, ki jih disk ni morel
	# realocirat, bodisi ker jih ni mogel prebrat, ali pa ker sistem zaradi
	# cacheiranja in podobnih razlogov niti ni poiskusal zapisovati v ta
	# sektor. Dolocene tezave se da resit z uporabo dd-ja z oflag=direct
	# nacinom (google it). Alert ce je vrednost razlicna od 0.
	if (exists $data->{smart}->{Offline_Uncorrectable} && $data->{smart}->{Offline_Uncorrectable} > $self->{Max_Offline_Uncorrectable}) {
		$err .= "\tOffline_Uncorrectable too high (value > treshold): $data->{smart}->{Offline_Uncorrectable} > $self->{Max_Offline_Uncorrectable}\n";
		$errors++;
	}

	# set error message in case of error
	if ($errors > 0) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	
	return ($errors > 0) ? 0 : 1;
}

sub _compareDeviceHealth {
	my ($self, $old, $new) = @_;
	unless (defined $new && ref($new) eq 'HASH') {
		$self->error("Invalid new data structure.");
		return 0;
	}
	unless (defined($old) && ref($old) eq 'HASH') {
		$self->error("Invalid new data structure.");
		return 0;
	}

	my ($errors, $delta) = (0, 0);
	my $err = '';
	
	no warnings;

	# * Raw_Read_Error_Rate - Ce je razlicen od 0, potem je (ali je slo) z
	# diskom v preteklosti nekaj narobe. Tu bi se splacalo preverjat razliko
	# med trenutnim in prejsnjim stanjem. Recimo da 10,000 errorjev razlike
	# med posameznimi checki se toleriramo.
	$delta = $new->{smart}->{Raw_Read_Error_Rate} - $old->{smart}->{Raw_Read_Error_Rate};
	if ($delta > $self->{Max_Delta_Raw_Read_Error_Rate}) {
		$err .= "\tRaw_Read_Error_Rate rate of change too high: (value > treshold): $delta > $self->{Max_Delta_Raw_Read_Error_Rate}\n";
		$errors++;
	}

	# * UDMA_CRC_Error_Count - povecevanje te vrednosti kaze na tezave bodisi
	# v UDMA kontrolerju, bodisi nakazuje na slabo kablovje. Vrednost se po
	# odpravi tezav ne resetira.
	$delta = $new->{smart}->{UDMA_CRC_Error_Count} - $old->{smart}->{UDMA_CRC_Error_Count};
	if ($delta > $self->{Max_Delta_UDMA_CRC_Error_Count}) {
		$err .= "\tUDMA_CRC_Error_Count rate of change too high: (value > treshold): $delta > $self->{Max_Delta_UDMA_CRC_Error_Count}\n";
		$errors++;
	}
	
	if ($errors > 0) {
		$err =~ s/\s+$//g;
		$self->error($err);
		return 0;
	}

	return 1;
}

sub _getDataStructEmpty {
	my ($self) = @_;

	my $data = {
		# metadata...
		meta => {
			family => undef,
			model => undef,
			serial => undef,
			firmware => undef,
			capacity => undef,
			smart_enabled => 0,
			smart_passed => 0,
		},
		# smart data (contains smart attr keys from @smart_attrs)
		smart => {},
	};

	return $data;
}

=head1 AUTHOR

Uros Golja

=head1 SEE ALSO

L<Noviforum::Adminalert::Check::LINUX>
L<Noviforum::Adminalert::Check::FREEBSD>
L<Noviforum::Adminalert::Check::OPENBSD>
L<Noviforum::Adminalert::Check::NETBSD>
L<Noviforum::Adminalert::Check::DARWIN>
L<Noviforum::Adminalert::Check::SUNOS>
L<Noviforum::Adminalert::Check>

=cut

1;