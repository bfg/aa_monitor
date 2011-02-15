package Noviforum::Adminalert::Check::TCPSocket;

use strict;
use warnings;

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::_Socket';

our $VERSION = 0.12;

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks is specified hostname listens on specified ports."
	);

	$self->cfgParamAdd(
		'hostname',
		'localhost',
		'Hostname, IP address or UNIX listening socket path.',
		$self->validate_str()
	);
	$self->cfgParamAdd(
		'ports',
		'',
		'Comma separated list of listening ports to connect to.',
		$self->validate_str()
	);
	$self->cfgParamAdd(
		'readline_regex',
		'',
		'Try to read line from connected socket and match content against specified regex. Syntax: /pattern/flags; Example: /som[eoa]+thing$/i',
		$self->validate_str()
	);
	$self->cfgParamAdd(
		'readline_max_lines',
		1,
		'Maximum number of lines to read. This parameter is used only if readline_regex parameter is set.',
		$self->validate_int(0, 100)
	);
	$self->cfgParamAdd(
		'readline_strip',
		1,
		'Strip read line before matching.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'debug',
		1,
		'Display debugging messages.',
		$self->validate_bool(),
	);

	return 1;	
}

sub check {
	my ($self) = @_;	
	my @ports = split(/\s*[;,]\s*/, $self->{ports});
	
	foreach my $port (split(/\s*[;,]\s*/, $self->{ports})) {
		return CHECK_ERR unless ($self->_checkConnection($self->{hostname}, $port));
	}

	return CHECK_OK;
}

sub toString {
	my $self = shift;
	return $self->{hostname} . ":" . $self->{ports};
}

sub _checkConnection {
	my ($self, $host, $port) = @_;
	$self->bufApp("$host port $port :: trying to connect.") if ($self->{debug});
	my $sock = $self->sockConnect($host, PeerPort => $port);

	# check connection state
	unless (defined $sock) {
		$self->{error} = "Unable to connect to host $host, port $port: $!";
		return 0;
	}
	$self->bufApp("$host port $port :: successfully connected.") if ($self->{debug});
	
	# optionally check welcome message
	if (length($self->{readline_regex}) > 0) {
		$self->bufApp("$host port $port :: checking peer's welcome message.") if ($self->{debug});
		$self->bufApp("$host port $port :: trying to compile regex '" . $self->{readline_regex} . "'.") if ($self->{debug});
		
		# create validator...
		my $v = $self->validate_regex();
		my $re = $v->($self->{readline_regex}, undef);

		unless (defined $re) {
			$self->{error} = "Invalid readline regex '" . $self->{readline_regex} . "': $@";
			return 0;
		}
		
		my $err = undef;
		my $timeout = 3;
		local $SIG{ALRM} = sub {
			$err = "Timeout ($timeout seconds) reading from socket.";
		};
		alarm($timeout);
		
		# read lines
		my $max = $self->{readline_max_lines};
		my $i = 0;
		my $found = 0;
		$self->bufApp("$host port $port :: reading lines (max $max) from peer.") if ($self->{debug});
		while (! defined $err && $i < $max) {
			$i++;
			my $line = $sock->getline();
			last unless (defined $line);

			if ($self->{readline_strip}) {
				$line =~ s/^\s+//g;
				$line =~ s/\s+$//g;
			}
			
			print "  read: '$line'" if ($self->{debug});
			
			# check if matches
			if ($line =~ $re) {
				$found = 1;
				last;
			}
		}
		alarm(0);
		
		if ($found) {
			print "Content in line $i matched regex pattern $re" if ($self->{debug});
		} else {
			if (defined $err) {
				$self->error($err);
			} else {
				$self->error(
					"No content that would match regex $re was found in $i read lines."
				);
			}
			return 0;
		}
	}
	
	$self->bufApp() if ($self->{debug});
	return 1;
}

1;