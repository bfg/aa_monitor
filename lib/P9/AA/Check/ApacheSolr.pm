package P9::AA::Check::ApacheSolr;

use strict;
use warnings;

use POSIX qw(strftime);

use P9::AA::Constants;
use base 'P9::AA::Check::XML';

our $VERSION = 0.10;

use constant HKEY_VERSION => 'index_version';
use constant HKEY_TIME => 'index_time';

=head1 NAME

This module checks L<Apache Solr|http://lucene.apache.org/solr/> availability.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check::XML> and implements the following methods:

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Checks Apache Solr availability."
	);

	$self->cfgParamAdd(
		'url',
		'http://localhost:8080/solr',
		'Apache SolR ***base*** URL address.',
		$self->validate_str(16 * 1024),
	);
	$self->cfgParamAdd(
		'index_update_interval',
		0,
		'Apache SolR ***base*** URL address.',
		$self->validate_int(0, 86400 * 365),
	);

	$self->cfgParamRemove('strict');
	$self->cfgParamRemove('schemas');
	$self->cfgParamRemove('ignore_http_status');
	$self->cfgParamRemove('request_body');
	$self->cfgParamRemove('request_method');

	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	my $result = CHECK_OK;
		
	# Phase I: solr ping
	unless ($self->solrPing()) {
		$result = CHECK_ERR;
		goto outta_check;
	}
	
	# Phase II: get solr stats
	my $stats = $self->getSolrCoreStats();
	unless (defined $stats) {
		$result = CHECK_ERR;
		goto outta_check;
	}
	
	# get current time...
	my $ts = time();
	
	# $self->bufApp("OLD history: " . $self->dumpVar($ho));
	
	# print stats
	$self->bufApp("Apache SolR data:");
	map {
		$self->bufApp(sprintf("    %-20.20s %s", $_, $stats->{'searcher'}->{'stats'}->{'stat'}->{$_}));
	} sort keys %{$stats->{'searcher'}->{'stats'}->{'stat'}};

	# Phase III: check index version

	# get current index version
	my $cur_version = $self->getSolrIndexVersion($stats);
	return CHECK_ERR unless ($cur_version > 0);

	# get old index version and change time
	my $old_version = $self->hoGet(HKEY_VERSION);
	my $old_time = $self->hoGet(HKEY_TIME);

	# did index version changed?
	my $version_diff = ((defined $old_version && defined $cur_version && $old_version ne $cur_version) || (! defined $old_version && defined $cur_version)) ? 1 : 0;

	if ($self->{index_update_interval} && defined $old_version && defined $old_time) {
		my $to = $old_time + $self->{index_update_interval};
		if ($ts > $to && $old_version eq $cur_version) {
			$self->error(
				"Index was not updated since " .
				strftime("%Y/%m/%d %H:%M:%S", localtime($old_time)) .
				" [" . ($ts - $old_time) . " second(s)]."
			);
			$result = CHECK_ERR;
		} else {
		}
	}	
	outta_check:
	
	# save current index version and change time if
	# index version has changed
	if ($version_diff) {
		if (defined $cur_version) {
			$self->bufApp();
			$self->bufApp(
				"Index version changed from $old_time to $cur_version since " .
				strftime("%Y/%m/%d %H:%M:%S", localtime($old_time)) .
				" [" . ($ts - $old_time) . " second(s)]."				
			);
			$self->hnSet(HKEY_VERSION, $cur_version);
		}
		$self->hnSet(HKEY_TIME, $ts);
	}
	
	return $result;
}

=head2 getSolrStats

 my $stats = $self->getSolrStats();
 my $stats = $self->getSolrStats(url => $base_url);

Fetches Solr stats from Apache Solr stats interface. Returns hashref on success,
otherwise undef.

B<NOTE>: This method supports all keys supported by L<P9::AA::Check::XML/getXML>.

=cut
sub getSolrStats {
	my ($self, %opt) = @_;
	my $url = delete($opt{url});
	$url = $self->{url} unless (defined $url);
	$url = $self->_getSolrUrl($url, '/admin/stats.jsp');

	my $xml = $self->getXML(url => $url, %opt);
	return undef unless (defined $xml);

	# sanitize stuff hash (remove ugly whitespaces from keys and values...)
	return $self->_sanitizeStats($xml);
}

=head2 getSolrCoreStats

 # get core stats
 my $core_stats = $self->getSolrCoreStats();
 my $core_stats = $self->getSolrCoreStats(url => $base_url);
 
 
 # get core stats from complete solr stats
 my $stats = $self->getSolrStats();
 my $core_stats = $self->getSolrCoreStats($stats);

Returns Solr CORE stats as hash reference on success, otherwise undef.

B<NOTE>: This method supports all keys supported by L<P9::AA::Check::XML/getXML>.

=cut
sub getSolrCoreStats {
	my $self = shift;
	my $data = (ref($_[0]) eq 'HASH') ? shift : $self->getSolrStats(@_);
	return undef unless (defined $data);
	
	# get core stats
	my $core = $data->{'solr-info'}->{'CORE'}->{'entry'};
	unless (defined $core && ref($core) eq 'HASH') {
		$self->error("Solr statistics data doesn't contain solr core data.");
		return undef;
	}
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN CORE STATS ---");
		$self->bufApp($self->dumpVar($core));
		$self->bufApp("--- END CORE STATS ---");
	}

	return $core;	
}

=head2 getSolrIndexVersion

 my $core_stats = $self->getSolrCoreStats();
 my $ver = $self->getSolrIndexVersion($core_stats);

Returns Solr current index version on success, otherwise 0.

=cut
sub getSolrIndexVersion {
	my ($self, $data) = @_;
	unless (defined $data && ref($data) eq 'HASH') {
		$data = $self->getSolrCoreStats();
		return undef unless (defined $data);
	}
	my $ver = $data->{'searcher'}->{'stats'}->{'stat'}->{'indexVersion'};
	unless (defined $ver && length $ver > 0 && $ver > 0) {
		$self->error("Solr core stats structure doesn't contain indexVersion element.");
		return 0;
	}
	
	return $ver;
}

=head2 solrPing

 my $ok = $self->solrPing();
 my $ok = $self->solrPing($base_url);

Performs SolR "ping". Returns 1 on success, otherwise 1.

B<NOTE>: This method supports all keys supported by L<P9::AA::Check::XML/getXML>.

=cut
sub solrPing {
	my $self = shift;
	my $url = shift;
	$url = $self->{url} unless (defined $url);
	
	# fix url
	$url = $self->_getSolrUrl($url, '/admin/ping');
	
	# get xml data
	my $xml = $self->getXML(url => $url, @_);
	unless (defined $xml && ref($xml) eq 'HASH') {
		$self->error("Unable to ping Apache Solr: " . $self->error());
		return 0;
	}
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN SOLR PING ---");
		$self->bufApp($self->dumpVar($xml));
		$self->bufApp("--- END SOLR PING ---");
	}
	
	# check status...
	my $st = $xml->{'str'}->{'content'};
	unless (defined $st && lc($st) eq 'ok') {
		no warnings;
		$self->error("Apache Solr ping returned status: '$st'");
		return 0;
	}
	
	return 1;
}

sub _getSolrUrl {
	my ($self, $url, $path) = @_;
	$url = '' unless (defined $url);
	$path = '' unless (defined $path);
	$path = '/' . $path unless ($path =~ m/^\//);

	# remove trailing slashes from url
	$url =~ s/\/+$//g;
	
	# concatenate
	return $url . $path;
}

# sanitizes solr stats xml hash reference...
sub _sanitizeStats {
	my ($self, $data) = @_;
	my $res = {};
	foreach my $k (keys %{$data}) {
		my $key = $k;
		my $ref = ref($data->{$k});
		$key =~ s/^\s+//g;
		$key =~ s/\s+$//g;
		if ($ref eq 'HASH') {
			if (exists($data->{$k}->{content}) && ref($data->{$k}->{content}) eq '') {
				$res->{$key} = _sanitize_val($data->{$k}->{content});
			} else {
				$res->{$key} = $self->_sanitizeStats($data->{$k});
			}
		}
		elsif ($ref eq 'ARRAY') {
			map {
				push(@{$res->{$key}}, _sanitize_val($_));
			} @{$data->{$k}};
			
		}
		else {
			$res->{$key} = _sanitize_val($data->{$k}); 
		}
	}
	
	return $res;
}

sub _sanitize_val {
	return undef if (ref($_[0]) ne '');
	$_[0] =~ s/^\s+//g;
	$_[0] =~ s/\s+$//g;
	return $_[0];
}

=head1 SEE ALSO

L<P9::AA::Check> L<P9::AA::Check::URL> L<P9::AA::Check::XML>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;