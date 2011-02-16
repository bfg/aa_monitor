package P9::AA::Check::Mount;

use strict;
use warnings;

use File::Basename;
use File::Spec;

use P9::AA::Constants;
use base 'P9::AA::Check';

use constant PROGRAM_NAME => 'mount';

our $VERSION = 0.16;

##################################################
#             OBJECT CONSTRUCTOR                 #
##################################################

##################################################
#              PUBLIC  METHODS                   #
##################################################

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks if all fstab entries are mounted. Excluded are swap and ones with 'noauto' option set."
	);
	
	die "Not implemented in new framework.";

	$self->{use_posix} = 0;
	$self->{follow_symlinks} = 1;
	$self->{debug} = 0;
}

# actually performs ping
sub check {
	my ($self) = @_;
	my $ok_flag = 1;
	my $fstab = $self->readFstab();
	my $mount = $self->readMounted();	
	return 0 unless (defined $fstab);
	return 0 unless (defined $mount);

	$self->bufApp();

	for my $i (keys %{$fstab}) {
		if (-e $i && -l $i) {
			my $str = "Fstab entry \"$i\" appears to be symbolic link.";
			if (! $self->{follow_symlinks}) {
				$str .= " Symlink resolving is turned off.";
			} else {
				$str .= " Trying to resolve it.";

				my $real_dest = undef;
				eval {
					$real_dest = readlink($i);
				};
				if ($@) {
					$self->{error} = "Unable to read destination for symbolic link \"$i\": $@";
					return 0;
				}
				unless (defined $real_dest) {
					$self->bufApp("WARNING: Fstab contains unresolvable symbolic link \"$i\"");
					next;
				}

				if ($real_dest =~ m/^\//) {
					$i = $real_dest;
				}
				elsif ($real_dest =~ /^.\/(.+)/) {
					$i = File::Spec->catfile(dirname($i), $1);
				} else {
					$i = File::Spec->catfile(dirname($i), $real_dest);
				}
				$str .= " Resolved to \"$i\".";
			}

			$self->bufApp($str);
		}
		unless(exists($mount->{$i})) {
			$ok_flag = 0;
			my $str = $i . " is NOT mounted!  (" . $fstab->{$i} . ")";
			$self->bufApp($str);
			$self->{error} .= $str . "; ";
		}
	}

	return $ok_flag;
}

sub readFstab {
	my ($self) = @_;
	my $fstab = {};
	local *F;
	my $file = "/etc/fstab";
	unless (open(F, $file)) {
		$self->{error} = "Unable to open file '$file': $!";
		return undef;
	}
	if ($self->{debug}) {
		$self->bufApp("##############################");
		$self->bufApp("#       FSTAB DATA           #");
		$self->bufApp("##############################");
		$self->bufApp();
	}

	while(<F>) {
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		next if (/^#/ || ! length($_));
		next unless (/^\// || /\s+nfs\s+/);
		next if (/noauto|swap/);
		if ($self->{debug}) {
			$self->bufApp($_);
		}
		my @data = split(/\s+/, $_);
		$fstab->{$data[0]} = $data[1];
	}
	close(F);
	$self->bufApp() if ($self->{debug});
	return $fstab;
}

sub readMounted {
	my ($self) = @_;
	my $mounted = {};
	local *F;
	
	my $command = _my_which(PROGRAM_NAME);
	unless (defined $command) {
		$self->{error} = "Unable to find program '" . PROGRAM_NAME . "' in \$PATH.";
		return undef;
	}
	
	$command .= " -p" if ($self->{use_posix});

	unless(open(F, $command . " |")) {
		$self->{error} = "Unable to invoke command '$command': $!";
		return undef;
	}

	if ($self->{debug}) {
		$self->bufApp("##############################");
		$self->bufApp("#       MOUNT DATA           #");
		$self->bufApp("##############################");
		$self->bufApp();
	}

	while(<F>) {
		$_ =~ s/^\s+//g;
		$_ =~ s/\s+$//g;
		next if (/^#/ || ! length($_));
		next unless (/^\// || /\s+type nfs\s+/);
		$self->bufApp($_) if ($self->{debug});
		my @data = split(/\s+/, $_);
		$mounted->{$data[0]} = $data[1];
	}
	close(F);
	
	$self->bufApp() if ($self->{debug});

	return $mounted;
}

1;