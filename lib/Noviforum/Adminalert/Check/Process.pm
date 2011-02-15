package Noviforum::Adminalert::Check::Process;

use strict;
use warnings;

use File::Basename;

use Noviforum::Adminalert::Constants;
use Noviforum::Adminalert::ParamValidator qw(validator_regex);

use base 'Noviforum::Adminalert::Check';

our $VERSION = 0.11;

my @script_interpreters = (
	qr/bin\/(?:ba|a|c|z|k)?sh$/,		# shells
	qr/bin\/(?:perl|python|ruby|php)$/,	# most popular script script interpreters
	qr/bin\/expect/,					# expect
);

=head1 NAME

Running process(es) discovering module.

=head1 DESCRIPTION

This module checks if specific process runs on system.

Module inherits from L<Noviforum::Adminalert::Check>

=head1 METHODS

=cut
# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks if a process is running."
	);
	
	$self->cfgParamAdd(
		'cmd',
		undef,
		'Running process must match specified regex pattern. Syntax: /PATTERN/flags',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'user',
		undef,
		'Process must be running by specified username or uid.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'use_basename',
		0,
		'Match cmd regex pattern against process basename?',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'detect_interpreters',
		0,
		'Try to detect common interpreter processes and match by running scripts.',
		$self->validate_bool(),
	);
	$self->cfgParamAdd(
		'min_process_count',
		1,
		'Minumum number of processes that must be discovered.',
		$self->validate_int(1),
	);
	
	return 1;
}

=head2 check

Check implementation.

=cut
sub check {
	my ($self) = @_;
	
	my $rv = validator_regex(undef);
	my $re = $rv->($self->{cmd});
	unless (defined $re) {
		no warnings;
		return $self->error("Invalid cmd regex '$self->{cmd}'; Valid syntax: /PATTERN/flags");
	}

	# get processes
	my $pl = $self->getProcessListComplex(
		basename => $self->{use_basename},
		user => $self->{user},
		regex => $re,
	);
	return CHECK_ERR unless (defined $pl);
	
	if ($self->{debug}) {
		$self->bufApp('--- BEGIN MATCHED PROCESSLIST ---');
		$self->bufApp($self->dumpVar($pl));
		$self->bufApp('--- END MATCHED PROCESSLIST ---');
	}

	my $num = scalar(@{$pl});
	$self->bufApp("Discovered $num process(es).");
	
	if ($num < $self->{min_process_count}) {
		return $self->error(
			"Discovered $num out of $self->{min_process_count} " .
			"required process(es)."
		);
	}
	
	return CHECK_OK;
}

=head2 getProcessListCmd

Returns command (as string) that should be executed on current OS to get list of B<all>
running processes.

=cut
sub getProcessListCmd {
	return 'ps -ef';
}

=head2 getProcessList

Returns arrayref of hashrefs describing list of currently running processes on system
on success, otherwise undef.

Example output:

 $res = [
  {
    'cmd' => '/opt/google/chrome/chrome',
    'pid' => '21948',
    'ppid' => '15190',
    'stime' => '10:10',
    'time' => '00:00:02',
    'uid' => 1000,
    'user' => 'bfg'
  },
  {
    'cmd' => '/usr/bin/amarok',
    'pid' => '22518',
    'ppid' => '1',
    'stime' => '10:15',
    'time' => '00:13:03',
    'uid' => 1000,
    'user' => 'bfg'
  },
 ];

=cut
sub getProcessList {
	my ($self) = @_;
	my $str = $self->getProcessListCmd();
	return undef unless (defined $str && length($str));

	# get processlist...
	my ($out, $exit_status) = $self->qx2($str);
	unless (defined $out && $exit_status == 0) {
		$self->error(
			"Unable to obtain process list: " .
			$self->error()
		);
		return undef;
	}
	
	#if ($self->{debug}) {
	#	$self->bufApp("--- BEGIN PROCESS LIST ---");
	#	map { $self->bufApp($_) } @{$out};
	#	$self->bufApp("--- END PROCESS LIST ---");
	#}

	my $data = [];
	foreach (@{$out}) {
		# trim
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		next if ($_ =~ m/^uid\s+/i);
		
		my ($user, $pid, $ppid, $c, $stime, $tty, $time, $cmd, @rest) = split(/\s+/, $_);
		next unless (defined $cmd && length($cmd));
		$cmd .= ' ' . join(' ', @rest) if (@rest);
		
		# ignore kernel processes
		next if ($cmd =~ m/^\[[\w\-\/:]+\]$/);
		
		# resolve user => uid
		my $uid = getpwnam($user);

		push(
			@{$data},
			{
				user => $user,
				uid => $uid,
				pid => $pid,
				ppid => $ppid,
				stime => $stime,
				time => $time,
				cmd => $cmd,
			}
		);
	}
	
	return $data;
}

=head2 getProcessListComplex (key => val, key2 => val2)

Returns filtered process list with the same structure as L<getProcessList> on success according to specified
filter keys on success, otherwise undef.


Supported filter keys:

=over

=item B<regex> (compiled regex, undef): Process must match specified pattern

=item B<basename> (boolean, 0): Apply B<regex> pattern to process basename

=item B<user> (string/integer, undef): Process uid or username must specified string/integer.

=back

=cut
sub getProcessListComplex {
	my ($self, %opt) = @_;
	my %o = (
		basename => $opt{basename} || 0,
		user => $opt{user} || undef,
		regex => $opt{regex} || undef,
	);
	
	# get all processes
	my $all = $self->getProcessList();
	return undef unless (defined $all);
	
	my $data = [];
	
	# filter $all
	foreach my $e (@{$all}) {
		my @cmd = split(/\s+/, $e->{cmd});
		
		# script interpreter process?
		if ($self->isScriptInterpreter($cmd[0])) {
			#print "  Is interpreter: '$cmd[0]': YES\n";
			# remove interpreter
			shift(@cmd);
			
			# remove interpreter arguments...
			while (@cmd) {
				# script command must start with /, ./ or alphanum char
				last if ($cmd[0] =~ m/^\.?\// || $cmd[0] =~ m/^\w+/);
				# print "  stripping interpreter argument: '$cmd[0]'\n";
				shift(@cmd);
			}
			
			# print "CMD: ", join(", ", @cmd), " out of '$e->{cmd}'\n";
		}
		
		my $cmd_str = '';

		# basename match?
		if ($o{basename}) {
			my $x = shift(@cmd);
			if (defined $x) {
				$cmd_str = basename($x);
			}
		} else {
			$cmd_str = shift(@cmd);
		}
		next unless (defined $cmd_str);
		$cmd_str .= ' ' . join(' ', @cmd) if (@cmd);
		
		# user check?
		if (defined $o{user} && length($o{user})) {
			if (defined $e->{user}) {
				next unless ($e->{user} eq $o{user});
			}
			elsif (defined $e->{uid}) {
				next unless ($e->{uid} eq $o{user});
			}
		}
		
		# does command matches regex?
		if (defined $o{regex}) {
			# print "validating $o{regex} pattern against string: '$cmd_str'\n";
			next unless ($cmd_str =~ $o{regex});
		}
	
		# this process matches...
		push(@{$data}, $e);
	}
	
	return $data;
}

sub isScriptInterpreter {
	my ($self, $str) = @_;
	return 0 unless ($self->{detect_interpreters});
	
	foreach (@script_interpreters) {
		return 1 if ($str =~ $_);
	}
	
	return 0;
}

=head1 AUTHOR

Uros Golja, Brane F. Gracnar

=head1 SEE ALSO

L<Noviforum::AdminAlert::Check>

=cut

1;