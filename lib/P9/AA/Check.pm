package P9::AA::Check;

use strict;
use warnings;

use Exporter;
use File::Spec;
use Data::Dumper;
use Sys::Hostname;
use POSIX qw(uname);
use File::Basename;
use Text::ParseWords;
use Time::HiRes qw(time);
use Digest::MD5 qw(md5_hex);
use Scalar::Util qw(blessed refaddr);

use P9::AA::Util;
use P9::AA::Constants qw(:all);
use P9::AA::ParamValidator;

use base 'P9::AA::Base';

our $VERSION = 0.20;

my $u = P9::AA::Util->new();

=head1 NAME

Base check class implementation.

=head1 DESCRIPTION

This is B<ABSTRACT> service checking class; It has implemented all methods
except B<L<check>>, which performes actual service check implementation.

=head1 WARNING

You shouldn't use this class to implement actual check. Recommended
way of doing service check is to use L<P9::AA::CheckHarness> class.

=head1 METHODS

B<IMPORTANT:> This class inherits everything from L<P9::AA::Base> class.

=cut 

sub _init {
	my $self = shift;
	$self->clearParams();
	$self->bufClear();
	$self->setParams(@_);

	return $self;
}

=head2 factory ($subclass [, @_])

Initializes package's subclass with specified optional argument.
Subclass is loaded in runtime.

This method behaves exactly as method B<factory()> in L<P9::AA::Base>
class except that tries to load operating system specific implementation of $subclass
first and returns base $subclass implementation if loading failed.

Returns initialized object on success, otherwise undef and sets error message.

=cut

sub factory {
	my $self   = shift;
	my $driver = shift;

	# no driver specified?
	unless (defined $driver && length($driver)) {
		return $self->SUPER::factory($driver, @_);
	}

	# try to load platform-specific implementation...
	my $os = uc($self->getOs());

	# try to initialize system-specific implementation
	my $driver_os = $driver . '::' . $os;
	my $obj = $self->SUPER::factory($driver_os, @_);

	#
	return $obj if (defined $obj);

	# seems like system-specific implementation doesn't exist.
	# let's try to create generic implementation.
	return $self->SUPER::factory($driver, @_);
}

sub getOs {
	my $os = (uname())[0];
	return $os;
}

=head2 error

 # retrieve last error message
 my $e = $check->error();		# returns string
 
 # set error message (allowed only for subclasses)
 $self->error('New error message'); # returns CHECK_ERR
 
 # clear error message
 $self->error('');	# returns CHECK_ERR

Returns last error message if called without arguments.

If called with arguments, which is only allowed if called
by subclass or by itself, sets new error message and returns
L<CHECK_ERR|P9::AA::Constants/CHECK_ERR>. To clear last error message call it with zero-length
string argument.

=cut

sub error {
	my $self = shift;
	unless (defined($self) && ref($self)) {
		return $self->SUPER::error(@_);
	}

	# if someone wants to set error message
	# it should be one of us.
	my ($package, $filename, $line) = caller;
	my $me = __PACKAGE__;
	if (@_ && $package =~ m/^$me/) {
		$self->{_error} = join('', @_);
		return CHECK_ERR;
	}

	return $self->{_error};
}

=head2 warning

 # retrieve warning message
 my $e = $check->warning();		# returns string
 
 # set warning message (allowed only for subclasses)
 $self->warning('New warning message'); # returns CHECK_WARN
 
 # clear warning message
 $self->warning('');	# returns CHECK_WARN

Returns last warning message if called without arguments

If called with arguments, which is only allowed if called
by subclass or by itself, sets new warning message and returns
L<CHECK_WARN|P9::AA::Constants/CHECK_WARN>. To clear last warning message call it with zero-length
string argument.

=cut

sub warning {
	my $self = shift;
	my ($package, $filename, $line) = caller;
	my $me = __PACKAGE__;
	if (@_ && $package =~ m/^$me/) {
		$self->{_warning} = join('', @_);
		return CHECK_WARN;
	}

	return $self->{_warning};
}

=head2 success

Clears last error message (if called by subclass) and always returns L<CHECK_OK|P9::AA::Constants/CHECK_OK>.

=cut
sub success {
	my ($self) = @_;
	my ($package, $filename, $line) = caller;
	my $me = __PACKAGE__;
	if (@_ && $package =~ m/^$me/) {
		$self->error('');
	}
	return CHECK_OK;
}

=head2 bufApp

Appends string $msg to internal message buffer.

=cut
sub bufApp {
	my $self = shift;
	my $str = (@_) ? join('', @_) : '';
	$str =~ s/[\r\n]+$//gm;
	$self->{_msgbuf} .= $str . "\n";
}

=head2 bufClear ()

Clears internal message buffer.

=cut

sub bufClear {
	my $self = shift;
	$self->{_msgbuf} = '';
}

=head2 bufGet ()

Returns internal message buffer as string

=cut

sub bufGet {
	my $self = shift;
	return $self->{_msgbuf};
}

=head2 getDrivers ()

Alias for L<getSubModules>; returns list of this class implementations.

=cut

sub getDrivers {
	my $self = shift;
	return $self->getSubModules();
}

=head2 clearParams ()

Resets configuration parameters to their default values. You should
probably reimplement this method in your check implementation class;
this is great place to define configuration parameters and create
some private structures.

This method must return 1 if succeeds, otherwise 1.

B<Example:>

 sub clearParams {
 	my ($self) = @_;
 	# don't forget to call parent's method
 	return 0 unless ($self->SUPER::clearParams());
 	
 	# let's create boolean parameter
 	$self->cfgParamAdd(
 		'bool_parameter',
 		0,
 		'This is example boolean parameter.',
 		$self->validate_bool()
 	);
 	
 	# we will have a private hash...
 	$self->{_something} = {};
 	
 	# clearParams() *MUST* return 1!
 	return 1;
 }

=cut

sub clearParams {
	my ($self) = @_;
	$self->cfgParamAdd('debug', 0, 'Display debugging messages.',
		$self->validate_bool());

	# history objects
	$self->{__hist_new} = undef;
	$self->{__hist_old} = undef;

	return 1;
}

=head2 set ($name, $val)

Sets configuration parameter $name to value $val. Returns 1 on success, otherwise 0.

B<NOTE:> Configuration parameter $name must be defined using L<cfgParamAdd()> method.

=cut

sub set {
	my ($self, $name, $val) = @_;
	return 0 unless (defined $name && length($name) > 0 && $name !~ m/^_/);

	my $re = undef;
	# do we have this parameter defined?
	unless (exists($self->{_cfg}->{$name})) {
		# do we have regex parameter?
		$re = $self->cfgParamIsRegex($name);
		return 0 unless (defined $re && $name =~ $re);
	}

	# get value validator...
	my $validator =
	  (defined $re)
	  ? $self->{_cfg}->{"$re"}->{validator}
	  : $self->{_cfg}->{$name}->{validator};

	# get default value
	my $default =
	  (defined $re)
	  ? $self->{_cfg}->{"$re"}->{default}
	  : $self->{_cfg}->{$name}->{default};

	# fix value with $validator
	if (defined $validator && ref($validator) eq 'CODE') {
		$val = eval { $validator->($val, $default) };
	}

	# set value...
	$self->{$name} = $val;

	#print "Setting '$name' => '$val'\n";

	return 1;
}

=head2 setParams (name => $value, name2 => $value2)

Sets multiple parameters at the same time. Returns number of parameters
that were actually set.

=cut

sub setParams {
	my $self = shift;
	my $i    = 0;
	while (@_) {
		my $k = shift;
		my $v = shift;
		$i += $self->set($k, $v);
	}

	return $i;
}

=head2 get ($name)

Returns value of configuration parameter $name on success, otherwise undef.

=cut

sub get {
	my ($self, $name) = @_;
	my $res = undef;
	if (defined $name && length($name) > 0 && exists($self->{$name})) {
		$res = $self->{$name};
	}
	return $res;
}

=head2 getParams ()

Returns all configuration parameters as hashref.

=cut

sub getParams {
	my $self = shift;
	my $r    = {};
	map { $r->{$_} = $self->get($_) } $self->cfgParamList();
	return $r;
}

sub checkClass {
	my ($self, $obj) = @_;
	$obj = $self unless (defined $obj);
	return $self->basenameClass($obj)
	  unless (blessed($obj) && $obj->isa(__PACKAGE__));

	my $me     = $self->basenameClass(__PACKAGE__);
	my $re_str = '::' . $me . '::' . '(.+)$';

	my $re  = qr/$re_str/;
	my $ref = ref($obj);

	my $impl = $self->basenameClass();
	if ($ref =~ $re) {
		$impl = $1;
	}
	return $impl;
}

sub getResultDataStruct {
	my $self = shift;
	my $t    = shift;

	no warnings;
	$t = time() unless (defined $t && $t > 0);

	my $r = {
		success => 0,    # true/false
		error =>
		  ERR_MSG_UNDEF,     # error message, must be the same as data->check->error
		data => {

			# check environment section
			environment => {
				hostname     => hostname(),
				program_name => basename($0),

				#program_version => sprintf("%-.2f", main->VERSION),
				program_version => main->VERSION,
			},

			# check module data section
			module => {

				#name => $self->basenameClass(),
				name    => $self->checkClass(),
				version => sprintf("%-.2f", $self->VERSION),
				class => (blessed($self)) ? ref($self) : $self,

				configuration => {

					#param_name => {
					#	value => "param value",
					#	default => "default value",
					#	description => "parameter description"
					#}
				}
			},

			# timings secttion
			timings => {
				total_start    => $t,
				total_finish   => 0,
				total_duration => 0,

				check_start    => 0,
				check_finish   => 0,
				check_duration => 0,
			},

			history => {
				changed         => 0,
			},

			# check result section
			check => {
				id              => '',
				result_code     => CHECK_INVALID,
				success         => 0,
				warning         => 0,
				error_message   => ERR_MSG_UNDEF,
				warning_message => '',
				messages        => '',
			},
		}
	};

	# add configuration propeties...
	foreach my $param ($self->cfgParamList()) {
		$r->{data}->{module}->{configuration}->{$param}->{value} =
		  $self->get($param);
		$r->{data}->{module}->{configuration}->{$param}->{default} =
		  $self->getParamDefaultVal($param);
		$r->{data}->{module}->{configuration}->{$param}->{description} =
		  $self->getParamDescription($param);
	}

	return $r;
}

sub configStr {
	my ($self) = @_;

	my $str = "";
	foreach (sort keys %{$self}) {
		next if ($_ =~ m/^_/);
		next if ($_ eq 'error');
		$str .= $_ . " = " . $self->{$_} . "\n";
	}
	return $str;
}

=head2 check

This method performs service health check. On success it returns CHECK_OK,
on warning returns CHECK_WARN, on error returns CHECK_ERR.

L<NOTE:> This method is not implemented in base class.

=cut

sub check {
	my ($self) = @_;
	$self->error("This method is not implemented by " . ref($self) . " class.");
	return 0;
}

=head2 toString ()

Returns string implementation of object considering currently set configuration
parameters. Default implementation returns empty string.

=cut

sub toString {
	return '';
}

=head2 hashCode

Returns object's hash code according to it's configuration as string.

=cut
sub hashCode {
	my $self = shift;
	my $h    = {};
	foreach (keys %{$self}) {
		next unless (defined $_ && length($_));
		next if ($_ =~ m/^_/);
		next if ($_ =~ m/^debug/);
		next unless (defined $self->{$_});
		$h->{$_} = $self->{$_};
	}
	
	# add classname
	$h->{__class} = ref($self); 

	return md5_hex($u->dumpVarCompact($h));
}

=head1 CONFIGURATION METHODS

=head2 cfgParamAdd

Prototype:

 $self->cfgParamAdd($name, $default_value, $description, $value_validator_sub)

Creates check configuration parameter. Arguments:

=over

=item B<$name> (string or compiled regular expression, mandatory)

Parameter name. If parameter name is compiled regular expression (using B<qr//> operator)
then parameter names passed to L<setParam ($name, $value)> method will be matched
against regex. If match succeedes, original passed parameter name will be set. 

=item B<$default_value> (mixed, default: undef)

Parameter's default value

=item B<$description> (string, default: "some string")

Parameter description

=item B<$value_validator_sub> (coderef, default: undef)

Parameter value validation function. If defined, specified coderef
is invoked every time method setParam($name, $value) is invoked.

Code is invoked with two parameters: new value and default value;
it must return value that B<will be set>.

B<Example>:

 # accept only numbers between 1-10; return
 # default value if provided number is out of
 # bounds.
 $validator = sub {
 	my ($val, $default) = @_;
 
 	return $default if ($val < 1 || $val > 10);
 	return $val;
 }

B<NOTE>: Simple way to define validator subs is module L<P9::AA::ParamValidator>.
It has already implemented some basic validators (strings, integers, floats, etc.); its methods
are exposed by B<validate_*> methods. See L<PARAMETER VALIDATOR METHODS> section for details.

See Parameter validation section for helper methods provided by this class.

B<IMPORTANT>: After configuration parameter is added it's value can be retrieved
by using $self->get($name) or by accessing $self->{$name} object property.

B<EXAMPLE:>

 $self->cfgParamAdd(
 	'integer_value',            # parameter name
 	6,                          # default value
 	'Some interger',            # Parameter description
 	$self->validate_int(1, 10), # value must be between 1 and 10, if not, default value of 6 will be applied.
 );

=back

=cut

sub cfgParamAdd {
	my ($self, $name, $default, $desc, $validator) = @_;

	# check name...
	return 0 unless (defined $name && length($name) > 0 && $name !~ m/^_/);

	# fix description
	$desc = 'Undescribed parameter' unless (defined $desc && length($desc));

	# save it for bad times :)
	$self->{_cfg}->{"$name"} = {
		name      => $name,        # could be object, reference
		default   => $default,
		desc      => $desc,
		validator => $validator,
	};

	# set parameter...
	$self->set($name, $default);

	return 1;
}

=head2 cfgParamRemove

Removes configuration parameter $name.

=cut

sub cfgParamRemove {
	my ($self, $name) = @_;
	return 0 unless (defined $name && length($name) > 0);
	return 0 unless (exists($self->{_cfg}->{"$name"}));

	# drop it...
	delete($self->{"$name"});
	delete($self->{_cfg}->{"$name"});
	return 1;
}

=head2 cfgParamList

Returns list of defined configuration parameters.

=cut

sub cfgParamList {
	my $self = shift;

	my %h = ();
	map { $h{$_} = 1 } keys %{$self->{_cfg}};

	foreach (keys %{$self}) {
		next if ($_ =~ m/^_/);
		next if (exists($h{$_}));
		next unless ($self->cfgParamIsRegex($_));
		$h{$_} = 1;
	}

	# return keys...
	return sort keys %h;
}

=head2 cfgParamIsRegex

Returns compiled regex if there is any defined regex-type configuration parameter
that matches $name, otherwise undef.

=cut

sub cfgParamIsRegex {
	my ($self, $name) = @_;
	return undef unless (defined $name && length($name));

	# check if $name matches any regular expression
	# parameters...
	foreach my $k (keys %{$self->{_cfg}}) {
		my $na = $self->{_cfg}->{$k}->{name};
		next unless (ref($na) eq 'Regexp');
		if ($name =~ $na) {
			return $na;
		}
	}

	return undef;
}

=head2 getParamDefaultVal

Returns parameter $name default value.

Parameter must be declared using B<cfgParamAdd> method.

=cut

sub getParamDefaultVal {
	my ($self, $name) = @_;
	return undef unless (defined $name && exists($self->{_cfg}->{"$name"}));

	# do we have value validator?
	my $validator = $self->{_cfg}->{"$name"}->{validator};
	if (defined $validator && ref($validator) eq 'CODE') {

		# call validator sub...
		my $val = eval { $validator->($self->{_cfg}->{"$name"}->{default}); };
		return $val;
	}
	else {
		return $self->{_cfg}->{"$name"}->{default};
	}
}

=head2 getParamDefaultDescription

Returns parameter $name description.

Parameter must be declared using B<cfgParamAdd> method.

=cut

sub getParamDescription {
	my ($self, $name) = @_;
	return undef unless (defined $name && exists($self->{_cfg}->{"$name"}));
	return $self->{_cfg}->{"$name"}->{desc};
}

=head1 UTILITY METHODS

=head2 dumpVar

Returns string representation of specified arguments using L<P9::AA::Util#dumpVar>.

=cut
sub dumpVar {
	my $self = shift;
	return $u->dumpVar(@_);
}

=head2 dumpVarCompact

Returns shortest possible string representation of specified arguments using L<P9::AA::Util#dumpVarCompact>.

=cut
sub dumpVarCompact {
	my $self = shift;
	return $u->dumpVarCompact(@_);
}

=head2 qx

Shorcut method for L<P9::AA::Util#qx>

=cut
sub qx {
	my $self = shift;
	my ($r, $ec) = $u->qx(@_);
	unless (defined $r && ref($r) eq 'ARRAY') {
		$self->error($u->error());
	}
	return (wantarray ? ($r, $ec) : $r);
}

=head2 qx2

Shorcut method for L<P9::AA::Util#qx2>

=cut
sub qx2 {
	my $self = shift;
	my ($r, $ec) = $u->qx2(@_);
	unless (defined $r && ref($r) eq 'ARRAY') {
		$self->error($u->error());
	}
	return (wantarray ? ($r, $ec) : $r);
}

=head1 PERSISTENT DATA METHODS

Check object has ability to persistently store data between checks if
L<P9::AA::History> objects are assigned after object
creation.

=head2 historyOld ($obj)

Sets/retrieves old history object. $obj must be initialized
L<P9::AA::History> object. 

=cut

sub historyOld {
	my ($self, $obj) = @_;
	if (blessed($obj) && $obj->isa(CLASS_HISTORY)) {
		$self->{__hist_old} = $obj;
	}

	return $self->{__hist_old};
}

=head2 hoGet ($key)

Retrieves custom property $key from assigned B<old history> object.

=cut

sub hoGet {
	my ($self, $key) = @_;
	$self->error('');
	unless (defined $self->{__hist_old}) {
		$self->error("Old history object is not set.");
		return undef;
	}

	return $self->{__hist_old}->get($key);
}

=head2 historyNew ($obj)

Sets/retrieves new history object. $obj must be initialized
L<P9::AA::History> object. 

=cut

sub historyNew {
	my ($self, $obj) = @_;
	if (blessed($obj) && $obj->isa(CLASS_HISTORY)) {
		$self->{__hist_new} = $obj;
	}

	return $self->{__hist_new};
}

=head2 hnGet ($key)

Retrieves custom property $key from assigned B<new history> object.

=cut

sub hnGet {
	my ($self, $key) = @_;
	$self->error('');
	unless (defined $self->{__hist_new}) {
		$self->error("New history object is not set.");
		return undef;
	}

	return $self->{__hist_new}->get($key);
}

=head2 hnSet ($key, $val)

Retrieves custom property $key to value $val to assigned B<new history> object.

=cut

sub hnSet {
	my ($self, $key, $val) = @_;
	$self->error('');
	unless (defined $self->{__hist_new}) {
		$self->error("New history object is not set.");
		return 0;
	}

	return $self->{__hist_new}->set($key, $val);
}

=head1 EXTENDING/IMPLEMENTING

This class is B<meant to be extended>. You should reimplement at least
L<check()> method, reimplementation of L<toString()> is encouraged.

See L<P9::AA::Check::EXAMPLE> for example check module.

=head1 PARAMETER VALIDATOR METHODS

Class implements some shortcuts for creating L<P9::AA::ParamValidator>
coderef validators.

=head2 validate_bool

See L<P9::AA::ParamValidator> for instructions.

=cut

# validator subs
sub validate_bool {
	shift;
	P9::AA::ParamValidator::validator_bool(@_);
}

=head2 validate_int

See L<P9::AA::ParamValidator> for instructions.

=cut

sub validate_int {
	shift;
	P9::AA::ParamValidator::validator_int(@_);
}

=head2 validate_float

See L<P9::AA::ParamValidator> for instructions.

=cut

sub validate_float {
	shift;
	P9::AA::ParamValidator::validator_float(@_);
}

=head2 validate_str

See L<P9::AA::ParamValidator> for instructions.

=cut

sub validate_str {
	shift;
	P9::AA::ParamValidator::validator_str(@_);
}

=head2 validate_ucstr

See L<P9::AA::ParamValidator> for instructions.

=cut

sub validate_ucstr {
	shift;
	P9::AA::ParamValidator::validator_ucstr(@_);
}

=head2 validate_lcstr

See L<P9::AA::ParamValidator> for instructions.

=cut

sub validate_lcstr {
	shift;
	P9::AA::ParamValidator::validator_lcstr(@_);
}

=head2 validate_regex

See L<P9::AA::ParamValidator#validator_regex> for instructions.

=cut

sub validate_regex {
	shift;
	P9::AA::ParamValidator::validator_regex(@_);
}

##############################################
#        tie() handle support methods        #
##############################################

=head1 TIE COMPATIBILITY

This class implements all methods that are required for successful
B<tie()>. If tied everything printed to object will invoke L<bufApp>
method.

=cut

sub TIEHANDLE {
	my $self = shift;
	return $self;
}

sub UNTIE { }

sub PRINT {
	my $self = shift;
	return $self->bufApp(@_);
}

sub PRINTF {
	my $self = shift;
	no warnings;
	return $self->bufApp(sprintf(@_));
}

sub FILENO {
	my $self = shift;
	return refaddr($self);
}

sub OPEN {
	return $_[0];
}

sub CLOSE { }

=head1 SEE ALSO

L<P9::AA::EXAMPLE>,
L<P9::AA::Base>,
L<P9::AA::CheckHarness>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;

# EOF