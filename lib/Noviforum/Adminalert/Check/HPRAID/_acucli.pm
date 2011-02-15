package Noviforum::Adminalert::Check::HPRAID::_acucli;

use strict;
use warnings;

use POSIX qw(getcwd);

use base 'Noviforum::Adminalert::Check::HPRAID';

use constant RAID_CMD => 'hpacucli';

our $VERSION = 0.10;

=head1 NAME

HPAcucli implementation of L<Noviforum::Adminalert::Check::HPRAID> module.

=head1 DESCRIPTION

Requires L<hpacucli(8)> command.

=cut

sub getAdapterData {
	my ($self) = @_;
	
	my $adapters = $self->getAdapterList();
	return undef unless (defined $adapters);
	
	my $result = {};
	foreach (@{$adapters}) {
		my $num = $_->{slot};
		
		# get data for adapter...
		my ($out, $exit_code) = $self->qx(RAID_CMD . ' controller slot=' . $num . ' physicaldrive all show');
		unless (defined $out) {
			$self->error(
				"Error fetching data for adapter slot $num: " .
				$self->error()
			);
			return undef;
		}

		# parse data for adapter...
		my $adapter_data = $self->parseAdapterData($out);
		unless (defined $adapter_data) {
			$self->error(
				"Error parsing data for adapter slot $num: " .
				$self->error()
			);
			return undef;
		}
		$result->{$num}->{name} = $_->{name};
		$result->{$num}->{serial} = $_->{serial};
		$result->{$num}->{volumes} = $adapter_data;
	}

	return $result;
}

sub getAdapterList {
	my ($self) = @_;
	my ($out, $exit_code) = $self->qx2(RAID_CMD . ' controller all show');
	return undef unless (defined $out);
	return $self->parseAdapterList($out);
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
	foreach my $line ($get_lines->()) {
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length $line);

		# $ hpacucli controller all show
		# Smart Array P410i in Slot 0 (Embedded)    (sn: 5001438006B03310)
		if ($line =~ m/^(.+)\s+in\s+Slot\s+(\d+)\s+/i) {
			my $name = $1;
			my $slot = int($2);
			my $serial = '';
			if ($line =~ m/\s+\(\s*sn:\s+([^\)]+)\)/i) {
				$serial = $1;
			}
			push(@{$r}, { slot => $slot, name => $name, serial => $serial });
		}
		
	}
	
	# nothing parsed out?
	unless (@{$r}) {
		$self->error("No HPRAID adapter data was parsed from input.");
		return undef;
	}

	if ($self->{debug}) {
		$self->bufApp("--- BEGIN HPRAID ADAPTER LIST ---");
		$self->bufApp($self->dumpVar($r));
		$self->bufApp("--- END HPRAID ADAPTER LIST ---");
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
		
#
#$ hpacucli controller slot=0 physicaldrive all show
#
#Smart Array P410i in Slot 0 (Embedded)
#
#   array A
#
#      physicaldrive 1I:1:1 (port 1I:box 1:bay 1, SAS, 146 GB, OK)
#      physicaldrive 1I:1:2 (port 1I:box 1:bay 2, SAS, 146 GB, OK)
#

	# result data
	my $data = {};

	my $array_name = undef;

	foreach my $line ($get_lines->()) {
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (defined $line && length $line);
		# print "parsing line: $line\n";
		
		if ($line =~ m/^array\s+(.+)/i) {
			$array_name = $1;
			next;
		}
		elsif ($line =~ m/^physicaldrive\s+[\w:]+\s+\((.+)\)/) {
			next unless (defined $array_name && length $array_name);
			my @tmp = split(/\s*[:;,]+\s*/, $1);
			my $status = lc(pop(@tmp));
			my $d = {};
			my $c = '';
			
			foreach my $f (@tmp) {
				if ($f =~ m/\s+{k|m|g|t]{1}b/i) {
					$c .= "$f, ";
					next;
				}
				if ($f =~ m/^(\w+)\s+(\w+)/) {
					$d->{$1} = $2;
				} else {
					$c .= "$f, ";
				}
			}

			$c =~ s/[,\s]+$//g;
			$d->{misc} = $c;
			$d->{status} = $status;
			
			# add data to result...
			push(@{$data->{$array_name}}, $d);
		}
	}

	unless (%{$data}) {
		$self->error("No HPRAID volume data was parsed from input.");
		return undef;
	}

	return $data;
}

sub VERSION {
	return $VERSION;
}

=head1 SEE ALSO

L<Noviforum::Adminalert::Check::HPRAID>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;