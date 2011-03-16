package P9::AA::Protocol::CMDL;

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

Processes command line invocation ("connection"), never returns because ends
execution using L<CORE/exit>.
 
=cut
sub process {
	my ($self, $argv, undef, $ts) = @_;
	$ts = time() unless (defined $ts);
	
	my $fatal_exit = $self->exitCodeFatal();
	
	# "parse" command line
	my $params = {};
	# first argument should be module name
	if (${$argv}[0] !~ m/=/) {
		$params->{module} = shift(@{$argv});
	}
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
		print $self->error(), "\n";
		exit $fatal_exit;
	}
	
	# perform the service check...
	local $@;
	my $data = eval { $harness->check($module, $params, $ts) };
	if ($@) {
		$log->error("Exception: $@");
		print "Exception while running check. See logs for details.\n";
		exit $fatal_exit;
	}
	
	# so called "headers"
	my $headers = {};
	
	# render the data
	my $body = $renderer->render($data, $headers);
	unless (defined $body) {
		print $renderer->error();
		exit $fatal_exit;
	}
	
	# write data to stdout...
	print $body;
	
	# select exit code
	my $exit_code = $headers->{exit_code};
	unless (defined $exit_code && $exit_code >= 0) {
		if ($data->{data}->{check}->{warning}) {
			$exit_code = $self->exitCodeWarn();
		}
		elsif ($data->{data}->{check}->{success}) {
			$exit_code = $self->exitCodeOk();
		}
		else {
			$exit_code = $self->exitCodeErr();
		}
	}

	exit $exit_code;
}

sub getOutputType {
	my ($self, $name) = @_;
	return (defined $name && length($name) > 0) ? $name : 'eval';
}

sub exitCodeFatal { 1 }
sub exitCodeOk { 0 }
sub exitCodeWarn { 1 }
sub exitCodeErr { 2 }

=head1 SEE ALSO

L<P9::AA::Protocol>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;