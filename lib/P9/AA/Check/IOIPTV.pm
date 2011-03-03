package P9::AA::Check::IOIPTV;

use strict;
use warnings;

use P9::AA::Constants;
use base 'P9::AA::Check::XML';

# version MUST be set
our $VERSION = 0.10;

=head1 NAME

IP IPTV module.

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"IO IPTV check."
	);

	# you can also remove any previously created
	# configuration parameter.
	# $self->cfgParamRemove('debug');
	
	# this method MUST return 1!
	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# get XML
	my ($xml, $xml_str) = $self->getXML();
	return CHECK_ERR unless (defined $xml && ref($xml) eq 'HASH');
	
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN XML STRUCT ---");
		$self->bufApp($self->dumpVar($xml));
		$self->bufApp("--- END XML STRUCT ---");
	}
	
	my $task = (exists($xml->{task}) && ref($xml->{task}) eq 'ARRAY') ? $xml->{task} : undef;
	unless (defined $task) {
		return $self->error("XML doesn't contain task element.");
	}

	# validate contents
	my $res = CHECK_OK;
	my $err = '';
	my $warn = '';
	
	my $i = 0;
	foreach my $e (@{$task}) {
		$i++;
		unless (defined $e && ref($e) eq 'HASH') {
			$warn .= 'Invalid XML task element $i: Not a valid reference: ' .
				$self->dumpVarCompact($e) . "\n";
			$res = CHECK_WARN unless ($res == CHECK_ERR);
			next;
		}
		my $id = $e->{_id} || undef;
		my $bps = $e->{byteps} || undef;
		my $active = $e->{active} || undef;
		unless (defined $id && defined $bps && defined $active) {
			$warn .= 'Invalid XML task element $i: id, bps and active are not defined: ' .
				$self->dumpVarCompact($e) . "\n";
			$res = CHECK_WARN unless ($res == CHECK_ERR);
			next;
		}
		
		$active = lc($active);
		my ($name, $type) = split(/\s*[;,]\s*/, $id, 2);
		unless (defined $name && defined $type) {
			$warn .= 'Invalid XML task element $i: id doesn\'t contain name and type ' .
				$self->dumpVarCompact($e) . "\n";
			$res = CHECK_WARN unless ($res == CHECK_ERR);
			next;
		}

		# ok, now do the real check...
		unless ($active eq 'true' || $active eq 'yes' || $active eq '1') {
			$err .= "Channel $name is not active.\n";
			$res = CHECK_ERR;
		}
	}
	

	unless ($res == CHECK_OK) {
		$err =~ s/\s+$//g;
		$warn =~ s/\s+$//g;
		$self->warning($warn) if (length($warn));
		$self->error($err) if (length($err));
	}

	return $res;
}

=head1 SEE ALSO

L<P9::AA::Check>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;