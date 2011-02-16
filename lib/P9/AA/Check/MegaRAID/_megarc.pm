package P9::AA::Check::MegaRAID::_megarc;

use strict;
use warnings;

use POSIX qw(getcwd);

use base 'P9::AA::Check::MegaRAID';

use constant RAID_CMD => 'megarc.bin';

our $VERSION = 0.17;

=head1 NAME

B<megarc.bin> based implementation of L<P9::AA::Check::MegaRAID> module.

=cut

sub getAdapterData {
	my ($self) = @_;
	
	my $adapters = $self->getAdapterList();
	return undef unless (defined $adapters);
	
	my $result = {};
	foreach (@{$adapters}) {
		my $num = $_->{adapter};
		
		# get data for adapter...
		my ($out, $exit_code) = $self->_runCommand(RAID_CMD . ' -dispCfg -a' . $num);
		unless (defined $out) {
			$self->error(
				"Error fetching data for adapter $num: " .
				$self->error()
			);
			return undef;
		}

		# parse data for adapter...
		my $adapter_data = $self->parseAdapterData($out);
		unless (defined $adapter_data) {
			$self->error(
				"Error parsing data for adapter $num: " .
				$self->error()
			);
			return undef;
		}

		$result->{$num}->{card} = $_->{card};
		$result->{$num}->{firmware} = $_->{firmware};
		$result->{$num}->{volumes} = $adapter_data;
	}

	return $result;
}

sub getAdapterList {
	my ($self) = @_;
	my ($out, $exit_code) = $self->_runCommand(RAID_CMD . ' -AllAdpInfo');
	return undef unless (defined $out);
	return $self->parseAdapterList($out);
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
	unlink(File::Spec->catfile($tmpd, "megarc.log"));

	# jump back to previous working directory
	unless (chdir($cwd)) {
		$self->error("Unable to change working directory to '$cwd': $!");
		return undef;
	}

	return @res;
}

sub parseAdapterList {
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

	my $r = [];
	my $header_read = 0;
	foreach my $line ($get_lines->()) {
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		
		unless ($header_read) {
			if ($line =~ m/^AdapterNo\s+FirmwareType\s+CardType/i) {
				$header_read = 1;
			}
			next;
		}
		
		# sample output...
		# AdapterNo  FirmwareType  CardType
		# 00          40LD/8SPAN    LSI MegaRAID SATA300-8X PCI-X
		my ($num, $firmware, @card) = split(/\s+/, $line);
		next unless (defined $num && length($num));
		{ no warnings; $num = int($num) }
		my $card = join(' ', @card);
		push(@{$r}, { adapter => $num, firmware => $firmware, card => $card });
	}
	
	# nothing parsed out?
	unless (@{$r}) {
		$self->error("No MegaRAID adapter data was parsed from input.");
		return undef;
	}

	if ($self->{debug}) {
		$self->bufApp("--- BEGIN MEGARAID ADAPTER LIST ---");
		$self->bufApp($self->dumpVar($r));
		$self->bufApp("--- END MEGARAID ADAPTER LIST ---");
	}

	return $r;
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

	# result data
	my $data = [];
	foreach my $line ($get_lines->()) {
		$line =~ s/^\W//g;
		$line =~ s/^\[A//g;
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;

		# Parse line
		if ($line =~ m/^(\d+)\s+(\w{2})\s+(\w{10})\s+(\w{10})\s+(\w+)/) {
			my $channel = $1;
			my $target = $2;
			my $start_block = $3;
			my $blocks = $4;
			my $status = $5;
			
			push(
				@{$data},
				{
					channel => $channel,
					target => $target,
					status => lc($status),
				}
			);
		}
	}

	unless (@{$data}) {
		$self->error("No volume data was parsed from input.");
		return undef;
	}

	return $data;
}

sub VERSION {
	return $VERSION;
}

=head1 SEE ALSO

L<P9::AA::Check::MegaRAID>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;