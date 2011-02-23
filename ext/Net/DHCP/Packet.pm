# Net::DHCP::Packet.pm
# Original Author: F. van Dun, S. Hadinger
# Author : D. Hamstead

package Net::DHCP::Packet;

# standard module declaration
use 5.8.0;
use strict;
our (@ISA, @EXPORT, @EXPORT_OK, $VERSION);
use Exporter;
$VERSION = 0.67;
@ISA = qw(Exporter);
@EXPORT = qw( packinet packinets unpackinet unpackinets );
@EXPORT_OK = qw( );

use Socket;
use Carp;
use Net::DHCP::Constants qw(:DEFAULT :dhcp_hashes :dhcp_other %DHO_FORMATS);
use Scalar::Util qw(looks_like_number);   # for numerical testing

#=======================================================================
sub new {
  my $class = shift;
  
  my $self = {  options => {},          # DHCP options
                options_order => []     # order in which the options were added
            };
  bless $self, $class;
  if (scalar @_ == 1) { # we build the packet from a binary string
    $self->marshall(shift);
  } else {
    my %args = @_;
    my @ordered_args = @_;
    exists($args{Comment})? $self->comment($args{Comment})  : $self->{comment} = undef;
    exists($args{Op})     ? $self->op($args{Op})            : $self->{op} = BOOTREQUEST();
    exists($args{Htype})  ? $self->htype($args{Htype})      : $self->{htype} = 1; # 10mb ethernet
    exists($args{Hlen})   ? $self->hlen($args{Hlen})        : $self->{hlen} = 6; # Use 6 bytes MAC
    exists($args{Hops})   ? $self->hops($args{Hops})        : $self->{hops} = 0;
    exists($args{Xid})    ? $self->xid($args{Xid})          : $self->{xid} = 0x12345678;
    exists($args{Secs})   ? $self->secs($args{Secs})        : $self->{secs} = 0;
    exists($args{Flags})  ? $self->flags($args{Flags})      : $self->{flags} = 0;
    exists($args{Ciaddr}) ? $self->ciaddr($args{Ciaddr})    : $self->{ciaddr} = "\0\0\0\0";
    exists($args{Yiaddr}) ? $self->yiaddr($args{Yiaddr})    : $self->{yiaddr} = "\0\0\0\0";
    exists($args{Siaddr}) ? $self->siaddr($args{Siaddr})    : $self->{siaddr} = "\0\0\0\0";
    exists($args{Giaddr}) ? $self->giaddr($args{Giaddr})    : $self->{giaddr} = "\0\0\0\0";
    exists($args{Chaddr}) ? $self->chaddr($args{Chaddr})    : $self->{chaddr} = "";
    exists($args{Sname})  ? $self->sname($args{Sname})      : $self->{sname} = "";
    exists($args{File})   ? $self->file($args{File})        : $self->{file} = "";
    exists($args{Padding})? $self->padding($args{Padding})  : $self->{padding} = "";
    exists($args{IsDhcp}) ? $self->isDhcp($args{IsDhcp})    : $self->{isDhcp} = 1;

    # TBM add DHCP option parsing
    while (defined(my $key = shift(@ordered_args))) {
      my $value = shift(@ordered_args);
      my $is_numeric;
      {
      	no warnings;
      	$is_numeric = ($key eq (0 + $key));
      }
      if ($is_numeric) {
      	$self->addOptionValue($key, $value);
      }
    }
  }
  return $self;
}
#=======================================================================
# comment attribute : enables transaction number identification
sub comment {
    my $self = shift;
    if (@_) { $self->{comment} = shift } 
    return $self->{comment};
} 

# op attribute
sub op {
    my $self = shift;
    if (@_) { $self->{op} = shift } 
    return $self->{op};
} 

# htype attribute
sub htype {
  my $self = shift;
  if (@_) { $self->{htype} = shift }
  return $self->{htype};
}

# hlen attribute
sub hlen {
  my $self = shift;
  if (@_) { $self->{hlen} = shift }
  if ($self->{hlen} < 0) {
    carp("hlen must not be < 0 (currently ".$self->{hlen}.")");
    $self->{hlen} = 0;
  }
  if ($self->{hlen} > 16) {
    carp("hlen must not be > 16 (currently ".$self->{hlen}.")");
    $self->{hlen} = 16;
  }
  return $self->{hlen};
}

# hops attribute
sub hops {
  my $self = shift;
  if (@_) { $self->{hops} = shift }
  return $self->{hops};
}

# xid attribute
sub xid {
  my $self = shift;
  if (@_) { $self->{xid} = shift }
  return $self->{xid};
}

# secs attribute
sub secs {
  my $self = shift;
  if (@_) { $self->{secs} = shift }
  return $self->{secs};
}

# flags attribute
sub flags {
  my $self = shift;
  if (@_) { $self->{flags} = shift }
  return $self->{flags};
}

# ciaddr attribute
sub ciaddr {
  my $self = shift;
  if (@_) { $self->{ciaddr} = packinet(shift) }
  return unpackinet($self->{ciaddr});
}
# ciaddr attribute, Raw version
sub ciaddrRaw {
  my $self = shift;
  if (@_) { $self->{ciaddr} = shift }
  return $self->{ciaddr};
}

# yiaddr attribute
sub yiaddr {
  my $self = shift;
  if (@_) { $self->{yiaddr} = packinet(shift) }
  return unpackinet($self->{yiaddr});
} 
# yiaddr attribute, Raw version
sub yiaddrRaw {
  my $self = shift;
  if (@_) { $self->{yiaddr} = shift }
  return $self->{yiaddr};
} 

# siaddr attribute
sub siaddr {
  my $self = shift;
  if (@_) { $self->{siaddr} = packinet(shift) }
  return unpackinet($self->{siaddr});
}
# siaddr attribute, Raw version
sub siaddrRaw {
  my $self = shift;
  if (@_) { $self->{siaddr} = shift }
  return $self->{siaddr};
}

# giaddr attribute
sub giaddr {
  my $self = shift;
  if (@_) { $self->{giaddr} = packinet(shift) }
  return unpackinet($self->{giaddr});
}
# giaddr attribute, Raw version
sub giaddrRaw {
  my $self = shift;
  if (@_) { $self->{giaddr} = shift }
  return $self->{giaddr};
}

# chaddr attribute
sub chaddr {
  my $self = shift;
  if (@_) { $self->{chaddr} = pack("H*", shift) }
  return unpack("H*", $self->{chaddr});
}
# chaddr attribute, Raw version
sub chaddrRaw {
  my $self = shift;
  if (@_) { $self->{chaddr} = shift }
  return $self->{chaddr};
}

# sname attribute
sub sname {
  use bytes;
  my $self = shift;
  if (@_) { $self->{sname} = shift }
  if (length($self->{sname}) > 63) {
    carp("'sname' must not be > 63 bytes, (currently ".length($self->{sname}).")");
    $self->{sname} = substr($self->{sname}, 0, 63);
  }
  return $self->{sname};
}

# file attribute
sub file {
  use bytes;
  my $self = shift;
  if (@_) { $self->{file} = shift } 
  if (length($self->{file}) > 127) {
    carp("'file' must not be > 127 bytes, (currently ".length($self->{file}).")");
    $self->{file} = substr($self->{file}, 0, 127);
  }
  return $self->{file};
}

# is it DHCP or BOOTP
#   -> DHCP needs magic cookie and options
sub isDhcp {
  my $self = shift;
  if (@_) { $self->{isDhcp} = shift } 
  return $self->{isDhcp};
}

# padding attribute
sub padding {
  my $self = shift;
  if (@_) { $self->{padding} = shift }
  return $self->{padding};
}
#=======================================================================
#sub addOption {               # deprecated
#  my $self = shift;
#  return $self->addOptionRaw(@_);
#}

sub addOptionRaw {
  my ($self,$key,$value_bin) = @_;
  $self->{options}->{$key} = $value_bin;
  push @{$self->{options_order}}, ($key);
}

sub addOptionValue($$$) {
  my $self = shift;
  my $code = shift;           # option code
  my $value = shift;
  my $value_bin;              # option value in binary format
  my $format = '';            # format for the option

  carp("addOptionValue: unknown format for code ($code)") unless exists($DHO_FORMATS{$code});
  $format = $DHO_FORMATS{$code} if exists($DHO_FORMATS{$code});

  # decompose input value into an array
  my @values;
  if (defined($value) && ($value ne '')) {
    @values = split(/[\s\/,;]+/, $value);      # array of values, split by space
  }
  
  # verify number of parameters
  if ($format eq 'string') {
    @values = ($value);                         # don't change format
  } elsif ($format =~ /s$/) {      # ends with an 's', meaning any number of parameters
    ;
  } elsif ($format =~ /2$/) { # ends with a '2', meaning couples of parameters
    croak("addOptionValue: only pairs of values expected for option '$code'") if ((@values % 2) != 0);
  } else {                    # only one parameter
    croak("addOptionValue: exactly one value expected for option '$code'") if (@values != 1);
  }

  if ($format eq 'inet') {
    $value_bin = packinet($values[0]);
  } elsif (($format eq 'inets') || ($format eq 'inets2')) {
    $value_bin = packinets_array(@values);
  } elsif ($format eq 'int') {
    $value_bin = pack('N', $values[0]);
  } elsif ($format eq 'short') {
    $value_bin = pack('n', $values[0]);
  } elsif ($format eq 'byte') {
    $value_bin = pack('C', $values[0]);
  } elsif ($format eq 'bytes') {
    $value_bin = pack('C*', @values);
  } elsif ($format eq 'string') {
    $value_bin = $values[0];
#  } elsif ($format eq 'relays') {
#    $value_bin = $self->encodeRelayAgent(@values);
#  } elsif ($format eq 'ids') {
#    $value_bin = $values[0];
#    # TBM bad format
  } else {
    $value_bin = $values[0];
  }

  $self->addOptionRaw($code, $value_bin);
}

#sub getOption {               # deprecated
#  my $self = shift;
#  return $self->getOptionRaw(@_);
#}

sub getOptionRaw {
  my ($self,$key) = @_;
  return $self->{options}->{$key} if exists($self->{options}->{$key});
  return undef;
}

sub getOptionValue($$) {
  my $self = shift;
  my ($code) = @_;
  my $format = '';

  carp("getOptionValue: unknown format for code ($code)") unless exists($DHO_FORMATS{$code});
  $format = $DHO_FORMATS{$code} if exists($DHO_FORMATS{$code});
  my $value_bin = $self->getOptionRaw($code);
  return undef unless defined($value_bin);
  my @values = ();
  
  if ($format eq 'inet') {
    $values[0] = unpackinet($value_bin);
  } elsif (($format eq 'inets') || ($format eq 'inets2')) {
    @values = unpackinets_array($value_bin);
  } elsif ($format eq 'int') {
    $values[0] = unpack('N', $value_bin);
  } elsif ($format eq 'short') {
    $values[0] = unpack('n', $value_bin);
  } elsif ($format eq 'shorts') {
    @values = unpack('n*', $value_bin);
  } elsif ($format eq 'byte') {
    $values[0] = unpack('C', $value_bin);
  } elsif ($format eq 'bytes') {
    @values = unpack('C*', $value_bin);
  } elsif ($format eq 'string') {
    $values[0] = $value_bin;
#  } elsif ($format eq 'relays') {
#    @values = $self->decodeRelayAgent($value_bin);
#    # TBM, bad format
#  } elsif ($format eq 'ids') {
#    $values[0] = $value_bin;
#    # TBM, bad format
  } else {
    $values[0] = $value_bin;
  }

  return join(" ", @values); 
#  return wantarray ? @values : $values[0];
}

sub removeOption {
  my ($self,$key) = @_;
  if (exists($self->{options}->{$key})) {
    my $i;
    for ($i = 0; $i < @{$self->{options_order}}; $i++) {
      last if ($self->{options_order}->[$i] == $key);
    }
    if ($i < @{$self->{options_order}}) {
      splice @{$self->{options_order}},$i,1;
    }
    delete ($self->{options}->{$key});
  }
}

#=======================================================================
my $BOOTP_FORMAT = 'C C C C N n n a4 a4 a4 a4 a16 Z64 Z128 a*';
#my $DHCP_MIN_LENGTH = length(pack($BOOTP_FORMAT));
#=======================================================================
sub serialize {
  use bytes;
  my ($self) = shift;
  my $options = shift;    # reference to an options hash for special options
  my $bytes = undef;
  
  $bytes = pack($BOOTP_FORMAT,      
    $self->{op},
    $self->{htype},
    $self->{hlen},
    $self->{hops},
    $self->{xid},
    $self->{secs},
    $self->{flags},
    $self->{ciaddr},
    $self->{yiaddr},
    $self->{siaddr},
    $self->{giaddr},
    $self->{chaddr},
    $self->{sname},
    $self->{file}
    );
  
  if ($self->{isDhcp}) {    # add MAGIC_COOKIE and options
    $bytes .= MAGIC_COOKIE(); 
    foreach my $key ( @{$self->{options_order}} ) {
      $bytes .= pack('C', $key);
      $bytes .= pack('C/a*', $self->{options}->{$key});
    }
    $bytes .= pack('C', 255);
  }
  
  $bytes .= $self->{padding};   # add optional padding
  
  # add padding if packet is less than minimum size
  my $min_padding = BOOTP_MIN_LEN() - length($bytes);
  if ($min_padding > 0) {
    $bytes .= "\0" x $min_padding;
  }
  
  # test if packet is not bigger than absolute maximum MTU
  if (length($bytes) > DHCP_MAX_MTU()) {
    croak("serialize: packet too big (".length($bytes)." greater than max MAX_MTU (".DHCP_MAX_MTU());
  }
  
  # test if packet length is not bigger than DHO_DHCP_MAX_MESSAGE_SIZE
  if ($options && exists($options->{DHO_DHCP_MAX_MESSAGE_SIZE()})) {    # maximum packet size is specified
    my $max_message_size = $options->{DHO_DHCP_MAX_MESSAGE_SIZE()};
    if (($max_message_size >= BOOTP_MIN_LEN()) && ($max_message_size < DHCP_MAX_MTU())) {
      # relevant message size
      if (length($bytes) > $max_message_size) {
        croak("serialize: message is bigger than allowed (".length($bytes)."), max specified :".$max_message_size);
      }
    }
  }

  return $bytes;
}
#=======================================================================
sub marshall {
  use bytes;
  my ($self, $buf) = @_;
  my $opt_buf;
  
  if (length($buf) < BOOTP_ABSOLUTE_MIN_LEN()) {
    croak("marshall: packet too small (".length($buf)."), absolute minimum size is ".BOOTP_ABSOLUTE_MIN_LEN());
  }
  if (length($buf) < BOOTP_MIN_LEN()) {
    carp("marshall: packet too small (".length($buf)."), minimum size is ".BOOTP_MIN_LEN());
  }
  if (length($buf) > DHCP_MAX_MTU()) {
    croak("marshall: packet too big (".length($buf)."), max MTU size is ".DHCP_MAX_MTU());
  }

  # if we are re-using this object, then we need to clear out these arrays
  delete $self->{options}
      if $self->{options};
  delete $self->{options_order}
      if $self->{options_order};
  
  (
  $self->{op},
  $self->{htype},
  $self->{hlen},
  $self->{hops},
  $self->{xid},
  $self->{secs},
  $self->{flags},
  $self->{ciaddr},
  $self->{yiaddr},
  $self->{siaddr},
  $self->{giaddr},
  $self->{chaddr},
  $self->{sname},
  $self->{file},
  $opt_buf ) = unpack($BOOTP_FORMAT, $buf);

  $self->{isDhcp} = 0;      # default to BOOTP
  if ((length($opt_buf) > 4) && (substr($opt_buf,0,4) eq MAGIC_COOKIE())) {
    # it is definitely DHCP
    $self->{isDhcp} = 1;

    my $pos = 4;  # Skip magic cookie
    my $total = length($opt_buf);
    my $type;
  
    while ($pos < $total) {
      $type = ord(substr($opt_buf,$pos++,1));
      next if ($type eq DHO_PAD());       # Skip padding bytes
      last if ($type eq DHO_END());       # Type 'FF' signals end of options.
      my $len = ord(substr($opt_buf,$pos++,1));
      my $option = substr($opt_buf,$pos,$len);
      $pos += $len;
      $self->addOptionRaw($type,$option);
    }
    
    # verify that we ended with an "END" code
    if ($type != DHO_END()) {
      croak("marshall: unexpected end of options");
    }
    
    # put remaining bytes in the padding attribute
    if ($pos < $total) {
      $self->{padding} = substr($opt_buf, $pos, $total-$pos);
    } else {
      $self->{padding} = '';
    }
  } else {
    # in bootp, everything is padding
    $self->{padding} = $opt_buf;
  }
  
  return $self;
}
#=======================================================================
sub decodeRelayAgent($$) {
  use bytes;
  my $self = shift;
  my ($opt_buf) = @_;
  my @opt = ();
  
  if (length($opt_buf) > 1) {
    my $pos = 0;
    my $total = length($opt_buf);
  
    while ($pos < $total) {
      my $type = ord(substr($opt_buf,$pos++,1));
      my $len = ord(substr($opt_buf,$pos++,1));
      my $option = substr($opt_buf,$pos,$len);
      $pos += $len;
      push @opt, $type, $option;
    }
  }
  return @opt;
}

sub encodeRelayAgent($@) {
  use bytes;
  my $self = shift;
  my @opt = @_;         # expect key-value pairs
  my $buf = '';

  while (defined(my $key= shift(@opt))) {
    my $value = shift(@opt);
    $buf .= pack('C', $key);
    $buf .= pack('C/a*', $value);
  }
  return $buf;
}
#=======================================================================
sub toString {
  my ($self) = @_;
  my $s = "";
  
  $s .= sprintf("comment = %s\n", $self->comment()) if defined($self->comment());
  $s .= sprintf("op = %s\n", (exists($REV_BOOTP_CODES{$self->op()}) && $REV_BOOTP_CODES{$self->op()}) || $self->op());
  $s .= sprintf("htype = %s\n", (exists($REV_HTYPE_CODES{$self->htype()}) && $REV_HTYPE_CODES{$self->htype()}) || $self->htype());
  $s .= sprintf("hlen = %s\n", $self->hlen());
  $s .= sprintf("hops = %s\n", $self->hops());
  $s .= sprintf("xid = %x\n", $self->xid());
  $s .= sprintf("secs = %i\n", $self->secs());
  $s .= sprintf("flags = %x\n", $self->flags());
  $s .= sprintf("ciaddr = %s\n", $self->ciaddr());
  $s .= sprintf("yiaddr = %s\n", $self->yiaddr());
  $s .= sprintf("siaddr = %s\n", $self->siaddr());
  $s .= sprintf("giaddr = %s\n", $self->giaddr());
  $s .= sprintf("chaddr = %s\n", substr($self->chaddr(),0,2 * $self->hlen()));
  $s .= sprintf("sname = %s\n", $self->sname());
  $s .= sprintf("file = %s\n", $self->file());
  $s .= "Options : \n";
  
  foreach my $key ( @{$self->{options_order}} ) {
    my $value;    # value of option to be printed
    
    if ($key == DHO_DHCP_MESSAGE_TYPE()) {
      $value = $self->getOptionValue($key);
      $value = (exists($REV_DHCP_MESSAGE{$value}) && $REV_DHCP_MESSAGE{$value}) || $self->getOptionValue($key);
    } else {
      if (exists($DHO_FORMATS{$key})) {
        $value = join(" ", $self->getOptionValue($key));
      } else {
        $value = $self->getOptionRaw($key);
      }
      $value =~ s/([[:^print:]])/ sprintf q[\x%02X], ord $1 /eg;  # printable text
    }    
    $s .= sprintf(" %s(%d) = %s\n", exists $REV_DHO_CODES{$key} ? $REV_DHO_CODES{$key}: '', $key, $value);
  }
  $s .= sprintf("padding [%s] = %s\n", length($self->{padding}), unpack('H*', $self->{padding}));
  
  return $s;
}
#=======================================================================
# internal utility functions
# never failing versions of the "Socket" module functions
sub unpackinet($) {		# bullet-proof version, never complains
	use bytes;
	my $ip = shift;
	return '0.0.0.0' if (length($ip) != 4);
	return ord(substr($ip,0,1)).'.'.ord(substr($ip,1,1)).'.'.
				 ord(substr($ip,2,1)).'.'.ord(substr($ip,3,1));
}

sub packinet($) {		# bullet-proof version, never complains
	use bytes;
	my $addr = shift;
	if ($addr =~ /(\d+)\.(\d+)\.(\d+)\.(\d+)/) {
  	return chr($1).chr($2).chr($3).chr($4);
	}
  return "\0\0\0\0";
}

sub packinets($) {    # multiple ip addresses, space delimited
  return join('', map { packinet($_) } split(/[\s\/,;]+/, shift));
}

sub packinets_array(@) {    # multiple ip addresses, space delimited
  return join('', map { packinet($_) } @_);
}

sub unpackinets($) {  # multiple ip addresses
  return join(" ", map { unpackinet($_) } unpack("(a4)*", shift));
}

sub unpackinets_array($) {  # multiple ip addresses, returns an array
  return map { unpackinet($_) } unpack("(a4)*", shift);
}

sub unpackRelayAgent(%) { # prints a human readable 'relay agent options'
  my %relay_opt = @_;
  return join(",", map { "($_)=".$relay_opt{$_} } (sort keys %relay_opt));
}

#=======================================================================

1;

=pod

=head1 NAME

Net::DHCP::Packet - Object methods to create a DHCP packet.

=head1 SYNOPSIS

   use Net::DHCP::Packet;

   my $p = new Net::DHCP::Packet->new(
        'Chaddr' => '000BCDEF', 
        'Xid' => 0x9F0FD,
        'Ciaddr' => '0.0.0.0',
        'Siaddr' => '0.0.0.0',
        'Hops' => 0);

=head1 DESCRIPTION

Represents a DHCP packet as specified in RFC 1533, RFC 2132.

=head1 CONSTRUCTOR

This module only provides basic constructor. For "easy" constructors, you can use
the L<Net::DHCP::Session> module.  

=over 4

=item new( )

=item new( BUFFER )

=item new( ARG => VALUE, ARG => VALUE... )

Creates an C<Net::DHCP::Packet> object, which can be used to send or receive
DHCP network packets. BOOTP is not supported.

Without argument, a default empty packet is created.

  $packet = Net::DHCP::Packet();

A C<BUFFER> argument is interpreted as a binary buffer like one provided
by the socket C<recv()> function. if the packet is malformed, a fatal error
is issued.

   use IO::Socket::INET;
   use Net::DHCP::Packet;
   
   $sock = IO::Socket::INET->new(LocalPort => 67, Proto => "udp", Broadcast => 1)
           or die "socket: $@";
           
   while ($sock->recv($newmsg, 1024)) {
       $packet = Net::DHCP::Packet->new($newmsg);
       print $packet->toString();
   }

To create a fresh new packet C<new()> takes arguments as a key-value pairs :

   ARGUMENT   FIELD      OCTETS       DESCRIPTION
   --------   -----      ------       -----------
   
   Op         op            1  Message op code / message type.
                               1 = BOOTREQUEST, 2 = BOOTREPLY
   Htype      htype         1  Hardware address type, see ARP section in "Assigned
                               Numbers" RFC; e.g., '1' = 10mb ethernet.
   Hlen       hlen          1  Hardware address length (e.g.  '6' for 10mb
                               ethernet).
   Hops       hops          1  Client sets to zero, optionally used by relay agents
                               when booting via a relay agent.
   Xid        xid           4  Transaction ID, a random number chosen by the
                               client, used by the client and server to associate
                               messages and responses between a client and a
                               server.
   Secs       secs          2  Filled in by client, seconds elapsed since client
                               began address acquisition or renewal process.
   Flags      flags         2  Flags (see figure 2).
   Ciaddr     ciaddr        4  Client IP address; only filled in if client is in
                               BOUND, RENEW or REBINDING state and can respond
                               to ARP requests.
   Yiaddr     yiaddr        4  'your' (client) IP address.
   Siaddr     siaddr        4  IP address of next server to use in bootstrap;
                               returned in DHCPOFFER, DHCPACK by server.
   Giaddr     giaddr        4  Relay agent IP address, used in booting via a
                               relay agent.
   Chaddr     chaddr       16  Client hardware address.
   Sname      sname        64  Optional server host name, null terminated string.
   File       file        128  Boot file name, null terminated string; "generic"
                               name or null in DHCPDISCOVER, fully qualified
                               directory-path name in DHCPOFFER.
   IsDhcp     isDhcp        4  Controls whether the packet is BOOTP or DHCP.
                               DHCP conatains the "magic cookie" of 4 bytes.
                               0x63 0x82 0x53 0x63.
   DHO_*code                   Optional parameters field.  See the options
                               documents for a list of defined options.
                               See Net::DHCP::Constants.
   Padding    padding       *  Optional padding at the end of the packet

See below methods for values and syntax descrption.

Note: DHCP options are created in the same order as key-value pairs.

=back

=head1 METHODS

=head2 ATTRIBUTE METHODS

=over 4

=item op( [BYTE] )

Sets/gets the I<BOOTP opcode>.

Normal values are:

  BOOTREQUEST()
  BOOTREPLY()

=item htype( [BYTE] )

Sets/gets the I<hardware address type>.

Common value is: C<HTYPE_ETHER()> (1) = ethernet

=item hlen ( [BYTE] )

Sets/gets the I<hardware address length>. Value must be between C<0> and C<16>.

For most NIC's, the MAC address has 6 bytes.

=item hops ( [BYTE] )

Sets/gets the I<number of hops>.

This field is incremented by each encountered DHCP relay agent. 

=item xid ( [INTEGER] )

Sets/gets the 32 bits I<transaction id>.

This field should be a random value set by the DHCP client.

=item secs ( [SHORT] )

Sets/gets the 16 bits I<elapsed boot time> in seconds.

=item flags ( [SHORT] )

Sets/gets the 16 bits I<flags>.

  0x8000 = Broadcast reply requested.

=item ciaddr ( [STRING])

Sets/gets the I<client IP address>.

IP address is only accepted as a string like '10.24.50.3'.

Note: IP address is internally stored as a 4 bytes binary string.
See L<Special methods> below.

=item yiaddr ( [STRING] )

Sets/gets the I<your IP address>.

IP address is only accepted as a string like '10.24.50.3'.

Note: IP address is internally stored as a 4 bytes binary string.
See L<Special methods> below.

=item siaddr ( [STRING] )

Sets/gets the I<next server IP address>.

IP address is only accepted as a string like '10.24.50.3'.

Note: IP address is internally stored as a 4 bytes binary string.
See L<Special methods> below.

=item giaddr ( [STRING] )

Sets/gets the I<relay agent IP address>.

IP address is only accepted as a string like '10.24.50.3'.

Note: IP address is internally stored as a 4 bytes binary string.
See L<Special methods> below.

=item chaddr ( [STRING] )

Sets/gets the I<client hardware address>. Its length is given by the C<hlen> attribute.

Valude is formatted as an Hexadecimal string representation.

  Example: "0010A706DFFF" for 6 bytes mac address.

Note : internal format is packed bytes string.
See L<Special methods> below.

=item sname ( [STRING] )

Sets/gets the "server host name". Maximum size is 63 bytes. If greater
a warning is issued.

=item file ( [STRING] )

Sets/gets the "boot file name". Maximum size is 127 bytes. If greater
a warning is issued.

=item isDhcp ( [BOOLEAN] )

Sets/gets the I<DHCP cookie>. Returns whether the cookie is valid or not,
hence whether the packet is DHCP or BOOTP.

Default value is C<1>, valid DHCP cookie.

=item padding ( [BYTES] )

Sets/gets the optional padding at the end of the DHCP packet, i.e. after
DHCP options.

=back

=head2 DHCP OPTIONS METHODS

This section describes how to read or set DHCP options. Methods are given
in two flavours : (i) text format with automatic type conversion,
(ii) raw binary format.

Standard way of accessing options is through automatic type conversion,
described in the L<DHCP OPTION TYPES> section. Only a subset of types
is supported, mainly those defined in rfc 2132.

Raw binary functions are provided for pure performance optimization,
and for unsupported types manipulation.

=over 4

=item addOptionValue ( CODE, VALUE )

Adds a DHCP option field. Common code values are listed in
C<Net::DHCP::Constants> C<DHO_>*.

Values are automatically converted according to their data types,
depending on their format as defined by RFC 2132.
Please see L<DHCP OPTION TYPES> for supported options and corresponding
formats.

If you nedd access to the raw binary values, please use C<addOptionRaw()>.

   $pac = Net::DHCP::Packet->new();
   $pac->addOption(DHO_DHCP_MESSAGE_TYPE(), DHCPINFORM());
   $pac->addOption(DHO_NAME_SERVERS(), "10.0.0.1", "10.0.0.2"));

=item getOptionValue ( CODE )

Returns the value of a DHCP option.

Automatic type conversion is done according to their data types,
as defined in RFC 2132.
Please see L<DHCP OPTION TYPES> for supported options and corresponding
formats.

If you nedd access to the raw binary values, please use C<getOptionRaw()>.

Return value is either a string or an array, depending on the context.

  $ip  = $pac->getOptionValue(DHO_SUBNET_MASK());
  $ips = $pac->getOptionValue(DHO_NAME_SERVERS());

=item addOptionRaw ( CODE, VALUE ) 

Adds a DHCP OPTION provided in packed binary format.
Please see corresponding RFC for manual type conversion.

=item getOptionRaw ( CODE )

Gets a DHCP OPTION provided in packed binary format.
Please see corresponding RFC for manual type conversion.

=item I<addOption ( CODE, VALUE )>

I<Removed as of version 0.60. Please use C<addOptionRaw()> instead.>

=item I<getOption ( CODE )>

I<Removed as of version 0.60. Please use C<getOptionRaw()> instead.>

=back

=item I<removeOption ( CODE )>

Remove option from option list.

=back

=head2 DHCP OPTIONS TYPES

This section describes supported option types (cf. rfc 2132).

For unsupported data types, please use C<getOptionRaw()> and
C<addOptionRaw> to manipulate binary format directly.

=over 4

=item dhcp message type

Only supported for DHO_DHCP_MESSAGE_TYPE (053) option.
Converts a integer to a single byte.

Option code for 'dhcp message' format:

  (053) DHO_DHCP_MESSAGE_TYPE

Example:

  $pac->addOptionValue(DHO_DHCP_MESSAGE_TYPE(), DHCPINFORM());

=item string

Pure string attribute, no type conversion.

Option codes for 'string' format:

  (012) DHO_HOST_NAME
  (014) DHO_MERIT_DUMP
  (015) DHO_DOMAIN_NAME
  (017) DHO_ROOT_PATH
  (018) DHO_EXTENSIONS_PATH
  (047) DHO_NETBIOS_SCOPE
  (056) DHO_DHCP_MESSAGE
  (060) DHO_VENDOR_CLASS_IDENTIFIER
  (062) DHO_NWIP_DOMAIN_NAME
  (064) DHO_NIS_DOMAIN
  (065) DHO_NIS_SERVER
  (066) DHO_TFTP_SERVER
  (067) DHO_BOOTFILE
  (086) DHO_NDS_TREE_NAME
  (098) DHO_USER_AUTHENTICATION_PROTOCOL

Example:

  $pac->addOptionValue(DHO_TFTP_SERVER(), "foobar");

=item single ip address

Exactly one IP address, in dotted numerical format '192.168.1.1'.

Option codes for 'single ip address' format:

  (001) DHO_SUBNET_MASK
  (016) DHO_SWAP_SERVER
  (028) DHO_BROADCAST_ADDRESS
  (032) DHO_ROUTER_SOLICITATION_ADDRESS
  (050) DHO_DHCP_REQUESTED_ADDRESS
  (054) DHO_DHCP_SERVER_IDENTIFIER
  (118) DHO_SUBNET_SELECTION

Example:

  $pac->addOptionValue(DHO_SUBNET_MASK(), "255.255.255.0");

=item multiple ip addresses

Any number of IP address, in dotted numerical format '192.168.1.1'.
Empty value allowed.

Option codes for 'multiple ip addresses' format:

  (003) DHO_ROUTERS
  (004) DHO_TIME_SERVERS
  (005) DHO_NAME_SERVERS
  (006) DHO_DOMAIN_NAME_SERVERS
  (007) DHO_LOG_SERVERS
  (008) DHO_COOKIE_SERVERS
  (009) DHO_LPR_SERVERS
  (010) DHO_IMPRESS_SERVERS
  (011) DHO_RESOURCE_LOCATION_SERVERS
  (041) DHO_NIS_SERVERS
  (042) DHO_NTP_SERVERS
  (044) DHO_NETBIOS_NAME_SERVERS
  (045) DHO_NETBIOS_DD_SERVER
  (048) DHO_FONT_SERVERS
  (049) DHO_X_DISPLAY_MANAGER
  (068) DHO_MOBILE_IP_HOME_AGENT
  (069) DHO_SMTP_SERVER
  (070) DHO_POP3_SERVER
  (071) DHO_NNTP_SERVER
  (072) DHO_WWW_SERVER
  (073) DHO_FINGER_SERVER
  (074) DHO_IRC_SERVER
  (075) DHO_STREETTALK_SERVER
  (076) DHO_STDA_SERVER
  (085) DHO_NDS_SERVERS

Example:

  $pac->addOptionValue(DHO_NAME_SERVERS(), "10.0.0.11 192.168.1.10");

=item pairs of ip addresses

Even number of IP address, in dotted numerical format '192.168.1.1'.
Empty value allowed.

Option codes for 'pairs of ip address' format:

  (021) DHO_POLICY_FILTER
  (033) DHO_STATIC_ROUTES

Example:

  $pac->addOptionValue(DHO_STATIC_ROUTES(), "10.0.0.1 192.168.1.254");

=item byte, short and integer

Numerical value in byte (8 bits), short (16 bits) or integer (32 bits)
format.

Option codes for 'byte (8)' format:

  (019) DHO_IP_FORWARDING
  (020) DHO_NON_LOCAL_SOURCE_ROUTING
  (023) DHO_DEFAULT_IP_TTL
  (027) DHO_ALL_SUBNETS_LOCAL
  (029) DHO_PERFORM_MASK_DISCOVERY
  (030) DHO_MASK_SUPPLIER
  (031) DHO_ROUTER_DISCOVERY
  (034) DHO_TRAILER_ENCAPSULATION
  (036) DHO_IEEE802_3_ENCAPSULATION
  (037) DHO_DEFAULT_TCP_TTL
  (039) DHO_TCP_KEEPALIVE_GARBAGE
  (046) DHO_NETBIOS_NODE_TYPE
  (052) DHO_DHCP_OPTION_OVERLOAD
  (116) DHO_AUTO_CONFIGURE

Option codes for 'short (16)' format:

  (013) DHO_BOOT_SIZE
  (022) DHO_MAX_DGRAM_REASSEMBLY
  (026) DHO_INTERFACE_MTU
  (057) DHO_DHCP_MAX_MESSAGE_SIZE

Option codes for 'integer (32)' format:

  (002) DHO_TIME_OFFSET
  (024) DHO_PATH_MTU_AGING_TIMEOUT
  (035) DHO_ARP_CACHE_TIMEOUT
  (038) DHO_TCP_KEEPALIVE_INTERVAL
  (051) DHO_DHCP_LEASE_TIME
  (058) DHO_DHCP_RENEWAL_TIME
  (059) DHO_DHCP_REBINDING_TIME

Examples:

  $pac->addOptionValue(DHO_DHCP_OPTION_OVERLOAD(), 3);
  $pac->addOptionValue(DHO_INTERFACE_MTU(), 1500);
  $pac->addOptionValue(DHO_DHCP_RENEWAL_TIME(), 24*60*60);

=item multiple bytes, shorts

A list a bytes or shorts.

Option codes for 'multiple bytes (8)' format:

  (055) DHO_DHCP_PARAMETER_REQUEST_LIST

Option codes for 'multiple shorts (16)' format:

  (025) DHO_PATH_MTU_PLATEAU_TABLE
  (117) DHO_NAME_SERVICE_SEARCH

Examples:

  $pac->addOptionValue(DHO_DHCP_PARAMETER_REQUEST_LIST(),  "1 3 6 12 15 28 42 72");

=back

=head2 SERIALIZATION METHODS

=over 4

=item serialize ()

Converts a Net::DHCP::Packet to a string, ready to put on the network.

=item marshall ( BYTES )

The inverse of serialize. Converts a string, presumably a 
received UDP packet, into a Net::DHCP::Packet.

If the packet is malformed, a fatal error is produced.

=back

=head2 HELPER METHODS

=over 4

=item toString ()

Returns a textual representation of the packet, for debugging.

=item packinet ( STRING )

Transforms a IP address "xx.xx.xx.xx" into a packed 4 bytes string.

These are simple never failing versions of inet_ntoa and inet_aton.

=item packinets ( STRING )

Transforms a list of space delimited IP addresses into a packed bytes string.

=item unpackinet ( STRING )

Transforms a packed bytes IP address into a "xx.xx.xx.xx" string.

=item unpackinets ( STRING )

Transforms a packed bytes liste of IP addresses into a list of
"xx.xx.xx.xx" space delimited string.

=back

=head2 SPECIAL METHODS

These methods are provided for performance tuning only. They give access
to internal data representation , thus avoiding unnecessary type conversion.

=over 4

=item ciaddrRaw ( [STRING])

Sets/gets the I<client IP address> in packed 4 characters binary strings.

=item yiaddrRaw ( [STRING] )

Sets/gets the I<your IP address> in packed 4 characters binary strings.

=item siaddrRaw ( [STRING] )

Sets/gets the I<next server IP address> in packed 4 characters binary strings.

=item giaddrRaw ( [STRING] )

Sets/gets the I<relay agent IP address> in packed 4 characters binary strings.

=item chaddrRaw ( [STRING] )

Sets/gets the I<client hardware address> in packed binary string.
Its length is given by the C<hlen> attribute.

=back

=head1 EXAMPLES

Sending a simple DHCP packet:

  #!/usr/bin/perl
  # Simple DHCP client - sending a broadcasted DHCP Discover request
  
  use IO::Socket::INET;
  use Net::DHCP::Packet;
  use Net::DHCP::Constants;
  
  # creat DHCP Packet
  $discover = Net::DHCP::Packet->new(
                        xid => int(rand(0xFFFFFFFF)), # random xid
                        Flags => 0x8000,              # ask for broadcast answer
                        DHO_DHCP_MESSAGE_TYPE() => DHCPDISCOVER()
                        );
  
  # send packet
  $handle = IO::Socket::INET->new(Proto => 'udp',
                                  Broadcast => 1,
                                  PeerPort => '67',
                                  LocalPort => '68',
                                  PeerAddr => '255.255.255.255')
                or die "socket: $@";     # yes, it uses $@ here
  $handle->send($discover->serialize())
                or die "Error sending broadcast inform:$!\n";

Sniffing DHCP packets.

  #!/usr/bin/perl
  # Simple DHCP server - listen to DHCP packets and print them
  
  use IO::Socket::INET;
  use Net::DHCP::Packet;
  $sock = IO::Socket::INET->new(LocalPort => 67, Proto => "udp", Broadcast => 1)
          or die "socket: $@";
  while ($sock->recv($newmsg, 1024)) {
          $packet = Net::DHCP::Packet->new($newmsg);
          print STDERR $packet->toString();
  }

Sending a LEASEQUERY (provided by John A. Murphy).

  #!/usr/bin/perl
  # Simple DHCP client - send a LeaseQuery (by IP) and receive the response
  
  use IO::Socket::INET;
  use Net::DHCP::Packet;
  use Net::DHCP::Constants;
  
  $usage = "usage: $0 DHCP_SERVER_IP DHCP_CLIENT_IP\n"; $ARGV[1] || die $usage;
  
  # create a socket
  $handle = IO::Socket::INET->new(Proto => 'udp',
                                  Broadcast => 1,
                                  PeerPort => '67',
                                  LocalPort => '67',
                                  PeerAddr => $ARGV[0])
                or die "socket: $@";     # yes, it uses $@ here
  
  # create DHCP Packet
  $inform = Net::DHCP::Packet->new(
                      op => BOOTREQUEST(),
                      Htype  => '0',
                      Hlen   => '0',
                      Ciaddr => $ARGV[1],
                      Giaddr => $handle->sockhost(),
                      Xid => int(rand(0xFFFFFFFF)),     # random xid
                      DHO_DHCP_MESSAGE_TYPE() => DHCPLEASEQUERY
                      );
  
  # send request
  $handle->send($inform->serialize()) or die "Error sending LeaseQuery: $!\n";
  
  #receive response
  $handle->recv($newmsg, 1024) or die;
  $packet = Net::DHCP::Packet->new($newmsg);
  print $packet->toString();

A simple DHCP Server is provided in the "examples" directory. It is composed of
"dhcpd.pl" a *very* simple server example, and "dhcpd_test.pl" a simple tester for
this server.

=head1 AUTHOR

Stephan Hadinger E<lt>shadinger@cpan.orgE<gt>.
Original version by F. van Dun.

=head1 BUGS

See L<https://rt.cpan.org/Dist/Display.html?Queue=Net-DHCP>

=head1 COPYRIGHT

This is free software. It can be distributed and/or modified under the same terms as
Perl itself.

=head1 SEE ALSO

L<Net::DHCP::Options>, L<Net::DHCP::Constants>.

Note: there is a Java version of this library: L<http://dhcp4java.sourceforge.net/>.

=cut
