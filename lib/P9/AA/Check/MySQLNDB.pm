package P9::AA::Check::MySQLNDB;

use strict;
use warnings;

use File::Spec;
use File::Glob qw(:glob);

use P9::AA::Constants;
use base 'P9::AA::Check';

our $VERSION = 0.11;

=head1 NAME

MySQL NDB cluster checking module

=head1 METHODS

This module inherits all methods from L<P9::AA::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks state of MySQL NDB cluster."
	);
	
	$self->cfgParamAdd(
		'ndb_host',
		'localhost',
		'NDB hostname',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'ndb_port',
		1186,
		'NDB listening port.',
		$self->validate_int(1, 65535),
	);
	
	return 1;
}

sub check {
	my ($self) = @_;
	
	my $run_str = 'ndb_mgm -t 1' . ' -c "' . $self->{ndb_host} . ":" . $self->{ndb_port} . '"';
	$run_str .= ' -e SHOW';
	
	my $pfd = undef;
	
	if ($self->{debug}) {
		$self->bufApp("DEBUG: Running command: $run_str");
	}
	
	# set timeout expired signal handler...
	local $SIG{ALRM} = sub {
		die "Command timeout exceeded.\n";
	};
	
	# set command timeout...
	alarm(3);	
	my ($out, $exit) = $self->qx2($run_str);
	alarm(0);
	unless (defined $out) {
		return CHECK_ERR;
	}
	
	my $ndbd_ndb_nodes = 0;
	my $ndbd_ndb_in = 0;
	my $ndb_mgmd_nodes = 0;
	my $ndb_mgmd_in = 0;
	my $mysql_api_nodes = 0;
	my $mysql_api_in = 0;
	
	# check output
	my $i = 0;
	my $r = CHECK_OK;
	my $err = "";
	foreach my $line (@{$out}) {
		$i++;
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length($line) > 0);

		if ($self->{debug}) {
			$self->bufApp("DEBUG COMMAND OUTPUT: $line");
		}
		
		if ($line =~ m/Unable to connect/i) {
			$err .= "Unable to connect to mgmd: $line; ";
			$r = 0;
			next;
		}
		
		# [ndbd(NDB)]     2 node(s)
		if ($line =~ m/^\[ndbd\(NDB\)\]\s+(\d+)\s+node/) {
			$ndbd_ndb_nodes = $1;
			$ndbd_ndb_in = 1;
			$ndb_mgmd_in = 0;
			$mysql_api_in = 0;
		}
		# [ndb_mgmd(MGM)] 2 node(s)
		elsif ($line =~ m/^\[ndb_mgmd\(MGM\)\]\s+(\d+)\s+node/) {
			$ndb_mgmd_nodes = $1;
			$ndbd_ndb_in = 0;
			$ndb_mgmd_in = 1;
			$mysql_api_in = 0;
		}
		# [mysqld(API)]   2 node(s)
		elsif ($line =~ m/^\[mysqld\(API\)\]\s+(\d+)\s+node/) {
			$mysql_api_nodes = $1;
			$ndbd_ndb_in = 0;
			$ndb_mgmd_in = 0;
			$mysql_api_in = 1;
		}
		else {
		# parse section data...

#~~~OK~~~
#[ndbd(NDB)]	2 node(s)
#id=3	@10.14.1.40  (Version: 5.0.45, Nodegroup: 0, Master)
#id=4	@10.14.1.41  (Version: 5.0.45, Nodegroup: 0) 
#[ndb_mgmd(MGM)]	2 node(s)
#id=1	@10.14.0.69  (Version: 5.0.51)
#id=2	@10.14.1.69  (Version: 5.0.51) 
#[mysqld(API)]	2 node(s)
#id=5	@10.14.1.41  (Version: 5.0.45)
#id=6	@10.14.1.40  (Version: 5.0.45)
#~~~FAILED~~~
#Connected to Management Server at: localhost:1186
#Cluster Configuration
#---------------------
#[ndbd(NDB)]     2 node(s)
#id=3    @10.14.1.40  (Version: 5.0.45, starting, Nodegroup: 0, Master)
#id=4    @10.14.1.41  (Version: 5.0.45, starting, Nodegroup: 0)
#
#[ndb_mgmd(MGM)] 2 node(s)
#id=1   (Version: 5.0.51)
#id=2 (not connected, accepting connect from 10.14.1.69)
#
#[mysqld(API)]   2 node(s)
#id=5 (not connected, accepting connect from any host)
#id=6 (not connected, accepting connect from any host)

			if ($line =~ m/^id=(\d+)\s+\@([\d\.]+)\s+\(([^\)]+)\)/) {
				my $id = $1;
				my $node_addr = $2;
				my $misc = $3;
				
				# running, but not started?
				if ($misc =~ m/,\s*starting\s*,/) {
					$err .= "Service is running, but is not yet started: $line; ";
					$r = CHECK_ERR;
				}
			} else {
				if ($ndbd_ndb_in) {
					$err .= "ndbd_ndb err: $line; ";
					$r = CHECK_ERR;
				}
				elsif ($ndb_mgmd_in) {
					$err .= "ndbd_mgmd err: $line; ";
					$r = CHECK_ERR;
				}
				elsif ($mysql_api_in) {
					$err .= "mysql_api err: $line;";
					$r = CHECK_ERR;
				}
			}
		}
	}
	
	unless ($r == CHECK_OK) {
		$err =~ s/\s+$//g;
		return $self->error($err);
	}

	return $r;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;