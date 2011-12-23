package P9::AA::Check::Memory;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';

# version MUST be set
our $VERSION = 0.12;

=head1 NAME

System memory and swap checking module.

=head1 METHODS

This module inherits all methods from L<P9::AA::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"Checks memory and swap usage."
	);

	$self->cfgParamAdd(
		'swap_warn',
		5,
		'Swap warning threshold in %.',
		$self->validate_int(0, 99)
	);
	$self->cfgParamAdd(
		'swap_err',
		25,
		'Swap error threshold in %.',
		$self->validate_int(1, 99)
	);
	$self->cfgParamAdd(
		'buffers_err',
		0,
		'Buffers error threshold in %.',
		$self->validate_int(0, 99)
	);
	$self->cfgParamAdd(
		'shared_err',
		0,
		'Shared error threshold in %.',
		$self->validate_int(0, 99)
	);

	
	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;

	# get data
	my $data = $self->getMemoryUsage();
	return CHECK_ERR unless (defined $data);
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN MEMORY DATA ---");
		$self->bufApp($self->dumpVar($data));
		$self->bufApp("--- END MEMORY DATA ---");
	}

	my $res = CHECK_OK;
	my $err = '';
	my $warn = '';
	
	# check swap...
	my $swap_used = $self->_p($data->{swap}->{used}, $data->{swap}->{total});
	if ($swap_used > 0) {
		if ($swap_used > $self->{swap_err}) {
			$err .= "Swap usage of $swap_used% exceeds threshold of $self->{swap_err}%.\n";
			$res = CHECK_ERR;
		}
		elsif ($self->{swap_warn} && $swap_used > $self->{swap_warn}) {
			$warn .= "Swap usage of $swap_used% exceeds warning threshold of $self->{swap_warn}%.\n";
			$res = CHECK_WARN unless ($res == CHECK_ERR);
		}
	}
	
	# check memory
	my $buffers_p = $self->_p($data->{memory}->{buffers}, $data->{memory}->{total});
	if ($self->{buffers_err} && $buffers_p > $self->{buffers_err}) {
		$err .= "Buffers usage of $buffers_p% exceeds threshold of $self->{buffers_err}%.\n";
		$res = CHECK_ERR;
	}
	my $shared_p = $self->_p($data->{memory}->{shared}, $data->{memory}->{total});
	if ($self->{shared_err} && $shared_p > $self->{shared_err}) {
		$err .= "Buffers usage of $shared_p% exceeds threshold of $self->{shared_err}%.\n";
		$res = CHECK_ERR;
	}

	if (length $warn) {
		$warn =~ s/\s+$//g;
		$self->warning($warn);
	}
	if ($res != CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}

	return $res;
}


=head2 getMemoryUsage

 my $u = $self->getMemoryUsage();

Returns memory/swap usage struct on success, otherwise undef.

Example output structure:

 {
  'memory' => {
    'buffers' => 0,
    'cached' => 0,
    'free' => 400,
    'shared' => 0,
    'total' => 512,
    'used' => 102
  },
  'swap' => {
    'free' => 2040,
    'total' => 2048,
    'used' => 7
  }
 }

=cut
sub getMemoryUsage {
	my ($self) = @_;
	# memory...
	my ($buf, $s) = $self->qx2($self->getMemoryUsageCmd());
	return undef unless ($buf);

	# parse it...
	my $memory = $self->parseMemoryUsage($buf);
	return undef unless (defined $memory);

	($buf, $s) = $self->qx2($self->getSwapUsageCmd());
	return undef unless ($buf);
	my $swap = $self->parseSwapUsage($buf);
	return undef unless (defined $swap);
	
	return { memory => $memory, swap => $swap };	
}

=head2 getMemoryUsageCmd

 my $cmd = $self->getMemoryUsageCmd();

Returns command needed to obtain memory usage data on current OS.

=cut
sub getMemoryUsageCmd {
	my $self = shift;
	die "Method getMemoryUsageCmd() is not implemented in " . ref($self);
}

=head2 getSwapUsageCmd

 my $cmd = $self->getSwapUsageCmd();

Returns command needed to obtain swap usage data on current OS.

=cut
sub getSwapUsageCmd {
	my $self = shift;
	die "Method getMemoryUsageCmd() is not implemented in " . ref($self);	
}

=head2 parseMemoryUsage

 my $data = $self->parseMemoryUsage($raw);

Parses RAW output (can be scalar or array ref) of free command and
returns hashref on success, otherwise undef.

Example result:

 {
    'buffers' => '95',
    'cached' => '1338',
    'free' => '221',
    'shared' => '0',
    'total' => '2982',
    'used' => '2760'
 };

=cut
sub parseMemoryUsage {
	my $self = shift;
	die "Method parseMemoryUsage() is not implemented in " . ref($self);
}

=head2 parseSwapUsage

 my $swap_data = $self->parseSwapUsage($raw);

Parses RAW output (can be scalar or array ref) of free command and
returns hashref on success, otherwise undef.

Example result:

  {
    'free' => '5037',
    'total' => '5119',
    'used' => '82'
  }

=cut
sub parseSwapUsage {
	my $self = shift;
	die "Method parseSwapUsage() is not implemented in " . ref($self);	
}

sub _p {
	my ($self, $a, $b) = @_;
	return 0 if (!defined $b || $b == 0);
	my $r = (sprintf(
		"%-2.2f",
		(abs($a) * 100) / abs($b)
	) + 0);
#	if ($self->{debug}) {
#	  $self->bufApp("A: $a, B: $b, RES: $r");
#	}
	
	return $r;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;