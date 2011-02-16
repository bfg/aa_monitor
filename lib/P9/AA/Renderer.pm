package P9::AA::Renderer;

use strict;
use warnings;

use POSIX qw(strftime);
use Time::HiRes qw(time);
use Scalar::Util qw(blessed);

use base 'P9::AA::Base';

our $VERSION = 0.11;

=head1 NAME

Check result data rendering class.

=head1 METHODS

This class inherits all methods from L<P9::AA::Base>.

=head2 render

 my $formatted = $renderer->render($data, $dst);

Renders hash reference returned by L<P9::AA::CheckHarness/check> method.

Returns raw formatted data on success, otherwise undef.

=cut
sub render {
	my ($self, $data, $res) = @_;
	die "Method render() is not implemented by " . ref($self) . " class.\n";
	return undef;
}

=head2 timeAsString

 use Time::HiRes qw(time);
 
 my $time_str = $renderer->timAsString(time());

Formats high resolution time to string.

=cut
sub timeAsString {
	my ($self, $time) = @_;
	$time = time() unless (defined $time);

	# time formatting string
	my $fmt_str = "%Y/%m/%d %H:%M:%S.%%-.3s %Z";

	# get int and frac
	my $int = int($time);
	my $frac = ($time - $int);
	if ($frac =~ /^0\.(\d+)$/) {
        $frac = $1;
	}

	# format first portion
	$fmt_str = strftime($fmt_str, localtime($int));

	# add microseconds && return
	return sprintf($fmt_str, $frac);
}

=head2 setHeader 

 $renderer->setHeader($dst, 'Content-Type', 'text/plain; charset=utf-8');

Tries to set http response header on B<$dst>; $dst can be object which
has implemented method B<header> (like L<HTTP::Response>) or it can be simple
hash reference, where just hash key will be set.  

=cut
sub setHeader {
	my $self = shift;
	my $obj = shift;
	my $name = shift;
	return 0 unless (defined $obj && defined $name);
	return 0 unless (ref($obj));
	
	my $v = join('', @_);
	return 0 unless (defined $v && length($v));
	
	if (blessed($obj)) {
		if ($obj->can('header')) {
			$obj->header($name, $v);
		}
	}
	elsif (ref($obj) eq 'HASH') {
		$obj->{$name} = $v;
	}
	return 1;	
}

=head1 SEE ALSO

L<P9::AA::CheckHarness>, 

L<P9::AA::Renderer::JSON>, 
L<P9::AA::Renderer::XML>,  
L<P9::AA::Renderer::HTML>, 
L<P9::AA::Renderer::PLAIN>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;