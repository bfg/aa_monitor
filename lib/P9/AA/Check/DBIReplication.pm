package P9::AA::Check::DBIReplication;

use strict;
use warnings;

use Time::HiRes qw(sleep);

use P9::AA::Constants;
use base 'P9::AA::Check::DBI';

our $VERSION = 0.12;

=head1 NAME

DBI replication check module.

=head1 DESCRIPTION

This module checks if replication is alive and kicking between two database
servers.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::DBI>. 

=cut

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Checks database replication state."
	);
	
	$self->cfgParamAdd(
		'peer_dsn',
		'DBI:mysql:database=some_database;host=some-host.example.com;port=3306',
		'Replication peer DBI Data Source Name Address. See perldoc DBI for details',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'replication_delay_msec',
		100,
		'Maximum replication delay in milliseconds.',
		$self->validate_int(1),
	);
	$self->cfgParamAdd(
		'table_name',
		'replication_test',
		'Replication table name; table is automatically created.',
		$self->validate_str_trim(64),
	);
	$self->cfgParamAdd(
		'two_way',
		0,
		'Check replication operation both ways (dsn => peer_dsn AND peer_dsn => dsn)',
		$self->validate_bool(),
	);

	$self->cfgParamRemove('query');

	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	# one-way replication...
	$self->bufApp("Checking replication status A => B");
	my $r = $self->_replicationCheck($self->{dsn}, $self->{peer_dsn});
	if ($r != CHECK_OK) {
		my $e = $self->error();
		return $self->error("One-way (A => B) replication doesn't work: " . $e);
	}
	
	# two way replication check?
	if ($self->{two_way}) {
		$self->bufApp();
		$self->bufApp("Checking replication status B => A");
		$r = $self->_replicationCheck($self->{peer_dsn}, $self->{dsn});
		if ($r != CHECK_OK) {
			my $e = $self->error();
			$self->error("One-way (A => B) replication works, two-way (B => A) replication doesn't work: " . $e);			
		}
	}
	
	return $r;
}

sub _getTableName {
	my $self = shift;
	if (defined $self->{table_name} && length($self->{table_name}) > 0) {
		return $self->{table_name};
	} else {
		return "checkrepl_table_" . sprintf("%-6.6d", int(rand(10000000)));
	}
}

sub _createTableSQL {
	my ($self, $table) = @_;
	$table = $self->_getTableName() unless (defined $table && length($table));
	return 'CREATE TABLE ' . $table . ' (a VARCHAR(100), PRIMARY KEY(a))';
}

sub _replicationCheck {
	my ($self, $dsn_orig, $dsn_peer) = @_;

	# try to connect...
	my $db_ref = $self->dbiConnect(
		$dsn_orig,
		$self->{username},
		$self->{password}
	);
	return CHECK_ERR unless ($db_ref);

	my $db_cmp = $self->dbiConnect(
		$dsn_peer,
		$self->{username},
		$self->{password}
	);
	return CHECK_ERR unless ($db_cmp);
	
	# check result...
	my $result = CHECK_ERR;
	
	
	# ok, we're connected to both dbs...
	# let's check if table does exist on the first connection
	my $table_name = $self->_getTableName();
	
	my $st_exists = $self->dbiQuery(
		$db_ref,
		'SELECT COUNT(*) FROM ' . $table_name
	);
	unless ($st_exists) {
		# nope, it does not exist, create it...
		my $ct_st = $self->dbiQuery($db_ref, $self->_createTableSQL($table_name));
		unless (defined $ct_st) {
			$self->error("Error creating replication test table $table_name on referential node: " . $self->error());
			goto outta_check;
		}	
	}

	# compute value
	my $repl_val = time() . '_' . rand();
	
	# insert random value
	my $ins_st = $self->dbiQuery(
		$db_ref,
		'INSERT INTO ' . $table_name . ' VALUES (?)',
		$repl_val
	);
	unless (defined $ins_st) {
		$self->error(
			"Error inserting testing value to table $table_name on referential node: ".
			$self->error()
		);
		goto outta_check;
	}
	
	# wait
	my $sleep_int = $self->{replication_delay_msec} / 1000;
	sleep($sleep_int);
	
	# time to check if value was replicated to peer node.
	my $sel_st = $self->dbiQuery(
		$db_cmp,
		'SELECT a FROM ' . $table_name . ' WHERE a = ?',
		$repl_val
	);
	unless (defined $sel_st) {
		$self->error(
			"Error fetching replication test value from replication peer node: " .
			$self->error()
		);
		goto outta_check;
	}
	# we need at least one row in that table
	unless ($sel_st->rows() > 0) {
		$self->error("No rows were read from replication table on peer node. Looks like replication delay.");
		goto outta_check;
	}
	# check each and every row if it contains test value...
	while (defined (my $row = $sel_st->fetchrow_arrayref())) {
		if ($row->[0] eq $repl_val) {
			$result = CHECK_OK;
			last;
		}
	}

	outta_check:

	# drop table on referential node.
	$self->dbiQuery($db_ref, 'DELETE FROM TABLE ' . $table_name) if (defined $db_ref);
	$self->dbiQuery($db_cmp, 'DELETE FROM TABLE ' . $table_name) if (defined $db_cmp && $result != CHECK_OK);

	# destroy statements
	undef $ins_st;
	undef $sel_st;
	undef $st_exists;
	
	# close connections
	$db_ref->disconnect();
	$db_cmp->disconnect();

	return $result;
}


=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<DBI>
L<P9::AA::Check::DBI>

=cut

1;