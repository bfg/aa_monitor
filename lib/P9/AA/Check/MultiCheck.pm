package P9::AA::Check::MultiCheck;

use strict;
use warnings;

use Time::HiRes qw(time);
use P9::AA::CheckHarness;

use P9::AA::Constants qw(:all);
use base 'P9::AA::Check::StackedCheck';

# version MUST be set
our $VERSION = 0.10;

=head1 NAME

Embed and combine other check modules to perform multiple checks.

=head1 DESCRIPTION

=head1 SYSNOPSIS

See L<P9::Check::AA::StackedCheck/SYNOPSIS>

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Performs multiple checks and evaluates results."
	);

	# define additional configuration variables...	
	$self->cfgParamRemove('expression');
	$self->cfgParamRemove('use_cache');

	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	return CHECK_ERR unless ($self->_checkParams());
	
	# final result
	my $fr = CHECK_OK;
	my $err = '';
	my $warn = '';

	# time to run some checks, bitchez...
	foreach my $name (keys %{$self->{check_definitions}}) {	  
	  my $r = $self->_performSubCheck($name);
	  unless (defined $r) {
	    return $self->error("Error running check $name: " . $self->error());
	  }
	  
	  # I FUCKING HATE WHEN I DISCOVER MY OWN
	  # BAD DESIGN SEVERAL YEARS LATER
	  # check result should be bitmask value
	  # FUUUUUCK!!!!!!!!!!
	  if ($r != CHECK_OK) {
	    if ($r == CHECK_ERR) {
	      $fr = CHECK_ERR;
	      $err .= "Check $name failed with error.\n";
	    }
	    elsif ($r == CHECK_WARN) {
	      $fr = ($fr == CHECK_ERR) ? CHECK_ERR : CHECK_WARN;
	      $warn .= "Check $name succeeded with warning.\n";
	    }
	  }
	}
	
	unless ($fr == CHECK_OK) {
	  $err =~ s/\s+$//g;
	  $warn =~ s/\s+$//g;
	  $self->error($err);
	  $self->warning($warn);
	}
	
	return $fr;
}

sub toString {
	my ($self) = @_;
	no warnings;
	return "$self->{expression}";
}

sub _checkParams {
	my ($self) = @_;
	
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
 	
 	return 1;
}

sub _validateSubCheckResult {
	my ($self, $name, $result) = @_;
	unless (defined $result && ref($result) eq 'HASH') {
		die "Check $name returned invalid result structure.\n";
	}
	
	my $c = $result->{data}->{check};
	my $res = $c->{result_code};
	unless (defined $res) {
		die "Check $name returned invalid result code.\n";
	}
	
	# build buffer message
	my $buf = sprintf("CHECK %-30s: %s", $name, result2str($res));
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
		$self->bufApp();
		$self->bufApp("=== BEGIN CHECK MESSAGES: $name");
		$self->bufApp($c->{messages});
		$self->bufApp();		
	}
	
	return $res;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;