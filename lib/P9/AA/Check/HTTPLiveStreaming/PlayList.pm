package P9::AA::Check::HTTPLiveStreaming::PlayList;

use strict;
use warnings;

use base 'P9::AA::Base';

use Carp;
use Scalar::Util qw(blessed);

our $AUTOLOAD;
our $VERSION = 0.10;

my $_parse_rec_level = undef;

# Extended M3U parser tags...
# See: http://tools.ietf.org/html/draft-pantos-http-live-streaming-06
my $_m3u_tags = [
  [
    'EXTINF',
    sub {
      my $r = {
        artist => undef,
        title => undef,
        length => 0
      };

      my ($len, $artist_title) = split(/\s*,+\s*/, $_[0], 2);
      {no warnings; $len += 0; $r->{length} = $len };
      if (defined $artist_title) {
        my ($artist, $title) = split(/\s*\-+\s*/, $artist_title, 2);
          if (defined $title) {
            $r->{artist} = $artist;
            $r->{title} = $title;
          } else {
            $r->{title} = $artist_title;
          }
        }
        return 0;
    }
  ],

  #3.3.1.  EXT-X-TARGETDURATION
  #
  #   The EXT-X-TARGETDURATION tag specifies the maximum media file
  #   duration.  The EXTINF duration of each media file in the Playlist
  #   file MUST be less than or equal to the target duration.  This tag
  #   MUST appear once in the Playlist file.  Its format is:
  #
  #   #EXT-X-TARGETDURATION:<s>
  #
  #   where s is an integer indicating the target duration in seconds.
  [
    qr/^EXT-X-TARGETDURATION/i,
    sub {
        my ($key, $val, $obj) = @_;
        no warnings;
		$obj->target_duration(abs(int($_[0])));
		return 0;
	}
  ],

  #3.3.2.  EXT-X-MEDIA-SEQUENCE
  #
  #   Each media file URI in a Playlist has a unique integer sequence
  #   number.  The sequence number of a URI is equal to the sequence number
  #   of the URI that preceded it plus one.  The EXT-X-MEDIA-SEQUENCE tag
  #   indicates the sequence number of the first URI that appears in a
  #   Playlist file.  Its format is:
  #
  #   #EXT-X-MEDIA-SEQUENCE:<number>
  #
  #   A Playlist file MUST NOT contain more than one EXT-X-MEDIA-SEQUENCE
  #   tag.  If the Playlist file does not contain an EXT-X-MEDIA-SEQUENCE
  #   tag then the sequence number of the first URI in the playlist SHALL
  #   be considered to be 0.
  #
  #   A media file's sequence number is not required to appear in its URI.
  #
  #   See Section 6.3.2 and Section 6.3.5 for information on handling the
  #   EXT-X-MEDIA-SEQUENCE tag.
  [
    qr/^EXT-XMEDIA-SEQUENCE/i,
    sub {
      
    }
  ],

  #3.3.3.  EXT-X-KEY
  #
  #   Media files MAY be encrypted.  The EXT-X-KEY tag provides information
  #   necessary to decrypt media files that follow it.  Its format is:
  #
  #   #EXT-X-KEY:<attribute-list>
  #
  #   The following attributes are defined:
  #
  #   The METHOD attribute specifies the encryption method.  It is of type
  #   enumerated-string.  Each EXT-X-KEY tag MUST contain a METHOD
  #   attribute.
  #
  #   Two methods are defined: NONE and AES-128
  [
    qr/^EXT-X-KEY/i,
    sub {
      
    }
  ],

  #3.3.4.  EXT-X-PROGRAM-DATE-TIME
  #
  #   The EXT-X-PROGRAM-DATE-TIME tag associates the beginning of the next
  #   media file with an absolute date and/or time.  The date/time
  #   representation is ISO/IEC 8601:2004 [ISO_8601] and SHOULD indicate a
  #   time zone.  For example:
  #
  #   #EXT-X-PROGRAM-DATE-TIME:<YYYY-MM-DDThh:mm:ssZ>
  #
  #   See Section 6.2.1 and Section 6.3.3 for more information on the EXT-
  #   X-PROGRAM-DATE-TIME tag.
  [
    qr/^EXT-X-PROGRAM-DATE-TIME/i,
    sub {
      
    }
  ],

  #3.3.5.  EXT-X-ALLOW-CACHE
  #
  #   The EXT-X-ALLOW-CACHE tag indicates whether the client MAY or MUST
  #   NOT cache downloaded media files for later replay.  It MAY occur
  #   anywhere in the Playlist file; it MUST NOT occur more than once.  The
  #   EXT-X-ALLOW-CACHE tag applies to all segments in the playlist.  Its
  #   format is:
  #
  #   EXT-X-ALLOW-CACHE:<YES|NO>
  [
    qr/^EXT-X-ALLOW-CACHE/i,
    sub {
      
    }
  ],

  #3.3.6.  EXT-X-PLAYLIST-TYPE
  #
  #   The EXT-X-PLAYLIST-TYPE tag provides mutability information about the
  #   Playlist file.  It is optional.  Its format is:
  #
  #   #EXT-X-PLAYLIST-TYPE:<EVENT|VOD>
  #
  #   Section 6.2.1 defines the implications of the EXT-X-PLAYLIST-TYPE
  #   tag.
  [
    qr/^EXT-X-PLAYLIST-TYPE/,
    sub {
      
    },
  ],

  #3.3.7.  EXT-X-ENDLIST
  #
  #   The EXT-X-ENDLIST tag indicates that no more media files will be
  #   added to the Playlist file.  It MAY occur anywhere in the Playlist
  #   file; it MUST NOT occur more than once.  Its format is:
  #
  #   EXT-X-ENDLIST
  [
    qr/^EXT-X-ENDLIST/i,
    sub {
      
    }
  ],

  #3.3.8.  EXT-X-STREAM-INF
  #
  #   The EXT-X-STREAM-INF tag indicates that the next URI in the Playlist
  #   file identifies another Playlist file.  Its format is:
  #
  #   #EXT-X-STREAM-INF:<attribute-list>
  #   <URI>
  #
  #   The following attributes are defined:
  #
  #   BANDWIDTH
  #
  #   The value is a decimal-integer of bits per second.  It MUST be an
  #   upper bound of the overall bitrate of each media file, calculated to
  #   include container overhead, that appears or will appear in the
  #   Playlist.
  #
  #   Every EXT-X-STREAM-INF tag MUST include the BANDWIDTH attribute.
  #
  #   PROGRAM-ID
  #
  #   The value is a decimal-integer that uniquely identifies a particular
  #   presentation within the scope of the Playlist file.
  #
  #   A Playlist file MAY contain multiple EXT-X-STREAM-INF tags with the
  #   same PROGRAM-ID to identify different encodings of the same
  #   presentation.  These variant playlists MAY contain additional EXT-X-
  #   STREAM-INF tags.
  #
  #   CODECS
  #
  #   The value is a quoted-string containing a comma-separated list of
  #   formats, where each format specifies a media sample type that is
  #   present in a media file in the Playlist file.  Valid format
  #   identifiers are those in the ISO File Format Name Space defined by
  #   RFC 4281 [RFC4281].
  #
  #   Every EXT-X-STREAM-INF tag SHOULD include a CODECS attribute.
  #
  #   RESOLUTION
  #
  #   The value is a decimal-resolution describing the approximate encoded
  #   horizontal and vertical resolution of video within the stream.
  [
    qr/^EXT-X-STREAM-INF$/i,
    sub {
      my ($key, $val, $res, $ctx, $line_num) = @_;
      if (defined $key && ! defined $val) {
        # create new playlist
        my $pl = $res->parse_url($key);
                
        # add attributes
        if (exists($ctx->{bandwidth})) {
          no warnings;
          $pl->bandwidth(abs(int($ctx->{bandwidth})));          
        }
        if (exists($ctx->{'program-id'})) {
          no warnings;
          $pl->program_id(abs(int($ctx->{'program-id'})));
        }
        if (exists $ctx->{codecs}) {
          $pl->codecs(split(/\s*,+\s*/, $ctx->{codecs}));
        }
        $pl->resolution($ctx->{resolution}) if (exists $ctx->{resolution});
        
        # add new playlist...
        $res->playlist_push($pl);

        # this is it...
        return 0;
      }
      
      # parse attributes
      my %h;
      foreach (split(/\s*,\s*/, $key)) {
        my ($key, $val) = split(/\s*=+\s*/, $_, 2);
        next unless (defined $key && defined $val);
        $key = lc($key);
        $key =~ s/^\s+//g;
        $key =~ s/\s+$//g;
        next unless (length $key);
        $ctx->{$key} = $val;
      }
      
      # this parsing sub should be re-run (with )
      return 1;
    }
  ],

  #3.3.9.  EXT-X-DISCONTINUITY
  #
  #   The EXT-X-DISCONTINUITY tag indicates an encoding discontinuity
  #   between the media file that follows it and the one that preceded it.
  #   The set of characteristics that MAY change is:
  #
  #   o  file format
  #
  #   o  number and type of tracks
  #
  #   o  encoding parameters
  #
  #   o  encoding sequence
  #
  #   o  timestamp sequence
  #
  #   Its format is:
  #
  #   #EXT-X-DISCONTINUITY
  #
  #   See Section 4, Section 6.2.1, and Section 6.3.3 for more information
  #   about the EXT-X-DISCONTINUITY tag.
  [
    qr/^EXT-X-DISCONTINUITY/i,
    sub {
      my ($key, $val, $res, $ctx, $line_num) = @_;
      return 0;
    }
  ],

  #3.3.10.  EXT-X-VERSION
  #
  #   The EXT-X-VERSION tag indicates the compatibility version of the
  #   Playlist file.  The Playlist file, its associated media, and its
  #   server MUST comply with all provisions of the most-recent version of
  #   this document describing the protocol version indicated by the tag
  #   value.
  #
  #   Its format is:
  #
  #   EXT-X-VERSION:<n>
  #
  #   where n is an integer indicating the protocol version.
  #
  #   A Playlist file MUST NOT contain more than one EXT-X-VERSION tag.  A
  #   Playlist file that does not contain an EXT-X-VERSION tag MUST comply
  #   with version 1 of this protocol.
  [
    qr/^EXT-X-VERSION/i,
    sub {
      my ($key, $val, $res, $ctx, $line_num) = @_;
      no warnings;
      $res->version(abs(int($val)));
      return 0;
    }
  ],
];

=head1 NAME

L<HTTP Live Streaming playlist|http://tools.ietf.org/html/draft-pantos-http-live-streaming-06> class.

=head1 METHODS

=cut

sub _init {
	my $self = shift;
	
	$self->{_entries} = [];
	$self->{_playlists} = [];

	return $self;
}

=head2 parse

 my $playlist = eval { $pl->parse($string) }

Returns parsed playlist object representing playlist file contained
in $buf on success. Croaks on error.

=cut
sub parse {
  my ($self, $body) = @_;

  my $res = __PACKAGE__->new();

  # check if it complies with m3u playlist format...
  # http://en.wikipedia.org/wiki/M3U
  # http://schworak.com/programming/music/playlist_m3u.asp

  my $first_line_passed = 0;
  my $i = 0;
  my @lines = split(/[\r\n]+/, $body);
  while (@lines) {
    $i++;
    my $line = CORE::shift(@lines);
    next unless (defined $line);
    $line =~ s/^\s+//g;
    $line =~ s/\s+$//g;
    next unless (length($line) > 0);

    # is this extended m3u?
    unless ($first_line_passed) {
      unless ($line =~ m/^#\s*extm3u\s*$/i) {
        $self->error("Playlist file is not extended m3u.");
        return undef;
      }
      $first_line_passed = 1;
      next;
    }
		
    # normal m3u extended stuff
    if ($line =~ m/^#\s*([a-z\-0-9]+):(.+)/i) {
      my $key = uc($1);
      my $val = $2;

      foreach my $e (@{$_m3u_tags}) {
        if ($key =~ $e->[0]) {

          # run coderef until handler is satisfied...
          my $ctx = {};   # parsing sub context
          while (1) {
            # run parsing sub
            local $@;
            my $r = eval { $e->[1]->($key, $val, $res, $ctx, $i) };
            if ($@) {
              $self->error("Error parsing line $i: $@");
              return undef;
            }
            
            # another run of the same sub?
            last if (! defined $r || $r == 0);
            
            # we'll run the same parsing sub
            # once again
            $key = CORE::shift(@lines);
            $val = undef;
          }
          
          # this tag has been parsed
          last;
        }
      }
    
    # hm, this must be just a playlist entry...
    } else {
      $res->push($line);
    }
  }

  return $res;
}

=head2 parse_url

 my $playlist = eval { $pl->parse_url($url) };

Parses playlist located at specified URL. Returns parsed playlist
object on success. Croaks on error.

=cut
sub parse_url {
  my ($self, $url) = @_;
  my $ua = $self->ua();
  
  $_parse_rec_level = 0 unless (defined $_parse_rec_level);
  $_parse_rec_level++;
  if ($_parse_rec_level > 9) {
    croak "Playlist contains too deep recursion (current level: $_parse_rec_level";
  }
  
  my $r = $ua->get($url);
  unless (defined $r && $r->is_success()) {
    no warnings;
    my $err = eval { $r->status_line() };
    Carp::croak "Unable to fetch playlist: $err";
  }
  
  # check content_type
  my $ct = $r->header('Content-Type');
  $self->_is_playlist_content_type($ct);
  
  # try to parse it...
  my $pl = $self->parse($r->decoded_content());
  
  $_parse_rec_level--;
  $_parse_rec_level = undef if ($_parse_rec_level <= 0);
  
  unless (defined $pl) {
    croak "Error parsing playlist: " . $self->error();
  }

  $pl->url($url);
  $pl->setDescription("Playlist " . $url);
  return $pl;
}

=head2 playlists

 my $num = $pl->playlists();
 my @list = $pl->playlists();

Returns number of embedded playlist objects in scalar context; returns
list of embedded playlist objects in list context.

=cut
sub playlists {
  my $self = shift;
  if (@_) {
    @{$self->{_playlists}} = @_;
  } else {
    return wantarray ?
      @{$self->{_playlists}}
      :
      ($#{$self->{_playlists}} + 1);
  }
}

=head2 playlist_push

 $playlist->playlist_push($pl2);

Pushes provided arguments to internal list of embedded playlists.

=cut
sub playlist_push {
  my $self = shift;
  push(@{$self->{_playlists}}, @_);
}

=head2 playlist_pop

 my $pl = $playlist->playlist_pop();

=cut
sub playlist_pop {
  my $self = shift;
  pop(@{$self->{_playlists}});
}

=head2 playlist_shift

 my $pl = $playlist->playlist_push();

=cut
sub playlist_shift {
  my $self = shift;
  shift(@{$self->{_playlists}});
}

=head2 playlist_unshift

 $playlist->playlist_unshift($pl2);

=cut
sub playlist_unshift {
  my $self = shift;
  unshift(@{$self->{_playlists}}, @_);
}

=head2 entries

 my $num = $playlist->entries();
 my @list = $playlist->entries();

Returns list of playlist entries in list context, returns number
of playlist entries in scalar context.

=cut
sub entries {
  my $self = shift;
  if (@_) {
    @{$self->{_entries}} = @_;
  }
  
  return wantarray ?
    @{$self->{_entries}}
    :
    ($#{$self->{_entries}} + 1);
}

=head2 entry

 my $e = $playlist->entry(0);

Returns playlist entry with specified index on success, otherwise undef.

=cut
sub entry {
  my ($self, $idx) = @_;
  return undef unless (defined $idx && $idx >= 0);
  return (defined $self->{_entries}->[$idx]) ?
    $self->{_entries}->[$idx] : undef;
}

=head2 push

 $playlist->push($entry);

Adds new playlist entry.

=cut
sub push {
  my $self = CORE::shift;
  CORE::push(@{$self->{_entries}}, @_);
}

=head2 pop

 my $entry = $playlist->pop();

Removes entry from the end of internal list.

=cut
sub pop {
  my $self = CORE::shift;
  CORE::pop(@{$self->{_entries}});
}

=head2 shift

 my $entry = $playlist->shift();

Removes first entry from internal list.

=cut
sub shift {
  my $self = CORE::shift;
  CORE::shift(@{$self->{_entries}});
}

=head2 unshift

 $playlist->unshift($entry);

Adds entry to the beginning of internal list.

=cut
sub unshift {
  my $self = CORE::shift;
  CORE::unshift(@{$self->{_entries}}, @_);
}

=head2 ua

 my $ua = $playlist->ua();
 $playlist->ua($ua);

Gets/sets L<LWP::UserAgent> used by playlist checker.

=cut
sub ua {
  my $self = CORE::shift;
  if (@_) {
    unless (defined $_[0] && blessed($_[0]) && $_[0]->isa('LWP::UserAgent')) {
      croak "Bad user-agent: " . $_[0];
    }
    $self->{_ua} = $_[0];
  }
  
  # try to get user-agent...
  unless (defined $self->{_ua}) {
    require LWP::UserAgent;
    $self->{_ua} = LWP::UserAgent->new(timeout => 5);
  }
  
  return $self->{_ua};
}

sub _is_playlist_content_type {
  my ($self, $ct) = @_;
  if (defined $ct) {
    $ct =~ s/\s*;.*$//g;
    $ct =~ s/^\s+//g;
    $ct =~ s/\s+$//g;
    $ct = undef unless (length($ct) > 0);
  }
  unless (
    defined $ct &&
    (
      $ct =~ m/^application\/(?:x-)?vnd\.apple\.mpegurl$/i ||
      $ct =~ m/^audio\/(?:x-)?+mpegurl$/i
     )) {
    no warnings;
    Carp::croak "Invalid playlist content-type: '$ct'";
    return 0;
  }

  return 1;
}

sub _err {
  my $err = CORE::shift;
  $err =~ s/^(.+)\s+at\s+\/.*/$1/g;
  return $err;
}

sub AUTOLOAD {
  my $self = CORE::shift;
  my $type = ref($self);# or Carp::croak "$self is not an object";

  my $name = $AUTOLOAD;
  $name =~ s/.*://;   # strip fully-qualified portion
  unless (defined $name && length $name && $name !~ m/^_/) {
    croak "Can't access `$name' field in class $type";
  }

  # getter/setter
  if (@_) {
    return $self->{$name} = CORE::shift;
  } else {
    return $self->{$name};
  }
}

=head1 SEE ALSO

=over

=item L<HTTP Live Streaming IETF draft|http://tools.ietf.org/html/draft-pantos-http-live-streaming-06>

=item L<HTTP Live streaming presentation|http://issuu.com/andruby/docs/http_live_streaming_presentatino>

=item L<HTTP Live streaming in GNU environment|http://blog.kyri0s.org/post/271121944/deploying-apples-http-live-streaming-in-a-gnu-linux>

=item L<P9::AA::Check::HTTPLiveStreaming>

=back

=head1 AUTHOR

Brane F. Gracnar

=cut

1;