package Noviforum::Adminalert::Check::DRBD;

use strict;
use warnings;

use IO::File;

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check';

use constant DRBD_STATUS_FILE => "/proc/drbd";
use constant MAX_LINES => 10240;

our $VERSION = 0.10;

##################################################
#              PUBLIC  METHODS                   #
##################################################

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks health of DRBD block devices."
	);

	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	my $data = undef;

	# get data structure...
	$data = $self->_readStatus();
	return CHECK_ERR unless (defined $data);

	# debug?
	if ($self->{debug}) {
		$self->bufApp("--- BBEGIN DRBD DATA ---");
		$self->bufApp($self->dumpVar($data));
		$self->bufApp("--- END DRBD DATA ---");
	}

	# check data structure
	return CHECK_ERR unless ($self->_validateStruct($data));
	return CHECK_OK;
}

sub _readStatus {
	my ($self) = @_;
	my $r = {
		version => 0,
		devices => {},
	};
	my $f = DRBD_STATUS_FILE;	
	unless (-f $f && -r $f) {
		$self->error("Unable to read DRBD status info [$f]: Missing or broken DRBD kernel support.");
		return undef;
	}

	my $fd = IO::File->new($f, 'r');
	unless (defined $fd) {
		$self->error("Unable to open DRBD status file '$f': $!");
		return 0;
	}
	

	if ($self->{debug}) {
		$self->bufApp("DEBUG:");
		$self->bufApp("DEBUG: Reading status file.");
		$self->bufApp("DEBUG: --- snip ---");
	}
	my $last_dev = undef;
	my $i = 0;
	# read status
	while ($i < MAX_LINES && defined (my $line = <$fd>)) {
		$i++;
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length($line) > 0);
		next if ($line =~ m/^#/);
		if ($self->{debug}) {
			$self->bufApp("DEBUG: $line");
		}
		
		# META INFO
		# version: 8.2.1 (api:86/proto:86-87)
		# GIT-hash: 318925802fc2638479ad090b73d7af45503dd184 build by root@bluewhite-12-64bit-dev.dev.interseek.com, 2007-11-29 19:45:25
		if ($line =~ m/^version:\s+([^\s]+)\s+/) {
			$r->{version} = $1;
			next;
		}
		elsif ($line =~ m/git-hash:\s+/i) {
			next;
		}
		
		# block device section...
		#
		# See: http://www.drbd.org/users-guide/ch-admin.html#s-check-status
		# 0: cs:Connected st:Primary/Primary ds:UpToDate/UpToDate C r---
		if ($line =~ m/^(\d+):\s+(.+)/) {
			my $dev = int($1);
			$self->_parseKeys($r->{devices}->{$dev}->{general}, $2);
			$last_dev = $dev;
			next;
		}
		# resync: used:0/31 hits:123025 misses:423 starving:0 dirty:0 changed:423
		# print "LAST_DEV: $last_dev\n";
		if (defined $last_dev && $line =~ m/^resync:\s+(.+)/) {
			$self->_parseKeys($r->{devices}->{$last_dev}->{resync}, $1);
		}
		# act_log: used:0/257 hits:16847161 misses:381747 starving:0 dirty:291 changed:381456
		elsif (defined $last_dev && $line =~ m/^act_log:\s+(.+)/) {
			$self->_parseKeys($r->{devices}->{$last_dev}->{act_log}, $1);
		}
		elsif (defined $last_dev) {
			$self->_parseKeys($r->{devices}->{$last_dev}->{general}, $line);
		} else {
			$self->bufApp("WARN: unparseable line: $line");
		}
	}
	close($fd);
	
	if ($self->{debug}) {
		$self->bufApp("DEBUG: --- snip ---");
		$self->bufApp("DEBUG:");
	}

	return $r;
}

sub _parseKeys {
	my $self = shift;
	my @data = split(/\s+/, $_[1]);
	map {
		my ($k, $v) = split(/:/, $_);
		if (defined $k && defined $v) {
			$_[0]->{$k} = $v;
		}
	} @data;

	return 1;
}

sub _validateStruct {
	my ($self, $data) = @_;
	my $r = 1;
	unless (defined $data && ref($data) eq 'HASH') {
		$self->error("Invalid DRBD status structure.");
		return 0;
	}

	if (! exists($data->{version}) || ! defined $data->{version}) {
		$self->error("Incomplete DRBD structure: missing driver version.");
		return 0
	} else {
		$self->bufApp("DRBD version: " . $data->{version});
	}
	
	# no configured DRBD devices?
	my $num = scalar(keys %{$data->{devices}});
	unless ($num) {
		$self->bufApp("WARNING: No configured devices found.");
		return 1;
	}
	
	$self->bufApp("");	
	my $err = undef;
	
	# check health of all found devices...
	foreach my $dev (sort keys %{$data->{devices}}) {
		no warnings;
		my $r_dev = "/dev/drbd" . $dev;
		my $x = $data->{devices}->{$dev};
		$self->bufApp("DEVICE: $r_dev");
		$self->bufApp("    INFO:");
		my $str = "roles: " . $x->{general}->{st} . "; connection: " . $x->{general}->{cs};
		$self->bufApp("          $str");
		$str = "disk states: " . $x->{general}->{ds};
		$self->bufApp("          $str");
		$self->bufApp("");
		
		# check health status
		# state
		if ($x->{general}->{st} =~ m/unknown/i) {
			$err .= "Device: $r_dev: one or more nodes have unknown role. ";
			$r = 0;
		}
		# connection
		if ($x->{general}->{cs} !~ m/^connected/i) {
			$err .= "Device: $r_dev: not connected. ";
			$r = 0;
		}
		# disks
		if ($x->{general}->{ds} !~ m/^UpToDate\/UpToDate$/i) {
			$err .= "Device: $r_dev: all backend disks are not in up2date state. ";
			$r = 0;
		}
	}

	if (defined $err) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	return $r;
}

1;

# EOF