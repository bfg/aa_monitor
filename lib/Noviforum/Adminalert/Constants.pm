package Noviforum::Adminalert::Constants;

use strict;
use warnings;

use Exporter;

=head1 NAME

Class containing constants.

=head1 SYNOPSIS

 # imports CHECK_OK, CHECK_ERR, CHECK_WARN
 use Noviforum::Adminalert::Check;
 
 # import everything
 use Noviforum::Adminalert::Check qw(:all);

=head1 EXPORTS

This class exports B<CHECK_OK, CHECK_WARN, CHECK_ERR> by default, other constants
can be imported separately, all constants can be imported by using B<:all> import
tag.

=head1 CONSTANTS

=head2 CHECK_OK

Check result constant indicating that check succeeded.

=cut

use constant CHECK_OK => 1;

=head2 CHECK_ERR

Check result constant indicating that check failed with error.

=cut

use constant CHECK_ERR => 0;

=head2 CHECK_WARN

Check result constant indicating that check succeeded with warning message.

=cut

use constant CHECK_WARN => 2;

=head2 CHECK_INVALID

Invalid check result code.

=cut
use constant CHECK_INVALID => -1;

my %_s = (
	CHECK_OK() => 'success',
	CHECK_WARN() => 'warning',
	CHECK_ERR() => 'error',
	CHECK_INVALID() => 'invalid check result code',
);

=head2 ERR_MSG_UNDEF

Contains default undefined error message string.

=cut

use constant ERR_MSG_UNDEF => 'Undefined error message';

=head2 CLASS_CHECK

Contains check classname.

=cut

use constant CLASS_CHECK => 'Noviforum::Adminalert::Check';

=head2 CLASS_HARNESS

Check harness class name.

=cut
use constant CLASS_HARNESS => 'Noviforum::Adminalert::CheckHarness';

=head2 CLASS_HISTORY

Contains history classname.

=cut
use constant CLASS_HISTORY => 'Noviforum::Adminalert::History';

=head2 CLASS_DAEMON

Daemon class name.

=cut
use constant CLASS_DAEMON => 'Noviforum::Adminalert::Daemon';

=head2 CLASS_RENDERER

Renderer class name.

=cut
use constant CLASS_RENDERER => 'Noviforum::Adminalert::Renderer';

=head2 CLASS_PROTOCOL

Protocol class name.

=cut
use constant CLASS_PROTOCOL => 'Noviforum::Adminalert::Protocol';

=head2 CLASS_CONFIG

Config class name.

=cut
use constant CLASS_CONFIG => 'Noviforum::Adminalert::Config';

=head2 CLASS_CONNECTION

Connection class name.

=cut
use constant CLASS_CONNECTION => 'Noviforum::Adminalert::Connection';

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter);

@EXPORT_OK = qw(
	CHECK_OK CHECK_ERR CHECK_WARN CHECK_INVALID
	ERR_MSG_UNDEF
	CLASS_CHECK CLASS_HISTORY CLASS_DAEMON CLASS_CONNECTION
	CLASS_CONFIG CLASS_HARNESS CLASS_RENDERER CLASS_PROTOCOL
	result2str str2result
);

@EXPORT = qw(
	CHECK_OK
	CHECK_ERR
	CHECK_WARN
	CHECK_INVALID
);

$EXPORT_TAGS{all} = [ @EXPORT_OK ];

our $VERSION = 0.10;

=head1 FUNCTIONS

=head2 result2str

Converts integer check result code to string.

=cut
sub result2str {
	my ($code) = @_;
	$code = CHECK_INVALID unless (defined $code);
	unless (exists($_s{$code})) {
		return $_s{CHECK_INVALID()};
	}
	return $_s{$code};
}

=head2 str2result

Converts string to check result code.

=cut
sub str2result {
	my ($str) = @_;
	return CHECK_INVALID unless (defined $str && length($str));
	$str = lc($str);
	foreach (keys %_s) {
		return $_ if (lc($_s{$_}) eq $str);
	}
	return CHECK_INVALID;
}

=head1 AUTHOR

Brane F. Gracnar

=cut

1;

# EOF