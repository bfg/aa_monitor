package P9::AA::Check::XML;

use strict;
use warnings;

use IO::File;
use File::Spec;
use File::Copy;
use XML::Simple;
use POSIX qw(strftime);
use File::Temp qw(tempfile);
use Digest::MD5 qw(md5_hex);

use P9::AA::Constants;
use base 'P9::AA::Check::URL';

our $VERSION = 0.11;

my $xmllint_errs = {
	0 => "No error",
	1 => "Unclassified",
	2 => "Error in DTD",
	3 => "Validation error",
	4 => "Validation error",
	5 => "Error in schema compilation",
	6 => "Error writing output",
	7 => "Error in pattern (generated when --pattern option is used)",
	8 => "Error in Reader registration (generated when --chkregister option is used)",
	9 => "Out of memory error",
};


=head1 NAME

XML service validating module.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::URL>.

=cut

##################################################
#              PUBLIC  METHODS                   #
##################################################

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Validates XML document."
	);

	$self->cfgParamAdd(
		'url',
		'http://localhost/document.xml',
		'XML document URL.',
		$self->validate_str(),
	);
	$self->cfgParamAdd(
		'strict',
		0,
		'Strict XML validation; Requires xmllint(1) from libxml2 package.',
		$self->validate_str()
	);
	$self->cfgParamAdd(
		'schemas',
		'',
		'Comma separated list of additional XML schema URLs used for XML validation. Requires strict=true.',
		$self->validate_str()
	);
	$self->cfgParamAdd(
		'cache_schemas',
		1,
		'Cache fetched schemas?',
		$self->validate_bool()
	);
	$self->cfgParamAdd(
		'ignore_http_status',
		0,
		'Try parse XML from response content even on non 2xx response status.',
		$self->validate_bool(),
	);
	
	# remove some unneeded params
	$self->cfgParamRemove('content_pattern');
	$self->cfgParamRemove('content_pattern_match');
	
	return 1;
}

sub check {
	my ($self) = @_;	
	
	# get XML
	my ($xml, $xml_str) = $self->getXML();
	return CHECK_ERR unless (defined $xml && ref($xml) eq 'HASH');
	
	# no strict checking? well, we succeeded!
	return CHECK_OK unless ($self->{strict});
	
	# perform strict XML check...
	return CHECK_ERR unless ($self->validateXMLStrict(\ $xml_str));
	return CHECK_OK;
}

=head2 getXML

Prototype:

 my ($xml_ref, $xml_str) = $self->getXML(%opt);

Example:

 my ($xml_ref, $xml_str) = $self->getXML(
 	url => "http://host.example.com/service/document.xml",
 	request_method => "POST",
 	username => $username,
 	password => $password,
 );

Fetches XML document from specified URL. Returns parsed XML document (using L<XML::Simple>) as
hash reference in scalar context or parsed xml document hash reference and raw xml document as scalar
in list context.

Returns undef on error.

=cut
sub getXML {
	my ($self, %opt) = @_;
	my $req = $self->prepareRequest(%opt);
	return undef unless (defined $req);

	# get response...
	my $response = $self->httpRequest($req);

	# error and we're not ignoring returned http status?
	if (! $response->is_success() && ! $self->{ignore_http_status}) {
		$self->error("Bad HTTP response: " . $response->status_line());
		return undef;
	}
	
	# create xml parser
	my $p = XML::Simple->new();
	
	# convert string to hash reference
	my $xml_str = $response->content();
	local $@;
	my $xml_ref = eval { $p->xml_in(\ $xml_str) };
	if ($@) {
		$self->error("Error parsing XML: $@");
		return undef;
	}

	# ok, now it's time to return data
	return (wantarray ? ($xml_ref, $xml_str) : $xml_ref);
}

=head2 validateXMLStrict

 $self->validateXMLStrict(\ $xml_string);
 $self->validateXMLStrict($xml_file);

Validates XML string scalar reference or file using L<xmllint(1)>. Returns
1 on success, otherwise 0.

=cut
sub validateXMLStrict {
	my ($self, $xml, @schemas) = @_;
	unless (defined $xml && length $xml) {
		$self->error("Undefined XML content.");
		return 0;
	}
	
	my $file = undef;
	my $file_remove = 0;
	if (ref($xml) eq 'SCALAR') {
		$file = $self->_writeTmpXML($xml);
		return 0 unless (defined $file);
		$file_remove = 1;
	}
	elsif (-f $xml && -r $xml) {
		$file = $xml;
	}
	else {
		$self->error("Invalid XML source (not a scalar reference nor a valid filename).");
		return 0;
	}

	# parse schemas from received xml document
	my $schema_urls = $self->_getXmlSchemasFromFile($file);
	unless (defined $schema_urls) {
		$self->error("Unable to parse schemas: " . $self->error());
		return 0;
	}

	# add schema urls
	push(@{$schema_urls}, @schemas) if (@schemas);
	
	# compute schema filenames...
	my $tmpdir = File::Spec->tmpdir();
	my $s = {};
	map {
		$s->{$_} = File::Spec->catfile($tmpdir, $> . "-xmlvalidate-" . md5_hex($_)) . ".xsd"; 
	} @{$schema_urls};

	# fetch xml schemas...
	foreach (keys %{$s}) {
		return 0 unless ($self->_fetchSchema($_, $s->{$_}, $self->{cache_schemas}));
	}
	
	# compute schema filenames
	my @schema_files = ();
	map {
		push(@schema_files, $s->{$_});
	} @{$schema_urls};

	# validate xml file against set of filename
	my $retval = $self->_validateXml($file, @schema_files);
	
	# something bad happened? backup up xml file...
	unless ($retval) {
		my $date = strftime("%Y-%m-%d-%H-%M-%S", localtime(time()));
		my $file_backup = $file . "-backup-" . $date;
		$self->bufApp("Archiving non-validated XML file as '$file_backup'.");
		copy($file, $file_backup);
	}

	# remove xml file
	unlink($file) if ($file_remove);

	return 1;
}

##################################################
#             PRIVATE  METHODS                   #
##################################################

sub _writeTmpXML {
	my ($self, $xml) = @_;
	my ($fd, $file) = tempfile();
	unless (defined $fd) {
		$self->error("Error writing XML to temporary file: $!");
		return undef;
	}
	
	# write data
	print $fd ${$xml};
	unless (close($fd)) {
		$self->error("Error closing temporary XML file: $!");
		unlink($file);
		return undef;
	}
	
	
	return $file;
}

# runs xmllint(1) over specified xml file and possibly defined xml schemas...
# arguments: xml file, [xml schema file, xml schema file, ...]
sub _validateXml {
	my $self = shift;
	my $xml = shift;
	
	# compute command
	my $cmd = 'xmllint --noout --nowarning --loaddtd';

	# add schemas
	map { $cmd .= ' --schema "' . $_ . '"' } @_;
	
	# add xml file...	
	$cmd .= ' "' . $xml . '"';
	
	if ($self->{debug}) {
		$self->bufApp("Running command: $cmd");
	}
	
	# run xmllint
	my ($out, $c) = $self->qx2($cmd);
	
	if ($c > 0) {
		my $err = exists($xmllint_errs->{$c}) ? $xmllint_errs->{$c} : "unknown error.";
		$self->error("xmllint(1) exited with status $c: " . $err);
		return 0;
	}
	
	return 1;
}

sub _getXmlSchemasFromFile {
	my ($self, $file) = @_;
	
	my $fd = IO::File->new($file, 'r');
	unless (defined $fd) {
		$self->error("Unable to open file '$file': $!");
		return undef;
	}

	return $self->_getXmlSchemas($fd);
}

sub _getXmlSchemas {
	my ($self, $fd) = @_;
	unless (defined $fd) {
		$self->error("Invalid filehandle.");
		return undef;
	}

	# result arrayref
	my $r = [];	

	# try rewind the file...
	local $@;
	eval { $fd->seek(0, 0) };
	if ($@) {
		$self->error("Unable to rewind XML filehandle: $@/$!");
		return undef;
	}

	my @to_parse = ();
	
	# read and parse
	while ($. < 10 && (my $line = <$fd>)) {
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		next unless (length($line) > 0);
		# print "aaa: $line\n";
		
		my @tmp = split(/\s+["']?/, $line);
		
		my $last_in = 0;
		my $chunk = "";
		foreach my $c (@tmp) {
			# print "CCCC= $c\n";
			
			if ($last_in) {
				$chunk .= " " . $c;
				# print "LAST_IN: '$chunk'\n";
				if ($c =~ m/["']>?$/) {
					push(@to_parse, $chunk);
					$last_in = 0;
					$chunk = "";
				}
			}
			elsif ($c =~ m/^xmlns:/ || $c =~ m/^xsi:/) {
				# print "XMLNS: $c\n";
				if ($c =~ m/["']$/) {
					push(@to_parse, $c);
				} else {
					if (length($chunk) > 0) {
						push(@to_parse, $chunk);
					}
					$last_in = 1;
					$chunk = $c;
				}
			}
		}
	}
	
	# strip unneeded stuff...
	my @x = ();
	map {
		$_ =~ s/[<>"']+//g;
		$_ =~ s/^(xmlns|xsi):(.+)=//g;
		
		push(@x, split(/\s+/, $_));
	} @to_parse;
	
	# weed out suspcious schemas...
	foreach my $e (@x) {
		# http://host.example.org/
		if ($e =~ m/^http(s)?:\/\/([\w\-\.]+)\/?$/) {
			# remove...
		}
		else {
			push(@{$r}, $e);
		}
	}
	
	if ($self->{debug}) {
		$self->bufApp('--- BEGIN XML SCHEMAS ---');
		map { $self->bufApp('    ' . $_ ) } @{$r};
		$self->bufApp('--- END XML SCHEMAS ---');
	}

	return $r;
}

sub _fetchSchema {
	my ($self, $url, $file, $use_cache) = @_;
	$use_cache = 0 unless (defined $use_cache);

	if (-e $file) {
		if (! -f $file) {
			$self->error("Filesystem entry '$file' already exists; but is not a plain file.");
			return 0;
		}
		if ($use_cache) {
			return 1;
		}
		unless (unlink($file)) {
			$self->error("File '$file' already exists; unable to remove it: $!");
			return 0;
		}
	}
	
	# try to fetch to file
	$self->bufApp("Fetching XML schema '$url' to file '$file'") if ($self->{debug});
	my $r = $self->httpGet($url, ":content_file" => $file);
	
	unless ($r->is_success()) {
		$self->error("Unable to download schema '$url': " . $r->status_line());
		return 0;
	}

	return 1;
}

=head1 SEE ALSO

L<P9::AA::Check::URL>, 
L<P9::AA::Check>, 
L<XML::Simple>, 
L<xmllint(1)>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;