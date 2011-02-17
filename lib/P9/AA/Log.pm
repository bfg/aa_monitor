package P9::AA::Log;

use strict;
use warnings;

use Sys::Syslog;

use constant OFF => 0;
use constant FATAL => 1;
use constant ERROR => 2;
use constant WARN => 3;
use constant INFO => 4;
use constant DEBUG => 5;
use constant TRACE => 6;

our $VERSION = 0.10;

my $lh = {
	'OFF' => OFF,
	'FATAL' => FATAL,
	'ERROR' => ERROR,
	'WARN' => WARN,
	'INFO' => INFO,
	'DEBUG' => DEBUG,
	'TRACE' => TRACE,
};

# singleton instance...
my $_obj = undef;

=head1 NAME

Simple logging class

=head1 SYNOPSIS

 my $log = P9::AA::Log->new();
 $log->info("Info message");
 $log->debug("Debug message");

=head1 METHODS

=cut

sub new {
	unless (defined $_obj) {
		$_obj = __PACKAGE__->_construct();
	}
	
	return $_obj;
}

# object destructor
sub DESTROY {
	my ($self) = @_;
	closelog();
}

sub _construct {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	$self->{ident} = '';
	$self->{level} = INFO;
	bless($self, $class);
	return $self;
}

sub ident {
	my ($self, $ident) = @_;
	return $self->{ident} unless (defined $ident);
	$self->{ident} = $ident;
	return $self->{ident};
}

=head2 level

 my $current_level = $log->level();
 $log->level(INFO);
 $log->level("info");

Gets/sets logging level.

=cut
sub level {
	my ($self, $level) = @_;
	return $self->{level} unless (defined $level && length($level) > 0);

	# number?
	if ($level =~ m/^\d+$/ && ($level >= OFF && $level <= TRACE)) {
		$self->{level} = $level;
		return $level;
	}
	
	# string...
	$self->{level} = $self->str2level($level);
	return $self->{level};
}

=head2 is_trace

Returns 1 if current logging level is TRACE.

=cut
sub is_trace {
	my $self = shift;
	return $self->_doLog(TRACE);
}

=head2 trace

 $log->trace("This is trace message with args: ", @args);

Logs message with level TRACE.

=cut
sub trace {
	my $self = shift;
	$self->msg(TRACE, @_);
}

=head2 is_debug

=cut
sub is_debug {
	my $self = shift;
	return $self->_doLog(DEBUG);
}

=head2 debug

 $log->debug("This is debug message with args: ", @args);

Logs message with level DEBUG.

=cut
sub debug {
	my $self = shift;
	$self->msg(DEBUG, @_);	
}

=head2 info

 $log->info("This is info message: ", @args);

Logs message with level INFO.

=cut
sub info {
	my $self = shift;
	$self->msg(INFO, @_);	
}

=head2 warn

=cut
sub warn {
	my $self = shift;
	$self->msg(WARN, @_);	
}

=head2 error

=cut
sub error {
	my $self = shift;
	$self->msg(ERROR, @_);
}

=head2 fatal

=cut
sub fatal {
	my $self = shift;
	$self->msg(ERROR, @_);	
}

=head2 level2str

=cut
sub level2str {
	my ($self, $level) = @_;
	$level = $self->{level} unless (defined $level);
	foreach my $l (keys %{$lh}) {
		if ($lh->{$l} == $level) {
			return $l;
		}
	}
}

=head2 str2level

 my $level = $log->str2level("info");
 $level == INFO # true

Converts logging level string name to integer representation.

=cut
sub str2level {
	my ($self, $level) = @_;
	$level = 'INFO' unless (defined $level && length($level) > 0);
	$level = uc($level);
	my $r = INFO;
	foreach my $l (keys %{$lh}) {
		if ($l eq $level) {
			$r = $lh->{$l};
			last;
		}
	}
	return $r;
}

=head2 msg
 
 $log->msg(LOG_DEBUG, "This", " is", "debug message");
 $log->msg(LOG_INFO, "This", " is", "message");

"Low-level" logging method.

=cut
sub msg {
	my $self = shift;
	my $priority = shift;
	$priority = INFO unless (defined $priority);
	
	# check priority...
	return 1 unless ($self->_doLog($priority));

	openlog($self->{ident}, "cons,pid", "local0");
	syslog("info", "%s", join('', '[', $self->level2str($priority), ']: ', @_));
	return 1;
}

sub _doLog {
	my ($self, $priority) = @_;
	# should we log this message?
	return 0 unless ($priority <= $self->{level});
	return 0 if ($priority == OFF);
	return 1;
}

=head1 AUTHORS

=over 4

=item *

Brane F. Gracnar

=back

=head1 SEE ALSO

=over 4

=item *

L<Sys::Syslog>

=back

=cut

1;