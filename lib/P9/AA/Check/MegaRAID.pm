package P9::AA::Check::MegaRAID;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check';

our $VERSION = 0.16;

=head1 NAME

LSI Logic MegaRAID adapter checking module.

=head1 METHODS

This class inherits all methods from L<P9::AA::Check>.

=cut
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks MegaRAID RAID array consistency."
	);

	$self->cfgParamAdd(
		'rebuild_state_is_ok',
		0,
		'Consider rebuild state as normal, errorless state?',
		$self->validate_bool(),
	);

	return 1;
}

sub check {
	my ($self) = @_;
	
	# get list of all adapters...
	my $data = $self->getAdapterData();
	return CHECK_ERR unless (defined $data);

	# print nice volume summary...
	$self->bufApp($self->adapterDataToString($data));

	if ($self->{debug}) {
		$self->bufApp("--- BEGIN MEGARAID DATA ---");
		$self->bufApp($self->dumpVar($data));
		$self->bufApp("--- END MEGARAID DATA ---");
	}
	
	my $res = CHECK_OK;
	my $err = '';
	my $warn = '';
	
	foreach my $adapter (sort keys %{$data}) {
		my $a = $data->{$adapter};
		foreach my $vol (@{$a->{volumes}}) {
			my $channel = $vol->{channel};
			my $target = $vol->{target};
			my $s = lc($vol->{status});
			next unless (defined $s && length $s);
			
			unless ($s eq 'online') {
				# rebuild maybe?
				if ($self->{rebuild_state_is_ok} && _is_rebuild($s)) {
					$warn .= "Adapter $adapter, channel $channel, target $target: $s\n";
					$res = CHECK_WARN unless ($res == CHECK_ERR);
				}
				# nop, plain error
				else {
					$err .= "Adapter $adapter, channel $channel, target $target: $s\n";
					$res = CHECK_ERR;					
				}
			}
		}
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

=head2 getAdapterData

 my $data = $self->getAdapterData();

Returns hash reference containing volume/disk info for B<all> adapters found on system on
success, otherwise undef.

Example output:

 {
  # adapter number: 0
  '0' => {
    'card' => 'LSI MegaRAID SATA300-8X PCI-X',
    'firmware' => '40LD/8SPAN',
    'volumes' => [
      {
        'channel' => '0',
        'status' => 'online',
        'target' => '00'
      },
      {
        'channel' => '0',
        'status' => 'online',
        'target' => '01'
      }
    ]
  }
 }

=cut
sub getAdapterData {
	my ($self, $adapter) = @_;
	$self->error("This method is not supported on " . $self->getOs() . " operating system.");
	return undef;
}

=head2 getAdapterList

 my $list = $self->getAdapterList();

Returns array reference of MegaRAID adapter numbers on success, otherwise undef.

Example return value:

 [
  {
    'adapter' => 0,
    'card' => 'LSI MegaRAID SATA300-8X PCI-X',
    'firmware' => '40LD/8SPAN'
  }
 ]

=cut
sub getAdapterList {
	my ($self) = @_;
	$self->error("This method is not implemented on " . $self->getOs() . " operating system.");
	return undef;
}

=head2 adapterDataToString

 my $str = $self->adapterDataToString($data);

Formats data returned by L</getAdapterData> to nice string summary.

=cut
sub adapterDataToString {
	my ($self, $data) = @_;
	no warnings;
	my $buf = '';

	foreach my $adapter (sort keys %{$data}) {
		my $a = $data->{$adapter};
		$buf .= "ADAPTER: $adapter\n";
		foreach my $vol (@{$a->{volumes}}) {
			my $channel = $vol->{channel};
			my $target = $vol->{target};
			my $s = lc($vol->{status});
			next unless (defined $s && length $s);

			$buf .= "  channel $channel, target $target: $s\n";
		}
		$buf .= "\n";
	}
	
	return $buf;
}

sub _is_rebuild {
	my ($s) = @_;
	return 0 unless (defined $s && length $s);
	$s = lc($s);
	return ($s eq 'rbld' && $s eq 'rebuild' && $s eq 'rebuilding') ? 1 : 0;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;