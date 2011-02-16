package P9::AA::Daemon;

use strict;
use warnings;

use IO::Select;
use Scalar::Util qw(blessed);
use POSIX qw(:sys_wait_h setsid);

use P9::AA::Config;
use base 'P9::AA::Base';

use constant MAX_CLIENTS => 50;

our $VERSION = 0.40;

my $_ipv6_available = undef;

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};

	##################################################
	#               PUBLIC VARS                      #
	##################################################
	$self->{_error} = '';

	##################################################
	#              PRIVATE VARS                      #
	##################################################
	$self->{_clients} = {};
	$self->{_daemonized} = 0;
	$self->{_chroot} = 0;
	$self->{_listeners} = [];
	$self->{_max_clients} = MAX_CLIENTS;
	$self->{_conn_class} = undef;

	bless($self, $class);
	return $self;
};

sub conn_class {
	my ($self, $name) = @_;
	if (defined $name) {
		$self->{_conn_class} = $name;
	}
	
	return $self->{_conn_class};
}

sub ipv6_available {
	unless (defined $_ipv6_available) {
		$_ipv6_available = eval 'require IO::Socket::INET6; 1' ? 1 : 0;
	}
	return $_ipv6_available;
}

sub num_clients {
	my ($self) = @_;
	return scalar(keys %{$self->{_clients}});
}

sub max_clients {
	my ($self, $num) = @_;
	no warnings;
	if (defined $num && $num > 0) {
		$self->{_max_clients} = $num;
	}
	return $self->{_max_clients};
}

sub daemonize {
	my ($self) = @_;
	$self->{_error} = '';
	my $e = "Unable to daemonize: ";
	if ($self->{_daemonized}) {
		$self->{_error} = $e . "Already daemonized.";
		return 0;
	}
	
	# change directory...
	unless (chdir('/')) {
		$self->{_error} = $e . "Unable to change directory to /: $!";
		return 0;
	}
	
	# close standard streams
	close(STDIN); close(STDOUT); close(STDERR);

	# reopen standard streams...
	unless (open(STDIN, '<', '/dev/null')) {
		$self->{_error} = $e . "Unable to open stdin from null device.";
		return 0;
	}
	unless (open(STDOUT, '>', '/dev/null')) {
		$self->{_error} = $e . "Unable to open stdout to null device.";
		return 0;
	}
	unless (open(STDERR, '>', '/dev/null')) {
		$self->{_error} = $e . "Unable to open stderr to null device.";
		return 0;
	}

	# fork!
	my $pid = fork();
	unless (defined $pid) {
		$self->{_error} = $e . "Unable to fork: $!";
		return 0;
	}
	
	# parent?
	if ($pid > 0) {
		exit 0;
	}
	
	setsid();
	$self->{_daemonized} = 1;

	$self->log_info("Successfully became a daemon (pid: $$).");
	return 1;
}

sub chroot {
	my ($self, $dir) = @_;
	$self->{_error} = '';
	unless (defined $dir && -d $dir && -r $dir) {
		no warnings;
		$self->{_error} = "Invalid chroot directory: '$dir'.";
		return 0;
	}
	
	unless (CORE::chroot($dir)) {
		$self->{_error} = "Unable to chroot to $dir: $!";
		return 0;
	}
	
	return 1;
}

sub setuid {
	my ($self, $user) = @_;
	$self->{_error} = '';
	my $uid = $user;
	my $e = "Unable to setuid to uid $user: ";

	# not a number?
	if ($uid !~ m/^\d+$/) {
		# try to resolve uid
		$uid = getpwnam($uid);
		unless (defined $uid && $uid >= 0) {
			$self->{_error} = $e . "Invalid user";
			return 0;
		}
	}
	
	return 1 if ($> == $uid);
	
	# try to setuid
	unless (POSIX::setuid($uid)) {
		$self->{_error} = $e . $!;
		return 0;
	}

	return 1;
}

sub setgid {
	my ($self, $group) = @_;
	$self->{_error} = '';
	my $gid = $group;
	my $e = "Unable to setgid to gid $group: ";

	# not a number?
	if ($gid !~ m/^\d+$/) {
		# try to resolve gid
		$gid = getgrnam($gid);
		unless (defined $gid && $gid >= 0) {
			$self->{_error} = "Invalid group";
			return 0;
		}
	}

	return 1 if ($) == $gid);
	
	# try to setgid
	unless (POSIX::setgid($gid)) {
		$self->{_error} = $e . $!;
		return 0;		
	}

	return 1;
}

sub run {
	my ($self, $cfg) = @_;
	$self->{_error} = '';
	
	# no configuration object given?
	# no problem - aa configuration class
	# always returns singleton instance already
	# configured by main script :)
	unless (defined $cfg) {
		$cfg = P9::AA::Config->new();
	}
	
	$self->log_info("Daemon startup.");

	# create listening socket (s)...
	my $sockets = $self->_listenersCreate(
		$cfg->get('listen_addr'),
		$cfg->get('listen_port'),
	);
	
	# none created?
	unless (defined $sockets && @{$sockets}) {
		$self->{_error} = "No listening sockets created: " . $self->error();
		return 0;
	}
	
	# save listening sockets...
	$self->{_listeners} = $sockets;
	
	# chroot?
	my $chroot = $cfg->get('chroot');
	if (defined $chroot && length($chroot) > 0 && ! $self->chroot($chroot)) {
		return 0;
	}
	
	# set user/group
	if ($cfg->get('group')) {
		return 0 unless ($self->setgid($cfg->get('group')));
	}
	if ($cfg->get('user')) {
		return 0 unless ($self->setuid($cfg->get('user')));
	}

	# shoud we daemonize?
	if ($cfg->get('daemon')) {
		return 0 unless ($self->daemonize());
		my $pf = $cfg->get('pid_file');
		$self->_pidWrite($pf, $$);
	}
	
	# install signal handlers...
	$self->_sighInstall();
	
	# run accept loop
	$self->_acceptLoop($cfg->get('max_clients'));
	
	# this is it!
	return 1;
}

sub shutdown {
	my ($self) = @_;
	$self->log_info("Shutdown.");
	
	# destroy listeners
	$self->_listenersDestroy();
	
	# kill all clients
	my $i = 0;
	foreach my $pid (keys %{$self->{_clients}}) {
		$i++ if (kill(9, $pid));
	}
	$self->log_debug("Destroyed $i client connections.");

	# this is it folx!
	return 1;
}

sub _listenersCreate {
	my ($self, $str, $port, $permisive) = @_;
	$permisive = 0 unless (defined $permisive);

	# parse portz string
	my @desc = split(/\s*[;,]+\s*/, $str);
	
	# return value
	my $r = [];
	
	foreach my $e (@desc) {
		next unless (defined $e);
		$e =~ s/\s+//g;
		$e =~ s/["']+//g;
		$e =~ s/[^a-z0-9:_\.\*\[\]\/]//g;
		next unless (defined $e && length($e) > 0);
		
		my $addr = $e;
		my $p = $port;
		
		# ipv4:port specification?
		if ($e =~ m/^(\d{1-3})\.(\d{1-3})\.(\d{1-3})\.(\d{1-3}):(\d+)$/) {
			$addr = $1 . '.' . $2 . '.' . $3 . '.' . $4;
			$p = $5;
		}
		# [v4_or_v6_addr]:port specification?
		elsif ($e =~ m/^\[([^\]]+)\]:(\d+)$/) {
			$addr = $1;
			$p = $2;
		}
		# *:port?
		elsif ($e =~ m/^\*:(\d+)$/) {
			$addr = '*';
			$p = $1;
		}
		# * ?
		elsif ($e eq '*') {
			$addr = $e;
			$p = $port;
		}

		my @s = ();
		
		if ($addr eq '*' || $addr eq '::') { # && $^O eq 'linux')) {
			# try to listen on all addresses...
			
			# try to create ipv6 listening socket...
			my $sock6 = $self->_listenerCreate('::', $p);
			my $e6 = $self->error();

			# NOTE: only linux creates ipv4/ipv6 listening
			# socket on dual-stack systems... therefore
			# there is the only portable way to create
			# ipv6 and ipv4 sockets on dual stack systems.

			# create ipv4 listening socket...
			my $sock4 = $self->_listenerCreate('0.0.0.0', $p);
			my $e4 = $self->error();
			
			# none of sockets were created?
			unless (defined $sock4 || defined $sock6) {
				unless ($permisive) {
					$self->{_error} = "Unable to create INADDR_ANY listening socket port $p: ".
						"IPv6 error: $e6; " .
						"IPv4 error: $e4";

					return undef;
				}
			}

			push(@s, $sock6) if (defined $sock6);
			push(@s, $sock4) if (defined $sock4);

		} else {
			my $sock = $self->_listenerCreate($addr, $p);
			if (! $sock && ! $permisive) {
				return undef;
			}
			push(@s, $sock);
		}
			
		push(@{$r}, @s) if (@s);
	}

	return $r;
}

sub _listenersDestroy {
	my ($self) = @_;
	my $i = 0;
	return $i unless (defined $self->{_listeners} && ref($self->{_listeners}) eq 'ARRAY');
	map { close($_); $i++ } @{$self->{_listeners}};
	$self->{_listeners} = [];
	return $i;
}

sub _listenerCreate {
	my ($self, $addr, $port) = @_;
	$self->{_error} = '';

	# set ipv4 in_addr_any address...
	$addr = '0.0.0.0' unless (defined $addr && length($addr) > 0);
	
	# is this unix domain socket listener?!
	my $unix = ($addr =~ m/^\/+/i) ? 1 : 0;
	
	# select socket class implementation
	my $class = ($unix) ? 'IO::Socket::UNIX' : 'IO::Socket::INET';
	
	# unix domain socket? remove it if exists...
	if ($unix && -e $addr) {
		unless (unlink($addr)) {
			$self->log_warn("Unable to remove already existing unix domain socket $addr: $!");
		}
	}
	
	# load goddamn class :)
	eval "use $class";
	if ($@) {
		$self->{_error} = "Unable to load listener class $class: $@";
		return undef;
	}
	
	# does it look like ipv6 address?
	if (! $unix && $self->_v6Addr($addr)) {
		# check for ipv6 support...
		unless ($self->ipv6_available()) {
			$self->{_error} = "Unable to create IPv6 listening socket $addr: IPv6 support is not available. Install IO::Socket::INET6 module.";
			return undef;
		}
		$class = 'IO::Socket::INET6';
	}

	# prepare listening socket options
	my %opt = (
		LocalAddr => $addr,
		LocalPort => $port,
		ReuseAddr => 1,
		Listen => 100,
	);
	
	# unix domain socket requires different arguments
	if ($unix) {
		%opt = (
			Local => $addr,
			ReuseAddr => 1,
			Listen => 100,
		);
		$port = '';
	}

	# create listener...
	$self->log_debug("Creating listening socket [$addr]:$port");
	my $sock = $class->new(%opt);
	unless (defined $sock) {
		$self->{_error} = "Unable to create listening socket [$addr]:$port: $!";
		return undef;
	}
	
	# if unix listening socket, make sure that is world
	# writeable
	if (defined $sock && $unix) {
		unless (chmod(oct('0666'), $addr)) {
			$self->log_warn("Unable to make unix domain socket $addr world writeable: $!");
		}
	}

	return $sock;
}

sub _sighInstall {
	my ($self) = @_;
	
	# we just ignore sigpipe
	$SIG{PIPE} = 'IGNORE';

	# install terminating signal handlers
	$SIG{INT} = $SIG{TERM} = sub {
		$self->shutdown();
		exit 0;
	};
	
	# reload configuration on sigHUP
	$SIG{HUP} = sub {
		my $cfg = P9::AA::Config->new();
		my $file = $cfg->lastLoadedConfigFile();
		unless (defined $file && length($file) > 0) {
			$self->log_warn(
				"SIGHUP received, but no configuration file " .
				"was previously loaded, ignoring."
			);
			return 0;
		}
		$self->log_warn("SIGHUP received, reloading configuration.");
		unless ($cfg->loadConfigFile($file)) {
			$self->log_error($cfg->error());
		}
		
		# max clients maybe?
		$self->max_clients($cfg->get('max_clients'));
	};

	# install sigchld handler
	$SIG{CHLD} = sub {
		while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
			# "destroy" client connection
			delete($self->{_clients}->{$pid});
		}
	};

	return 1;
}

sub _sighDestroy {
	my $self = shift;
	
	# reset signal handlers...
	$SIG{INT} = $SIG{TERM} = $SIG{HUP} = 'DEFAULT';
	
	# SIGCHLD
	$SIG{CHLD} = 'DEFAULT';
}

sub _getAddr {
	my ($self, $sock) = @_;
	return '' unless (defined $sock && blessed($sock) && $sock->connected());
	my $r = '';
	if ($sock->isa('IO::Socket::UNIX')) {
		$r = $sock->hostpath();
	} else {
		$r = '[' . $sock->peerhost() . ']:' . $sock->peerport();
	}
	return $r;
}

sub _acceptLoop {
	my ($self) = @_;
	
	# create selector
	my $selector = IO::Select->new();
	
	# add all listening sockets to selector
	map { $selector->add($_) } @{$self->{_listeners}};
	
	# enter finite infinite loop
	while (@{$self->{_listeners}}) {
		#$self->_cleanupStaleKids();

		while (my @ready = $selector->can_read()) {
			#$self->_cleanupStaleKids();

			foreach my $fh (@ready) {
				# accept client's socket
				my $client = $fh->accept();
			
				# process accepted socket...
				$self->_processConnection($client);
			}
			#$self->_cleanupStaleKids();
		}
	}
	
	$self->log_debug("No more listening sockets, stopping accept loop.");
	return 1;
}

sub _processConnection {
	my ($self, $client) = @_;
	return 0 unless (defined $client);

	# get client's address
	my $addr = $self->_getAddr($client);

	# too many clients?
	my $no_clients = $self->num_clients();
	my $max_clients = $self->max_clients();
	if ($no_clients >= $max_clients) {
		$self->log_warn(
			"Too many concurrent connections ($no_clients/$max_clients); Dropping client $addr"
		);
		$self->_socketCleanup($client);
		return 0;
	}

	$self->log_debug("Connection from " . $addr);
			
	# try to create new process in which we will process
	# new connection
	my $pid = fork();

	unless (defined $pid) {
		$self->log_error("Unable to fork: $!");
		$self->_socketCleanup($client);
		return 0;
	}
			
	# child?
	if ($pid == 0) {
		# close parent's listeners
		$self->_listenersDestroy();
		
		# reset signal handlers...
		$self->_sighDestroy();
		
		# get connection class name...
		my $class = $self->conn_class();
		unless (defined $class && length($class) > 0) {
			$self->fatal("No connection class is set; dropping connection.");
			$self->_socketCleanup($client, 1);
			return 0;
		}
		# load class
		eval "require $class";
		if ($@) {
			$self->fatal("Error loading required runtime class $class: $@");
			$self->_socketCleanup($client, 1);
			return 0;
		}

		# create connection object...
		my $conn = $class->new();
		if (! defined $class || ! blessed($conn)) {
			$self->fatal("Class $class constructor returned undefined value; dropping connection.");
			$self->_socketCleanup($client, 1);
			return 0;
		}
		elsif (! $conn->can('process')) {
			$self->fatal("Class $class doesn't implement method process(\$socket); dropping connection.");
			$self->_socketCleanup($client, 1);
			return 0;
		}

		# now process the goddamn connection...
		my $r = 0;
		eval { $r = $conn->process($client) };
		if ($@) {
			$self->log_error("Exception while processing connection: $@");
		}
		unless ($r) {
			$self->log_error($conn->error());
		}

		# cleanup socket and exit...
		$self->_socketCleanup($client, 1);
			
	# this is parent
	} else {
		# register client connection
		$self->{_clients}->{$pid} = time();

		# we don't need client's socket anymore
		close($client);
	}

	return 1;
}

sub _socketCleanup {
	my ($self, $socket, $exit) = @_;
	$exit = 0 unless (defined $exit);
	CORE::shutdown($socket, 2) if ($socket->connected());
	close($socket);
	exit 0 if ($exit);
}

sub _pidWrite {
	my ($self, $file, $pid) = @_;
	return 1 unless (defined $file && length($file) > 0);
	$pid = $$ unless (defined $pid);
	my $fd = IO::File->new($file, 'w');
	unless (defined $fd) {
		$self->error("Unable to open pid file $file for writing: $!");
		return 1;
	}
	
	print $fd $pid;
	close($fd);
	return 1;
}

sub _v6Addr {
	my ($self, $addr) = @_;
	return 0 unless (defined $addr && length($addr) > 0);
	return ($addr =~ m/:/) ? 1 : 0;
}

sub _cleanupStaleKids {
	my ($self) = @_;
	$self->log_info("_cleanupStaleKids(); startup.");
	my $t = time();
	my $exec_time_max = 10;

	# no child execution time limit?
	return 1 unless ($exec_time_max > 0);

	foreach my $pid (%{$self->{_clients}}) {
		my $time_started = $self->{_clients}->{$pid};
		next unless (kill(0, $pid));
		
		$self->log_info("started: $time_started; max: $exec_time_max, sum: ", ($time_started + $exec_time_max), " t: $t");
		
		# time to forcibly kill child?
		if (($time_started + $exec_time_max) <= $t) {
			$self->log_warn(
				"Child $pid exceeded connection maximum processing time of $exec_time_max " .
				"second(s). Destroying child."
			);
			unless (kill(9, $pid)) {
				$self->error("Error killing child $pid: $!");
			}
			
			# delete child
			# delete($self->{_clients}->{$pid});
		}
	}
}

1;