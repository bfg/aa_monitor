package Noviforum::Adminalert::Check::Kerberos;

use strict;
use warnings;

use Authen::Krb5::Simple;

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check';

our $VERSION = 0.11;

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks KerberosV authentication system."
	);

	$self->cfgParamAdd(
		'realm',
		'EXAMPLE.ORG',
		'Kerberos realm',
		$self->validate_str(250),
	);
	$self->cfgParamAdd(
		'username',
		undef,
		'Kerberos username',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'password',
		undef,
		'Kerberos password.',
		$self->validate_str(200),
	);

	return 1;
}

sub check {
	my ($self) = @_;
	my $krb = Authen::Krb5::Simple->new();
	$krb->realm($self->{realm});
	
	unless (defined $self->{username} && defined $self->{password}) {
		return $self->error("Undefined username or password.");
	}

	local $@;
	my $r = eval { $krb->authenticate($self->{username}, $self->{password})	};

	if ($@) {
		return $self->error("Kerberos authentication failed: $@");
	}
	elsif (! $r) {
		return $self->error("Kerberos error " . $krb->errcode() . ": " . $krb->errstr());
	}

	return CHECK_OK;
}

sub toString {
	my $self = shift;
	no warnings;
	return $self->{username} . '@' . $self->{realm};
}

=head1 AUTHOR

Brane F. Gracnar

=cut

1;