package P9::AA::Check::HTTPSmoothStreaming;

use strict;
use warnings;

use Encode;
use XML::Parser;
use Time::HiRes qw(time);
use File::Temp qw(tempfile);

use P9::AA::Constants;
use base 'P9::AA::Check::XML';


our $VERSION = '0.11';

=head1 NAME

L<HTTP smooth streaming|http://www.iis.net/download/SmoothStreaming> checking module.

=head1 METHODS

This module inheriths all methods from L<P9::AA::Check::XML>.

=cut

sub clearParams {
  my ($self) = @_;

  # run parent's clearParams
  return 0 unless ($self->SUPER::clearParams());

  # set module description
  $self->setDescription("HTTP Smooth streaming check.");

  $self->cfgParamAdd(
    'redirects', 5,
    'Maximum number of allowed redirects.',
    $self->validate_int(0, 10),
  );
  $self->cfgParamAdd(
    'debug_trace', 0,
    'Enables heavy debugging messages.',
    $self->validate_bool(0),
  );
  $self->cfgParamAdd(
    'chunk_num', 0,
    'Try to download specified data chunk. Set to -1 to validate random chunk number.',
    $self->validate_int(-1, 0, undef),
  );
  $self->cfgParamAdd(
    'require_audio', 1,
    'Require audio track in manifest (1: require, 0: prefer, issue warning unless present, -1: disallow audio, issue error if present)',
    $self->validate_int(-1, 1, 1)
  );
  $self->cfgParamAdd(
    'require_video', 1,
    'Require video track in manifest (1: require, 0: prefer, issue warning unless present, -1: disallow audio, issue error if present)',
    $self->validate_int(-1, 1, 1)
  );

  # you can also remove any previously created
  # configuration parameter.
  $self->cfgParamRemove('content_pattern');
  $self->cfgParamRemove('content_pattern_match');
  $self->cfgParamRemove('debug_response');
  $self->cfgParamRemove('request_body');
  $self->cfgParamRemove('schemas');
  $self->cfgParamRemove('strict');
  $self->cfgParamRemove('ignore_http_status');
  $self->cfgParamRemove('url');

  $self->{request_method} = 'GET';
  $self->cfgParamAdd(
    'url',
    'http://localhost/media/movie.ism',
    'Full movie ISM file URL.',
    sub {
      my $code = $self->validate_str( 16 * 1024 );
      my $str = $code->(@_);
      # sanitize
      $str =~ s/^\s+//g;
      $str =~ s/\s+$//g;
      
      # remove possible manifest suffix
      if ($str =~ m/\/+manifest$/) {
        $str =~ s/\/+manifest$//g;
      }
      # remove trailing slashes
      $str =~ s/\/+$//g;
      return $str;
    },
  );

  # this method MUST return 1!
  return 1;
}

# actually performs ping
sub check {
  my ($self) = @_;
  
  # get manifest file...
  my $manifest = $self->getManifest($self->{url});
  return $self->error() unless (defined $manifest);
  
  # check manifest
  my $res = CHECK_OK;
  my $err = '';
  my $warn = '';
  
  foreach my $type (qw(audio video)) {
    my $x = $self->checkManifest($manifest, $type);
    $self->_validateCheckManifest($x, $type, \$res, \$err, \$warn);
  }

  #if (length($err) > 0) {
  unless ($res == CHECK_OK) {
    $err =~ s/^\s+//gm;
    $err =~ s/\s+$//gm;
    $warn =~ s/^\s+//gm;
    $warn =~ s/\s+$//gm;
    $self->warning($warn);
    $self->error($err);
  }
  
  return $res;
}

=head2 getManifest

Prototype:

 my $manifest = $self->getManifest($url);
 unless (defined $manifest) {
   die "Error retrieving manifest file: " . $manifest->error() . "\n";
 }

Returns parsed manifest structure for specified URL. Returns
parsed manifest as hash reference on success, otherwise undef.

Returns undef on error.

B<NOTE>: This method supports all keys supported by L<P9::AA::Check::URL/prepareRequest>.

=cut
sub getManifest {
  my $self = shift;
  my $url = shift;
  $url = $self->{url} unless (defined $url);
  
  unless ($url =~ m/\/+manifest$/i) {
    $url .= '/manifest';
  }
  
  # get parser
  local $XML::Simple::PREFERRED_PARSER = 'XML::Parser';
  my $parser = $self->getXMLParser(ForceArray => 1);

  my $xml = $self->getXML(@_, url => $url, request_method => 'GET', parser => $parser);
  return undef unless (defined $xml);

  # lowecase all hash keys and return...
  $xml = $self->_hashLcKeys($xml);

  if ($self->{debug_trace}) {
    $self->bufApp("--- BEGIN MANIFEST ---");
    $self->bufApp($self->dumpVar($xml));
    $self->bufApp("--- END MANIFEST ---");
  }
  
  return $xml;
}

=head2 checkManifest

Prototype:

 my $r = $self->checkManifest($manifest, [ $type = "audio", [ $chunk_num = 0 ]])

Manifest structure validation method. This method tries to download one chunk of data
for each defined manifest defined structures (audio, video) for all quality levels.

Returns 1 on success, otherwise 0.

=cut
sub checkManifest {
  my ($self, $manifest, $type, $chunk_num) = @_;
  $chunk_num = $self->{chunk_num} unless (defined $chunk_num);
  { no warnings; $chunk_num = int($chunk_num); }
  $type = 'audio' unless (defined $type && length($type) > 0);
  $type = lc($type);
  
  my $top_err = "Invalid manifest structure for type $type: ";
  
  # get audio and video streams...
  my $data = $self->_searchManifest($manifest, $type);
  unless (defined $data && defined $data) {
    $self->error($top_err . $self->error());
    return 0;
  }
  
  my $base_url = $data->{url} || '';
  
  $self->bufApp(
    ucfirst($type) .
    " stream has $data->{qualitylevels} quality level(s)" .
    " in $data->{chunks} chunk(s)."
  );
  unless ($data->{qualitylevels} > 0) {
    $self->error("Manifest for $type doesn't contain any quality levels.");
    return 0;
  }
  unless ($data->{chunks} > 0) {
    $self->error("Manifest for $type doesn't contain any chunks.");
    return 0;
  }
  
  my $r = 1;
  my $err = '';
  foreach my $ql (1 .. $data->{qualitylevels}) {
    $self->error('');
    my $qld = undef;
    if (ref($data->{qualitylevel}) eq 'HASH') {
      $qld = $data->{qualitylevel};
    }
    elsif (ref($data->{qualitylevel}) eq 'ARRAY') {
      $qld = $data->{qualitylevel}->[($ql - 1)];
    }
    else {
      $err = $top_err . "Invalid qualitylevel manifest structure.";
      $r = 0;
      last;
    }
    unless (defined $qld && ref($qld) eq 'HASH') {
      $err .= $top_err . "Quality level structure for level $ql\n";
      $r = 0;
      next;
    }
    my $bitrate = $qld->{bitrate};
    my $height = $qld->{maxheight};
    my $width = $qld->{maxwidth};
    my $cnum = ($chunk_num >= 0) ? $chunk_num : int(rand($data->{chunks}));
    my $start_time = $self->_getStartTime($data, $cnum);
    unless ($start_time >= 0) {
      $err .= $top_err . $self->error() . "\n";
      $r = 0;
      next;
    }
    
    # format url
    my $url = $base_url;
    $url =~ s/{bitrate}/$bitrate/gm;
    $url =~ s/{start\s*time}/$start_time/gm;
    my $real_url = $self->{url} . '/' . $url;
    
    my $str = "  Quality level $ql, bitrate $bitrate, ";
    if (defined $width && defined $height) {
      $str .= "size: ${width}x${height}, ";
    }
    $str .= "chunk $cnum, URL: $real_url";
    $self->bufApp($str);
    
    unless ($self->_checkUrl($real_url)) {
      $err .= $top_err . $self->error() . "\n";
      $r = 0;
    }
  }
  
  unless ($r) {
    $err =~ s/^\s+//g;
    $err =~ s/\s+$//gm;
    $self->error($err);
  }

  return $r;
}

sub _validateCheckManifest {
  my ($self, $val, $type, $res, $err, $warn) = @_;
  my $policy = $self->{'require_' . $type} || 1;

  if ($policy == 1) {
    unless ($val) {
      $$res = CHECK_ERR;
      $$err .= $self->error() . "\n";
    }
  }
  elsif ($policy == 0) {
    unless ($val) {
      $$res = CHECK_WARN unless ($$res == CHECK_ERR);
      $$warn .= $self->error() . "\n";
    }
  }
  elsif ($policy == -1) {
    if ($val) {
      $$res = CHECK_ERR;
      $$err .= "Stream type $type shouldn't be present, but it is.\n";
    }
  }
}

sub _searchManifest {
  my ($self, $manifest, $type) = @_;
  unless (defined $manifest && ref($manifest) eq 'HASH') {
    $self->error("Invalid or undefined manifest reference.");
    return undef;
  }
  $type = 'audio' unless (defined $type && length($type) > 0);
  $type = lc($type);

  my $key = undef;
  foreach (@{$manifest->{streamindex}}) {
    if (exists $_->{name} && lc($_->{name}) eq $type) {
      return $_
    }
  }
  
  $self->error("Key '$type' does not exist.");
  return undef;
}

sub _getStartTime {
  my ($self, $data, $chunk_num) = @_;
  unless (defined $data && ref($data) eq 'HASH') {
    $self->error("Invalid data argument");
    return -1;
  }
  unless (exists $data->{c} && ref($data->{c}) eq 'ARRAY') {
    $self->error("Invalid data structure 'c' element is not array reference.");
    return -1;
  }
  $chunk_num = 0 unless (defined $chunk_num);
  $chunk_num = abs(int($chunk_num));

  my $len = $#{$data->{c}};
  if ($chunk_num < 0 || $chunk_num > $len) {
    $self->error("Chunk number $chunk_num is out of range.");
    return -1;
  }
  
  my $v = (exists $data->{c}->[$chunk_num]->{d}) ?
    $data->{c}->[$chunk_num]->{d} : -1;
  
  unless ($v >= 0) {
    $self->error("Unable to find chunk number $chunk_num.");
  }
  
  return $v;
}

sub _hashLcKeys {
  my ($self, $h, $level) = @_;
  $level = 0 unless (defined $level);
  return undef unless ($level < 9);
  return undef unless (defined $h);


  my $ref = ref($h);  
  if ($ref eq 'HASH') {
    foreach my $k (keys %{$h}) {
      my $kn = lc($k);
      if ($k ne $kn) {
        $h->{$kn} = $self->_hashLcKeys($h->{$k}, ($level + 1));
        delete $h->{$k};
      }
    }
  }
  elsif ($ref eq 'ARRAY') {
    my $len = $#{$h};
    for (my $i = 0; $i <= $len; $i++) {
      $h->[$i] = $self->_hashLcKeys($h->[$i], ($level + 1));
    }
  }
  
  return $h;  
}

sub _checkUrl {
  my ($self, $url) = @_;
  unless (defined $url && length($url) > 0) {
    $self->error("Undefined URL.");
    return 0;
  }
  my $top_err = "Error downloading $url: ";

  # create temporary file..
  my ($fh, $file) = tempfile();
  close($fh);
  unless (defined $file && -f $file) {
    $self->error($top_err . "Unable to create temporary file: $!");
    return 0;
  }
  
  my $ua = $self->getUa();

  # time to download some stuff...
  my $ts = time();
  
  my $r = $ua->get(
    $url,
    ':content_file' => $file,
  );
  my $duration = time() - $ts;
  
  my $res = 1;
  if (defined $r && $r->is_success()) {
    # check file
    my @s = stat($file);
    if (!@s) {
      $self->error($top_err . "Unable to stat(2) downloaded file: $!");
      $res = 0;
    }
    # size should be greater than zero...
    elsif ($s[7] < 1) {
      $self->error($top_err . "Downloaded downloaded empty file $file.");
      $res = 0;
    }
    else {
      $self->bufApp(
        "    Successfully downloaded $s[7] bytes in " .
        sprintf("%-.3f msec ", $duration  * 1000) . 
        "[" . int($s[7] / $duration). " B/sec]."
      );
    }
  } else {
    $res = 0;
    local $@;
    eval {
      $self->error($top_err . $r->status_line());
    };
  }
  
  unlink($file);
  return $res;
}

=head1 SEE ALSO

=over

=item L<P9::AA::Check::URL>

=item L<P9::AA::Check>

=item L<Smooth Streaming Protocol Specification|http://download.microsoft.com/download/B/0/B/B0B199DB-41E6-400F-90CD-C350D0C14A53/[MS-SSTR].pdf>

=item L<IIS smooth streaming README|http://learn.iis.net/page.aspx/1046/iis-media-services-readme/>

=item L<Nginx smooth streaming module|http://h264.code-shop.com/trac/wiki/Mod-Smooth-Streaming-Nginx-Version1>

=back

=head1 AUTHOR

Brane F. Gracnar

=cut

1;
