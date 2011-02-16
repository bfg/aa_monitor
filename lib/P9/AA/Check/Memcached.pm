package P9::AA::Check::Memcached;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::_Socket';

our $VERSION = 0.11;

use constant MEMCACHED_DEFAULT_PORT => 11211;
use constant CRLF => "\r\n";

##################################################
#              PUBLIC  METHODS                   #
##################################################

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Memcached health checking module."
	);
	
	$self->cfgParamAdd(
		'host',
		'localhost',
		'Memcached host. Host can contain :<port>.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'port',
		11211,
		'Memcached listening port',
		$self->validate_int(1, 65535)
	);
	$self->cfgParamAdd(
		'timeout',
		1,
		'Timeout in seconds.',
		$self->validate_int(1)
	);
	
	$self->cfgParamRemove('timeout_connect');
	
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# try to connect to memcached
	my $conn = $self->mcConnect($self->{host});
	return CHECK_ERR unless (defined $conn);
	
	# put something to blabla
	my $key = "_key_" . sprintf("%-7.7d", int(rand(2000000)));
	my $val = rand();
	$self->bufApp("TX KEY: '$key'; VALUE: '$val'");
	return CHECK_ERR unless (defined $self->mcSet($conn, $key, rand()));
	$val = $self->mcGet($conn, $key);
	return CHECK_ERR unless (defined $val);
	$self->bufApp("RX KEY: '$key'; VALUE: '$val'");

	# try to fetch stats
	my $stats = $self->mcCmd($conn, "stats");
	return CHECK_ERR unless (defined $stats);
	$self->bufApp("");
	$self->bufApp("MEMCACHED STATS");
	$self->bufApp("--- snip ---");
	map {
		$self->bufApp($_);
	} split(/[\r\n]+/, $stats);
	$self->bufApp("--- snip ---");

	return CHECK_OK;
}

sub toString {
	my $self = shift;
	no warnings;
	my $str = $self->{host};
	if ($self->{host} !~ /:\d+$/) {
		$str .= ':' . $self->{port};
	}
	return $str;
}

##################################################
#              PRIVATE METHODS                   #
##################################################

sub mcConnect {
	my ($self, $addr) = @_;
	unless (defined $addr) {
		$self->error("Undefined memcached host:port");
		return undef;
	}
	# remove spaces
	$addr =~ s/\s+//g;

	# parse host, port
	my ($ip, $port) = (undef, undef);
	if ($addr =~ m/^([a-z\[\]0-9-\.]+):(\d+)?$/i) {
		$ip = $1;
		$port = $2;
	} else {
		$ip = $addr;
	}
	$port = MEMCACHED_DEFAULT_PORT unless (defined $port && $port > 0);

	# try to connect
	return $self->sockConnect($ip, PeerPort => $port, Timeout => $self->{timeout});
}

sub mcCmd {
	my ($self, $sock, $cmd) = @_;
	$self->error('');
	my $err = "Unable to execute command '$cmd': ";
	unless (defined $cmd && length($cmd) > 0) {
		$self->error($err . "Undefined command.");
		return undef;
	}
	unless (defined $sock && $sock->connected()) {
		$self->error($err . "Invalid connection socket.");
		return undef;
	}
	
	# send command
	my $prefix = "DEBUG [" . $sock->peerhost() . ":" . $sock->peerport() . "]:";
	$self->bufApp("$prefix Sending command: $cmd") if ($self->{debug});
	print $sock $cmd . CRLF;
	
	my $r = undef;
	my $error = "";
	
	my $timeout = 0;

	# read response in a safe way
	eval {
		# install local sighandler for handling
		# read timeouts
		local $SIG{ALRM} = sub {
			die "Timeout reading response from server.\n";
		};
		alarm($self->{timeout});
		
		# read response
		while (<$sock>) {
			alarm($self->{timeout});
			# print STDERR "GOT: $_";
			my $x = $_;
			$x =~ s/^\s+//g;
			$x =~ s/\s+$//g;
	
			# end of response?
			if ($x =~ m/^end$/i) {
				# nothing read from backend so far
				# but already end of response?
				$error = "Zero byte response from backend; probaby nothing was found on queries." unless (defined $r);
				last;
			}
			elsif ($x =~ m/^error$/i) {
				$r = undef;
				$error = "Invalid command.";
				last;
			}
			elsif ($x =~ m/^[a-z]+_error\s+(.*)$/i) {
				no warnings;
				$r = undef;
				$error = "Client or server error: $1";
				last;
			}
			elsif ($x =~ m/^value\s+/i) {
				next;
			}
			elsif ($x =~ m/^(?:(?:not_)?stored|exists|not_found|deleted)$/i) {
				$r = $x;
				last;
			}

			$r .= $_;
		}
		# disable sigalrm
		alarm(0);
	};

	# check for fatal injuries...
	if ($@) {
		$self->error($err . "Timeout reading from remote server.");
		return undef;
	}
	
	if ($self->{debug}) {
		$self->bufApp("$prefix Command response:");
		$self->bufApp("--- snip ---");
		$self->bufApp($r) if (defined $r);
		$self->bufApp("--- snip ---"); 
	}
	
	if (! $r) {
		$self->error($err . $error);
	} else {
		# remove last \r\n
		$r = substr($r, 0, (length($r) - length(CRLF)));
	}

	return $r;
}

sub mcSet {
	my ($self, $sock, $key, $value, $expire) = @_;
	return undef unless ($self->mcValidateKey($key));
	$expire = 100 unless (defined $expire);
	$value = "" unless (defined $value);

	my $cmd = "set $key 0 $expire " . length($value);
	$cmd .= CRLF . $value;

	return $self->mcCmd($sock, $cmd);
}

sub mcGet {
	my ($self, $sock, $key) = @_;
	return undef unless ($self->mcValidateKey($key));
	my $cmd = "get $key";
	return $self->mcCmd($sock, $cmd);
}

sub mcRemove {
	my ($self, $sock, $key) = @_;
	return undef unless ($self->mcValidateKey($key));
	my $cmd = "delete $key";
	return $self->mcCmd($sock, $cmd);
}

sub mcValidateKey {
	my ($self, $key) = @_;
	unless (defined $key && length($key) > 0) {
		$self->error("Invalid key.");
		return 0;
	}
	return 1;
}

1;