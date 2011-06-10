package P9::AA::Check::Areca;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';
use Data::Dumper;

# version MUST be set
our $VERSION = 0.01;

=head1 NAME

Areca RAID adapter checking module.

=head1 METHODS

This class inherits all methods from L<P9::AA::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Checks Areca RAID array for consistency."
	);

	# Adapter index
	$self->cfgParamAdd(
		'adapter',
		1,	
		'Adapter index.',
		$self->validate_int(1, 8)
	);
	
	# define additional configuration variables...
	#$self->cfgParamAdd(
		#'param_bool',
		#0,
		#'This is boolean configuration parameter "bool" with default value of false.',
		#$self->validate_bool()
	#);
	#$self->cfgParamAdd(
		#'param_int',
		#12,
		#'This is integer configuration parameter with min value -1, max value 15 and default of 12.',
		#$self->validate_int(-1, 15)
	#);
	#$self->cfgParamAdd(
		#'param_float',
		#3.141592,
		#'This is float configuration parameter with min value 0.1, max value 6.2 and default value of pi. ' .
		#'Float precision is set to 2.',
		#$self->validate_float(0.1, 6.2, 2),
	#);
	#$self->cfgParamAdd(
		#'string',
		#undef,
		#'This is string configuration parameter with default value undef and with maximum string length of 30.',
		#$self->validate_str(30),
	#);
	#$self->cfgParamAdd(
		#'string_uppercase',
		#'blabla',
		#'This is string parameter which shoule always hold uppercased string.',
		#$self->validate_ucstr(30),
	#);
	#$self->cfgParamAdd(
		#'string_lowercase',
		#'BLAla',
		#'This is string parameter which should always hold lowercased string.',
		#$self->validate_lcstr(30),
	#);

	# you can also remove any previously created
	# configuration parameter.
	# $self->cfgParamRemove('debug');
	
	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;

	$self->bufApp(Dumper $self->getRAIDSetData($self->{adapter}));
	$self->bufApp(Dumper $self->getVolumeSetData($self->{adapter}));
	$self->bufApp(Dumper $self->getDiskData($self->{adapter}));
	
	return 1;
	#$self->getVolumeSetData($self->{adapter});
	#$self->getRAIDSetData($self->{adapter});

	## We can raise some messages ;)
	#$self->bufApp("Hello message buffer world from " . ref($self));		# what else?
	
	## get service state data
	#my $d = $self->getExampleData();
	#unless ($d) {
		#return $self->error("Unable to get data: " . $self->error());
	#}
	

	## success!
	#if ($d->{value} < 0.34) {
		## we will return success...
		#return $self->success();

		## Above is shortcut for:
		##
		## return CHECK_OK;
	#}
	## warning!
	#elsif ($d->{value} < 0.67) {
		## this is considered warning
		#return $self->warning(
			#"Random generator decided that this check " .
			#"should succeed with this WARNING message."
		#);

		## Above is shortcut for:
		##
		## $self->warning("warning message");
		## return CHECK_WARN;
	#}
	## epic fatal fail!
	#else {
		## this is considered warning
		#return $self->error(
			#"Random generator decided that this check " .
			#"should FAIL with this horrible ERROR message."
		#);
		
		## Above is shortcut for:
		##
		## $self->error("error message");
		## return CHECK_ERR;
	#}
}

# describes check, optional.
sub toString {
	my ($self) = @_;
	no warnings;

	my $str = $self->{string_uppercase} . '/' . $self->{param_bool} . '/' . $self->{param_int};	
	return $str
}

#sub getExampleData {
	#my ($self) = @_;

	## for demonstration purposes only
	## to demonstrate check delay.
	#use Time::HiRes qw(sleep);
	#my $delay = rand(0.35);
	#$self->bufApp("Random check delay: $delay second(s)");
	#sleep($delay);
	
	## simulate data retrieval failure
	#if (rand() > 0.8) {
		#$self->error("Data retrieval failed: BECAUSE IT FAILED.");
		#return undef;
	#}
	
	## simulate exception while data retrieval
	#if (rand() > 0.7) {
		#die "HORRIBLE exception occurred while retrieving data.";
	#}
	
	## result structure...
	#my $result = {
		#value => rand()
	#};
	
	#return $result;
#}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;
