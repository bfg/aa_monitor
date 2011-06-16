package P9::AA::Check::StackedCheck;

use strict;
use warnings;

use Time::HiRes qw(time);
use P9::AA::CheckHarness;

use P9::AA::Constants;
use base 'P9::AA::Check';

# version MUST be set
our $VERSION = 0.10;

=head1 NAME

Embed and combine other check modules to perform complex checks.

=head1 DESCRIPTION

Sometimes several different checks must be performed in specific order to discover
real state of some service. For example, if you want the check state of your LAMP
production, you must check MySQL database, Apache webserver and PHP FCGI interpreter.

=head1 SYSNOPSIS

Generate JSON file with check settings.

 {
   "debug": false,
   "expression": "APACHE && MYSQL && PHP",
   "check_definitions": {
      "APACHE": {
         "module": "ProxyCheck",
         "params": {
            "REAL_HOSTPORT": "host.example.org:1552",
            "REAL_MODULE": "Process",
            "cmd":  "/^apache2\\s+/",
            "use_basename": true,
            "min_process_count": 3
          }
      },
      "PHP": {
         "module": "ProxyCheck",
         "params": {
            "REAL_HOSTPORT": "host.example.org:1552",
            "REAL_MODULE": "Process",
            "cmd":  "/^php-cgi\\s+/",
            "use_basename": true,
            "min_process_count": 3
         }
      },
      "MYSQL": {
         "module": "DBI",
         "params": {
            "dsn": "DBI:mysql:database=db_name;host=host.example.org;port=3306",
            "query":  "SELECT COUNT(*) FROM table_name",
            "username": "some_user",
            "password": "secr3t"
         }
      }
   }
 }

Query for status using cURL:

 curl -X POST --data-binary @stackedcheck.json  -H "Content-Type: application/json" http://localhost:1552/StackedCheck.txt

Parameter B<check_definitions> has complex datatype, but it can be also set using GET request method. Here's the recipe:

=over

=item * put parameter B<check_definitions> to it's own file

 {
      "APACHE": {
         "module": "ProxyCheck",
         "params": {
            "REAL_HOSTPORT": "host.example.org:1552",
            "REAL_MODULE": "Process",
            "cmd":  "/^apache2\\s+/",
            "use_basename": true,
            "min_process_count": 3
          }
      },
      "PHP": {
         "module": "ProxyCheck",
         "params": {
            "REAL_HOSTPORT": "host.example.org:1552",
            "REAL_MODULE": "Process",
            "cmd":  "/^php-cgi\\s+/",
            "use_basename": true,
            "min_process_count": 3
         }
      },
      "MYSQL": {
         "module": "DBI",
         "params": {
            "dsn": "DBI:mysql:database=db_name;host=host.example.org;port=3306",
            "query":  "SELECT COUNT(*) FROM table_name",
            "username": "some_user",
            "password": "secr3t"
         }
      }
 }

=item * convert file to base64 encoded string

 $ base64 -w 0 < check_definitions.json

=item * build URL, add B<base64:> prefix to B<check_definitions> url parameter

 $ curl http://localhost:1552/StackedCheck/?debug=true&expression=APACHE%20%26%26%20MYSQL%20%26%26%20PHP&check_definitions=base64:<base64_string>

=back 

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Embed and combine other check modules and perform complex checks."
	);

	# define additional configuration variables...
	$self->cfgParamAdd(
		'expression',
		undef,
		'Stacked check expression, see module documentation for details.',
		$self->validate_str(4 * 1024)
	);
	$self->cfgParamAdd(
		'check_definitions',
		{},
		'Check definitions, see module documentation for details.',
		$self->validate_complex()
	);
	
	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	return CHECK_ERR unless ($self->_checkParams());
	
	# generate expression code
	my $code = $self->_generateCode($self->{expression});
	return CHECK_ERR unless (defined $code);
	
	# execute expression code
	local $@;
	my $res = eval { $code->($self) };
	if ($@) {
		my $e = $@;
		$e =~ s/[\r\n]+$//g;
		return $self->error("Exception executing expression code: $e");
	}
	
	# return result
	return ($res) ? CHECK_OK : CHECK_ERR;
}

sub toString {
	my ($self) = @_;
	no warnings;
	return "$self->{expression}";
}

sub _checkParams {
	my ($self) = @_;
	
	# check definitions
	unless (defined $self->{check_definitions} && ref($self->{check_definitions}) eq 'HASH') {
		$self->error("Undefined parameter check_definitions.");
		return 0;
	}
	unless (%{$self->{check_definitions}}) {
		$self->error("No check definitions were specified.");
		return 0;
	}
	my $err = "Invalid parameter check_definitions: ";
	foreach my $e (keys %{$self->{check_definitions}}) {
		unless (defined $e && length($e) > 0) {
			$self->error($err . "zero-length definition key name.");
			return 0;
		}
		my $def = $self->{check_definitions}->{$e};
		
		# get module and params...
		my $module = $def->{module};
		my $params = $def->{params};
		unless (defined $module && length $module > 0) {
			$self->error($err . "Check definition $e: No check module name.");
			return 0;
		}
		# params?
		$params = {} unless (defined $params && ref($params) eq 'HASH');
		$def->{params} = $params;
 	}
 	
 	# check expression
 	my $e = $self->{expression};
 	unless (defined $e && length $e > 0) {
 		$self->error("Undefined check expression.");
 		return 0;
 	}
 	
 	return 1;
}

sub _performSubCheck {
	my ($self, $name) = @_;
	unless (defined $name && length($name) > 0) {
		die "Undefined check name.\n";
	}
	unless (exists($self->{check_definitions}->{$name})) {
		die "Check name '$name' doesn't exist in check_definitions.\n";
	}

	my $c = $self->{check_definitions}->{$name};
	
	my $module = $c->{module};
	my $params = $c->{params};

	# create harness...
	my $h = P9::AA::CheckHarness->new();
	my $ts = time();
		
	# perform check
	my $res = $h->check($c->{module}, $c->{params}, $ts);
	
	return $self->_validateSubCheckResult($name, $res);
}

sub _validateSubCheckResult {
	my ($self, $name, $result) = @_;
	unless (defined $result && ref($result) eq 'HASH') {
		die "Check $name returned invalid result structure.\n";
	}
	
	my $c = $result->{data}->{check};
	my $res = $c->{result_code};
	unless (defined $res) {
		die "Check $name returned invalid result code.\n";
	}
	
	# convert to boolean value
	my $val = ($res == CHECK_OK || $res == CHECK_WARN) ? 1 : 0;
	
	# build buffer message
	my $buf = sprintf("CHECK %-30s: %d", $name, $val);
	$buf .= " [";
	$buf .= "success" if ($c->{success});
	if ($c->{warning}) {
		$buf .= "warning: $c->{warning_message}"
	}
	unless ($c->{success} || $c->{warning}) {
		$buf .= "error: $c->{error_message}";
	}
	$buf .= "]";
	$self->bufApp($buf);

	# should we print message buffer?
	if ($self->{debug}) {
		$self->bufApp();
		$self->bufApp("=== BEGIN CHECK MESSAGES: $name");
		$self->bufApp($c->{messages});
		$self->bufApp();		
	}
	
	return $val;
}

sub _generateCode {
	my ($self, $expr) = @_;
	unless (defined $expr && length($expr) > 0) {
		$self->error("Undefined expression.");
		return undef;
	}
	
	# check for invalid chars...
	if ($expr =~ m/[^\w\^\|&=\!<>\(\)\ ]+/i) {
		$self->error("Expression contains invalid characters.");
		return undef;
	}
	
	# do some search and replaces
	$expr =~ s/\s*([\w]+)\s*/ \$_[0]->_performSubCheck(\'$1\') /g;
	my $code_str = 'sub { return(' . $expr . ') }';

	# print STDERR "GENERATED CODE:\n" . $code_str . "\n";
	
	# compile code
	local $@;
	my $code = eval $code_str;
	if ($@) {
		$self->error("Error compiling check expression code: $@");
		return undef;
	}
	unless (defined $code && ref($code) eq 'CODE') {
		$self->error("Error compiling check expression code: eval returned undefined code reference.");
		return undef;
	}

	return $code;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;