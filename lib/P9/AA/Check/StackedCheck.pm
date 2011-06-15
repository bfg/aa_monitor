package P9::AA::Check::StackedCheck;

use strict;
use warnings;

use Time::HiRes qw(time);
use P9::AA::CheckHarness;

use P9::AA::Constants;
use base 'P9::AA::Check';

# version MUST be set
our $VERSION = 0.10;

=head1 NAME

Embed and combine other check modules and perform complex checks.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Embed and combine other check modules and perform complex checks. WARNING: EXPERIMENTAL MODULE!"
	);

	# define additional configuration variables...
	$self->cfgParamAdd(
		'expression',
		undef,
		'Stacked check expression.',
		$self->validate_str(4 * 1024)
	);
	$self->cfgParamAdd(
		'check_definitions',
		{},
		'Check definition',
		\ &_validator,
	);
	
	# checks hash
	$self->{_checks} = {};

	# you can also remove any previously created
	# configuration parameter.
	# $self->cfgParamRemove('debug');
	
	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	$self->{_checks} = {};
	return CHECK_ERR unless ($self->_checkParams());
	
	# check results...
	my $cr = {};
	
	# perform all specified checks...
	foreach my $name (keys %{$self->{check_definitions}}) {
		my $def = $self->{check_definitions}->{$name};
		my $module = $def->{module};
		my $params = $def->{params};
		
		# create harness...
		my $h = P9::AA::CheckHarness->new();
		my $ts = time();
		
		# perform check
		my $res = $h->check($module, $params, $ts);
		
		# store stuff
		$cr->{$name} = $res;
	}
	
	# validate check results against check expression
	return ($self->_validateCheckResults($cr)) ? CHECK_OK : CHECK_ERR;
}

sub _validateCheckResults {
	my ($self, $cr) = @_;
	
	my $exp = $self->{expression};
	
	$exp =~ s/\s*([\w]+)\s*/ \$o->_perform(\'$1\', \$d) /g;
	my $code_str = 'sub { my $o = shift; my $d = shift; return(' . $exp . ') }';
	
	# compile code
	local $@;
	my $code = eval $code_str;
	if ($@) {
		$self->error("Error compiling check expression code: $@");
		return 0;
	}
	unless (defined $code && ref($code) eq 'CODE') {
		$self->error("Error compiling check expression code: eval returned undefined code reference.");
		return 0;
	}
	
	# run the code
	$self->bufApp("--- BEGIN STACKED CHECKS ---");
	local $@;
	my $res = $code->($self, $cr);
	if ($@) {
		$self->error("Error running check expression code: $@");
		return 0;
	}
	$self->bufApp("--- END STACKED CHECKS ---");
	
	unless ($res) {
		$self->error("Check expression code returned false value.");
	}
	return $res;
}

sub _perform {
	my ($self, $name, $cr) = @_;

	# get result
	my $c = $cr->{$name}->{data}->{check};
	my $res = $c->{result_code};
	$res = CHECK_ERR unless (defined $res);
	
	# convert to boolean value
	my $val = ($res == CHECK_OK || $res == CHECK_WARN) ? 1 : 0;
	
	# build buffer message
	my $buf = sprintf("CHECK %-30s: %d", $name, $val);
	$buf .= " [";
	$buf .= "success" if ($c->{success});
	if ($c->{warning}) {
		$buf .= "warning: $c->{warning_message}"
	}
	unless ($c->{success} || $c->{warning}) {
		$buf .= "error: $c->{error_message}";
	}
	$buf .= "]";
	$self->bufApp($buf);

	# should we print message buffer?
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN CHECK MESSAGES ---");
		$self->bufApp($c->{messages});
		$self->bufApp("--- END CHECK MESSAGES ---");
		$self->bufApp();
	}
	
	return $val;
}

sub toString {
	my ($self) = @_;
	no warnings;
	return "$self->{expression}";
}

sub _checkParams {
	my ($self) = @_;
	
	# check definitions
	unless (defined $self->{check_definitions} && ref($self->{check_definitions}) eq 'HASH') {
		$self->error("Undefined parameter check_definitions.");
		return 0;
	}
	unless (%{$self->{check_definitions}}) {
		$self->error("No check definitions were specified.");
		return 0;
	}
	my $err = "Invalid parameter check_definitions: ";
	foreach my $e (keys %{$self->{check_definitions}}) {
		unless (defined $e && length($e) > 0) {
			$self->error($err . "zero-length definition key name.");
			return 0;
		}
		my $def = $self->{check_definitions}->{$e};
		
		# get module and params...
		my $module = $def->{module};
		my $params = $def->{params};
		unless (defined $module && length $module > 0) {
			$self->error($err . "Check definition $e: No check module name.");
			return 0;
		}
		# params?
		$params = {} unless (defined $params && ref($params) eq 'HASH');
		$def->{params} = $params;
		
 	}
 	
 	# check expression
 	my $e = $self->{expression};
 	unless (defined $e && length $e > 0) {
 		$self->error("Undefined check expression.");
 		return 0;
 	}
 	
 	return 1;
}

# hash parameter validator
sub _validator {
	my ($cfg) = @_;
	
	my $ref = ref($cfg);
	
	# already a hash?
	if ($ref eq 'HASH') {
		return $cfg;
	}
	# string?
	elsif ($ref eq '') {
		use JSON;
		my $j = JSON->new();
		$j->utf8(1);
		$j->relaxed(1);
		
		# try to decode
		local $@;
		my $res = eval { $j->decode($cfg) };
		if ($@) {
			print STDERR "Error decoding configuration string to hash: $@\n";
		}
		return $res if defined $res;
	}

	return {};
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;
