package P9::AA::Connection;

use strict;
use warnings;

use POSIX qw(strftime);
use Time::HiRes qw(time);
use Scalar::Util qw(blessed);

use P9::AA::Log;
use P9::AA::Constants qw(:all);

use constant MAX_PROCESSING_TIME => 300;
use constant PROTO_DEFAULT => 'HTTP';

our $VERSION = 0.10;

my $log = P9::AA::Log->new();
my @_classes = (
	CLASS_PROTOCOL,
	CLASS_HARNESS,
	CLASS_RENDERER,
);

##################################################
#             OBJECT CONSTRUCTOR                 #
##################################################

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	$self->_init();
	return $self;
}

sub _init {
	my ($self) = @_;
	$self->{_error} = '';
	return 1;
}

sub error {
	my $self = shift;
	return $self->{_error};
}

sub loadModules {
	foreach my $m (@_classes) {
		local $@;
		eval "use $m; 1";
		if ($@) {
			$log->fatal("Error loading module $m: $@");
			return 0;
		}
	}
	return 1;
}

sub process {
	my ($self, $in, $out) = @_;
	$out = $in unless (defined $out);

	# get current time...
	my $ts = time();
	
	# install timeout watchdog
	local $SIG{ALRM} = sub {
		$log->error(
			"Process execution timeout of " .
			MAX_PROCESSING_TIME .
			" exceeded."
		);
		# fuck the client.
		CORE::exit 0;
	};
	# install alarm
	alarm(MAX_PROCESSING_TIME);
	
	# load required modules
	unless ($self->loadModules()) {
		return 0;
	}
	
	my $cfg = P9::AA::Config->new();
	
	# select protocol...
	my $proto = $cfg->get('protocol');
	$proto = PROTO_DEFAULT unless (defined $proto && length($proto));
	$proto = uc($proto);
	$log->debug("Using protocol: $proto");
	
	# create protocol object...
	my $proto_obj = CLASS_PROTOCOL->factory($proto);
	unless (defined $proto_obj) {
		$self->{_error} = "Unable to create object for protocol $proto: " .
			CLASS_PROTOCOL->error();
		return 0;
	}
	
	# process "connection"
	my $r = $proto_obj->process($in, $out, $ts);
	unless ($r) {
		$self->{_error} = "Error processing connection: " . $proto_obj->error();
	}
	
	# remove alarm timer
	alarm(0);
	
	return $r;
}

1;

# EOF