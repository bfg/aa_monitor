package P9::AA::Check::MultiCheck;

use strict;
use warnings;

use P9::AA::CheckHarness;

use P9::AA::Constants qw(:all);
use base 'P9::AA::Check::StackedCheck';

use constant WEIGHT_SCORE_MIN => 1;
use constant WEIGHT_SCORE_MAX => 100;
use constant WEIGHT_SCORE_DEFAULT => WEIGHT_SCORE_MAX;

# version MUST be set
our $VERSION = 0.10;

=head1 NAME

Embed and combine other check modules to perform multiple checks; check return value
is computed from all sub check partial results.

=head1 DESCRIPTION

Final check result
is L<weighted sum|http://en.wikipedia.org/wiki/Weighted_sum_model> function of check results
returdned by checks identified by B<check_definitions> property. Each check defined in 
B<check_definitions> has it's own name and additional optional parameter B<weight>
(integer value between 1 and 99, default: 1).
Final check result is defined with properties B<warning_threshold>
and B<error_threshold>, both expressed as percents of the maximum final score. Maximum
final score is computed value as if all checks would return B<CHECK_OK>.


See L<B<StackedCheck>|P9::AA::Check::StackedCheck/SYNOPSIS> for information regarding configuration
and input data.

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
  $self->cfgParamAdd(
    'warning_threshold',
    75,
    'Total check score warning threshold in percents.',
    $self->validate_int(0,100),
  );
  $self->cfgParamAdd(
    'error_threshold',
    50,
    'Total check score error threshold in percents.',
    $self->validate_int(0,100),
  );
  $self->cfgParamRemove('expression');
  $self->cfgParamRemove('use_cache');

  # this method MUST return 1!
  return 1;
}

# actually performs ping
sub check {
  my ($self) = @_;
  return CHECK_ERR unless ($self->_checkParams());
  
  # score sum
  my $sum = 0;

  # time to run some checks, bitchez...
  foreach my $name (keys %{$self->{check_definitions}}) {    
    my $r = $self->_performSubCheck($name);
    unless (defined $r) {
      return $self->error("Error running check $name: " . $self->error());
    }
    
    # add scores to sum
    $sum += $self->_r2score($name, $r);
  }
  
  # check results...
  my $max_sum = 3;
  my $sum_percent = sprintf("%-.2f", ($sum / $max_sum) * 100);
  
  $self->bufApp();
  $self->bufApp("Check result score: $sum_percent%");

  # final result
  my $fr = CHECK_OK;  
  if ($sum_percent < $self->{error_threshold}) {
    $self->error("Check score $sum_percent% is lower than error threshold $self->{error_threshold}%.");
    $fr = CHECK_ERR;
  }
  elsif ($sum_percent < $self->{warning_threshold}) {
    $self->warning("Check score $sum_percent% is lower than warning threshold $self->{warning_threshold}%.");
    $fr = CHECK_WARN;
  }

  return $fr;
}

sub toString {
  my ($self) = @_;
  no warnings;
  return join(', ', sort(keys %{$self->{check_definitions}}));
}

sub _r2score {
  my ($self, $name, $r) = @_;
  my $res = 0;
  if ($r == CHECK_OK) {
    $res = 3;
  }
  elsif ($r == CHECK_WARN) {
    $res = 2;
  }
  elsif ($r == CHECK_ERR) {
    $res = 1;
  }
  
  # observe the weight value!
  return ($res * $self->_getWeight($name));
}

sub _getWeight {
  my ($self, $name) = @_;
  # get check weight score (1 - 100)
  my $s = $self->_getWeightScore($name);
   
  # sum all weight scores
  my $ss = 0;
  map {
    $ss += $self->_getWeightScore($_)
  } keys %{$self->{check_definitions}};
  
  # real weight is percentage of the sum
  # of all weight scores
  return ($s / $ss);
}

sub _getWeightScore {
  my ($self, $name) = @_;
  return WEIGHT_SCORE_DEFAULT unless (defined $name && length($name) > 0);
  return WEIGHT_SCORE_DEFAULT unless (exists($self->{check_definitions}->{$name}));

  my $s = $self->{check_definitions}->{$name}->{params}->{weight};
  { no warnings; $s += 0; $s = int($s) }
  
  # check bounds
  $s = ($s <= WEIGHT_SCORE_MIN) ? WEIGHT_SCORE_MIN : $s;
  $s = ($s >= WEIGHT_SCORE_MAX) ? WEIGHT_SCORE_MAX : $s;
  
  return $s;
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
  my $buf = sprintf("CHECK %-30s: %-7s", $name, result2str($res));

  $buf .= " [weight score: " . sprintf("%-3d", $self->_getWeightScore($name));
  $buf .= " weight: " . sprintf("%-.2f", $self->_getWeight($name));
  $buf .= " final result: " . sprintf("%-.2f", $self->_r2score($name, $res));
  $buf .= "]";

  unless ($res == CHECK_OK) {
    $buf .= " [";
    if ($res == CHECK_WARN) {
      $buf .= "warning: $c->{warning_message}"
    }
    elsif ($res == CHECK_ERR) {
      $buf .= "error: $c->{error_message}"
    }
    $buf .= "]";
  }

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

L<P9::AA::StackedCheck> L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;