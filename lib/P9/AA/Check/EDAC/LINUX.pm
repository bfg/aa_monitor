package P9::AA::Check::EDAC::LINUX;

use strict;
use warnings;

use IO::File;
use File::Spec;
use File::Basename;
use POSIX qw(strftime);

use P9::AA::Constants;
use base 'P9::AA::Check::EDAC';

use constant MAX_LINES => 500;
use constant EDAC_SYSFS_ROOT => '/sys/devices/system/edac';
use constant EDAC_SYSFS_MC =>  EDAC_SYSFS_ROOT . '/mc';
use constant EDAC_PROCFS_ROOT => '/proc/mc';

our $VERSION = 0.20;

##################################################
#              PUBLIC  METHODS                   #
##################################################

sub edac_data {
  my ($self) = @_;
  if (-d EDAC_SYSFS_ROOT) {
    $self->_edac_data_sysfs;
}
elsif (-d EDAC_PROCFS_ROOT) {
  $self->_edac_data_proc;
} else {
  die "This sux.\n";
    $self->SUPER::edac_data;
  }
}

sub edac_reset {
  my ($self, $mc) = @_;
  unless ($> == 0) {
    $self->error("Resetting EDAC counters feature requires process to be started with r00t privileges.");
    return 0;
  }

  my $file = File::Spec->catfile(EDAC_SYSFS_MC, $mc, "reset_counters");
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

##################################################
#              PRIVATE METHODS                   #
##################################################

sub _edac_data_proc {
  my ($self) = @_;
  my $dir = EDAC_PROCFS_ROOT;

  $self->bufApp("Obtaining EDAC statistics from proc filesystem.");
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

    # read file
    my $module_num = undef;
    my $file = File::Spec->catfile($dir, $file);
    my @lines = $self->_file_read($file, MAX_LINES);
    unless (@lines) {
      $self->error("Unable to open file '$file': $!");
      $res = undef;
      next;
    }
    foreach my $line (@lines) {
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
  }

  return $res;
}

sub _edac_data_sysfs {
  my ($self) = @_;
  my $dir = EDAC_SYSFS_ROOT;
  my $res = {};
  my $fd = undef;
  my $data = undef;
  my @contents;

  # check pci errors
  my $file = File::Spec->catfile($dir, "pci", "pci_parity_count");
  if (-f $file) {
    unless (defined($data = $self->_file_read($file))) {
      $self->error("Unable to check PCI parity error count: " . $self->error());
      return undef;
    }
    $res->{pci}->{err_count} = int($data);
  }

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
  my $ver = $self->_file_read(File::Spec->catfile($dir, "mc_version"));
  $ver = '' unless (defined $ver);
  $self->bufApp("EDAC version: " . $ver);
  $self->bufApp();

  foreach my $entry (sort @contents) {
    next unless (-d File::Spec->catdir($dir, $entry));
    next unless ($entry =~ m/^mc\d+$/);
    my $d = File::Spec->catdir($dir, $entry);
    my $mn = $self->_sysfs_controller_name($entry);
    $mn = '' unless (defined $mn);
    $self->bufApp("Checking memory controller '$entry' [" . $mn . "].");
    $self->bufApp("Counters reset time: " . strftime("%Y/%m/%d %H:%M:%S", localtime($self->_edac_last_reset($entry))));

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

      my $f = File::Spec->catfile($d, $mc_entry, "ce_count");
      $self->bufApp("    Checking controller entry '$mc_entry'.");

      $data = $self->_file_read($f);
      unless (defined $data) {
        $self->error("Unable to read corrected errors (CE) count: " . $self->error());
        return undef;
      }
      $res->{mem}->{$entry}->{$module_num}->{ce_count} = int($data);

      $data = $self->_file_read(File::Spec->catfile($d, $mc_entry, "ue_count"));
      unless (defined $data) {
        $self->error("Unable to read corrected errors (UE) count: " . $self->error());
        return undef;
      }
      $res->{mem}->{$entry}->{$module_num}->{ue_count} = int($data);
      $res->{mem}->{$entry}->{$module_num}->{size} = $self->_file_read(File::Spec->catfile($d, $mc_entry, "size_mb"));
      $res->{mem}->{$entry}->{$module_num}->{type} = $self->_file_read(File::Spec->catfile($d, $mc_entry, "mem_type"));
    }

    # reset counters on controller if requested
    if ($self->{reset_counters}) {
      my $s = "Reseting counters memory controller '$entry': ";
      $s .= ($self->edac_reset($entry)) ? "OK" : "FAILURE [" . $self->error() . "]";
      $self->bufApp($s);
    }

    $self->bufApp();
  }

  return $res;
}

sub _sysfs_controller_name {
  my ($self, $mc) = @_;
  foreach my $x (qw(module_name mc_name)) {
    my $buf = $self->_file_read(File::Spec->catfile(EDAC_SYSFS_MC, $mc, $x));
    return $buf if (defined $buf);
  }
  return '';
}

sub _file_read {
  my ($self, $file, $lines) = @_;
  $lines = 1 unless (defined $lines);
  my @res;

  my $fd = IO::File->new($file, "r");
  unless (defined $fd) {
    $self->error("Unable to open file '$file': $!");
    return @res;
  }

  my $i = 0;
  while ((my $i++ <= $lines || $i < MAX_LINES) && defined (my $l = <$fd>)) {
    $l =~ s/^\s+//g;
    $l =~ s/\s+$//g;
    push(@res, $l) if (length($l));
  }

  return @res;
}

sub _edac_last_reset {
  my ($self, $mc) = @_;
  my $file = File::Spec->catfile(EDAC_SYSFS_MC, $mc, "seconds_since_reset");
  my $str = $self->_file_read($file);
  return 0 unless (defined $str);
  no warnings;
  return (time() - int($str));
}

=head1 AUTHOR

Brane F. Gracnar

=cut

1;