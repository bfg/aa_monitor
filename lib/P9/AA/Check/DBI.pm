package P9::AA::Check::DBI;

use strict;
use warnings;

use DBI;
use Scalar::Util qw(refaddr);

use P9::AA::Constants;
use base 'P9::AA::Check';

our $VERSION = 0.11;

=head1 NAME

=head1 METHODS

This module inherits all methods from L<P9::AA::Check>.

=cut
# add some configuration vars
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Check database health."
	);
	
	$self->cfgParamAdd(
		'dsn',
		'DBI:mysql:database=some_database;host=localhost;port=3306',
		'DBI Data Source Name Address. See perldoc DBI for details',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'username',
		undef,
		'Database username.',
		$self->validate_str(100),
	);
	$self->cfgParamAdd(
		'password',
		undef,
		'Database password.',
		$self->validate_str(100),
	);
	$self->cfgParamAdd(
		'query',
		undef,
		'SQL query to execute. If query is not defined check will succeed with successfull connetion to database.',
		$self->validate_str(4 * 1024)
	);

	# this method MUST return 1!
	return 1;
}

sub check {
	my ($self) = @_;

	# try to connect...
	my $db = $self->dbiConnect(
		$self->{dsn},
		$self->{username},
		$self->{password}
	);
	return CHECK_ERR unless ($db);

	return CHECK_OK unless (defined $self->{query} && length($self->{query}) > 0);
	
	# execute query
	my $r = $self->dbiQuery($db, $self->{query});
	return CHECK_ERR unless ($r);
	
	# on successfull ping, we return 1, otherwise 0...
	return CHECK_OK;
}

sub toString {
	my $self = shift;
	no warnings;
	return $self->{username} . '@' . $self->{dsn};
}

=head2 dbiConnect ($dsn, $user, $pass [, $opt = {}])

 my $dbh = $self->dbiConnect(
 	'DBI:mysql:database=some_db;host=host.example.com;port=3306',
 	'username',
 	's3cret0',
 );
 unless (defined $dbh) {
 	die "Connect failed: ", $self->error();
 }

Connects to database. Returns initialized database handle object on success, otherwise undef.

=cut
sub dbiConnect {
	my ($self, $dsn, $user, $pass, $opt) = @_;
	
	# \; => ;
	$dsn =~ s/\\;/;/g;

	unless (defined $opt && ref($opt) eq 'HASH') {
		$opt = {
			RaiseError => 0,
			PrintError => 0,
		}
	}
	
	# connect
	$self->bufApp("Connecting to DSN '$dsn' using username '$user'.") if ($self->{debug});
	my $dbh = DBI->connect($dsn, $user, $pass, $opt);
	unless (defined $dbh) {
		$self->error("Unable to connect to DSN '$dsn': " . DBI->errstr());
		return undef;
	}
	my $id = refaddr($dbh);
	$self->bufApp("  Successfully created connection id $id") if ($self->{debug});
	
	return $dbh;
}

=head2 dbiQuery ($dbh, $sql [ @prepared_statement_binding_values])

 my $r = $self->dbiQuery(
 	$dbh,
 	'SELECT a,b FROM table WHERE id = ? AND c = ?',
 	10,
 	'blahblah'
 );

Compiles SQL $sql to prepared statement using database handle $dbh
and executes it with optional prepared statement binding values.

Returns initialized prepared statement object on success, otherwise undef.

=cut
sub dbiQuery {
	my $self = shift;
	my $db = shift;
	my $sql = shift;
	
	my $db_id = refaddr($db);
	
	# prepare statement...
	$self->bufApp("[$db_id] Preparing SQL: $sql") if ($self->{debug});
	my $st = $db->prepare($sql);
	unless (defined $st) {
		$self->error("Error preparing SQL on connection $db_id: " . $db->errstr());
		return undef;
	}
	
	# now try to execute the query...
	$self->bufApp("  Executing SQL with bound values: ", join(", ", @_)) if ($self->{debug});
	my $r = $st->execute(@_);
	unless (defined $r) {
		$self->error("Error executing SQL on connection $db_id: " . $db->errstr());
		return undef;
	}
	
	if ($self->{debug}) {
		$self->bufApp("  Query returned " . $st->rows() . " row(s).") if ($self->{debug});
	}
	
	return $st;
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<DBI>
L<P9::AA::Check>

=cut

1;