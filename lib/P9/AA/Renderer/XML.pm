package P9::AA::Renderer::XML;

# try to load fast xml parser
#BEGIN { eval 'require XML::Parser' }

use strict;
use warnings;

use XML::Simple;
use Storable qw(dclone);

use constant true => 'true';
use constant false => 'false';

use base 'P9::AA::Renderer';

our $VERSION = 0.14;

=head1 NAME

XML output renderer.

=cut
sub render {
	my ($self, $data, $resp) = @_;
	
	# create xml writer
	my $writer = XML::Simple->new(
		AttrIndent => 1,
		NoAttr => 0,
		NormaliseSpace => 1,
		RootName => "aa_monitor",
		SuppressEmpty => 0,
		XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>',
	);
	
	# set headers
	$self->setHeader($resp, 'Content-Type', 'application/xml; charset=utf-8');

	# copy result structure, so that we can
	# make some modification of data
	my $mydata = dclone($data);

	# convert booleans to true/false
	if (exists($mydata->{success})) {
		$mydata->{success} = ($mydata->{success}) ? true : false;
	}
	if (exists($mydata->{data}->{check}->{success})) {
		$mydata->{data}->{check}->{success} = $mydata->{data}->{check}->{success} ?
			true : false;
	}
	if (exists($data->{data}->{check}->{warning})) {
		$mydata->{data}->{check}->{warning} = $mydata->{data}->{check}->{warning} ?
			true : false;
	}
	if (exists($mydata->{data}->{history}->{changed})) {
		$mydata->{data}->{history}->{changed} = $mydata->{data}->{history}->{changed} ?
			true : false;
	}

	return $writer->xml_out($data);
}

=head1 SEE ALSO

L<P9::AA::Renderer>, L<XML::Simple>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;