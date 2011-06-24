package P9::AA::Check::ArecaRAID::_arecacli;

use strict;
use warnings;

use File::Spec;
use POSIX qw(getcwd);

use base 'P9::AA::Check::ArecaRAID';

my @RAID_CMD = qw/ areca-cli cli64 cli32 /;

our $VERSION = 0.01;

=head1 NAME

Implementation of L<P9::AA::Check::ArecaRAID> module based
on Areca's cli32/cli64 command-line utility. Note that 
the cli32/cli64 utility is renamed to alreca-cli in 
the Planet9 Linux distribution. 

=cut

=head2 getAdapterData

 my $data = $self->getAdapterData($adapter);

Returns hash reference containing adapter data on success, otherwise undef.
$adapter is the adapter number to look at, defaults to 1 if not defined.

=cut
sub getAdapterData {
	my ($self, $adapter) = @_;
	my ($data, $exit_code) = $self->_runCli('sys info', $adapter);
	return undef if ($exit_code);
	return $self->_parseAdapterData($data);
}

=head2 getDiskData

 my $data = $self->getDiskData($adapter);

Returns hash reference containing disk data on success, otherwise undef.
$adapter is the adapter number to look at, defaults to 1 if not defined.

=cut
sub getDiskData {
	my ($self, $adapter) = @_;
	my ($data, $exit_code) = $self->_runCli('disk info', $adapter);
	return undef if ($exit_code);
	return $self->_parseDiskData($data);
}

=head2 getVolumeSetData

 my $data = $self->getVolumeSetData($adapter);

Returns hash reference containing volume set data on success, otherwise undef.
$adapter is the adapter number to look at, defaults to 1 if not defined.

=cut
sub getVolumeSetData {
	my ($self, $adapter) = @_;
	my ($data, $exit_code) = $self->_runCli('vsf info', $adapter);
	return undef if (! defined $data || $exit_code);
	return $self->_parseVolumeSetData($data);
}

=head2 getRAIDSetData

 my $data = $self->getRAIDSetData($adapter);

Returns hash reference containing RAID set data on success, otherwise undef.
$adapter is the adapter number to look at, defaults to 1 if not defined.

=cut
sub getRAIDSetData {
	my ($self, $adapter) = @_;
	my ($data, $exit_code) = $self->_runCli('rsf info', $adapter);
	return undef if ($exit_code);
	return $self->_parseRAIDSetData($data);
}

=head2 setIdLight

 my $data = $self->setIdLight($id, $password, $adapter);

Blink the identify-light given by the index $id on the designated $adapter.
To actually do this this, password given by $password must be set. Turn the
blinking off with $id == 0.

=cut
sub setIdLight {
	my ($self, $id, $password, $adapter) = @_;
	return undef unless (defined $id and defined $password);

	my ($out, $exit_code);

	# set adapter
	($out, $exit_code) = $self->_runCli('rsf info', $adapter);
	return undef if ($exit_code);

	# set password
	return undef unless ($self->_setPassword($password));	

	# run the cli
	($out, $exit_code) = $self->_runCli("disk identify drv=$id", $adapter);
	return $exit_code ? 0 : 1;
}

sub VERSION {
	return $VERSION;
}

##################################################
#              PRIVATE METHODS                   #
##################################################
# my ($out, $retval) = $self->_runCommand($cmd);
#
#Runs the specified system command ($cmd). Returns an array ($out, $retval); 
#$out is the STDOUT of the command, $ret is the command's return value.
sub _runCommand {
	my ($self, $cmd) = @_;
	unless ($cmd) {
		$self->error("Nothing to run.");
		return undef;
	}
	
	# run command...
	my ($out, $retval) = $self->qx($cmd);

	# complain if there is error
	if ($retval) {
		$self->error("######################################## [BEGIN COMMAND OUTPUT] ########################################");
		map { 
			$self->error(join("\n", $_));
		} @$out;
		$self->error("######################################## [END COMMAND OUTPUT] ########################################");
		$self->error("Command '$cmd' exited with return value '$retval'");
	}
	else {
		$self->_debug("######################################## [BEGIN COMMAND OUTPUT] ########################################");
		map { 
			$self->_debug(join("\n", $_));
		} @$out;
		$self->_debug("######################################## [END COMMAND OUTPUT] ########################################");
		$self->_debug("Command '$cmd' exited with return value '$retval'");
	}
	return ($out, $retval);	
}

# self->_debug($msg);
#
#Spew out some debug message if we are in debug mode.
sub _debug {
	my ($self, $msg) = @_;
	if ($self->{debug}) {
		$self->bufApp("DEBUG: $msg");
	}
}

sub _setCurrentAdapter {
	my ($self, $adapter) = @_;

	# set default adapter (1)
	$adapter = (defined $adapter ? $adapter : 1);
	$self->_debug("Setting current adapter to: $adapter");

	# run the Areca cli
	my $cli = $self->_getArecaCli();
	return undef unless defined($cli);

	my $run = $cli . " 'set curctrl=$adapter'";
	my ($out, $exit_code) = $self->_runCommand($run);

	return (! defined $out || $exit_code) ? 0 : 1;
}

sub _getArecaCli {
	my ($self) = @_;
	foreach (@RAID_CMD) {
		my $cli = $self->which($_);
		return $cli if (defined $cli);
	}
	$self->error("Areca CLI utility (" . join(", ", @RAID_CMD) . ") not found on system.");
	return undef;
}

# my ($out, $retval) = $self->_runCli($command, $adapter);
#
#Runs the Areca command ($command) on the Areca adapter ($adapter). Returns 
#an array ($out, $retval); $out is the STDOUT of the areca-cli command, 
#$ret is its return value.
sub _runCli {
	my ($self, $command, $adapter) = @_;

	# set proper Areca adapter
	unless ($self->_setCurrentAdapter($adapter)) {
		$self->error("Could not set adapter '$adapter': " . $self->error());
		return undef;
	}

	my $cli = $self->_getArecaCli();
	return undef unless defined($cli);

	my $run = $cli . " '$command'";
	return ($self->_runCommand($run));
}

# my ($rsd) = $self->_parseRAIDSetData($data);
#
#Parses the scalar data ($data) into a hash ($rsd). $data is supposed to be
#the output given by the Areca's 'rsf info' command.
sub _parseRAIDSetData {
	my ($self, $data) = @_;
	
	unless (defined $data) {
		$self->error("No data given.");
		return undef;
	}

	my $rsd = [];
	foreach my $line (@$data) {
		# skip the junk
		next if (
			$line =~ m/^=/ or
			$line =~ m/^\s+#/ or
			$line =~ m/^GuiErrMsg/
		);
	
		# make up an empty RAIDSetData hash	
		my $rs = {
			"Id"			=> undef,
			"Name"			=> undef,
			"Disks"			=> undef,
			"TotalCap"		=> undef,
			"FreeCap"		=> undef,
			"DiskChannels"	=> undef,
			"State"			=> undef,
		};
		
		# parse the line
		if ($line =~ m/^\s+(\d+)\s+(Raid Set # \d{2})\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/) {
			$rs->{Id} 			= $1; 
			$rs->{Name} 		= $2; 
			$rs->{Disks} 		= $3; 
			$rs->{TotalCap}		= $4; 
			$rs->{FreeCap}		= $5; 
			$rs->{DiskChannels} = $6; 
			$rs->{State} 		= $7; 
		};

		# append the parsed stuff to list
		push(@$rsd, $rs);
	}

	return $rsd;
}

# my ($vsd) = $self->_parseVolumeSetData($data);
#
#Parses the scalar data ($data) into a hash ($vsd). $data is supposed to be
#the output given by the Areca's 'vsf info' command.
sub _parseVolumeSetData {
	my ($self, $data) = @_;
	
	unless (defined $data) {
		$self->error("No data given.");
		return undef;
	}

	my $vsd = [];
	foreach my $line (@$data) {
		# skip the junk
		next if (
			$line =~ m/^=/ or
			$line =~ m/^\s+#/ or
			$line =~ m/^GuiErrMsg/
		);
	
		# make up an empty VolumeSetData hash	
		my $vs = {
			"Id"			=> undef,
			"Name"			=> undef,
			"Raid Name"		=> undef,
			"Level"			=> undef,
			"Capacity"		=> undef,
			"Ch/Id/Lun"		=> undef,
			"State"			=> undef,
		};
		
		# parse the line
		if ($line =~ m/^\s+(\d+)\s+(\S+)\s+(Raid Set # \d{2})\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/) {
			$vs->{Id} 			= $1; 
			$vs->{Name} 		= $2; 
			$vs->{'Raid Name'} 	= $3; 
			$vs->{Level}		= $4; 
			$vs->{Capacity}		= $5; 
			$vs->{'Ch/Id/Lun'}	= $6; 
			$vs->{State} 		= $7; 
		};

		# append the parsed stuff to list
		push(@$vsd, $vs);
	}

	return $vsd;
}

# my ($vsd) = $self->_parseDiskData($data);
#
#Parses the scalar data ($data) into a hash ($vsd). $data is supposed to be
#the output given by the Areca's 'disk info' command.
sub _parseDiskData {
	my ($self, $data) = @_;
	
	unless (defined $data) {
		$self->error("No data given.");
		return undef;
	}

	my $dd = [];
	foreach my $line (@$data) {
		# skip the junk
		next if (
			$line =~ m/^=/ or
			$line =~ m/^\s+#/ or
			$line =~ m/^GuiErrMsg/
		);
	
		# make up an empty DiskData hash	
		my $d = {
			"Id"			=> undef,
			"Ch#"			=> undef,
			"ModelName"		=> undef,
			"Capacity"		=> undef,
			"Usage"			=> undef,
		};
		
		# parse the line
		if ($line =~ m/^\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(Raid Set # \d{2})/) {
			$d->{Id} 		= $1; 
			$d->{'Ch#'} 	= $2; 
			$d->{ModelName}	= $3; 
			$d->{Capacity}	= $4; 
			$d->{Usage}		= $5; 
		};

		# append the parsed stuff to list
		push(@$dd, $d);
	}

	return $dd;
}

# my ($ad) = $self->_parseAdapterData($data);
#
#Parses the scalar data ($data) into a hash ($ad). $data is supposed to be
#the output given by the Areca's 'system info' command.
sub _parseAdapterData {
	my ($self, $data) = @_;
	
	unless (defined $data) {
		$self->error("No data given.");
		return undef;
	}

	# make up an empty AdapterData hash	
	my $ad = {
		"Main Processor"		=> undef,
		"CPU ICache Size"		=> undef,
		"CPU DCache Size"		=> undef,
		"CPU SCache Size"		=> undef,
		"System Memory"			=> undef,
		"Firmware Version"		=> undef,
		"BOOT ROM Version"		=> undef,
		"Serial Number"			=> undef,
		"Controller Name"		=> undef,
		"Current IP Address"	=> undef,
	};
		
	foreach my $line (@$data) {
		# skip the junk
		next if (
			$line =~ m/^=/ or
			$line =~ m/^\s+#/ or
			$line =~ m/^GuiErrMsg/
		);
	
		# parse the line
		if ($line =~ m/^\s*(.*):\s*(.*)$/) {
			my $name = $1;
			my $value = $2;
			$name =~ s/\s+$//g;
			$value =~ s/\s+$//g;
			$ad->{"$name"} = $value;
		};
	}
	return $ad;
}

# my ($success) = $self->_setPassword($password, $adapter);
#
#Sets the password ($password) for the Areca adapter ($adapter). Returns true
#if successful, false on fail, and undef if an error occured.
sub _setPassword {
	my ($self, $password, $adapter) = @_;
	return undef unless (defined $password);
	my ($data, $exit_code) = $self->_runCli("set password=$password", $adapter);
	return $exit_code ? 0 : 1;
}

=head1 SEE ALSO

L<P9::AA::Check::ArecaRAID>

=head1 AUTHOR

Uros Golja

=cut

1;
