package P9::AA::History;

use strict;
use warnings;

use File::Spec;
use Scalar::Util qw(blessed);
use Storable qw(lock_nstore lock_retrieve dclone);

our $VERSION = 0.11;

use constant IDENT_PREFIX => "history.";

##################################################
#             OBJECT CONSTRUCTOR                 #
##################################################


=head1 NAME

Simple persistent data container.

=head1 DESCRIPTION

This class is used by L<P9::AA::CheckHarness> and L<P9::AA::Check>
classes for cross-service-check data persistence.

=head1 CONSTRUCTOR

Constructor doesn't accept any arguments.

=cut
sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = {};

	bless($self, $class);
	$self->reset();
	return $self;
}

##################################################
#              PUBLIC  METHODS                   #
##################################################

=head1 METHODS

=head2 error

Returns last error message.

=cut
sub error {
	my $self = shift;
	if (@_) {
		my $e = $self->{_error};
		$self->{_error} = join('', @_);
		return $e;
	}
	return $self->{_error};
}

=head2 reset

Resets internal state to default values. All saved data B<except> object ident will be lost. See L</ident> method
description for explanation.

=cut
sub reset {
	my ($self) = @_;
	
	# last error...
	$self->{_error} = '';
	
	# ping data
	$self->{_mdata} = {};
		
	# custom data
	$self->{_cdata} = {};
	
	# storage directory...
	$self->{_dir} = File::Spec->tmpdir();

	# object ident...
	unless (exists $self->{_ident} && defined $self->{_ident}) {
		$self->{_ident} = undef;
	}

	$self->{_mdata} = {
		result => -1,
		message => '',
		msgbuf => '',
		time => 0
	};

	return 1;
}

=head2 clone

Clones existing history object and clears L</ident> flag.

=cut
sub clone {
	my ($self) = @_;
	local $@;
	my $clone = eval { dclone($self) };
	$clone->{_ident} = undef if (defined $clone);
	return $clone;
}

=head1 METADATA METHODS

L<P9::AA::Check/check> result and support information are considered as metadata. 

=head2 mset

 $history->mset($key, $val);

Sets metadata key $key to value $val.

=cut
sub mset {
	my ($self, $key, $val) = @_;
	$self->{_mdata}->{"$key"} = $val;
}

=head2 mget

 my $val = $history->mget($key);

Retrieves metadata key $key.

=cut
sub mget {
	my ($self, $key) = @_;
	return (exists $self->{_mdata}->{"$key"}) ? $self->{_mdata}->{"$key"} : undef; 
}

=head1 OTHER METHODS

=head2 get

 my $val = $history->get($key);

Returns previously set property $name on success. Returns undef in case of invalid
key $key or if $key was not set.

=cut
sub get {
	my ($self, $key) = @_;
	return undef unless (defined $key && length($key));
	return undef unless (exists($self->{_cdata}->{$key}));
	return $self->{_cdata}->{$key};
}


=head2 set

 $history->set($key, $val);

Sets custom property $key.

Returns 1 on success, otherwise 0.

=cut
sub set {
	my ($self, $key, $val) = @_;
	unless (defined $key && length($key) > 0) {
		return 0;
	}
	$self->{_cdata}->{$key} = $val;
	return 1;
}

=head1 PERSISTENCE METHODS

=head2 ident

 # set ident
 $history->ident('sfkjhsfkhkshfskdhfsd');
 
 # retrieve ident
 my $ident = $history->ident();

Retrieves or sets new ident string. Ident is used by filename computation by L</load> and L</save> methods.
Both of them will fail unless there is no ident set.

Returns ident string on success, otherwise undef.

B<WARNING:> once ident is set it cannot be changed.
 
=cut
sub ident {
	my ($self, $str) = @_;
	if (defined $str && length($str)) {
		# ident already set?
		return undef if (defined $self->{_ident});
		
		# set new one
		$self->{_ident} = $str;
	}
	return $self->{_ident};
}

=head2 dir

 # get current directory...
 my $dir = $history->dir();
 
 # set new directory...
 my $dir = $history->dir("/some/other/dir");

Retrieves or sets storage directory.

=cut
sub dir {
	my ($self, $dir) = @_;
	if (defined $dir && -d $dir && -w $dir) {
		$self->{_dir} = $dir
	}
	return $self->{_dir};
}

=head2 load

 $history->load($ident [, $dir = File::Spec->tmpdir() ]);

Tries to load history for ident $ident. Always returns new initialized history
object regardless if loading of existing file succeeded or not.

=cut
sub load {
	my ($self, $ident, $dir) = @_;
	my $file = $self->_fname($dir, $ident);
	return __PACKAGE__->new() unless (defined $ident && defined $file);

	# try to load it.
	local $@;
	my $obj = eval { lock_retrieve($file) };
	
	# problem?
	if ($@ || ! (defined $obj && blessed($obj) && $obj->isa(__PACKAGE__))) {
		$obj = __PACKAGE__->new();
		$obj->ident($ident);
	}

	return $obj;
}

=head2 save

 my $res = $history->save([ $dir = File::Spec->tmpdir() ]);

Tries to save current object to disk using specified ident.

Returns 1 on success, otherwise 0.

=cut
sub save {
	my ($self, $dir) = @_;
	my $file = $self->_fname($dir);
	return 0 unless (defined $file);

	local $@;
	eval { lock_nstore($self, $file) };
	if ($@) {
		$self->error("Error saving to file $file: $@");
		return 0;
	}
	
	# lock permissions
	chmod(oct("600"), $file);

	return 1;
}

##################################################
#              PUBLIC  METHODS                   #
##################################################

sub _fname {
	my ($self, $dir, $ident) = @_;
	$dir = $self->{_dir} unless (defined $dir && length($dir));
	$ident = $self->{_ident} unless (defined $ident);
	my $sfx = (defined $ident && length($ident) > 0) ?
		'.' . $ident :
		''; 
	
	return File::Spec->catfile(
		$dir,
		IDENT_PREFIX . $> . $sfx
	);
}

=head1 SEE ALSO

L<Storable> - storage format used by this module.

=head1 AUTHOR

Brane F. Gracnar

=cut

1;