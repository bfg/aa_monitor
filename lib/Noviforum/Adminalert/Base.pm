package Noviforum::Adminalert::Base;

use strict;
use warnings;

use Scalar::Util qw(blessed);
use Noviforum::Adminalert::Log;

my $Error = '';
my $log = Noviforum::Adminalert::Log->new();

=head1 NAME

Base object class with some free sugar.

=head1 SYNOPSIS

 package MyPackage
 
 use base 'Noviforum::Adminalert::Base';
 
 sub _init {
 	my $self = shift;
 	$self->{_answer} = 42;
 	return $self;
 }
 sub answer { return shift->{_answer} }
 
 package main;
 
 my $p = MyPackage->new();
 print $p->answer(), "\n";

=head1 OBJECT CONSTRUCTOR

Object constructor doesn't take any arguments, they are passed to
L<_init(@_)> protected method.

=cut
sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	bless($self, $class);
	return $self->__init(@_);
}

=head1 METHODS

=head2 error

 # retrieves last error message
 my $err = $self->error();
 
 # sets new error message.
 $self->error('This is horrible error message');

Sets/returns last error message.

=cut
sub error {
	my $self = shift;
	if (@_) {
		if (defined $self && ref($self)) {
			$self->{_error} = join('', @_);
		} else {
			$Error = join('', @_);
		}
	}

	return $Error unless (defined($self) && ref($self));
	return $self->{_error};
}

=head2 factory

B<EXAMPLE:>

 my $obj = $self->factory(
 	'SubPackage',
 	key => $val
 );
 
 unless (defined $obj) {
 	print "Error: ", $self->error(), "\n";
 }

Initializes package's subclass with specified optional argument.
Subclass is loaded in runtime.

Returns initialized object on success, otherwise undef and sets error message.

=cut
sub factory {
	my $self = shift;
	my $driver = shift;

	# no driver? well, return ourselves :)
	unless (defined $driver && length($driver) > 0) {
		return $self->new();
	}
	
	# sanitize driver...
	$driver =~ s/\.+//g;
	$driver =~ s/[^\w:]+//g;

	my $class = (ref($self)) ? ref($self) : $self;
	$class .= '::' . $driver;

	# try to load module
	eval "require $class";

	# check for injuries
	if ($@) {
		my $ex = $@;
		# don't leak information about @INC
		$ex =~ s/\s*\(\@INC\s*contains.+//g;
		$Error = "Unable to load driver module '$class': $ex";
		$Error =~ s/\s+$//g;
		$self->log_debug("Error loading class $class: $@");
		return undef;
	}
	if ($log->is_debug()) {
		no warnings;
		$self->log_debug(
			"Successfully loaded class $class version " .
			sprintf("%-.2f", $class->VERSION())
		);
	}

	# initialize object
	my $obj = undef;
	eval { $obj = $class->new(@_) };
	
	if ($@) {
		$Error = "Unable to create $driver object: $@";
		$Error =~ s/\s+$//g;
	}

	return $obj;
}

=head2 get

 my $val = $self->get($key)
 
Retrieves object property $key.

=cut
sub get {
	my ($self, $key) = @_;
	return undef unless (defined $key && length($key));
	return undef if ($key =~ m/^_/);
	return undef unless (exists($self->{$key}));
	return $self->{$key};
}

=head2 set

 my $r = $self->set($key, $val);

Sets object property $key to $val. Returns 1 on success, otherwise 0.

=cut
sub set {
	my ($self, $key, $val) = @_;
	return 0 unless (defined $key && length($key));
	return 0 if ($key =~ m/^_/);
	return 0 unless ($key =~ m/^[a-z\_0-9]+/i);
	
	$self->{$key} = $val;
	return 1;
}

=head2 setParams

 my $num = $self->setParams( a => 'b', c => 'd');

=cut
sub setParams {
	my $self = shift;
	my $i = 0;
	while (@_) {
		my $k = shift;
		my $v = shift;
		next unless (defined $k);
		$i += $self->set($k, $v);
	}
	
	return $i;
}

=head2 getSubModules

Returns list of submodule implementations. Each of them can be
used as $subclass argument for L</factory> method.

=cut
sub getSubModules {
	my $self = shift;
	my(@drivers, %seen_dir);
	
	local $@;

	my $package = (ref($self)) ? ref($self) : $self;
	$package =~ s/::/\//g;

	my $dirh = undef;
	foreach  my $d (@INC) {
		chomp($d);
		my $dir = $d . "/" . $package;

		next unless (-d $dir);
		next if ($seen_dir{$d});

		$seen_dir{$d} = 1;

		next unless (opendir($dirh, $dir));
		foreach my $f (readdir($dirh)){
			next unless ($f =~ s/\.pm$//);
			next if ($f eq 'NullP');
			next if ($f eq 'EXAMPLE');
			next if ($f =~ m/^_/);

			# this driver seems ok, push it into list of drivers
			push(@drivers, $f) unless ($seen_dir{$f});
			$seen_dir{$f} = $d;
		}
		closedir($dirh);
	}

	# "return sort @drivers" will not DWIM in scalar context.
	return (wantarray ? sort @drivers : @drivers);
}

=head1 LOGGING METHODS

This base also initializes L<Noviforum::Adminalert::Log> module
on startup.

=head2 log_info

Logs message with priority info.

=cut
sub log_info {
	shift;
	$log->info(@_);
}

=head2 log_warn

Logs message with priority warn.

=cut
sub log_warn {
	shift;
	$log->warn(@_);
}

=head2 log_err

Logs message with priority of error.

=cut
sub log_err {
	log_error(@_);
}

=head2 log_error

Logs message with priority of error.

=cut
sub log_error {
	shift;
	$log->error(@_);	
}

=head2 log_fatal

Logs message with priority warn.

=cut
sub log_fatal {
	shift;
	$log->fatal(@_);
}

=head2 log_debug

Logs message with priority debug.

=cut
sub log_debug {
	shift;
	$log->debug(@_);
}

=head2 log_trace

Logs message with priority trace.

=cut
sub log_trace {
	shift;
	$log->trace(@_);
}

=head2 log_level

 # get logging level
 my $level = $self->log_level();
 
 # set new logging level
 $self->log_level("info");

Returns or sets logging level.

=cut
sub log_level {
	shift;
	return $log->level(@_);
}

=head2 setDescription

 $self->setDescription('This is current object description');

Sets object description.

=cut
sub setDescription {
	my $self = shift;
	$self->{_description} = join('', @_);
}

=head2 getDescription

Returns object description previously set by L</setDescription>.

=cut
sub getDescription {
	return shift->{_description};
}

=head2 basenameClass

 my $name = $self->basenameClass();
 my $name_obj = $self->basenameClass($obj);

Returns class basename as string.

=cut
sub basenameClass {
	my ($self, $sth) = @_;
	$sth = $self unless (defined $sth);
	return '' unless (defined $sth);
	
	my $str = (ref($sth)) ? ref($sth) : $sth;
	if ($str =~ m/::([\w]+)$/) {
		return $1;
	}
	return $str;
}

=head1 PROTECTED METHODS

=head2 _init

This method is called just by parent constructor. You can perform your
custom object initialzation here.

B<WARNING:> Return value must be B<$self>!

Example:

 sub _init {
 	my ($self) = @_;
 	
 	if (rand() > 0.8) {
 		die "s00xxxor.";
 	} else {
 		$self->{_this_is_something} = 'FLAG';
 		return $self;
 	}
 }

=cut
sub _init {
	return shift;
}

sub __init {
	my $self = shift;
	$self->error('');
	$self->setDescription(
		"This is generic module description."
	);
	return $self->_init(@_);
}

=head1 SEE ALSO

L<Noviforum::Adminalert::Check>

=head1 AUTHOR

Brane F. Gracnar 

=cut
1;