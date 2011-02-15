package Noviforum::Adminalert::Daemon::ANYEVENT::HTTPRequest;

use strict;
use warnings;

use AnyEvent::HTTPD::Request;

use base 'AnyEvent::HTTPD::Request';

sub header {
	my $self = shift;
	my $name = shift;

	# get headers
	my $h = $self->headers();
	
	# set header?!
	if (@_) {
		$h->{$name} = join('', @_);
		return 1;
	}

	# return header
	return (exists($h->{$name})) ? $h->{$name} : undef;
}

sub code {
	my $self = shift;
	if (@_) {
		return 200;
	}

	print "asked for status code.\n";
	return 200;
}

1;