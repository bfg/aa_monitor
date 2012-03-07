package P9::AA::Check::IOIPTV;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::XML';

# version MUST be set
our $VERSION = 0.11;

=head1 NAME

IO IPTV module.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"IO IPTV check."
	);

	$self->cfgParamAdd(
		'min_byteps',
		0,
		'Minimum byteps rate.',
		$self->validate_int(0)
	);	
	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# get XML
	my $p = $self->getXMLParser(ForceArray => 0);
	my ($xml, $xml_str) = $self->getXML(parser => $p);
	return CHECK_ERR unless (defined $xml && ref($xml) eq 'HASH');
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN XML STRUCT ---");
		$self->bufApp($self->dumpVar($xml));
		$self->bufApp("--- END XML STRUCT ---");
	}
	
	my $res = CHECK_OK;
	
	my $task = (exists($xml->{task}) && ref($xml->{task}) eq 'ARRAY') ? $xml->{task} : undef;
	if (! defined $task) {
		# try to validate single element
		return $self->_checkChannel($xml);
	} else {
		my $i = 0;
		foreach my $e (@{$task}) {
			$i++;
			my $r = $self->_checkChannel($e, $i);
			if ($r != CHECK_OK) {
				$res = $r unless ($res == CHECK_ERR);
			}
		}
	}
	
	return $res;
}

sub _checkChannel {
	my ($self, $e, $i) = @_;
	$i = 1 unless (defined $i);
	unless (defined $e && ref($e) eq 'HASH') {
		no warnings;
		return $self->error($self->error() . "\nNot a hash reference.");
	}
	
	my $res = CHECK_OK;
	my $err = '';
	my $warn = '';
	
	# $self->bufApp("HAHAHAHA: " . $self->dumpVar($e));

	my $id = $e->{_id} || undef;
	my $bps = eval { no warnings; int($e->{byteps}) } || 0;
	my $active = $e->{active} || undef;
	unless (defined $id && defined $bps && defined $active) {
		$warn .= "Invalid XML task element: id, bps and active are not defined.\n";
		$res = CHECK_WARN unless ($res == CHECK_ERR);
	}

	$active = lc($active);
	my ($name, $type) = split(/\s*[;,]\s*/, $id, 2);
#	unless (defined $name && defined $type) {
#		$warn .= "Invalid XML task element $i: id doesn't contain name and type.\n";
#		$res = CHECK_WARN unless ($res == CHECK_WARN);
#	}

	# ok, now do the real check...
	unless ($active eq 'true' || $active eq 'yes' || $active eq '1') {
		$err .= "Channel $name is not active.\n";
		$res = CHECK_ERR;
	}
	
	# check rate
	if ($self->{min_byteps} > 0 && $bps < $self->{min_byteps}) {
		$err .= "Rate $bps B/s is lower than specified rate of $self->{min_byteps} B/s.\n";
		$res = CHECK_ERR;
	}
	
	unless ($res == CHECK_OK) {
		no warnings;
		my $pfx = "Channel [" . ((defined $name) ? $name : $i) . "]: ";
		if ($res == CHECK_WARN) {
			$self->warning($self->warning() . $pfx . $warn);
		}
		if ($res == CHECK_ERR) {
			$self->error($self->error() . $pfx . $err);
		}
	}

	return $res;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;