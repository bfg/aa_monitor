package P9::AA::Renderer::PLAIN;

use strict;
use warnings;

use POSIX qw(strftime);

use P9::AA::Constants qw(:all);
use base 'P9::AA::Renderer';

our $VERSION = 0.12;

=head1 NAME

Plaintext output renderer.

=cut

sub render {
	my ($self, $data, $resp) = @_;

	# header
	my $buf = $self->renderHeader($data);
	
	# report
	$buf .= $self->renderReport($data);
	
	# messages
	$buf .= $self->renderMessages($data);
	
	# history
	$buf .= $self->renderHistory($data);
	
	# timings
	$buf .= $self->renderTimings($data);
	
	# configuration
	$buf .= $self->renderConfiguration($data);
	
	# general info
	$buf .= $self->renderGeneralInfo($data);
	
	# footer
	$buf .= $self->renderFooter($data);

	# set headers
	$self->setHeader($resp, 'Content-Type', 'text/plain; charset=utf-8');
	
	return $buf;


	my $ok = $data->{data}->{check}->{success};

	# PING RESULT

	# search ok if $ok
	if ($ok) {
		$buf .= "<!--SEARCH OK-->\n";
	}

	# set headers
	$self->setHeader($resp, 'Content-Type', 'text/plain; charset=utf-8');

	return $buf;
}

sub renderHeader {
	my ($self, $data) = @_;
	return '';
}

sub renderReport {
	my ($self, $data) = @_;
	my $buf = '';

	$buf .= "##############################\n";
	$buf .= "#        CHECK RESULT        #\n";
	$buf .= "##############################\n";
	my $fmt = "%-20.20s%s\n";
	my $success = 'NO';
	if ($data->{data}->{check}->{success}) {
		if ($data->{data}->{check}->{warning}) {
			$success = 'YES, WITH WARNING';
		} else {
			$success = 'YES';
		}
	}
	$buf .= "\n" . sprintf($fmt, "SUCCESS: ", $success) . "\n";

	# print error...
	unless ($data->{data}->{check}->{success}) {
		$buf .= "##############################\n";
		$buf .= "#        CHECK ERROR         #\n";
		$buf .= "##############################\n";
		$buf .= "\n";
		$buf .= $data->{data}->{check}->{error_message}. "\n";
		$buf .= "\n";
	}

	# is this warning?
	if ($data->{data}->{check}->{warning}) {
		$buf .= "##############################\n";
		$buf .= "#       CHECK WARNING        #\n";
		$buf .= "##############################\n";
		$buf .= "\n";
		$buf .= $data->{data}->{check}->{warning_message}. "\n";
		$buf .= "\n";
	}

	return $buf;
}

sub renderMessages {
	my ($self, $data) = @_;
	my $buf = '';
	# check messages
	if (length($data->{data}->{check}->{messages})) {
		$buf .= "##############################\n";
		$buf .= "#       CHECK MESSAGES       #\n";
		$buf .= "##############################\n";
		$buf .= "\n";
		$buf .= $data->{data}->{check}->{messages};
		$buf .= "\n";
	}
	return $buf;
}

sub renderHistory {
	my ($self, $data) = @_;
	my $buf = '';
	if ($data->{data}->{history}->{changed}) {
		my $time_str = strftime("%d.%m.%Y %H:%M:%S", localtime($data->{data}->{history}->{last_time}));
		my $time_diff = sprintf("%-.3f", $data->{data}->{history}->{time_diff});
		$buf .= "##############################\n";
		$buf .= "#          HISTORY           #\n";
		$buf .= "##############################\n";
		$buf .= "Status change since: $time_str [$time_diff second(s) ago].\n";
		my $res = $data->{data}->{history}->{last_result_code};
		my $res_str = result2str($res);
		$buf .= "Last result was: $res_str\n";
		if ($res != CHECK_OK) {
			$buf .= "Last message was: " . $data->{data}->{history}->{last_message} . "\n";
		}
		$buf .= "\n";
	}
	return $buf;
}

sub renderTimings {
	my ($self, $data) = @_;

	my $fmt = "%-20.20s%s\n";
	my $buf = '';
	$buf .= "##############################\n";
	$buf .= "#          TIMINGS           #\n";
	$buf .= "##############################\n";

	$buf .= sprintf(
		$fmt, "CHECK DURATION: ",
		sprintf("%-.3f", ($data->{data}->{timings}->{check_duration} * 1000)) . " ms"
	);
	$buf .= sprintf(
		$fmt, "TOTAL DURATION: ",
		sprintf("%-.3f", ($data->{data}->{timings}->{total_duration} * 1000)) . " ms"
	);
	$buf .= "\n";
	$buf .= sprintf($fmt, "STARTED:", $self->timeAsString($data->{data}->{timings}->{total_start}));
	$buf .= sprintf($fmt, "FINISHED: ", $self->timeAsString($data->{data}->{timings}->{total_finish}));
	$buf .= "\n";

	return $buf;
}

sub renderConfiguration {
	my ($self, $data) = @_;
	my $buf = '';
	$buf .= "##############################\n";
	$buf .= "#    CHECK CONFIGURATION     #\n";
	$buf .= "##############################\n";
	foreach my $k (sort keys %{$data->{data}->{module}->{configuration}}) {
		my $e = $data->{data}->{module}->{configuration}->{$k};
		next unless (defined $e);
		$buf .= "$k = " . (defined($e->{value}) ? $e->{value} : '') . "\n";
	}
	$buf .= "\n";

	return $buf;	
}

sub renderGeneralInfo {
	my ($self, $data) = @_;
	my $buf = '';
	$buf .= "##############################\n";
	$buf .= "#       GENERAL INFO         #\n";
	$buf .= "##############################\n";
	$buf .= "module: " . $data->{data}->{module}->{name} . '/' . $data->{data}->{module}->{version} . "\n";
	$buf .= "hostname: " . $data-> {data}->{environment}->{hostname} . "\n";
	$buf .= "software: " .
			$data-> {data}->{environment}->{program_name} . '/' .
			$data-> {data}->{environment}->{program_version} . "\n";
	$buf .= "\n";
	return $buf;
}

sub renderFooter {
	my ($self, $data) = @_;
	if ($data->{data}->{check}->{success}) {
		return "\n<!--SEARCH OK-->\n";
	}
	return '';
}

=head1 SEE ALSO

L<P9::AA::Renderer>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;