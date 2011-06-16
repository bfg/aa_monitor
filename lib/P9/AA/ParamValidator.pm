package P9::AA::ParamValidator;

use strict;
use warnings;

use Exporter;
use Scalar::Util qw(blessed);

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter);

@EXPORT_OK = qw(
	validator_bool
	validator_int
	validator_float
	validator_regex
	validator_str
	validator_ucstr
	validator_lcstr
	validator_list
	validator_hash
	validator_str_ltrim
	validator_str_rtrim
	validator_str_trim
	validator_string
);

$EXPORT_TAGS{':all'} = @EXPORT_OK;

our $VERSION = 0.11;

my $_has_base64 = undef;
my $_has_json = undef;

=head1 NAME

Simple input parameter validator.

=head1 DESCRIPTION

This module provides lightweight input parameter validation functions
with some eval()-like behaviour...

=head1 SYNOPSIS

 # create boolean validator with default return value of 1
 my $bool = validator_bool(1);
 
 $bool->();         # 1
 $bool->("true");   # 1
 $bool->("no");     # 0
 $bool->(undef, 1); # 1

=head1 EXPORTS

This module doesn't export anything by default. You can import any function
separately or import them all by using B<:all> import tag.

=head1 FUNCTIONS

=head2 validator_bool([$default = 0])

Returns boolean parameter validation coderef.

=cut
sub validator_bool {
	my ($default) = @_;
	$default = 0 unless (defined $default);
	$default = ($default) ? 1 : 0;
	return sub {
		my ($val, $def) = @_;
		$def = $default unless (defined $def);
		$def = _as_bool($def);
		return $def unless (defined $val && length($val));
		return _as_bool($val);
	};
}

=head2 validator_int ($min = undef, $max = undef, $default = 0)

Returns integer validator coderef

=cut
sub validator_int {
	my ($min, $max, $default) = @_;
	return validator_float($min, $max, 0, $default);
}

=head2 validator_float ($min = undef, $max = undef, $precision = 6, $default = 0)

Returns float validator coderef. Coderef has the following prototype:

$code($value, [ $default = undef, $min = undef, $max = undef, $precision = undef])

B<Example:>

 my $v = validator_float(-0.4, 10.2, 2, 0.1);
 $v->(20);				# 0.10
 $v->(20, 16.4);		# 16.4

=cut
sub validator_float {
	my ($min, $max, $precision, $default) = @_;
	$precision = 6 unless (defined $precision);
	$default = 0 unless (defined $default);

	return sub {
		my ($val, $de, $mi, $ma, $pre) = @_;
		$de = $default unless (defined $de);
		$pre = $precision unless (defined $pre);
		$mi = $min unless (defined $mi);
		$ma = $max unless (defined $ma);
		$val = $de unless (defined $val);
		
		# validate limiting params...
		{
			no warnings;
			
			$val += 0;
			$mi += 0 if (defined $mi);
			$ma += 0 if (defined $ma);
			$de += 0;
			$pre = abs(int($pre));
		}
	
		$val = $de if (defined $mi && $val < $mi);
		$val = $de if (defined $ma && $val > $ma);
		
		# apply precision...
		if (defined $pre) {
			$val = sprintf(
				'%-.' . $pre . 'f',
				$val
			);
		}
		
		# convert to number
		$val += 0;

		return $val;
	};
}

=head2 validator_str ($max_len = 1024, $default = '')

Returns string validator coderef. Coderef has the following
prototype:

$code->($value, [$default = undef, $max_len = undef, $allowed_str, $allowed_str2, ...])

B<Example>:

 my $v = validator_str(4, "default");
 $v->();                # 'defa'
 $v->("testing");       # 'test'
 $v->("", 'sth', 2);    # ''
 $v->(undef, 'sth', 2); # 'st'

=cut
sub validator_str {
	my $max_len = shift;
	my $default = shift;
	$max_len = 0 unless (defined $max_len);
	$default = undef unless (defined $default && ! ref($default));
	my @valid = @_;

	return sub {
		my ($val, $def, $ml) = @_;
		$def = $default unless (defined $def && !ref($def));
		$def = _as_str($def);
		$ml = $max_len unless (defined $ml);
		use bytes;
		no warnings;
		$ml = abs(int($ml));
		
		my $res = _as_str($val);
		if (defined $res) {
			$res = substr($res, 0, $ml) if ($ml > 0);
			if (@valid) {
				my $found = 0;
				foreach (@valid) {
					if ($_ eq $res) {
						$found = 1;
						last;
					}
				}
				$res = $def unless ($found);
			}	
		}
		
		# explicitly stringify result
		$res .= '' if (defined $res);
		
		return $res;
	}
}

=head2 validator_ucstr

The same as validate_str() except that result is always upercased.

=cut
sub validator_ucstr {
	my $validator = validator_str(@_);
	return sub {
		my $r = $validator->(@_);
		$r = uc($r) if (defined $r);
		return $r;
	};
}

=head2 validator_lcstr

The same as validate_str() except that result is always lowercased.

=cut
sub validator_lcstr {
	my $validator = validator_str(@_);
	return sub {
		my $r = $validator->(@_);
		$r = lc($r) if (defined $r);
		return $r;
	};
}

=head2 validator_str_trim

Same as validate_str except that result is always trimmed.

=cut
sub validator_str_trim {
	my $validator = validator_str(@_);
	return sub {
		my $r = $validator->(@_);
		if (defined $r) {
			$r =~ s/^\s+//g;
			$r =~ s/\s+$//g;
		}
		return $r;
	};
}

=head2 validator_str_ltrim

Same as validate_str except that result is always trimmed at the beginning of the string.

=cut
sub validator_str_ltrim {
	my $validator = validator_str(@_);
	return sub {
		my $r = $validator->(@_);
		if (defined $r) {
			$r =~ s/^\s+//g;
		}
		return $r;
	};
}

=head2 validator_str_rtrim

Same as validate_str except that result is always trimmed on the end of string.

=cut
sub validator_str_rtrim {
	my $validator = validator_str(@_);
	return sub {
		my $r = $validator->(@_);
		if (defined $r) {
			$r =~ s/\s+$//g;
		}
		return $r;
	};
}

=head2 validator_list

Validates array reference argument.

=cut
sub validator_list {
	my ($default) = @_;
	$default = [] unless (defined $default && ref($default) eq 'ARRAY');
	return sub {
		my ($val, $def) = @_;
		my $r = $val;
		$r = $def unless (defined $r && ref($r) eq 'ARRAY');
		$r = $default unless (defined $r && ref($r) eq 'ARRAY');
		return $r;
	};
}

=head2 validator_hash

Validates hash reference argument.

=cut
sub validator_hash {
	my ($default) = @_;
	$default = {} unless (defined $default && ref($default) eq 'HASH');
	return sub {
		my ($val, $def) = @_;
		my $r = $val;
		$r = $def unless (defined $r && ref($r) eq 'HASH');
		$r = $default unless (defined $r && ref($r) eq 'HASH');
		return $r;
	};
}

=head2 validator_regex

Returns string to compiled regex coderef validator. Coderef has the
the following prototype:

$code->($string, [$default = undef])

B<Example:>

 my $v = validator_regex();
 
 my $re = $v->('/^som[aeo]+thing/i');   # returns compiled regular expression
 $v->('/aaa[/');                        # returns undef (bad regex)
 $v->('/aaa[/', $re);                   # returns $re because regex string compilation failed

=cut
sub validator_regex {
	return sub {
		my ($str, $default) = @_;
		if (defined $default) {
			# $default must be pre-compiled regular expression
			my $ref = ref($default);
			if ($ref eq '') {
				# simple scalar, try to compile it...
				$default = _compile_regex($default);
			}
			elsif ($ref eq 'Regexp') {
				# $default is ok...
			}
			else {
				$default = undef;
			}
		}
		return $default unless (defined $str && length($str) > 2);
		
		my $regex = _compile_regex($str);
		return (defined $regex) ? $regex : $default;
	};
}

=head2 validator_complex ([ $default = undef ])

Returns string to complex perl data structure validator. Coderef has the following prototype:

 $code->({ $base64_encoded_string | $json_string | $perl_ref}, [ $default = undef ] );

This validator returns original argument if it is HASH or ARRAY reference. If argument is
string or SCALAR reference it tries to parse it as JSON string. If string is prefixed with
B<base64:> string will be base64 decoded before trying to decode JSON. 

EXAMPLES:

 my $json_string = '{ "X": { "Y": "Z" } }';
 my $base64_str = 'base64:' . encode_base64($json_string);
 
 # create validator which returns empty hashref on parsing error
 my $code = validator_complex({})
 
 my $ref = $code->($base64_str);
 my $ref = $code->($base64_str, { a => 'b' });
 
 my $ref = $code->($json_string)
 my $ref = $code->($json_string, { c => 'd' });

=cut
sub validator_complex {
	my ($default) = @_;
	return sub {
		my ($data, $def) = @_;
		$def = $default unless (defined $def);
		return $def unless (defined $data);
		
		# array or hash ref? return it!
		my $ref = ref($data);
		if ($ref eq 'HASH' || $ref eq 'ARRAY') {
			return $data;
		}
		# plain JSON string?
		elsif ($ref eq '' || $ref eq 'SCALAR') {
			# no json support? this sucks...
			return $def unless (_has_json());
			
			# create string ref.
			my $str = ($ref eq 'SCALAR') ? $data : \ $data;
			
			# base64 encoded JSON string?
			if (${$str} =~ m/^base64:/i) {
				# no base64 support? return default value
				return $def unless (_has_base64());
				
				# remove base64: prefix
				${$str} = substr(${$str}, 6);
				
				# decode string
				${$str} = MIME::Base64::decode_base64(${$str});
			}
			
			# try to decode json
			my $jp = JSON->new();
			$jp->utf8(1);
			$jp->relaxed(1);
			local $@;
			my $s = eval { $jp->decode(${$str}) };
			if ($@) {
				my $err = $@;
				eval 'require P9::AA::Log';
				unless ($@) {
					my $l = P9::AA::Log->new();
					$l->error("Error parsing base64 JSON string: $err");
				}
			}
			
			return (defined $s) ? $s : $def;
		}
		# looks like something else... return default value
		else {
			return $def
		}
	};
}

sub _has_base64 {
	return $_has_base64 if (defined $_has_base64);
	
	# check it...
	local $@;
	$_has_base64 = eval 'use MIME::Base64; 1';
	return $_has_base64;	
}

sub _has_json {
	return $_has_json if (defined $_has_json);
	
	# check it...
	local $@;
	$_has_json = eval 'use JSON; 1';
	return $_has_json;
}

sub _as_str {
	my ($val) = @_;
	my $res = undef;
	return undef unless (defined $val);

	# try to stringify argument...
	if (blessed($val)) {
		if ($val->can('toString')) {
			$res = $val->toString();
		}
		elsif ($val->can('to_string')) {
			$res = $val->to_string();
		}
		elsif ($val->can('to_str')) {
			$res = $val->to_str();					
		}
		elsif ($val->can('to_s')) {
		$res = $val->to_s();
		}
		elsif ($val->can('as_string')) {
			$res = $val->as_string();
		}
		elsif ($val->can('as_str')) {
			$res = $val->as_str();
		}
		elsif ($val->can('string')) {
			$res = $val->string();
		}
		else {
			$res = "$val";
		}
	} else {
		$res = "$val";
	}

	return $res;
}

sub _as_bool {
	my ($val) = @_;
	return 0 unless (defined $val && length $val);
	$val =~ s/^\s+//g;
	$val =~ s/\s+$//g;
	$val = lc($val);
	return ($val eq '1' || $val =~ m/^y(es)?$/ || $val =~ m/^t(rue)?$/) ? 1 : 0;
}

sub _compile_regex {
	my ($str) = @_;

	my $flags = '';
	my $pattern = '';
		
	# check regex syntax: must be /<reg_text>/flags
	if ($str =~ m/^\/(.+)\/([imosx]{0,5})?$/) {
		$pattern = $1;
		$flags = $2;
		$flags = '' unless (defined $flags);
	} else {
		die "Invalid regex syntax. Valid syntax: /PATTERN/flags; example: /^sys/i\n";
	}
		
	my $r = eval { qr/(?$flags:$pattern)/ };
	return $r;
}

=head1 AUTHOR

Brane F. Gracnar

=cut

1;