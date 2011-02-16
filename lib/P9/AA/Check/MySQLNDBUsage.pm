package P9::AA::Check::MySQLNDBUsage;

use strict;
use warnings;

use IPC::Open3;

use P9::AA::Constants;
use base 'P9::AA::Check::MySQLNDB';

use constant MAX_LINES => 4 * 1024;

our $VERSION = 0.03;

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks MySQL NDB cluster usage."
	);

	$self->cfgParamAdd(
		'ndb_index_threshold',
		75,
		'NDB index usage threshold in %.',
		$self->validate_int(1, 99),
	);
	$self->cfgParamAdd(
		'ndb_data_threshold',
		75,
		'NDB data usage threshold in %.',
		$self->validate_int(1, 99),
	);
	
	return 1;
}

sub check {
	my ($self) = @_;
	
	my $run_str = 'ndb_mgm -t 1' . ' -c "' . $self->{ndb_host} . ":" . $self->{ndb_port} . '"';
	
	if ($self->{debug}) {
		$self->bufApp("DEBUG: Running command: $run_str");
	}
	
	# instal pipe signal handler...
	local $SIG{PIPE} = sub {
		die "Received SIGPIPE! This should not happen!\n";
	};
	
	# set timeout expired signal handler...
	local $SIG{ALRM} = sub {
		die "Command timeout exceeded.\n";
	};
	
	# set command timeout...
	alarm(3);

	my ($stdin, $stdout, $stderr);
	my $pid = open3($stdin, $stdout, $stderr, $run_str);
	unless ($pid) {
		return $self->error("Unable to exec $!");
	}
	
	# send command
	print $stdin "ALL REPORT MemoryUsage\nQUIT\n"; 

	# read pipe
	my $i = 0;
	my $err = "";
	my $r = CHECK_OK;
	while (($i < MAX_LINES) && defined (my $line = <$stdout>)) {
		$i++;
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length($line) > 0);

		if ($self->{debug}) {
			$self->bufApp("DEBUG COMMAND OUTPUT: $line");
		}
		
		if ($line =~ m/Unable to connect/i) {
			$err .= "Unable to connect to mgmd: $line; ";
			$r = CHECK_ERR;
			next;
		}

		# parse section data...
=pod
~~~OK~~~
Sending dump signal with data:
0x000003e8 Sending dump signal with data:
0x000003e8 
ndb_mgm> Node 3: Data usage is 14%(14030 32K pages of total 98304)
Node 3: Index usage is 1%(4561 8K pages of total 393248)
Node 4: Data usage is 14%(14023 32K pages of total 98304)
Node 4: Index usage is 1%(4562 8K pages of total 393248)
~~~FAILED~~~
=cut

		
		# check data usage
		if ($line =~ m/^Node (\d+): Data usage is (\d+)%\((.*)\)$/) {
			my $id = $1;
			my $usage = $2;
			my $usage_long = $3;
			
			if ($usage >= $self->{ndb_data_threshold}) {
				$self->bufApp("ERROR: NDB node_id: $id, database memory usage over limit: $usage% ($usage_long), threshold is set to $self->{ndb_data_threshold}%!");
				$err .= "Node $id data mem over limit: $usage%; ";
				$r = CHECK_ERR;
			}
			else {
				$self->bufApp("NDB node_id: $id, data usage OK: $usage% ($usage_long)");
			}
		}
		# check index usage
		elsif ($line =~ m/^Node (\d+): Index usage is (\d+)%\((.*)\)$/) {
			my $id = $1;
			my $usage = $2;
			my $usage_long = $3;
			
			if ($usage >= $self->{ndb_index_threshold}) {
				$self->bufApp("ERROR: NDB node_id: $id, index memory usage over limit: $usage% ($usage_long), threshold is set to $self->{ndb_index_threshold}%!");
				$err .= "Node $id index mem over limit: $usage%; ";
				$r = CHECK_ERR;
			}
			else {
				$self->bufApp("NDB node_id: $id, index usage OK: $usage% ($usage_long)");
			}
		}
		else {
			if ($self->{debug}) {
				$self->bufApp("Cannot parse line: $line");
			}
		}
	}

	# close pipe
	unless (close($stdout)) {
		$self->bufApp("WARNING: Unable to properly close pipe filedescriptor: $!");
	}
	
	unless ($r == CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}

	return $r;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Uros Golja

=cut
1;