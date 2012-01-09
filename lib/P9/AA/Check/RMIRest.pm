package P9::AA::Check::RMIRest;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::JSON';
our $VERSION = '0.10';

=head1 NAME

RMI over REST proprietary checking module. Requires running B<rmi-rest> webapp proxy
application.

=head1 METHODS

This class inherits all methods from L<P9::AA:Check::JSON> and implements to following ones:

=cut
sub clearParams {
  my ($self) = @_;

  # run parent's clearParams
  return 0 unless ($self->SUPER::clearParams());

  # set module description
  $self->setDescription(
    "This is RMI over REST/JSON checking module, requires rmi-rest proxy"
  );

  # define additional configuration variables...
  $self->cfgParamAdd(
    'host',
    'localhost',
    'RMI registry listening hostname or IP address',
    $self->validate_str(1024)
  );
  $self->cfgParamAdd(
    'port',
    1099,
    'RMI registry listening port',
    $self->validate_int(1, 65535)
  );
  $self->cfgParamAdd(
    'registry',
    'IndexDirectory',
    'RMI registry name',
    $self->validate_str(1024)
  );
  $self->cfgParamAdd(
    'rmi_proxy_url',
    'http://localhost:8080/',
    'RMI over REST proxy URL address',
    $self->validate_str(1024)
  );
  $self->cfgParamAdd(
    'rmi_timeout',
    3.5,
    'RMI operation timeout in seconds (subsecond precision is supported).',
    $self->validate_float(0, 300, 3)
  );

  # you can also remove any previously created
  # configuration parameter.
  $self->cfgParamRemove('content_pattern');
  $self->cfgParamRemove('content_pattern_match');
  $self->cfgParamRemove('host_header');
  $self->cfgParamRemove('user_agent');
  $self->cfgParamRemove('ignore_http_status');
  $self->cfgParamRemove('redirects');
  $self->cfgParamRemove('request_body');
  $self->cfgParamRemove('request_method');
  $self->cfgParamRemove('url');
  $self->cfgParamRemove(qr/^header[\w\-]+/);
  $self->cfgParamRemove('timeout');

  # this method MUST return 1!
  return 1;
}

# actually performs ping
sub check {
  my ($self) = @_;
  my $r = $self->checkRmiRegistry($self->getRmiUrl());
}

# describes check, optional.
sub toString {
  my ($self) = @_;
  no warnings;
  return
    $self->getRmiUrl() . ' @ ' . $self->{rmi_proxy_url};
}

=head2 getRmiUrl

 my $rmi_url = $self->getRmiUrl();
 my $rmi_url = $self->getRmiUrl($host, $port, $name);

Returns RMI URL as string.

=cut
sub getRmiUrl {
  my ($self, $host, $port, $registry) = @_;
  my $r = '//';
  $r .= $host || $self->{host};
  $r .= ':' . ($port || $self->{port});
  $r .= '/' . ($registry || $self->{registry});
}

=head2 parseRmiUrl

 my ($host, $port, $registry) = $self->parseRmiUrl($rmi_url);

=cut
sub parseRmiUrl {
  my ($self, $url) = @_;
  
  if ($url =~ m/^\/\/([a-z0-9-:\.]+):(\d+)\/(\w+)$/) {
    return ($1, $2, $3);
  } else {
    $self->error("Invalid RMI URL syntax: '$url'");
    return undef;
  }
}

=head2 checkRmiRegistry

 my $r = $self->checkRmiRegistry($rmi_url, $rest_proxy_url);

Performs RMI URL check using B<rmi-rest> webapplication running on
optional $rest_proxy_url URL. Returns 1 on success, otherwise 0.

=cut
sub checkRmiRegistry {
  my ($self, $rmi_url, $rest_proxy_url) = @_;
  $rest_proxy_url = $self->{rmi_proxy_url} unless (defined $rest_proxy_url);
  
  my ($host, $port, $name) = $self->parseRmiUrl($rmi_url);
  return 0 unless (defined $host);
  
  # build URL
  my $real_url = $rest_proxy_url;
  $real_url =~ s/\/+$//g;
  $real_url .= "/rest/v1/$host/$port/$name/check";
  
  if ($self->{rmi_timeout} > 0) {
    $real_url .= '?timeout=' . ($self->{rmi_timeout} * 1000);
  }
  
  # perform the request
  my $json = $self->getJSON(
    url => $real_url,
    headerAccept => 'application/json',
    timeout => ($self->{rmi_timeout} + 1),
  );
  return 0 unless (defined $json && ref($json) eq 'HASH');
  
  # check json data...
  unless ($json->{check}->{success}) {
    no warnings;
    $self->error(
      "REST service reports error: " .
      $json->{check}->{error}
     );
     return 0;
  }
  
  return 1;
}

=head1 SEE ALSO

L<P9::AA::Check::JSON>, L<P9::AA::Check> 

=head1 AUTHOR

Brane F. Gracnar

=cut

1;