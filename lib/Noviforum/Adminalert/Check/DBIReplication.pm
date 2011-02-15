package Noviforum::Adminalert::Check::DBIReplication;

use strict;
use warnings;

use Time::HiRes qw(sleep);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::DBI';

our $VERSION = 0.10;

=head1 NAME

DBI replication check module.

=head1 DESCRIPTION

This module checks if replication is alive and kicking between two database
servers.

=head1 METHODS

This module inherits all methods from L<Noviforum::Adminalert::Check::DBI>. 

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

	$self->cfgParamRemove('query');

	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	# try to connect...
	my $db_ref = $self->dbiConnect(
		$self->{dsn},
		$self->{username},
		$self->{password}
	);
	return CHECK_ERR unless ($db_ref);

	my $db_cmp = $self->dbiConnect(
		$self->{peer_dsn},
		$self->{username},
		$self->{password}
	);
	return CHECK_ERR unless ($db_cmp);
	
	# create table
	my $table_name = $self->_getTableName();
	
	my $result = CHECK_ERR;
	
	# create table on referential node...
	my $ct_st = $self->dbiQuery($db_ref, $self->_createTableSQL($table_name));
	unless (defined $ct_st) {
		$self->error("Error creating replication test table $table_name on referential node: " . $self->error());
		goto outta_check;
	}
	
	# value
	my $repl_val = time() . '_' . rand();
	
	# insert random value
	my $ins_st = $self->dbiQuery(
		$db_ref,
		'INSERT INTO ' . $table_name . 'VALUES (?)',
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
	$self->dbiQuery($db_ref, 'DROP TABLE ' . $table_name);
	$self->dbiQuery($db_cmp, 'DROP TABLE ' . $table_name) unless ($result == CHECK_OK);
	
	# close connections
	$db_ref->disconnect();
	$db_cmp->disconnect();

	return $result;
}

sub _getTableName {
	return "checkrepl_table_" . sprintf("%-6.6d", int(rand(10000000)));
}

sub _createTableSQL {
	my ($self, $table) = @_;
	$table = $self->_getTableName() unless (defined $table && length($table));
	return 'CREATE TABLE ' . $table . '(a VARCHAR(100))';
}


=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<DBI>
L<Noviforum::Adminalert::Check::DBI>

=cut

1;