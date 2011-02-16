package P9::AA::Check::MegaSAS::_megacli;

use strict;
use warnings;

use File::Spec;
use POSIX qw(getcwd);

use base 'P9::AA::Check::MegaSAS';

use constant RAID_CMD => 'MegaCli';

our $VERSION = 0.11;

=head1 NAME

Implementation of L<P9::AA::Check::MegaSAS> module based
on MegaCli command line utility.

=cut
sub getAdapterData {
	my ($self) = @_;
	
	# run command
	my ($out, $exit_code) = $self->_runCommand(RAID_CMD . ' -CfgDsply -aALL');
	return undef unless (defined $out);
	
	# parse adapter data...
	return $self->parseAdapterData($out);
}

sub parseAdapterData {
	my ($self, $in) = @_;
	my $ref = ref($in);
	unless (defined $in && ($ref eq 'SCALAR' || $ref eq 'ARRAY')) {
		$self->error("Input data must be defined array or scalar reference.");
		return undef;
	}
	
	# get_lines sub
	my $get_lines = ($ref eq 'SCALAR') ?
		sub { split(/[\r\n]+/, ${$in}) }
		:
		sub { @{$in} };

	# result structure...
	my $result = {};

	# parse output
	my $adapter = undef;
	my $volume = undef;
	my $volume_state = undef;
	my $disk_num = undef;
	my $disk_state = undef;
	my $err = '';
	my $data = {};
	foreach my $line ($get_lines->()) {
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;

		if ($line =~ m/Adapter:\s+(\d+)/) {
			$adapter = $1;
			$volume = undef;
			$volume_state = undef;
			$disk_num = undef;
			$disk_state = undef;			
		}
		elsif ($line =~ m/^DISK GROUPS:\s+(\d+)$/i) {
			$volume = int($1);
			$volume_state = undef;
			$disk_num = undef;
			$disk_state = undef;
		}
		elsif ($line =~ m/^Physical\s+Disk:\s+(\d+)/i) {
			$disk_num = int($1);
			$disk_state = undef;
		}
		elsif ($line =~ m/^State:\s+(.+)$/i) {
			$result->{$adapter}->{$volume}->{state} = lc($1);
		}
		elsif ($line =~ m/^Firmware\s+state:\s+(.+)$/i) {
			$result->{$adapter}->{$volume}->{$disk_num}->{state} = lc($1);
		}
		
		if (defined $adapter && defined $volume && defined $disk_num) {
			my ($k, $v) = split(/\s*:\s*/, $line, 2);
			next unless (defined $k && defined $v);
			$k =~ s/\s+/_/g;
			$k = lc($k);
			$result->{$adapter}->{$volume}->{$disk_num}->{$k} = $v;
		}
	}

	return $result;
}

sub VERSION {
	return $VERSION;
}

##################################################
#              PRIVATE METHODS                   #
##################################################

sub _runCommand {
	my $self = shift;
	unless (@_) {
		$self->error("Nothing to run.");
		return undef;
	}
	
	my $cwd = getcwd();
	my $tmpd = File::Spec->tmpdir();
	unless (chdir($tmpd)) {
		$self->error("Unable to change working directory to '$tmpd': $!");
		return undef;
	}
	
	# run command...
	my @res = $self->qx2(@_);

	# remove megarc.log and don't check for errors
	unlink(File::Spec->catfile($tmpd, "MegaSAS.log"));

	# jump back to previous working directory
	unless (chdir($cwd)) {
		$self->error("Unable to change working directory to '$cwd': $!");
		return undef;
	}

	return @res;
}

=head1 SEE ALSO

L<P9::AA::Check::MegaSAS>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;