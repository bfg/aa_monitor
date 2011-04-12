package P9::AA::Util;

use strict;
use warnings;

use Data::Dumper;
use Text::ParseWords;
use Scalar::Util qw(blessed);

our $VERSION = 0.11;

my $_obj = undef;

=head1 NAME

Miscellaneous handy methods.

=head1 SYNOPSIS

 my $u = P9::AA::Util->new();
 
 my ($output, $exit_code) = $u->qx2('ls -al /tmp');
 unless (defined $output) {
 	print "error: ", $u->error(), "\n";
 }

=head1 CONSTRUCTOR

Object constructor doesn't take any parameters and B<always returns singleton>
instance.

=cut
sub new {
	return $_obj if (defined $_obj);

	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = { _error => '' };
	return bless($self, __PACKAGE__);
}

=head1 METHODS

=head2 error

Returns last error.

=cut
sub error {
	return shift->{_error};
}

=head2 qx

Runs command specified as string or array using qx// operator. Returns arrayref containing
command output in scalar context or (output, exit_code) in list context.

Method returns B<undef> in case of exception.

 my $cmd = "ls -al /tmp /etc";
 my $output = $check->qx($cmd);	# $output is ARRAY reference
                                # containing $cmd output one line per list element.
 
 # we want exit code too!
 my ($output, $exit_code) = $check->qx($cmd);
 
 # check for injuries
 unless (defined $output) {
 	print "HORRIBLE ERROR: ", $check->error(), "\n";
 }
 
 # check exit code
 if ($exit_code != 0) {
 	print "ERROR executing command: ", $check->error(), "\n";
 }
 
 # we don't want to involve shell to get
 # program's output...
 my @cmd = qw(/bin/ls -al /tmp /etc);
 my ($output, $exit_code) = $check->qx(@cmd);

B<NOTE:> Exit code is computed from B<$?> using L<getExitCode> method.

=cut
sub qx {
	my $self = shift;
	unless (@_) {
		$self->_error('No command was given.');
		return undef;
	}

	my $cmd_str = join(' ', @_);

	# result structure
	my $result = [];

	# run command...
	@{$result} = qx/@_/;
	my $s = $?;
	if ($@) {
		$self->_error("Exception while running command '$cmd_str': $@");
		return undef;
	}
	my $exit_code = $self->getExitCode($s);

	return (wantarray ? ($result, $exit_code) : $result);
}

=head2 qx2

"Improved" version of L<qx> method. Takes command string, resolves
words using B<shellwords> function in L<Text::ParseWords>, tries to resolve full program name
using L<which> method and invokes command capturing it's stdout
without involving shell (/bin/sh -c).

For return values see L<qx> method.

B<WARNING:> STDERR output is lost and stream redirection doesn't work.
 
 # this is shorter way of...
 my ($output, $exit_code) = $self->qx2('ls /tmp');
 
 # doing this:
 my ($output, $exit_code) = $self->qx('/bin/ls', '/tmp');

See also L<qx> method for return argument description.

=cut
sub qx2 {
	my $self = shift;
	unless (@_) {
		$self->_error("No command to run was given.");
		return undef;
	}

	my @cmd = shellwords(@_);
	my $prog = shift(@cmd);
	my $full_prog = $self->which($prog);
	return undef unless (defined $full_prog);
	unshift(@cmd, $full_prog);

	# do the execution
	return $self->qx(@cmd);
}

=head2 getExitCode

 system('some_cmd');
 my $rv = $?;
 
 # get exit code
 my $exit_code = $u->getExitCode($rv);
 if ($exit_code >= 0) {
 	print "Proces exited with exit code: $exit_code\n";
 }
 else {
 	print "Process execution failed: ", $u->error(), "\n";
 }
 
Converts q//, system(), qx// or SIGCHLD return status to process exit
code. Returns B<-1> for failed execution, otherwise exit code.

=cut
sub getExitCode {
	my ($self, $code) = @_;
	if ($code < 0) {
		$self->_error("Failed to execute: $!");
		return -1;
	}
	elsif ($code & 127) {
		$self->_error("Process died with signal "
			  . ($code & 127) . ", "
			  . ($code & 128) ? "with" : "without" . " coredump.");
		return -1;
	}
	else {
		return ($code >> 8);
	}
}

=head2 which

Search for program $prog in $PATH. Returns full executable on success,
otherwise undef.

 my $full_path = $u->which('ls');	# returns '/bin/ls' on most systems

=cut

sub which {
	my ($self, $prog) = @_;
	unless (defined $prog) {
		$self->_error("Undefined program name.");
		return undef;
	}

	# already full path name?
	return $prog if (-f $prog && -x $prog);

	# sanitize prog
	$prog =~ s/[^\w\-\.]//gi;
	unless (length($prog)) {
		$self->_error("Zero-length program name.");
		return undef;
	}

	foreach my $dir (split(/[:;]+/, $ENV{PATH}), "/usr/local/bin", "/sbin", "/usr/sbin", "/usr/local/sbin") {
		my $f = File::Spec->catfile($dir, $prog);
		return $f if (-x $f);
		
		if ($^O =~ m/(?:win|os2)/i) {
			$f .= ".exe";
			return $f if (-x $f);
		}
	}

	$self->_error("Program '$prog' was not found in \$PATH.");
	return undef;
}

=head2 dumpVar

Returns human readable string representation of method arguments using L<Data::Dumper>.

=cut
sub dumpVar {
	my $self = shift;
	my $d    = Data::Dumper->new([@_]);
	$d->Terse(1);
	$d->Sortkeys(1);
	$d->Indent(1);
	return $d->Dump();
}

=head2 dumpVarCompact

Returns shortest possible string representation of method arguments using L<Data::Dumper>.

=cut
sub dumpVarCompact {
	my $self = shift;
	my $d    = Data::Dumper->new([@_]);
	$d->Terse(1);
	$d->Sortkeys(1);
	$d->Indent(0);
	return $d->Dump();
}

=head2 newId ()

Returns new random id as 8 character string.

=cut

sub newId {
	return sprintf("%x", int(rand(0xFFFFFFFF)));
}

=head2 getBaseUrl

 my $base_url = $u->getBaseUrl($uri_object);

Returns aa_monitor base URL (string) from provided L<URI> object.

=cut
sub getBaseUrl {
	my ($self, $uri) = @_;
	return '/' unless (blessed($uri) && $uri->isa('URI'));
	
	my $u = '';
	if ($uri->can('host_port')) {
		my $scheme = $uri->scheme();
		$u = $scheme || 'http';
		$u .= '://';
		$u .= $uri->host();
		my $p = $uri->port();
		if (defined $scheme && $scheme eq 'https') {
			$u .= ":$p" unless ($p == 443);
		} else {
			$u .= ":$p" unless ($p == 80);
		}
	}
	
	# add path...
	my $path = $uri->path();

	# strip documentation info
	$path =~ s/\/doc\/*.*//g;
	
	my @path = split(/\/+/, $path);
	
	# add path
	#$path .= '/' unless (length $path);
	$u .= $path;
	#print STDERR "base url from uri '$uri' => '$u'\n";
	
	return $u;
}

sub _error {
	my $self = shift;
	if (@_) {
		$self->{_error} = join('', @_);
	} else {
		$self->{_error} = '';
	}
}

=head1 AUTHOR

Brane F. Gracnar

=cut
1;