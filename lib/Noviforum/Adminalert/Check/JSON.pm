package Noviforum::Adminalert::Check::JSON;

use strict;
use warnings;

use JSON;

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::URL';

# version MUST be set
our $VERSION = 0.10;

=head1 NAME

JSON webservice validating module.

=head1 METHODS

This module inherits all methods from L<Noviforum::Adminalert::Check::URL>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Validate JSON/REST service response."
	);

	$self->cfgParamAdd(
		'ignore_http_status',
		0,
		'Try parse JSON from response content even on non 2xx response status.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'debug_json',
		0,
		'Debug parsed JSON.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'strict',
		1,
		'Be strict to JSON specification at parsing.',
		$self->validate_bool(),
	);


	$self->cfgParamRemove('content_pattern');
	$self->cfgParamRemove('content_pattern_match');

	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	my $json = $self->getJSON();

	if ($self->{debug}) {
		$self->bufApp("--- BEGIN RETURNED JSON ---");
		$self->bufApp($self->dumpVar($json));
		$self->bufApp("--- BEGIN RETURNED JSON ---");
	}

	return (defined $json) ? CHECK_OK : CHECK_ERR;
}

=head2 getJSON

 my $json = $self->getJSON(url => 'http://host.example.com/svc/something', %opt);
 
Returns decoded JSON response as hash reference on success, otherwise undef.

See L<Noviforum::Adminalert::Check::URL/prepareRequest> for B<%opt> description.

=cut
sub getJSON {
	my ($self, %opt) = @_;

	# get request...
	my $req = $self->prepareRequest(%opt, 'headerAccept' => 'application/json');
	return undef unless ($req);

	# perform request...
	my $r = $self->httpRequest($req);
	return undef unless (defined $r);
	
	# error and we're not ignoring returned http status?
	if (! $r->is_success() && ! $self->{ignore_http_status}) {
		$self->error("Bad HTTP response: " . $r->status_line());
		return undef;
	}

	# let's try to parse json from returned content
	my $j = $self->getJSONParser();

	# get json string...
	my $json_str = $r->decoded_content();
	
	# preprocess json string
	return undef unless ($self->_preprocessRawJSON(\ $json_str));

	local $@;
	my $json = eval { $j->decode($json_str) };
	if ($@) {
		$self->error("Exception while parsing JSON: $@");
		return undef;
	}
	unless (defined $json) {
		$self->error("JSON parser returned undefined structure.");
		return undef;
	}
	
	if ($self->{debug_json}) {
		$self->bufApp("--- BEGIN PARSED JSON ---");
		$self->bufApp($self->dumpVar($json));
		$self->bufApp("--- END PARSED JSON ---");
	}

	return $json;
}

=head2 getJSONParser

 my $p = $self->getJSONParser

Returns initialized and configured L<JSON> object.

=cut
sub getJSONParser {
	my $self = shift;
	my $j = JSON->new();
	$j->utf8(1);
	$j->relaxed(1) unless ($self->{strict});
	return $j;
}

sub _preprocessRawJSON {
	my ($self, $json) = @_;
	return 1;
}

=head1 SEE ALSO

L<Noviforum::Adminalert::Check::URL>, 
L<JSON>, 
L<Noviforum::Adminalert::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;