package P9::AA::Check::FileCheck;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';

use POSIX qw(strftime);

our $VERSION = 0.20;

=head1 NAME

File existence checking module.

=cut
sub clearParams {
  my ($self) = @_;

  return 0 unless ($self->SUPER::clearParams());

  $self->setDescription(
    "This is checks for existence of files/directories."
  );

  $self->cfgParamAdd(
    'file_pattern',
    undef,
    'Filename pattern.',
    $self->validate_str(1024),
  );

  $self->cfgParamAdd(
    'check_expr',
    'f',
    'Check expression (example: (f && x) || d)',
    $self->validate_lcstr(64),
  );

  $self->cfgParamAdd(
    'false_expr',
    0,
    'Check expression must be reversed.',
    $self->validate_bool
  );

  $self->cfgParamAdd(
    'time_offset',
    0,
    'Time offset in seconds from current time used for filename calculation.',
    $self->validate_int()
  );

  1;
}

sub check {
  my ($self) = @_;
  my $f = $self->getFilename();
  return $self->error("Undefined filename.") unless (defined $f);

  local $@;
  my $validator = eval { $self->getValidator() };
  return $self->error("Error compiling validator function: $@") unless (ref($validator) eq 'CODE');

  my $c = eval { $validator->($f) };
  return $self->error($@) unless ($c);
  $self->success;
}

sub toString {
  shift->{file_pattern};
}

sub getFilename {
  my ($self, $patt, $t) = @_;
  $t = time() unless (defined $t);

  $patt = $self->{file_pattern} unless (defined $patt && length $patt);
  return undef unless (defined $patt && length $patt);

  # resolve dates
  my $file = strftime($patt, localtime($t + $self->{time_offset}));

  return $file;
}

sub getValidator {
  my ($self) = @_;
  my $code = $self->_validatorCodeStr();
  return eval $code;
}

sub _validatorCodeStr {
  my ($self) = @_;
  my $t = $self->{check_expr};
  $t =~ s/[^a-z\|\&]+//g;

  my $code_str = 'sub { no warnings; (';
  my $sub_str = '';
  map {
    if (defined $_ && length $_) {
      if ($_ eq '(' || $_ eq ')') {
        $sub_str .= $_;
      }
      elsif ($_ eq '||' || $_ eq '&&') {
        $sub_str .= ' ' . $_;
      }
      else {
        $sub_str .= ' -' . $_ . ' $_[0]';
      }
    }
  } split(/\s*(\|\||&&|\(|\))\s*/, $t);

  $sub_str =~ s/^\s+//g;
  $sub_str =~ s/\s+$//g;

  $code_str .= $sub_str . ') ';
  $code_str .= $self->{false_expr} ? '&&' : '||';
  $code_str .=
    ' die "' .
    ($self->{false_expr} ? 'FALSE ' : '') .
    'File check expression \"$self->{check_expr}\" failed for \"$_[0]\": $!\n"; 1 }';

  if ($self->{debug}) {
    $self->bufApp("Generated perl code: $code_str");
  }

  $code_str;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;