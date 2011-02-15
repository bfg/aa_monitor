package Noviforum::Adminalert::Renderer::JSON;

use strict;
use warnings;

use JSON;
use Storable qw(dclone);

use base 'Noviforum::Adminalert::Renderer';

our $VERSION = 0.12;

=head1

JSON output renderer.

=cut

sub render {
	my ($self, $data, $resp) = @_;
	
	my $j = JSON->new();
	$j->utf8(1);
	$j->allow_unknown(1);
	$j->allow_blessed(1);
	$j->convert_blessed(0);
	$j->shrink(1);
	# not implemented in JSON::XS
	# $j->allow_bignum(1);

	# set headers
	$self->setHeader($resp, 'Content-Type', 'application/json; charset=utf-8');
	
	# copy result structure, so that we can
	# make some modification of data
	my $mydata = dclone($data);
	
	# convert booleans to true/false
	if (exists($mydata->{success})) {
		$mydata->{success} = ($mydata->{success}) ? JSON::true : JSON::false;
	}
	if (exists($mydata->{data}->{check}->{success})) {
		$mydata->{data}->{check}->{success} = $mydata->{data}->{check}->{success} ?
			JSON::true : JSON::false;
	}
	if (exists($mydata->{data}->{check}->{warning})) {
		$mydata->{data}->{check}->{warning} = $mydata->{data}->{check}->{warning} ?
			JSON::true : JSON::false;
	}
	if (exists($mydata->{data}->{history}->{changed})) {
		$mydata->{data}->{history}->{changed} = $mydata->{data}->{history}->{changed} ?
			JSON::true : JSON::false;
	}
	
	# convert timing times to milliseconds
	no warnings;
	map {
		$mydata->{data}->{timings}->{$_} = $mydata->{data}->{timings}->{$_} * 1000;
	} keys %{$mydata->{data}->{timings}};

	return $j->encode($mydata);
}

=head1 SEE ALSO

L<Noviforum::Adminalert::Renderer>, L<JSON>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;

# EOF