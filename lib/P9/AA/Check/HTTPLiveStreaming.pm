package P9::AA::Check::HTTPLiveStreaming;

use strict;
use warnings;

use Time::HiRes qw(time);
use File::Temp qw(tempfile);
use Scalar::Util qw(blessed);

use P9::AA::Constants;
use base 'P9::AA::Check::URL';

use P9::AA::Check::HTTPLiveStreaming::PlayList;

our $VERSION = 0.11;


=head1 NAME

L<HTTP Live Streaming|http://tools.ietf.org/html/draft-pantos-http-live-streaming-06> checking module.

=head1 METHODS

This class inherits all methods from L<P9::AA::Check::URL>.

=cut
sub clearParams {
  my ($self) = @_;

  # run parent's clearParams
  return 0 unless ($self->SUPER::clearParams());

  # set module description
  $self->setDescription(
    "HTTP Live Streaming check."
  );

  $self->cfgParamAdd(
    'redirects',
    5,
    'Maximum number of allowed redirects.',
    $self->validate_int(0, 10),
  );
  $self->cfgParamAdd(
    'chunk_num', 0,
    'Try to download specified data chunk. Set to -1 to validate random chunk number.',
    $self->validate_int(-1, undef, 0),
  );


  $self->cfgParamRemove('content_pattern');
  $self->cfgParamRemove('content_pattern_match');
  # $self->cfgParamRemove('debug_response');
  $self->cfgParamRemove('request_body');
  $self->{request_method} = 'GET';

  # this method MUST return 1!
  return 1;
}

# actually performs ping
sub check {
  my ($self) = @_;
  
  # get playlist
  my $playlist = $self->getPlayList($self->{url});
  return CHECK_ERR unless (defined $playlist);
  
  # check streams...
  return $self->checkPlayList($playlist) ?
    CHECK_OK : CHECK_ERR;
}

=head2 getPlayList

Prototype:

 my $playlist = $self->getPlayList($url);

Returns parsed L<P9::AA::Check::HTTPLiveStreaming::PlayList> object on success, otherwise undef.

=cut
sub getPlayList {
  my ($self, $url) = @_;
  $url = $self->{url} unless (defined $url);
  
  # configure playlist parser...
  my $p = P9::AA::Check::HTTPLiveStreaming::PlayList->new();
  $p->ua($self->getUa());
  
  local $@;
  my $playlist = eval { $p->parse_url($url) };
  if ($@) {
    $self->error("Invalid playlist '$url': " . _err($@));
    return undef;
  }

  if ($self->{debug}) {
    $self->bufApp("--- BEGIN PLAYLIST ---");
    $self->bufApp($self->dumpVar($playlist));
    $self->bufApp("--- END PLAYLIST ---");
  }

  return $playlist;
}

=head2 checkPlayList

Prototype:

 my $r = $self->checkPlayList($playlist);

This method validates provided L<P9::AA::Check::HTTPLiveStreaming::PlayList>
object (tries to download one or more chunks). Returns 1 on success, otherwise 0.
 
=cut
sub checkPlayList {
  my ($self, $p, $rec_level) = @_;
  unless (defined $p && blessed($p) && $p->isa('P9::AA::Check::HTTPLiveStreaming::PlayList')) {
    no warnings;
    $self->error("Invalid playlist object: '$p'");
    return 0;
  }

  $rec_level = 0 unless (defined $rec_level);
  if ($rec_level > 9) {
    return $self->error("Too deep recursion depth: $rec_level");
  }
  
  # message prefix
  my $prefix = "  " x $rec_level;
  
  # get entry/playlist count
  my $n_entries = $p->entries();
  my $n_pls = $p->playlists();
  
  $self->bufApp($prefix . "Playlist " . $p->url() . " [entries: $n_entries, playlists: $n_pls]");
  
  my $err = '';
  # check embedded playlists...
  my $r = 1;
  foreach my $pl ($p->playlists()) {
    my $x = $self->checkPlayList($pl, ($rec_level + 1));
    unless ($x) {
      $err .= $self->error() . "\n";
      $r = 0;
    }
  }
  
  # check one of the entries...
  if ($n_entries > 0) {
    my $eidx = $self->{chunk_num};
    $eidx = int(rand($n_entries)) if ($eidx < 0);
    my $entry = $p->entry($eidx);
    if (defined $entry) {
      my $x = $self->checkEntry($entry, $rec_level);
      unless ($x) {
        $err .= $self->error() . "\n";
        $r = 0;
      }
    } else {
      $self->error("Invalid entry idx: $eidx");
    }
  }
  
  # set error...
  unless ($r) {
    $err =~ s/^\s+//g;
    $err =~ s/\s+$//g;
    $self->error($err);
  }
  
  return $r;
}

sub checkEntry {
  my ($self, $entry, $rec_level) = @_;
  $rec_level = 0 unless (defined $rec_level);
  
  my $top_err = "Error checking media file chunk $entry: ";

  # message prefix
  my $prefix = "  " x $rec_level;
  $prefix .= "  ";
  
  my $res = 0;

  # create temporary file
  my ($fh, $file) = tempfile();
  close($fh);
  unless (-f $file && -r $file) {
    $self->error($top_err . "Unable to create temporary file: $!");
    goto outta_check;
  }
  
  if ($self->{debug}) {
    $self->bufApp($prefix . "Checking entry $entry to file $file.");
  }
  
  my $ua = $self->getUa();
  my $ts = time();

  my %opts = ();
  $opts{Host} = $self->{host_header} if ($self->{host_header});
  $opts{Host} = $self->{headerHost} if ($self->{headerHost});

  my $r = $ua->get($entry, %opts, ':content_file' => $file);
  my $duration = time() - $ts;
  unless (defined $r && $r->is_success()) {
    $self->error($top_err . $r->status_line());
    goto outta_check;
  }
  
  # try to stat the file
  my @s = stat($file);
  unless (@s) {
    $self->error($top_err . "Unable to stat file $file: $!");
    goto outta_check;
  }
  my $size = $s[7] || 0;
  unless ($size > 0) {
    $self->error($top_err . "Downloaded null-length file.");
    goto outta_check;
  }
  
  $res = 1;
  outta_check:
  
  unlink($file);
  my $status = ($res) ?
    "Successfully downloaded $s[7] bytes of media file "
    :
    "Failed to download media file ";

  $self->bufApp(
    $prefix .
    $status .
    sprintf("in %-.3f msec ", $duration  * 1000) . 
    "(" . int($size / $duration). " B/sec) " .
    "[$entry]"
  );

  return $res;
}

sub _err {
  my $err = CORE::shift;
  $err =~ s/^(.+)\s+at\s+\/.*/$1/g;
  return $err;
}

=head1 SEE ALSO

=over

=item L<P9::AA::Check::HTTPLiveStreaming::PlayList>

=item L<P9::AA::Check::URL>

=item L<P9::AA::Check>

=back

=head1 AUTHOR

Brane F. Gracnar

=cut

1;