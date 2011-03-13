package P9::AA::Config;

use strict;
use warnings;

use IO::File;

use FindBin;
use File::Spec;
use Cwd qw(realpath);

use P9::AA::Log;

use constant MAX_LINES => 500;

my $log = P9::AA::Log->new();
my @_cfg_files = (
	realpath(
		File::Spec->catfile(
			$FindBin::Bin,
			'..',
			'conf',
			'aa_monitor.conf'
		)
	),
	realpath(
		File::Spec->catfile(
			$FindBin::Bin,
			'..',
			'etc',
			'aa_monitor.conf'
		)
	),
	'/etc/aa_monitor/aa_monitor.conf',
	'/usr/local/etc/aa_monitor/aa_monitor.conf'
);

my $_obj = undef;

=head1 NAME

Simple configuration class.

=head1 DESCRIPTION

Configuration class.

=head1 CONSTRUCTOR

This class can be initialized as B<singleton> instance (default) or as a
normal new instance.

=head2 singleton

Returns singleton instance of L<P9::AA::Config>.

=head2 new

Alias method for L<P9::AA::Config#singleton> method.

=head2 construct

Returns new instance of  L<P9::AA::Config>.

=cut
sub construct {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	$self->_init();
	return $self;
}

sub singleton {
	unless (defined $_obj) {
		$_obj = __PACKAGE__->construct();
	}
	return $_obj;	
}

sub new { singleton(@_) }

sub _init {
	my ($self) = @_;
	$self->{_error} = '';
	$self->{_last} = '';
	$self->reset();
	return 1;
}

=head1 METHODS

=head2 error

Returns last error message as string.

=cut
sub error {
	return shift->{_error};
}

=head2 reset

 $cfg->reset();

Resets configuration to default values. Always returns 1.

=cut
sub reset {
	my ($self) = @_;

	$self->{_cfg} = {
		enable_doc => 1,
		
		# daemon options
		listen_addr => '*',
		listen_port => 1552,
		pid_file => '/tmp/aa_monitor.pid',
		user => undef,
		group => undef,
		chroot => undef,
		modules_enabled => [],
		modules_disabled => [],
		daemon => 1,
		daemon_impl => 'basic',
		log_level => 'info',
		max_clients => 50,
		
		# Protocol selection
		protocol => 'http',

		# SSL/TLS stuff
		ssl_enabled => 0,
		ssl_cert_file => undef,
		ssl_key_file => undef,
		ssl_ca_file => undef,
		ssl_ca_path => undef,
		ssl_verify_mode => 0,
		ssl_crl_file => undef,
	};

	return 1;
}

=head2 load

Tries to load configuration. Will try to load any first found file from predefined configuration
file locations if configuration file argument is omitted.

Returns 1 on success, otherwise.

=cut
sub load {
	my ($self, $file) = @_;
	if (defined $file && length($file)) {
		return $self->loadConfigFile($file);
	}
	
	foreach my $f ($self->configSearchList()) {
		return 1 if ($self->loadConfigFile($f));
	}
	
	return 0;
}

=head2 configSearchList

Returns configuration file search list.

 print "Will try to load the first file"
 map { print "\t" . $_ . "\n" } $cfg->configSearchList();

=cut
sub configSearchList {
	return @_cfg_files;
}

=head2 toString

Returns current configuration as string value, which can be used to
write configuration file.

 my $fh = IO::File->new('configuration.txt', 'w');
 print $fh $cfg->toString();

=cut
sub toString {
	my ($self) = @_;

	no warnings;
	my $str = <<EOF
#
# aa_monitor configuration
#

# enable documentation rendering?
enable_doc = $self->{_cfg}->{enable_doc}

# Comma separated list of listening ports or
# UNIX socket paths
# Syntax: *:<port>, [<addr>]:<port>, <addr>:<port>, /path/to/listen.sock
listen_addr = $self->{_cfg}->{listen_addr}

# Listening port. Ignored if listening
# address is unix socket path.
listen_port = $self->{_cfg}->{listeni_port}

# Pid file path if running as daemon
pid_file = $self->{_cfg}->{pid_file}

# Run as specified user (username or uid)
user = $self->{_cfg}->{user}

# Run as specified group (groupname or gid)
group = $self->{_cfg}->{group}

# Chroot to specified directory
chroot = $self->{_cfg}->{chroot}

# Run in background/daemonize (boolean)
daemon = $self->{_cfg}->{daemon}

# log level
log_level = $self->{_cfg}->{log_level}

# DAEMON OPTIONS...

# daemon implementation
# Possible values: basic, anyevent
#
# WARNING: anyevent implementation is highly
#          experimental and currently supports
#          only plain http protocol!
daemon_impl = $self->{_cfg}->{daemon_impl}

# maximum concurrent clients
max_clients = $self->{_cfg}->{max_clients}
		
# Protocol selection
# Possible values: http, https, cgi, fastcgi
protocol = $self->{_cfg}->{protocol}

# SSL/TLS stuff

# Enable SSL on listening socket (boolean)?
# NOTE: This option could be automatically changed
# depending to selected protocol
ssl_enabled = $self->{_cfg}->{ssl_enabled}

# See perldoc IO::Socket::SSL
# for details of the following
# configuration parameters.
ssl_cert_file = $self->{_cfg}->{ssl_cert_file}
ssl_key_file = $self->{_cfg}->{ssl_key_file}
ssl_ca_file = $self->{_cfg}->{ssl_ca_file}
ssl_ca_path = $self->{_cfg}->{ssl_ca_path}
ssl_verify_mode = $self->{_cfg}->{ssl_verify_mode}
ssl_crl_file = $self->{_cfg}->{ssl_crl_file}

#
# Comma separated list of enabled check
# modules
#
EOF
;
	$str .= 'modules_enabled = ' . join(', ', @{$self->{_cfg}->{modules_enabled}}) . "\n\n";

	$str .= <<EOF
#
# Comma separated list of disabled check
# modules
# 
EOF
;
	$str .= 'modules_disabled = ' . join(', ', @{$self->{_cfg}->{modules_disabled}}) . "\n\n";

	$str .= <<EOF
# EOF
EOF
;
	return $str;	
}

=head2 loadConfigFile

Loads specific configuration file. Returns 1 on success, otherwise 0.

 my $r = $cfg->loadConfigFile($file);
 unless ($r) {
 	print "Loading of $file failed: ", $cfg->error(), "\n";
 }

=cut
sub loadConfigFile {
	my ($self, $file, $max_lines) = @_;
	unless (defined $file && length($file)) {
		$self->{_error} = "Undefined configuration file.";
		return 0;
	}
	$max_lines = MAX_LINES unless (defined $max_lines && $max_lines > 0);
	my $fd = IO::File->new($file, 'r');
	unless (defined $fd) {
		$self->{_error} = "Unable to open configuration file $file: $!";
		return 0;
	}
	
	my $i = 0;
	my $num = 0;
	while ($i < $max_lines && defined(my $line = <$fd>)) {
		$i++;
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length($line) > 0);
		next if ($line =~ m/^[#;]+/);
		
		my ($key, $value) = split(/\s+[=:]+\s+/, $line, 2);
		next unless (defined $key && defined $value);

		# strip key
		$key =~ s/^\s+//g;
		$key =~ s/\s+$//g;

		# strip value
		$value =~ s/^['"\s]+//g;
		$value =~ s/['"\s]+$//g;

		next unless (length($key) > 0);
		next unless (length($value) > 0);
		
		# boolean stuff?
		if ($value =~ m/^t(?:rue)?$/i || $value =~ m/^y(?:es)?$/) {
			$value = 1;
		}
		elsif ($value =~ m/^f(?:alse)?$/i || $value =~ m/^n(?:o)?$/i) {
			$value = 0;
		}
		elsif ($value =~ m/^(?:undef|null|nil)$/) {
			$value = undef;
		}
		
		# set configuration parameter
		if ($self->set($key, $value)) {
			$num++;
		}
	}
	if ($num > 0) {
		$log->debug(
			"Succesfully parsed configuration file $file: read $i lines, " .
			"parsed $num configuration keys."
		);
	} else {
		$log->warn(
			"Succesfully read configuration file $file: read $i lines, " .
			"but no configuration keys were parsed."
		);
	}
	
	# save last loaded filename
	$self->{_last} = $file;

	return 1;
}

=head2 lastLoadedConfigFile

Returns last configuration filename (if any) that was successfully loaded.

 print "last loaded config: ", $cfg->lastLoadedConfigFile(), "\n";

=cut
sub lastLoadedConfigFile {
	my ($self) = @_;
	return $self->{_last};
}

=head2 set

Sets configuration property.

 $cfg->set($key, $value);

=cut
sub set {
	my ($self, $name, $value) = @_;
	if (exists($self->{_cfg}->{$name})) {
		my $r = ref($self->{_cfg}->{$name});

		if ($r eq 'ARRAY') {
			@{$self->{_cfg}->{$name}} = ();
			map {
				if (defined $_ && length($_) > 0) {
					push(@{$self->{_cfg}->{$name}}, $_)
				}
			} split(/\s*[,;|]+\s*/, $value);
		}
		else {
			$self->{_cfg}->{$name} = $value;
		}
		
		return 1;
	}
	
	$self->{_error} = "Invalid config parameter name.";
	return 0;
}

=head2 get

Returns configuration property value. Returns value on success, otherwise undef.

 print "Listening address: ", $cfg->get('listen_addr'), "\n";

=cut
sub get {
	my ($self, $name) = @_;
	if (exists($self->{_cfg}->{$name})) {
		return $self->{_cfg}->{$name}
	}
	return undef;
}

=head2 list

Returns list of defined configuration properties.

 print "Defined configuration properties: ", join(", ", $cfg->list()), "\n";

=cut
sub list {
	my ($self) = @_;
	return sort keys %{$self->{_cfg}};
}

=head1 AUTHOR

Brane F. Gracnar

=cut

1;

# EOF