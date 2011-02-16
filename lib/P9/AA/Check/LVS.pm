package P9::AA::Check::LVS;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::Process';

use constant PROGRAM_NAME => 'ipvsadm';

our $VERSION = 0.15;

=head1 NAME

Linux Virtual Server service health check.

=head1 METHODS

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks Linux LVS virtual host table. Requires Linux operating system with LVS kernel support and ipvsadm(8) command."
	);
	
	$self->cfgParamAdd(
		'resolve_names',
		0,
		'Resolve LVS addresses to names?',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'check_ldirectord',
		1,
		'Check ldirectord(8) process?',
		$self->validate_bool(),
	);
	
	# remove process config parameters
	$self->cfgParamRemove('cmd');
	$self->cfgParamRemove('min_process_count');
	$self->cfgParamRemove('use_basename');

	return 1;
}

=head2 check

Checks local LVS configuration.

=cut
sub check {
	my ($self) = @_;
	my $os = $self->getOs();
	unless (lc($os) eq 'linux') {
		$self->error("This module doesn't work on $os operating system.");
		return CHECK_ERR;
	}
	
	my $result = CHECK_OK;
	my $data = $self->getLVSData();
	return CHECK_ERR unless (defined $data);
	
	my $err = '';
	
	unless (scalar keys %{$data} > 0) {
		$self->error("No LVS configuration listed by ipvsadm(8).");
		return CHECK_ERR;
	}
	
	foreach my $vhost (keys %{$data}) {
		if (($#{$data->{$vhost}->{servers}} + 1) < 1) {
			my $str = "Virtual server '" . $data->{$vhost}->{name} . "' has no associated real servers.";
			$err .= $str . "\n";
			$result = CHECK_ERR;
		}
	}

	# also check ldirectord...
	unless ($self->_checkLdirectord()) {
		$err .= $self->error() . "\n";
		$result = CHECK_ERR;
	}

	if ($result != CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}
	
	# we succeeded
	return $result;
}


=head2 getLVSData

Returns hash reference containing current LVS state on success, otherwise undef.

=cut
sub getLVSData {
	my ($self) = @_;
	my $data = {};

	# compute command
	my @cmd = (PROGRAM_NAME);
	push(@cmd, '-L');
	push(@cmd, '-n') unless ($self->{resolve_names});

	# run program
	my ($out, $exit_status) = $self->qx2(@cmd);
	unless (defined $out && ref($out) eq 'ARRAY' && $exit_status == 0) {
		return undef;
	}

	if ($self->{debug}) {
		$self->bufApp("--- BEGIN LVS RAW DATA ---");
		map { $self->bufApp($_) } @{$out};
		$self->bufApp("---  END LVS RAW DATA  ---");
	}
	
	my $header_read = 0;
	my $last_vhost = "";
	foreach (@{$out}) {
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		next unless (length($_) > 0);
		
		unless ($header_read) {
			$header_read = 1 if (/^-> RemoteAddress:Port/);
			next;
		}
		
		# virthost real server entry
		if (/^-> (.+)/) {
			my @tmp = split(/\s+/, $1);
			my ($addr, $port) = split(/:/, $tmp[0]);
			my $real_server = {
				addr => $addr,
				port => $port,
				forward => $tmp[1],
				weight => $tmp[2],
				conn_act => $tmp[3],
				conn_incat => $tmp[4]
			};
			push(@{$data->{$last_vhost}->{servers}}, $real_server);
		}
		# lvs virthost entry
		elsif (/^(tcp|udp|icmp)\s+([^\s]+)\s+([^\s]+)\s+(.+)/i) {
			my $struct = {
				name => $2,
				proto => $1,
				host => $2,
				scheduler => $3,
				flags => $4,
				servers => []
			};
			$data->{$2} = $struct;
			$last_vhost = $2;
		}
	}

	if ($self->{debug}) {
		$self->bufApp("--- BEGIN LVS DATA ---");
		$self->bufApp($self->dumpVar($data));
		$self->bufApp("---  END LVS DATA  ---");
	}

	return $data;
}

sub _checkLdirectord {
	my ($self) = @_;
	unless ($self->{check_ldirectord}) {
		$self->bufApp("Ldirectord check is disabled, returning success.");
		return 1;
	}
	
	# try to get processlist...
	my $pl = $self->getProcessListComplex(
		basename => 0,
		user => 'root',
		regex => qr/bin\/ldirectord/
	);
	return 0 unless (defined $pl);
	
	# nothing found?
	unless (scalar(@{$pl}) >= 1) {
		$self->error("ldirectord(8) doesn't seem to be running.");
		return 0;
	}
	
	$self->bufApp('ldirectord(8) seems to be running as pid ' . $pl->[0]->{pid});

	return 1;
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<P9::AA::Check>

=cut

1;