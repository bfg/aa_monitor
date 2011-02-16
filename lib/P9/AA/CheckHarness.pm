package P9::AA::CheckHarness;

use strict;
use warnings;

use POSIX qw(strftime);
use Time::HiRes qw(time);
use Scalar::Util qw(blessed);

use P9::AA::Constants qw(:all);

use P9::AA::Util;
use P9::AA::Check;
use P9::AA::Config;
use P9::AA::History;

use P9::AA::Log;

our $VERSION = 0.10;
my $log = P9::AA::Log->new();
my $u = P9::AA::Util->new();

=head1 NAME

Wrapper around L<P9::AA::Check> class for simple service checking.

=head1 DESCRIPTION

=head1 SYNOPSIS

 use Time::HiRes qw(time);
 use P9::AA::CheckHarness;
  
 # select check module
 my $module = 'DNS';
 
 # check module params
 my $params = {
 	host => 'www.example.com',
 	nameserver => '192.168.1.1',
 };
 
 # create checking harness
 my $harness = P9::AA::CheckHarness->new();
 
 # check start time
 my $ts = time();
 
 # perform check
 my $res = $harness->check($module, $params, $ts);

=head1 METHODS

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};
	$self->{_error} = "";
	$self->{_ts} = time();
	bless($self, $class);
	return $self;
}

=head2 error

Returns last error message.

=cut
sub error {
	my $self = shift;
	return $self->{_error};
}

=head2 check

 my $result = $harness->check($module, $params, $ts);

Tries to load $module implementation of L<P9::AA::Check> class, configures it with $params
and invokes L<P9::AA::Check|check()> method triggering service check.

This method also configures old/new service check history classes(L<P9::AA::History>), deals with
service check logging and time measuring.

Returns hash reference on success, otherwise undef and sets error message.

B<WARNING>: This method B<BLOCKS> during check execution. See L<P9::AA::CheckHarness::AnyEvent>
for asynchronous version if you can't afford blocking entire process while performing service checks.

=cut
sub check {
	my ($self, $module, $params, $ts) = @_;
	
	my $id = $u->newId();

	# check start time?
	{ no warnings; $ts += 0 };
	$ts = $self->{_ts} unless ($ts > 0);
	$ts = time() unless ($ts > 0);

	# check parameters?
	$params = {} unless (defined $params && ref($params) eq 'HASH');

	# get default check data object...
	my $data = $self->_newCheckData($ts);
	$data->{data}->{check}->{id} = $id;

	# remove module section
	delete($data->{data}->{module});
	
	# bad check module?
	unless (defined $module && ! ref($module) && length($module) > 0) {
		my $err = 'No check module was specified.';
		$err .= "\n\n";
		$err .= $self->getList();
		
		$data->{success} = 0;
		$data->{error} = $err;
		$data->{data}->{check}->{error_message} = $err;

		return $self->_doTotalTiming($data);
	}

	# is this check module allowed?
	return undef unless ($self->_isAllowed($module));

	# create check object
	my $check = CLASS_CHECK->factory($module, %{$params});
	unless (defined $check) {
		my $err = CLASS_CHECK->error();
		$log->error($err);
		$data->{error} = $err;
		$data->{data}->{check}->{error_message} = $err;		
		return $self->_doTotalTiming($data);
	}

	# ok we have check object, let's re-create
	# result data hash
	$data = $check->getResultDataStruct($ts);
	$data->{data}->{check}->{id} = $id;
	
	# get check object's hash value
	my $hashcode = $check->hashCode();
	
	# create new history object
	my $hist_new = CLASS_HISTORY->new();
	$hist_new->ident($hashcode);
	
	# try to load old history
	my $hist_old = $hist_new->load($hashcode);
	# $hist_old->setIdent($hashcode);

	# assign history objects...
	$check->historyNew($hist_new);
	$check->historyOld($hist_old);

	# temporary re-route stdio streams to check object
	tie *STDERR, $check;
	tie *STDOUT, $check;
	local *STH;
	tie *STH, $check;		# STH filehandle must be created, in order we want
							# to select() it.
	select(STH);			# default printing will be now appended to message
							# buffer using bufApp() method.

	# mark check startup time
	my $tc_start = time();
	my $check_as_str = $check->toString(); 
	$data->{data}->{check}->{as_string} = $check_as_str;
	my $c_error = undef;
	
	# PERFORM THE CHECK!
	local $@;
	my $c_result = eval { $check->check() };	

	# exception performing check?
	if ($@) {
		# format error message
		my $err = 'Exception performing check: ' . $@;
		$err =~ s/\s+$//;

		# set result and error message
		$c_result = CHECK_ERR;
		$c_error = $err;
	}
	elsif (! defined $c_result) {
		$c_result = CHECK_ERR;
	}

	# fix check timers
	$self->_doCheckTiming($data, $tc_start);
	
	# add result code...
	$data->{data}->{check}->{result_code} = $c_result + 0;

	# add messagebuffer
	$data->{data}->{check}->{messages} = $check->bufGet();
	
	# re-establish stdio streams
	untie *STH if (tied *STH);
	untie *STDERR if (tied *STDERR);
	untie *STDOUT if (tied *STDOUT);
	select(*STDOUT);
	
	# check error/warning message...
	$c_error = $check->error() unless (defined $c_error);
		
	# check error?
	if ($c_result == CHECK_ERR) {
		$data->{success} = 0;
		$data->{error} = $c_error;
		$data->{data}->{check}->{error_message} = $c_error;
	}
	# check ok, but with warning?
	elsif ($c_result == CHECK_WARN) {
		$data->{success} = 1;
		$data->{data}->{check}->{success} = 1;
		$data->{data}->{check}->{warning} = 1;
		$data->{data}->{check}->{error_message} = '';
		$data->{data}->{check}->{warning_message} = $check->warning();
	}
	# this must be success!
	elsif ($c_result == CHECK_OK) {
		$data->{success} = 1;
		$data->{data}->{check}->{success} = 1;
		$data->{error} = '';
		$data->{data}->{check}->{error_message} = '';
		$data->{data}->{check}->{warning_message} = '';
	}
	
	# has history changed?
	$self->_doHistory($data, $hist_old, $hist_new);

	# do the logging
	$self->_doLog($data);
	
	# fix timers and return data
	return $self->_doTotalTiming($data);
}

=head2 getList

 my $str = $harness->getList([ $as_html = 0]);

Returns list of all available checking modules with version and description as string.

=cut
sub getList {
	my ($self, $as_html) = @_;
	$as_html = 0 unless (defined $as_html);

	my $str = "List of available check modules:\n\n";
	foreach my $name (CLASS_CHECK->getDrivers()) {
		my $obj = CLASS_CHECK->factory($name);
		next unless (defined $obj);
		no warnings;
		if ($as_html) {
			$str .= "<div>\n";
			$str .= "<a href='/$name'>$name</a>\n";
			$str .="</div>\n";
		} else {
			$str .= sprintf(
				"%-30.30s(%-2.2f) :: %s\n",
				$name,
				$obj->VERSION(),
				$obj->getDescription()
			);
		}
	}
	return $str;
}

sub _doTotalTiming {
	my ($self, $s) = @_;

	# total time
	my $t = time();
	$s->{data}->{timings}->{total_finish} = $t;
	$s->{data}->{timings}->{total_duration} = $t - $s->{data}->{timings}->{total_start};
	return $s;
}

sub _doCheckTiming {
	my ($self, $s, $ts, $te) = @_;
	return 0 unless (defined $s && ref($s) eq 'HASH');
	no warnings;
	unless (defined $ts && $ts > 0) {
		$ts = $s->{data}->{timings}->{check_start}
	}
	
	if ($ts > 0) {
		$te = time() unless (defined $te && $te > 0);
		my $duration = $te - $ts;
	
		$s->{data}->{timings}->{check_duration} = $duration;
		$s->{data}->{timings}->{check_finish} = $te;
		$s->{data}->{timings}->{check_start} = $ts;
	
	} else {
		$s->{data}->{timings}->{check_start} = 0;
		$s->{data}->{timings}->{check_finish} = 0;
		$s->{data}->{timings}->{check_duration} = 0;
	}
}

sub _newCheckData {
	my $ts = time();
	my $c = CLASS_CHECK->new();
	return $c->getResultDataStruct();
}

sub _isAllowed {
	my ($self, $module) = @_;
	return 0 unless (defined $module);

	my $cfg = P9::AA::Config->new();

	# is this module allowed?
	my $enabled = $cfg->get('modules_enabled');
	my $disabled = $cfg->get('modules_disabled');
	
	# disabled module?
	if (ref($disabled) eq 'ARRAY' && grep(/^$module$/, @{$disabled}) > 0) {
		$self->{_error} = 'Check module is disabled.';
		return 0;
	}
	# not enabled?
	elsif (ref($enabled) eq 'ARRAY' && @{$enabled} && grep(/^$module$/, @{$enabled}) < 1) {
		$self->{_error} = 'Check module is not enabled.';
		return 0;
	}
	
	return 1;
}

sub _doHistory {
	my ($self, $data, $old, $new) = @_;
	return 0 unless (blessed($old) && blessed($new) && $old->isa(CLASS_HISTORY) && $new->isa(CLASS_HISTORY));
	return 0 unless (defined $data && ref($data) eq 'HASH');
	
	my $id = $data->{data}->{check}->{id};
	my $result = $data->{data}->{check}->{result_code};
	my $result_str = result2str($result);
	
	my $tc_old = $old->mget('time');
	my $tc_new = $data->{data}->{timings}->{check_finish};
	
	my $msg = '';
	if ($result == CHECK_ERR) {
		$msg = $data->{data}->{check}->{error_message};
	}
	elsif ($result == CHECK_WARN) {
		$msg = $data->{data}->{check}->{warning_message};
	}

	# assign new stuff
	$new->mset(time => $tc_new);
	$new->mset(result => $result);
	$new->mset(message => $msg);
	$new->mset(buf => $data->{data}->{check}->{messages});
	$new->mset(id => $id);

	# is this result different to last one?
	my $result_old = $old->mget('result');
	my $time_old = $old->mget('time');
	if ($result_old != $result && (defined $time_old && $time_old > 0)) {
		my $result_old_str = result2str($result_old);
		
		# last history time...
		my $history_time = strftime("%Y/%m/%d %H:%M:%S", localtime($time_old));		
		my $history_timediff = $tc_new - $time_old;

		# $data->{data}->{history}->{time} = $tc;
		
		# add history data to $data
		$data->{data}->{history}->{last_time} = $time_old;
		$data->{data}->{history}->{time_diff} = $history_timediff;
		$data->{data}->{history}->{changed} = 1;
		$data->{data}->{history}->{last_result_code} = $result_old;
		$data->{data}->{history}->{last_result} = result2str($result_old);
		$data->{data}->{history}->{last_message} = $old->mget('message');
		$data->{data}->{history}->{last_id} = $old->mget('id');
		$data->{data}->{history}->{last_buf} = $old->mget('buf');
		
		# log history change...
		my $log_str = "[$id] Check result changed since last check at $history_time from $result_old_str to $result_str.";
		$log->info($log_str);
	}
	
	# save new history
	unless ($new->save()) {
		$log->warn("[$id] Error saving history data: " . $new->error());
	}

	return 0;
}

sub _doLog {
	my ($self, $data) = @_;
	return 0 unless (defined $data && ref($data) eq 'HASH');
	
	my $id = $data->{data}->{check}->{id};
	my $module = $data->{data}->{module}->{name};
	my $check_as_str = $data->{data}->{check}->{as_string};
	my $result = $data->{data}->{check}->{result_code};

	# generate logging message
	my $log_str = "[$id] " . $module . ' [' . $check_as_str . ']; ' .
		'result=' . result2str($result);
	
	if ($result != CHECK_OK) {
		no warnings;
		if ($result == CHECK_ERR) {
			$log_str .= ' [' . $data->{data}->{check}->{error_message} . ']';
		}
		elsif ($result == CHECK_WARN){
			$log_str .= ' [' . $data->{data}->{check}->{warning_message} . ']';
		}
	}

	$log_str .= '; check_duration: ' . sprintf("%-.3f", ($data->{data}->{timings}->{check_duration}) * 1000) . ' ms';
	$log_str .= '; total_duration: ' . sprintf("%-.3f", (time() - $data->{data}->{timings}->{total_start}) * 1000) . ' ms';
	
	
	# now log the message
	if ($result == CHECK_OK) {
		$log->info($log_str);
	}
	elsif ($result == CHECK_WARN) {
		$log->warn($log_str);
	}
	else {
		$log->error($log_str);
	}
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<P9::AA::Check>
L<P9::AA::CheckHarness::AnyEvent>

=cut
1;