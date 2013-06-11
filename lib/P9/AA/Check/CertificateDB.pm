package P9::AA::Check::CertificateDB;

use strict;
use warnings;

use IO::File;
use HTTP::Date;
use File::Find;
use IPC::Open3;
use Cwd qw(realpath);
use Symbol qw(gensym);

use P9::AA::Util;
use P9::AA::Constants;
use base 'P9::AA::Check';

use constant SECS_IN_DAY => 24 * 60 * 60;
use constant BUF_LEN     => 1024 * 1024;

our $VERSION = 0.20;

my $u = P9::AA::Util->new;

##################################################
#              PUBLIC  METHODS                   #
##################################################

=head1 NAME

Checks directories for expired certificates. Requires L<openssl(1)> binary.

=cut

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks directories for expires x509 certificates. Requires openssl(1) command."
	);
	
	$self->cfgParamAdd(
		'path',
		'/tmp',
		'Comma separated list of directories containing certificates.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'days',
		60,
		'How many days before expiration error should be reported?',
		$self->validate_int(1)
	);
	$self->cfgParamAdd(
		'daysWarn',
		70,
		'How many days before expiration warning should be reported?',
		$self->validate_int(1)
	);
  $self->cfgParamAdd(
    'pkcsPassword',
    undef,
    'PKCS 7/12 input passphrase',
    $self->validate_str(128)
  );
	
	return 1;
}

=head2 check ()

Performs x509 certificate check.

=cut
sub check {
  my ($self) = @_;
  unless (defined $self->{path} && length($self->{path})) {
    return $self->error("Undefined x509 certificate directory path.");
  }

  # parse and resolve provided paths
  my @paths = ();
  map {
    my $x = realpath($_);
    push(@paths, $x) if (defined $x && -d $x && -r $x);
  } split(/\s*[,;]+\s*/, $self->{path});

  return $self->error("No certificates were found in specified paths.") unless (@paths);

  $self->bufApp("Certificate search path: ", join(", ", @paths));
  $self->bufApp();

  my @files = $self->_find_files(@paths);
  if ($self->{debug}) {
    $self->bufApp("Found the following certificates:");
    map { $self->bufApp("  $_") } @files;
    $self->bufApp();
  }

  my ($res, $err, $warn) = (CHECK_OK, [], []);
  foreach my $f (@files) {
    my ($r, $e, $w) = $self->_validate_file($f);
    $res = $self->_res_calc($r, $res);
    push(@$err, "CERT: $f:\n  " . join("\n  ", @$e)) if (@$e);
    push(@$warn, "CERT: $f:\n  " . join("\n  ", @$w)) if (@$w);
  }

  $self->warning(join("\n", @$warn)) if (@$warn);
  $self->error(join("\n", @$err)) if (@$err);
  return $res;
}

sub toString {
	my $self = shift;
	no warnings;
	return $self->{days} . '/' . $self->{daysWarn} . ' @ ' . $self->{path};
}

##################################################
#              PRIVATE METHODS                   #
##################################################

sub _find_files {
  my $self = shift;
  my @r = ();
  no warnings 'File::Find';
  find(
    {
      wanted => sub {
        my $file = $File::Find::name;
        if ($file =~ m/\.(pkcs12|pkcs7|p12|crt|pem|der)$/i && -f $file) {
          push(@r, $file)
        }
      },
      follow => 1,
      follow_skip => 2,
      no_chdir => 1,
    },
    @_
  );
  return @r;
}

sub _validate_file {
  my ($self, $file) = @_;
  my ($res, $err, $warn) = (CHECK_OK, [], []);

  local $@;
  my @certs = eval { $self->_file_get_certs($file) };
  if ($@ || ! @certs) {
    $res = CHECK_ERR;
    my $ex = $@; $ex =~ s/\s+$//g;
    push(@$err, $ex);
    goto outta_validate_file;
  }
  $self->bufApp($file . ': ' . $self->_cert_to_s(\@certs));

  foreach my $c ($self->_file_get_certs($file)) {
    my ($r, $e, $w) = $self->_validate_struct($c);
    $res = $self->_res_calc($r, $res);
    push(@$err, @$e) if (@$e);
    push(@$warn, @$w) if (@$w);
  }
  outta_validate_file:
  return ($res, $err, $warn);
}

sub _res_calc {
  my ($self, $new_r, $old_r) = @_;
  return $old_r if ($old_r == CHECK_ERR);
  return $new_r if ($new_r == CHECK_ERR);
  return $old_r if ($old_r == CHECK_WARN);
  return $new_r;
}

sub _cert_to_s {
  my ($self, $c) = @_;
  no warnings;
  my $r = '';
  $r .= "File contains " . scalar(@$c) . " certificates.\n";
  my $i = 0;
  map {
    $i++;
    $r .= "  Subcert $i:\n";
    $r .= "    Issuer:   $_->{issuer}\n";
    $r .= "    Subject:  $_->{subject}\n";
    $r .= "    Validity: $_->{valid_start_str} <=> $_->{valid_end_str}\n";
  } @$c;
  return $r;
}

sub _validate_struct {
  my ($self, $s) = @_;
  my $r = CHECK_OK;
  my ($err, $warn) = ([], []);

  # check attrs
  for (qw(
          issuer key_length subject valid_end valid_end_str
          valid_start valid_start_str version
       )) {
    unless (defined $s->{$_} && length($s->{$_})) {
      $r = CHECK_ERR;
      push(@$err, "Missing certificate attribute: $_");
    }
  }
  goto outta_validate_s if (@$err);

  # check validity
  my $t = time;
  my $expire_warn = $t + (SECS_IN_DAY * $self->{daysWarn});
  my $expire_err = $t + (SECS_IN_DAY * $self->{days});
  my $expire_days = sprintf("%-.1f", ($s->{valid_end} - $t) / SECS_IN_DAY);

  if ($s->{valid_start} > $t) {
    push(@$err, 'Certificate is not valid yet: ' . $s->{valid_start_str});
    $r = CHECK_ERR;
  }
  elsif ($expire_days <= 0) {
    push(@$err, 'Certificate validity EXPIRED on ' . $s->{valid_end_str});
    $r = CHECK_ERR;
  }
  elsif ($expire_days < $self->{days}) {
    push(@$err, "Certificate will EXPIRE in $expire_days days on " . $s->{valid_end_str});
    $r = CHECK_ERR;
  }
  elsif ($expire_days < $self->{daysWarn}) {
    push(@$warn, "Certificate will expire in $expire_days days on " . $s->{valid_end_str});
    $r = CHECK_WARN;
  }

  outta_validate_s:
  return ($r, $err, $warn);
}


sub _file_get_certs {
  my ($self, $file) = @_;
  my @r;
  map { push(@r, $self->_parse_pem($_)) } $self->_parse_file($file);
  return @r;
}

sub _parse_file {
  my ($self, $file) = @_;
  die "Undefined or non-existing certificate file.\n" unless (defined $file && length $file && -f $file);

  if ($file =~ m/\.(?:crt|pem)$/i) {
    return $self->_parse_file_pem($file);
  }
  elsif ($file =~ m/\.(?:der)$/i) {
    return $self->_parse_file_der($file);
  }
  elsif ($file =~ m/\.(?:p12|pkc12|pkcs7)$/i) {
    return $self->_parse_file_pkcs12($file);
  }
  else {
    die "Invalid or unrecognized file '$file'.\n";
  }
}

sub _file_read {
  my ($self, $file) = @_;
  my $fd = IO::File->new($file, 'r') || die "Unable to open file '$file': $!\n";
  my $buf = '';
  read($fd, $buf, BUF_LEN);
  close($fd);
  return $buf;
}

sub _parse_file_der {
  my ($self, $file) = @_;
  $self->_split_multi_pem($self->_der2pem($file));
}

sub _parse_file_pem {
  my ($self, $file) = @_;
  $self->_split_multi_pem($self->_file_read($file));
}

sub _parse_file_pkcs12 {
  my ($self, $file) = @_;
  $self->_split_multi_pem($self->_pkcs2pem($file));
}

sub _der2pem {
  my ($self, $file) = @_;
  my @cmd = ('x509', '-in', $file, '-chain', '-inform', 'DER', '-passin', 'stdin');
  my ($pid, $in, $o, $e) = $self->_openssl(@cmd);
  close($in); close($e);
  my $buf = '';
  read($o, $buf, BUF_LEN);
  close($o);
  waitpid($pid, 0);
  my $st = $u->getExitCode($?);
  die "Openssl command exited with status: $st\n" unless ($st == 0);
  return $buf;
}

sub _pkcs2pem {
  my ($self, $file) = @_;
  my $pk_type = ($file =~ m/\.(?:pkcs7|pk7)$/i) ? 'pkcs7' : 'pkcs12';
  my @cmd = ($pk_type, '-in', $file, '-chain', '-nodes', '-passin', 'stdin');
  my ($pid, $in, $o, $e) = $self->_openssl(@cmd);
  print $in "$self->{pkcsPassword}\n";
  close($in);
  my $buf = '';
  read($o, $buf, BUF_LEN);
  close($o); close($e);
  waitpid($pid, 0);
  my $st = $u->getExitCode($?);
  die "Error converting pkcs => pem: bad password? (openssl exit status: $st)\n" unless ($st == 0);
  return $buf;
}

sub _parse_date {
  my ($str) = @_;
  return 0 unless (defined $str && length($str) > 0);
  my $r = 0;

  # Apr 19 12:59:12 2007 GMT
  # ->
  # 09 Feb 1994 22:23:32 GMT [HTTP format (no weekday)]
  #print "PARSING: '$str'\n";
  if ($str =~ m/^([a-z]{3})\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)\s+GMT/i) {
    my $s = "$2 $1 $6 $3:$4:$5 GMT";
    $r = str2time($s);
    $r = 0 unless (defined $r);
  }
  return $r;
}

sub _split_multi_pem {
  my ($self, $str) = @_;
  my @r = ();

  # $self->bufApp("Splitting multi-pem: " . $u->dumpVarCompact($str)) if ($self->{debug});

  my $e = undef;
  foreach my $l (split(/[\r\n]+/, $str)) {
    if (defined $e) {
      if ($l =~ m/-----END CERTIFICATE-----/) {
        $e .= $l . "\n";
        push(@r, $e);
        $e = undef;
      } else {
        $e .= $l . "\n";
      }
    } else {
      if ($l =~ m/-----BEGIN CERTIFICATE-----/) {
        $e = $l . "\n";
      }
    }
  }

  #$self->bufApp("Returning: " . $u->dumpVarCompact(\@r)) if ($self->{debug});
  return wantarray ? @r : \@r;
}

sub _parse_pem {
  my ($self, $s) = @_;
  my $err = 'Unable to parse PEM: ';
  die "$err: Undefined input\n" unless (defined $s && length($s));

  my @cmd = ('x509', '-text', '-noout');
  my ($pid, $in, $o, $e) = $self->_openssl(@cmd);
  print $in $s;
  close($in);
  my $buf;
  read($o, $buf, BUF_LEN);
  close($o); close($e);
  waitpid($pid, 0);
  my $st = $u->getExitCode($?);
  die "Openssl command exited with status: $st\n" unless ($st == 0);
  return $self->_parse_openssl_x509($buf);
}

sub _parse_openssl_x509 {
  my ($self, $str) = @_;
  my $r = {};
  foreach my $l (split(/[\r\n]+/, $str)) {
    if ($l =~ m/\s+Version:\s+(\d+)/) {
      $r->{version} = $1;
    }
    elsif ($l =~ m/\s+Serial\s+Number:\s+(\d+)/) {
      $r->{serial} = $1;
    }
    elsif ($l =~ m/\s+Issuer:\s*(.+)/) {
      $r->{issuer} = $1;
    }
    elsif ($l =~ m/\s+Not\s+Before\s*:\s*(.+)/) {
      $r->{valid_start_str} = $1;
      $r->{valid_start} = _parse_date($1);
    }
    elsif ($l =~ m/\s+Not\s+After\s*:\s*(.+)/) {
      $r->{valid_end_str} = $1;
      $r->{valid_end} = _parse_date($1);
    }
    elsif ($l =~ m/\s+Subject:\s*(.+)/) {
      $r->{subject} = $1;
    }
    elsif ($l =~ m/\s+Public-Key\s*:\s+\((\d+)\s+bit\)/) {
      $r->{key_length} = $1;
    }
  }
  unless (%{$r}) {
    $self->error("Unable to parse anything about certificate.");
    return undef;
  }
  return $r;
}

my $_openssl = undef;
sub _openssl {
  my $self = shift;
  my ($stdin, $stdout, $stderr) = (gensym, gensym, gensym);
  unless (defined $_openssl) {
    $_openssl = $u->which('openssl') || 'openssl';
  }
  $self->bufApp("Running: $_openssl " . join(' ', @_)) if ($self->{debug});
  my $pid = open3($stdin, $stdout, $stderr, $_openssl, @_) || die "Unable to run openssl: $!\n";
  return ($pid, $stdin, $stdout, $stderr);
}

=head2 AUTHOR

Brane F. Gracnar

=head2 SEE ALSO

L<P9::AA::Check>

=cut

1;