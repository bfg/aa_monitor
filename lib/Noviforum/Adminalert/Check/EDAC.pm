package Noviforum::Adminalert::Check::EDAC;

use strict;
use warnings;

use IO::File;
use File::Spec;
use File::Basename;
use POSIX qw(strftime);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check';

use constant MAXLINES => 500;

our $VERSION = 0.16;

##################################################
#              PUBLIC  METHODS                   #
##################################################

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());

	$self->setDescription(
		"Checks for ECC memory errors and PCI parity errors. Operates only on Linux OS."
	);
	
	$self->cfgParamAdd(
		'ue_threshold',
		0,
		'Uncorrectable errors threshold.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'ce_threshold',
		0,
		'Correctable errors threshold.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'pci_threshold',
		0,
		'PCI errors threshold.',
		$self->validate_int(0),
	);
	$self->cfgParamAdd(
		'reset_counters',
		0,
		'Reset EDAC counters?',
		$self->validate_bool(),
	);

	return 1;
}

sub check {
	my ($self) = @_;
	my $os = $self->getOs();
	unless (lc($os) eq 'linux') {
		die "This module works only on Linux operating system [$os is not supported].\n";
	}

	my $result = CHECK_OK;
	$self->bufApp("");
	$self->bufApp("### EDAC test: ###");
	
	my $struct = undef;
	
	if (-d "/sys/devices/system/edac") {
		$struct = $self->_pingEDACSysfs();
	}
	elsif (-d "/proc/mc") {
		$struct = $self->_pingEDACProc();
	}
	else {	
		$self->bufApp("Unable to read EDAC statistics: EDAC support is not compiled in kernel, or hardware does not support ECC.");
		return CHECK_OK;
	}

	return CHECK_ERR unless ($struct);
	
	# check for validity
	unless (exists($struct->{mem}) && exists($struct->{pci}) && keys(%{$struct->{mem}}) > 0) {
		$self->bufApp("Unable to read EDAC statistics: EDAC enabled hardware is not available on the system.");
		return CHECK_OK;
	}

	# check edac structure
	$self->bufApp();
	$self->bufApp("Checking EDAC structures: ");

	foreach my $c (sort keys %{$struct->{mem}}) {
		foreach my $m (sort keys %{$struct->{mem}->{$c}}) {
			my $ue = int($struct->{mem}->{$c}->{$m}->{ue_count});
			my $ce = int($struct->{mem}->{$c}->{$m}->{ce_count});
			my $r = "OK";
			
			if ($ue > $self->{ue_threshold} || $ce > $self->{ce_threshold}) {
				$self->error("ECC errors detected (UE: $ue, CE: $ce) on controller '$c', slot '$m'.");
				$result = CHECK_ERR;
				$r = "FAILURE";
			}

			$self->bufApp("    Controller $c, slot $m: $r");
		}
	}

	# Check for PCI errors...
	$self->bufApp();
	my $str = "Checking EDAC structures for PCI parity errors: ";
	if ($struct->{pci}->{err_count} > $self->{pci_threshold}) {
		$self->error($struct->{pci}->{err_count} . " parity errors detected on PCI bus.");
		$str .= "FAILURE";
		$result = CHECK_ERR;
	} else {
		$str .= "OK";
	}
	$self->bufApp($str);

	return $result;
}

##################################################
#              PRIVATE METHODS                   #
##################################################

sub _pingEDACProc {
	my ($self) = @_;
	my $dir = "/proc/mc";
	
	$self->bufApp("Obtaining EDAC statistics from /proc filesystem.");
	$self->bufApp();
	
	my $res = {};

	# open directory, read contents
	my $dirh = undef;
	unless (opendir($dirh, $dir)) {
		$self->error("Unable to open directory '$dir': $!");
		return undef;
	}
	my @contents = readdir($dirh);
	closedir($dirh);
	shift(@contents); shift(@contents);
	
	# parse each and every file
	foreach my $file (@contents) {
		#$self->bufApp("Checking memory controller 'mc${file}'.");
		my $file = File::Spec->catfile($dir, $file);
		my $fd = IO::File->new($file, "r");
		
		unless (defined $fd) {
			$self->error("Unable to open file '$file': $!");
			$res = undef;
			next;
		}
		
		# read file
		my $i = 0;
		my $module_num = undef;
		while ($i < MAXLINES && defined(my $line = <$fd>)) {
			$line =~ s/^\s+//g;
			$line =~ s/\s+$//g;
			$i++;
			if (length($line) < 1) {
				$module_num = undef;
				next;
			}

			my $edac_version = "";

			if ($line =~ m/^MC Core:\s+(.+)/) {
				$self->bufApp("EDAC version: $1");
				$self->bufApp();
			}
			elsif ($line =~ m/^MC Module:\s+(.+)/) {
				$self->bufApp("Checking memory controller 'mc" . basename($file) . "' [$1].");
			}
			elsif ($line =~ m/^Total PCI Parity:\s+(\d+)/) {
				$res->{pci}->{err_count} = $1;
			}
			# module lines
			elsif ($line =~ m/^(\d+)/) {
				$module_num = $1 unless (defined $module_num);
				my @tmp = split(/:/, $line);
				# 0:|:Memory Size:        2048 MiB
				# 0:|:Mem Type:           Registered-DDR
				# 0:|:Dev Type:           x4
				# 0:|:EDAC Mode:          S4ECD4ED
				# 0:|:UE:                 0
				# 0:|:CE:                 0
				# 0.0::CE:                0
				# 0.1::CE:                0
				#
				# slot_number : X : key : value
				# 
				map { $_ =~ s/^\s+//g; $_ =~ s/\s+$//g; } @tmp;

				#print "GOT: ", Dumper(\ @tmp), "\n";
				my $mc = "mc" . basename($file);
				if ($tmp[2] eq 'UE') {
					$res->{mem}->{$mc}->{$module_num}->{ue_count} = $tmp[3];
				}
				elsif ($tmp[2] eq 'CE') {
					$res->{mem}->{$mc}->{$module_num}->{ce_count} = $tmp[3];
				}
				elsif ($tmp[2] =~ m/ size/i) {
					$res->{mem}->{$mc}->{$module_num}->{size} = (split(/\s+/, $tmp[3]))[0];
				}
				elsif ($tmp[2] =~ m/mem type/i) {
					$res->{mem}->{$mc}->{$module_num}->{type} = $tmp[3];
				}
			}
		}
		$fd = undef;
	}

	return $res;
}

sub _pingEDACSysfs {
	my ($self) = @_;
	my $dir = "/sys/devices/system/edac";
	my $res = {};
	my $fd = undef;
	my $data = undef;
	my @contents;
	
	# check pci errors
	my $file = File::Spec->catfile($dir, "pci", "pci_parity_count");
	unless (defined($data = $self->_readFile($file))) {
		$self->error("Unable to check PCI parity error count: " . $self->error());
		return undef;
	}
	$res->{pci}->{err_count} = int($data);

	# check memory controller errors
	$dir = File::Spec->catdir($dir, "mc");
	my $dirh = undef;
	unless (opendir($dirh, $dir)) {
		$self->error("Unable to open directory '$dir': $!");
		return undef;
	}
	@contents = readdir($dirh);
	shift(@contents); shift(@contents);
	closedir($dirh);
	
	# read some specific data
	$self->bufApp("EDAC version: " . $self->_readFile(File::Spec->catfile($dir, "mc_version")));
	$self->bufApp();

	foreach my $entry (sort @contents) {
		next unless (-d File::Spec->catdir($dir, $entry));
		next unless ($entry =~ m/^mc\d+$/);
		my $d = File::Spec->catdir($dir, $entry);
		$self->bufApp("Checking memory controller '$entry' [" . $self->_readFile(File::Spec->catfile($d, "module_name")) . "].");
		$self->bufApp("Counters reset time: " . strftime("%d.%m.%Y at %H:%M:%S", localtime($self->_lastResetTime($entry))));

		unless (opendir($dirh, $d)) {
			$self->error("Unable to open directory '$d': $!");
			return undef;
		}
		my @c = readdir($dirh);
		shift(@c); shift(@c);
		closedir($dirh);
		
		foreach my $mc_entry (sort @c) {
			next unless (-d File::Spec->catdir($dir, $entry, $mc_entry));
			my $module_num = undef;
			if ($mc_entry =~ m/^csrow(\d+)/) {
				$module_num = $1;
			} else {
				next;
			}

			$self->bufApp("    Checking controller entry '$mc_entry'.");

			$data = $self->_readFile(File::Spec->catfile($d, $mc_entry, "ce_count"));
			unless (defined $data) {
				$self->error("Unable to read corrected errors (CE) count: " . $self->error());
				return undef;
			}
			$res->{mem}->{$entry}->{$module_num}->{ce_count} = int($data);

			$data = $self->_readFile(File::Spec->catfile($d, $mc_entry, "ue_count"));
			unless (defined $data) {
				$self->error("Unable to read corrected errors (UE) count: " . $self->error());
				return undef;
			}
			$res->{mem}->{$entry}->{$module_num}->{ue_count} = int($data);
			$res->{mem}->{$entry}->{$module_num}->{size} = $self->_readFile(File::Spec->catfile($d, $mc_entry, "size_mb"));
			$res->{mem}->{$entry}->{$module_num}->{type} = $self->_readFile(File::Spec->catfile($d, $mc_entry, "mem_type"));
		}

		# reset counters on controller if requested		
		if ($self->{reset_counters}) {
			my $s = "Reseting counters memory controller '$entry': ";
			$s .= ($self->_resetCounters($entry)) ? "OK" : "FAILURE [" . $self->{error} . "]";
			$self->bufApp($s);
		}

		$self->bufApp();
	}

	return $res;
}

sub _readFile {
	my ($self, $file) = @_;
	my $str = undef;
	my $fd = IO::File->new($file, "r");
	unless (defined $fd) {
		$self->error("Unable to open file '$file': $!");
		return undef;
	}
	# read it
	$str = $fd->getline();
	unless (defined $str && length($str) > 0) {
		$self->error("Invalid input data.");
		return undef;
	}
	$fd = undef;
	$str =~ s/\s+$//g;

	return $str;
}

sub resetCounters {
	my ($self, $mc) = @_;
	unless ($> == 0) {
		$self->error("Resetting EDAC counters feature requires process to be started with r00t privileges.");
		return 0;
	}

	my $file = File::Spec->catfile("/sys/devices/system/edac", "mc", $mc, "reset_counters");
	my $fd = IO::File->new($file, 'w');
	unless (defined $fd) {
		$self->error("Unable to reset counters on memory controller '$mc': $!");
		return 0;
	}
	print $fd "1\n";
	unless ($fd->close()) {
		$self->error("Unable to reset counters on memory controller '$mc': $!");
		return 0;
	}
	$fd = undef;
	return 1;
}

sub _lastResetTime {
	my ($self, $mc) = @_;
	my $file = File::Spec->catfile("/sys/devices/system/edac", "mc", $mc, "seconds_since_reset");
	my $str = $self->_readFile($file);
	return 0 unless (defined $str);
	no warnings;
	return (time() - int($str));
}

=head1 AUTHOR

Brane F. Gracnar

=cut

1;