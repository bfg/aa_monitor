package Noviforum::Adminalert::Check::MDRAID;

use strict;
use warnings;

use IO::File;

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check';

use constant MAXLINES => 1024;
use constant MDSTAT => "/proc/mdstat";

our $VERSION = 0.15;

##################################################
#              PUBLIC  METHODS                   #
##################################################

sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks Linux software RAID array consistency."
	);
	
	return 1;
}

sub check {
	my ($self) = @_;
	my $os = $self->getOs();
	unless (lc($os) eq 'linux') {
		return $self->error("This module is not implemented on $os operating system.");
	}

	# if there is no file, just return success
	my $file = MDSTAT;
	if (! -e $file) {
		$self->bufApp("File $file does not exist, assuming that there is no MD raid support in kernel, returning success.");
		return CHECK_OK;
	}

	# try to open mdstat file
	my $fd = undef;
	unless (defined ($fd = IO::File->new($file, "r"))) {
		return $self->error("Unable to open mdstat file '$file': $!");
	}

	# read file
	my $i = 0;
	my %data = ();
	my $last_device = undef;
	my $result = CHECK_OK;
	my $err = '';
	$self->bufApp(sprintf("%-30.30s%s", "DEVICE", "STATUS"));
	while ($i < MAXLINES && defined (my $line = <$fd>)) {
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;

		if (defined $last_device && $line =~ m/^\d+/) {
			if ($line =~ m/_/) {
				$err .= "Software RAID array '$last_device' is not in optimal state\n";
				$result = CHECK_ERR;
			}

			$self->bufApp(sprintf("%-30.30s%s", "/dev/" . $last_device, $line));
		}

		if ($line =~ /^(md\d+)\s+:\s+/) {
			$last_device = $1;
		}

		$i++;
	}
	
	if ($result != CHECK_OK) {
		$err =~ s/\s+$//g;
		$self->error($err);
	}

	return $result;
}

=head1 AUTHOR

Brane F. Gracnar

=head1 SEE ALSO

L<Noviforum::Adminalert::Check>

=cut

1;