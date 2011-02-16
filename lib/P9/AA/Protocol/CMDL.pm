package P9::AA::Protocol::CMDL;

# $Id: CMDL.pm 2344 2011-02-14 16:35:49Z bfg $
# $Date: 2011-02-14 17:35:49 +0100 (Mon, 14 Feb 2011) $
# $Author: bfg $
# $Revision: 2344 $
# $LastChangedRevision: 2344 $
# $LastChangedBy: bfg $
# $LastChangedDate: 2011-02-14 17:35:49 +0100 (Mon, 14 Feb 2011) $
# $URL: https://svn.interseek.com/repositories/admin/aa_monitor/trunk/lib/Noviforum/Adminalert/Protocol/CMDL.pm $

use strict;
use warnings;

use Time::HiRes qw(time);

use P9::AA::Log;
use P9::AA::Protocol;

use vars qw(@ISA);
@ISA = qw(P9::AA::Protocol);

our $VERSION = 0.10;
my $log = P9::AA::Log->new();

=head1 NAME

Command line "protocol" implementation.

=head1 METHODS

This class inherits all methods from L<P9::AA::Protocol>.

=head1 process

B<PROTOTYPE:>

 $self->process($argv, undef [, $time_start = time() ])

Processes command line invocation ("connection"), never returns becouse ends
execution using L<CORE/exit>.
 
=cut
sub process {
	my ($self, $argv, undef, $ts) = @_;
	$ts = time() unless (defined $ts);

	# "parse" command line
	my $params = {};
	foreach (@{$argv}) {
		my ($k, $v) = split(/\s*=\s*/, $_, 2);
		next unless (defined $k && defined $v);
		$params->{$k} = $v;
	};
	
	# get module
	my $module = delete($params->{module});
	# remove weird stuff from module name...
	$module =~ s/[^\w]+//g if (defined $module);
	
	# get output type
	my $output_type = $self->getOutputType(delete($params->{output_type}));

	# create check harness...
	my $harness = P9::AA::CheckHarness->new();

	# create output renderer
	my $renderer = $self->getRenderer($output_type);
	unless (defined $renderer) {
		print STDERR $self->error(), "\n";
		exit 1;
	}
	
	# perform the service check...
	local $@;
	my $data = eval { $harness->check($module, $params, $ts) };
	if ($@) {
		$log->error("Exception: $@");
		print STDERR "Exception while running check. See logs for details.\n";
		exit 1;
	}
	
	# so called "headers"
	my $headers = {};
	
	# render the data
	my $body = $renderer->render($data, $headers);
	unless (defined $body) {
		print STDERR $renderer->error();
		return 0;
	}
	
	# write data to stdout...
	print $body;
	
	# select exit code
	my $exit_code = $headers->{exit_code};
	unless (defined $exit_code && $exit_code >= 0) {
		$exit_code = ! $data->{ping}->{result}->{success};
	}

	exit $exit_code;
}

sub getOutputType {
	my ($self, $name) = @_;
	return (defined $name && length($name) > 0) ? $name : 'eval';
	
}

=head1 SEE ALSO

L<P9::AA::Protocol>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;