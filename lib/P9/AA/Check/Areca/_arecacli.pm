package P9::AA::Check::Areca::_arecacli;

use strict;
use warnings;

use File::Spec;
use POSIX qw(getcwd);

use base 'P9::AA::Check::Areca';

use constant RAID_CMD => 'areca-cli';

our $VERSION = 0.01;

=head1 NAME

Implementation of L<P9::AA::Check::Areca> module based
on Areca's cli32/cli64 command-line utility. Note that 
the cli32/cli64 utility is renamed to alreca-cli in 
the Planet9 Linux distribution. 

=cut

=head2 getAdapterData

 my $data = $self->getAdapterData();

Returns hash reference containing adapter data on success, otherwise undef.

=cut
sub getAdapterData {
	my ($self) = @_;
	my ($data, $exit_code) = $self->_runCli('sys info');
	return undef if ($exit_code);
	return $self->_parseAdapterData($data);
}

=head2 getDiskData

 my $data = $self->getDiskData();

Returns hash reference containing disk data on success, otherwise undef.

=cut
sub getDiskData {
	my ($self, $adapter) = @_;
	my ($data, $exit_code) = $self->_runCli('disk info', $adapter);
	return undef if ($exit_code);
	return $self->_parseDiskData($data);
}

=head2 getVolumeSetData

 my $data = $self->getVolumeSetData();

Returns hash reference containing volume set data on success, otherwise undef.

=cut
sub getVolumeSetData {
	my ($self, $adapter) = @_;
	my ($data, $exit_code) = $self->_runCli('vsf info', $adapter);
	return undef if ($exit_code);
	return $self->_parseVolumeSetData($data);
}

=head2 getRAIDSetData

 my $data = $self->getRAIDSetData();

Returns hash reference containing RAID set data on success, otherwise undef.

=cut
sub getRAIDSetData {
	my ($self, $adapter) = @_;
	my ($data, $exit_code) = $self->_runCli('rsf info', $adapter);
	return undef if ($exit_code);
	return $self->_parseRAIDSetData($data);
}


sub VERSION {
	return $VERSION;
}

##################################################
#              PRIVATE METHODS                   #
##################################################
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
		#$self->_debug(join("\n", @$out));
		$self->_debug("######################################## [END COMMAND OUTPUT] ########################################");
		$self->_debug("Command '$cmd' exited with return value '$retval'");
	}
	return ($out, $retval);	
}

sub _debug {
	my ($self, $msg) = @_;
	if ($self->{debug}) {
		$self->bufApp("DEBUG: $msg");
	}
}

sub _getDefaultAdapter {
	my ($self, $adapter) = @_;
	$adapter = 1 if (!defined $adapter);
	return $adapter;
}

sub _setCurrentAdapter {
	my ($self, $adapter) = @_;

	# run the Areca cli
	$adapter = $self->_getDefaultAdapter($adapter);
	my $run = RAID_CMD . " 'set curctrl=$adapter'";
	my ($out, $exit_code) = $self->_runCommand($run);

	return ($exit_code ? 0 : 1);
}

sub _runCli {
	my ($self, $command, $adapter) = @_;

	# set proper Areca adapter
	unless ($self->_setCurrentAdapter($adapter)) {
		$self->error("Could not set adapter '$adapter'.");
		return undef;
	}

	my $run = RAID_CMD . " '$command'";
	return ($self->_runCommand($run));
}

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
	
		# make up an empty RAIDSet hash	
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
	
		# make up an empty RAIDSet hash	
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
	
		# make up an empty RAIDSet hash	
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





=head1 SEE ALSO

L<P9::AA::Check::Areca>

=head1 AUTHOR

Uros Golja

=cut

1;
