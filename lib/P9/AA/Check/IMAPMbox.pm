package P9::AA::Check::IMAPMbox;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::IMAP';

use HTTP::Date qw(str2time);

our $VERSION = 0.10;

=head1 NAME

Checks IMAP mailbox for some weird behaviours.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::IMAP>.

=cut
sub clearParams {
  my ($self) = @_;

  # run parent's clearParams
  return 0 unless ($self->SUPER::clearParams());

  # set module description
  $self->setDescription("Mailbox for IMAP servers");
  
  $self->cfgParamAdd(
    'must_be_unread',
    1,
    'Message must be marked as unread',
    $self->validate_bool,
  );
  
  $self->cfgParamAdd(
    'min_age',
    3600,
    'Minumum message age in seconds',
    $self->validate_int(0)
  );

  $self->cfgParamAdd(
    'min_msgs',
    -1,
    'Minimum number of messages in mailbox',
    $self->validate_int(0)
  );

  $self->cfgParamAdd(
    'max_msgs',
    -1,
    'Maximum number of messages in mailbox',
    $self->validate_int(0)
  );

  return 1;
}

# actually performs ping
sub check {
  my ($self) = @_;

  # CONNECT
  my $sock = $self->imapConnect();
  return CHECK_ERR unless ($sock);
  $self->bufApp("Successfully established connection with IMAP server.");
  
  my $i = $self->imapSockMeta($sock);
  
  # select inbox
  return CHECK_ERR unless ($self->imapSelectMbox($sock, $self->{imap_mailbox}));
  $self->bufApp("Successfully opened mailbox $self->{imap_mailbox} [$i->{imap_nmsgs} messages].");

  my $buf = $self->_imapCmd2($sock, "FETCH 1:* (FLAGS INTERNALDATE RFC822.SIZE)");

  # disconnect
  $self->imapDisconnect($sock);

  # get message list
  my $list = $self->_parseMsgList($buf);
  return CHECK_ERR unless (defined $list && ref($list) eq 'ARRAY');

  # just validate them, will ya...
  $self->bufApp("MSG_LIST: " . $self->dumpVar($list)) if ($self->{debug});
  $self->_validateMsgList($list);
}

sub _imapCmd2 {
  my ($self, $sock, $cmd) = @_;
  $self->{imap_body} = '';
  return undef unless ($self->imapCmd($sock, $cmd));
  my $i = $self->imapSockMeta($sock);
  my $buf = $i->{imap_ctrl};
  #$self->{imap_ctr} = '';
  $buf = '' unless (defined $buf);
  return $buf;
}

sub _validateMsgList {
  my ($self, $list) = @_;

  # check number of messages...
  my $num_msgs = $#{$list} + 1;
  if ($self->{min_msgs} >= 0 && $num_msgs < $self->{min_msgs}) {
    return $self->error("Mailbox contains only $num_msgs messages out of required $self->{min_msgs}.");
  }
  if ($self->{max_msgs} >= 0 && $num_msgs > $self->{max_msgs}) {
    return $self->error("Mailbox contains more messages than allowed ($num_msgs/$self->{max_msgs}).");
  }

  my $res = CHECK_OK;
  my $warns = '';
  my $errs = '';
  map {
    my $t = $self->_validateMsg($_);
    $warns .= $self->warning() . "\n" if ($t == CHECK_WARN);
    $errs .= $self->error() . "\n" if ($t == CHECK_ERR);
    $res = _res($res, $t);
  } @$list;

  $self->warning($warns) if (length($warns));
  $self->error($errs) if (length($errs));
  $res;
}

sub _validateMsg {
  my ($self, $msg) = @_;
  my $t = time;
  return $self->error("Bad message struct.") unless (defined $msg && ref($msg) eq 'HASH');

  # no time? no problem, heh
  return CHECK_OK unless (exists $msg->{time} && $msg->{time});
  
  my $is_read = (exists $msg->{flags} && $msg->{flags} =~ m/Seen/i);
  my $is_older = ($msg->{time} < ($t - $self->{min_age}));

  if ($self->{must_be_unread}) {
    if ($is_older && ! $is_read) {
      $self->error("Unread message is older than $self->{min_age} second(s).");
      return CHECK_ERR;
    }
  } else {
    if ($is_older) {
      $self->error("Read message is older than $self->{min_age} second(s).");
      return CHECK_ERR;
    }
  }
  CHECK_OK;
}

sub _res {
  my ($old, $new) = @_;
  return $new if ($new == CHECK_ERR);
  if ($old == CHECK_ERR) {
    return $old;
  }
  elsif ($old == CHECK_WARN) {
    return $old;
  }

  $new;
}

sub _parseMsgList {
  my ($self, $buf) = @_;
  my $r = [];

  foreach my $l (split(/[\r\n]+/, $buf)) {
    next unless ($l =~ m/^(?:\s*\*\s+)?\d+\s+/);
    $l =~ s/^(?:\s*\*\s+)?\d+\s+FETCH\s+\(//g;
    $l =~ s/\)$//g;
    my $e = _parse_llist($l);
    $e->{time} = str2time($e->{internaldate}) if (exists $e->{internaldate});
    push(@$r, $e);
  }

  return $r;
}

sub _parse_llist {
  my $r = {};
  my $key = undef;
  my $buf = '';
  foreach my $e (split(/\s+/, $_[0])) {
    next unless (length($e));
    if (defined $key) {
      if (_iskey($e)) {
        $r->{_sanitize_key($key)} = _sanitize_val($buf);
        $key = $e;
        $buf = '';
      } else {
        $buf .= ' ' . $e;
      }
    } else {
      if (_iskey($e)) {
        $key = $e;
        $buf = '';
      } else {
        $buf .= ' ' . $e;
      }
    }
  }

  if (defined $key && length($buf)) {
    $r->{_sanitize_key($key)} = _sanitize_val($buf);
  }

  return $r;
}

sub _iskey {
  if ($_[0] =~ m/^[A-Z\.0-9]+$/) {
    return 0 if ($_[0] =~ m/^[\d\.]+/);
    return 0 if (length($_[0]) < 3);
    return 1;
  } else {
    return 0;
  }
}

sub _sanitize_val {
  my ($s) = @_;
  $s =~ s/^["'\s]+//g;
  $s =~ s/["'\s]+$//g;
  $s;
}

sub _sanitize_key {
  my ($s) = @_;
  $s = lc($s);
  $s =~ s/[\.-]+/_/g;
  $s;
}

=head1 SEE ALSO

L<P9::AA::Check::IMAP>, 
L<P9::AA::Check>, 

=head1 AUTHOR

Brane F. Gracnar

=cut
1;