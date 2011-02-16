#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
use Getopt::Long;
use Cwd qw(abs_path);
use File::Basename;

# determine libdir and put it into @INC
use lib (
	'/usr/lib/aa_monitor',
	'/usr/local/lib/aa_monitor',
	abs_path($FindBin::RealBin .  "/../" . "lib"),
	abs_path($FindBin::RealBin .  "/../" . "ext"),
);

use P9::AA::Log;
use P9::AA::Config;
use P9::AA::Constants qw(:all);

#############################################################
#                    Runtime variables                      #
#############################################################
my $MYNAME= basename($0);

our $VERSION = '1.0.0_2';

my $log = P9::AA::Log->new();
my $cfg = P9::AA::Config->new();

my $cmd_line = 0;
my $nagios = 0;

#############################################################
#                        FUNCTIONS                          #
#############################################################

sub print_var {
	my ($val, $bool) = @_;
	$bool = 0 unless (defined $bool);
	my $str = "";
	
	if ($bool) {
		$str = ($val) ? "yes" : "no"; 	
	} else {
		if (defined $val) {
			$str = '"' . $val . '"';
		} else {
			$str = "undefined";
		}
	}

	return $str;
}

sub name {
	return $MYNAME;
}

sub config_load {
	my ($file) = @_;
	unless ($cfg->loadConfigFile($file)) {
		print STDERR "FATAL: ", $cfg->error(), "\n";
		exit 1;
	}
	return 1;
}

sub invoked_as_cgi {
	return (
		exists($ENV{GATEWAY_INTERFACE}) &&
		$ENV{GATEWAY_INTERFACE} =~ m/^CGI\/\d+/i &&
		exists($ENV{REMOTE_ADDR}) &&
		exists($ENV{REQUEST_METHOD})
	) ? 1 : 0;
}

sub get_connection {
	# load required modules
	local $@;
	eval "use " . CLASS_CONNECTION . '; 1;';
	if ($@) {
		$log->error($@);
		print STDERR "FATAL: $@\n";
		exit 1;
	}
	
	# create "connection"
	return CLASS_CONNECTION->new();
}

sub process_cgi {
	# This is essential!
	$cfg->set('protocol', 'cgi');

	# get "connection"
	my $c = get_connection();
	
	# process it...
	my $r = $c->process(\*STDIN, \*STDOUT);
	
	# this is it :)
	exit(! $r);
}

sub process_cmdl {
	# force protocol
	$cfg->set('protocol', ($nagios) ? 'nagios' : 'cmdl');

	# get "connection"
	my $c = get_connection();
	
	# process it...
	my $r = $c->process(\ @_);
	
	# this is it :)
	exit(! $r);
}

sub process_daemon {
	my $impl = $cfg->get('daemon_impl');
	$impl = 'BASIC' unless (defined $impl && length($impl));
	$impl = uc($impl);
	
	# try to load daemon class
	local $@;
	eval "use " . CLASS_DAEMON . '; 1';
	if ($@) {
		print STDERR "Unable to load daemon class: $@";
		exit 1;
	}

	# create server object...
	my $server = CLASS_DAEMON->factory($impl);
	unless (defined $server) {
		print STDERR 
			"ERROR creating server: " .
			CLASS_DAEMON->error(). "\n";
		return 0; 
	}
	
	# set connection class
	$server->conn_class(CLASS_CONNECTION);

	# start the goddamn server
	my $r = $server->run($cfg);
	unless ($r) {
		$log->error($server->error());
		print STDERR "ERROR: ", $server->error(), "\n";
	}

	return $r;
}

sub printhelp {
	print <<EOF
Usage: $MYNAME [OPTIONS]

This is aa_monitor, interface to modular service health checking
architecture. This script can be used as:

 * command line client
 * nagios external check
 * CGI script
 * standalone HTTP(s) server
 * standalone FCGI server

EOF
;
	print "OPTIONS:\n";
	print "  -c      --config=FILE    Loads specified configuration file\n";
	print "          --default-config Prints default configuration file\n";
	print "\n";
	print "CONFIGURATION FILE LOCATIONS:\n";
	print "\n";
	foreach ($cfg->configSearchList()) {
		print "       $_\n" if (defined $_);
	}
	print "\n";
	print "COMMAND LINE OPTIONS:\n";
	print "  -e      --cmdline        Run as command line client\n";
	print "  -N      --nagios         Run as nagios external check\n";
	print "\n";
	print "DAEMON OPTIONS:\n";
	print "  -p      --port           HTTP server listening port (Default: ", print_var($cfg->get('listen_port')), ")\n";
	print "  -H      --addr           Comma separated list of HTTP server bind addresses and unix socket paths\n";
	print "                           (Default: ", print_var($cfg->get('listen_addr')), ")\n";
	print "  -X      --protocol=PROTO Specifies daemon protocol (Default: ", print_var($cfg->get('protocol')), ")\n";
	print "  -P      --pid-file       Daemon pid file (Default: ", print_var($cfg->get('pid_file')), ")\n";
	print "\n";
	print "          --daemon         Run as daemon (Default: ", print_var($cfg->get('daemon'), 1), ")\n";
	print "          --no-daemon      Don't run as daemon\n";
	print "\n";
	print "          --daemon-impl    Specifies daemon implementation (Default: ", print_var($cfg->get('daemon_impl')), ")\n";
	print "  -u      --user           Run as specified user. Requires root startup privileges. (Default: ", print_var($cfg->get('user')), ")\n";
	print "  -g      --group          Run under specified gid. Requires root startup privileges (Default: ", print_var($cfg->get('group')), ")\n";
	print "          --debug          Enables debugging\n";
	print "\n";
	print "  -A      --enabled-mods   Comma separated list of allowed ping modules\n";
	print "  -D      --disabled-mods  Comma separated list of disabled ping modules\n";
	print "\n";
	print "OTHER OPTIONS:\n";
	print "  -l      --list-modules   Prints out list of available ping modules.\n";
	print "          --doc            List documentation.\n";
	print "  -V      --version        Print script version\n";
	print "  -h      --help           This help message\n";
}

#############################################################
#                          MAIN                             #
#############################################################

# try to load configuration
$cfg->load();

# do we have AA_MONITOR_CONFIG env variable?
if (exists($ENV{AA_MONITOR_CONFIG}) && length($ENV{AA_MONITOR_CONFIG})) {
	config_load($ENV{AA_MONITOR_CONFIG});
}

# there is no point of parsing command line
# if we were invoked as CGI script...
if (invoked_as_cgi()) {
	process_cgi();
	exit 0;
}

# parse command line
Getopt::Long::Configure('bundling', 'gnu_compat');
my $r = GetOptions(
	'c|config=s' => sub { config_load($_[1]) },
	'default-config' => sub {
		print $cfg->toString();
		exit 0;
	},
	'e|cmdline' => \ $cmd_line,
	'N|nagios' => sub { $cmd_line = 1; $nagios = 1 },
	'p|port=i' => sub { $cfg->set('listen_port', $_[1]) },
	'H|addr=s' => sub { $cfg->set('listen_addr', $_[1]) },
	'X|protocol=s' => sub { $cfg->set('protocol', $_[1]) },
	'P|pid-file=s' => sub { $cfg->set('pid_file', $_[1]) },
	'daemon!' => sub { $cfg->set('daemon', $_[1]) },
	'daemon-impl=s' => sub { $cfg->set('daemon_impl', $_[1]) },
	'u|user=s' => sub { $cfg->set('user', $_[1]) },
	'g|group=s' => sub { $cfg->set('group', $_[1]) },
	'debug!' => sub { $cfg->set('log_level', 'debug') },
	'A|allowed-mods=s' => sub { $cfg->set('modules_enabled', $_[1]) },
	'D|disabled-mods=s' => sub { $cfg->set('modules_disabled', $_[1]) },
	'l|list-modules' => sub {
		eval {
			my $class = CLASS_CHECK;
			eval "use $class; 1";
			print join(" ", CLASS_CHECK->getDrivers()), "\n";
		};
		if ($@) { die $@; } 
		exit 0;
	},
	'doc:s' => sub {
		my $doc = $_[1];
		$doc = 'Noviforum::Adminalert' unless (defined $doc && length $doc);
		$ENV{PERL5LIB} = join(':', @INC);
		exec('perldoc', $doc);
	},
	'V|version' => sub {
		printf("%s %s\n", $MYNAME, $VERSION);
		exit 0;
	},
	'h|help' => sub {
		printhelp();
		exit 0;
	}
);

unless ($r) {
	print STDERR "Invalid command line options. Run $MYNAME --help for help.\n";
	exit 1;
}

# assign log level
$log->level($cfg->get('log_level'));

# command line client or daemon process?
$r = ($cmd_line) ? process_cmdl(@ARGV) : process_daemon();
exit(! $r);

# EOF
