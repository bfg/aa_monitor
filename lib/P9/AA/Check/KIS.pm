package P9::AA::Check::KIS;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::DBI';

our $VERSION = 0.03;

##################################################
#              PUBLIC  METHODS                   #
##################################################

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"This module checks if the KeywordInventoryServer import has been done at the start of each month."
	);
	
	$self->cfgParamAdd(
		'table',
		'NORMALIZED_TRAFFIC',
		'KeywordInventoryServer table name.',
		$self->validate_str(100),
	);
	$self->cfgParamAdd(
		'dom',
		10,
		'Day of month on which import should be done.',
		$self->validate_int(1, 31),
	);
	
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;

	# connect
	my $dbh = $self->dbiConnect($self->{dsn}, $self->{username}, $self->{password});
	return CHECK_ERR unless ($dbh);
	
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time());
	$year += 1900;
	my $query_year = $year;
	my $query_mon = $mon;
	if ($query_mon == 0) { 
		$query_mon = 12;
		$query_year--;
	}
	
	# execute SQL
	my $sql = "SELECT COUNT(*) from " . $self->{table} . ' WHERE MONTH LIKE ?';
	my $st = $self->dbiQuery(
		$dbh,
		$sql,
		$query_year . "-" . sprintf("%.2d", $query_mon) . '%'
	);
	return CHECK_OK unless (defined $st);

	my @result = $st->fetchrow_array();	
	my ($rows) = @result;
	if ($mday <= $self->{dom}) {
		$self->bufApp("We are the ${mday}" . $self->_ordinal($mday) . " of the current month. I am set to return success before the $self->{dom}" . $self->_ordinal($self->{dom}) . ". So, success!");
	}
	else {
		$self->bufApp("We are the ${mday}" . $self->_ordinal($mday) . " of the current month. I am set to check for results in the database after the $self->{dom}" . $self->_ordinal($self->{dom}) . ". So, here goes.");
		if ($rows > 0) {
			$self->bufApp("The table '$self->{table}' contains $rows rows.");
			return CHECK_OK;
		}
		else {
			$self->error("The table '$self->{table}' is empty! Not good.");
			return CHECK_ERR;
		}
	}

	return CHECK_OK;
}

sub toString {
	my $self = shift;
	no warnings;
	return $self->{username} . '@' . $self->{dsn} . '/' . $self->{dom};
}

sub _ordinal {
	my ($self, $num) = @_;
	return undef unless (defined($num) and $num =~ m/^\d+$/); 

	if ($num == 1) {
		return "st";
	}
	elsif ($num == 2) {
		return "nd";
	}
	elsif ($num == 3) {
		return "rd";
	}
	else {
		return "th";
	}
}

=head1 AUTHOR

Uros Golja

=cut

1;