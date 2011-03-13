package P9::AA::Check::CertificateDB;

use strict;
use warnings;

use HTTP::Date;
use File::Find;
use Cwd qw(realpath);

use P9::AA::Constants;
use base 'P9::AA::Check';

use constant SECS_IN_DAY => 24 * 60 * 60;

our $VERSION = 0.12;

##################################################
#              PUBLIC  METHODS                   #
##################################################

=head1 NAME

Checks directories for expired certificates.

=head1 METHODS

=cut

# add some configuration vars
sub clearParams {
	my ($self) = @_;
	return 0 unless ($self->SUPER::clearParams());
	
	$self->setDescription(
		"Checks directories for expires x509 certificates. Requires openssl(1) command."
	);
	
	$self->cfgParamAdd(
		'path',
		'/tmp',
		'Comma separated list of directories containing certificates.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'days',
		60,
		'How many days before expiration error should be reported?',
		$self->validate_int(1)
	);
	
	return 1;
}

=head2 check ()

Performs x509 certificate check.

=cut
sub check {
	my ($self) = @_;
	unless (defined $self->{path} && length($self->{path})) {
		return $self->error("Undefined x509 certificate directory path.");
	}
	
	# parse and resolve provided paths
	my @paths = ();
	map {
		my $x = realpath($_);
		push(@paths, $x) if (defined $x && -d $x && -r $x);
	} split(/\s*[,;]+\s*/, $self->{path});
	
	unless (@paths) {
		return $self->error("No valid certificate directories were specified.");
	}

	$self->bufApp("Certificate search path: ", join(", ", @paths));
	$self->bufApp();
	
	$self->{_is_ok} = 1;

	# perform search...
	no warnings 'File::Find';
	find({
			wanted => sub {
				my $file = $File::Find::name;
				return 1 unless (-f $file);
				$self->_checkFile($file);
			},
			follow => 1,
			follow_skip => 2,
			no_chdir => 1,
		},
		@paths
	);

	# return result
	unless ($self->{_is_ok}) {
		return $self->error("One or more certificates have already expired or will expire soon. See message buffer for details.");
	}

	return $self->success();
}

sub toString {
	my $self = shift;
	no warnings;
	return $self->{days} . ' @ ' . $self->{path};
}

##################################################
#              PRIVATE METHODS                   #
##################################################

sub _checkFile {
	my ($self, $file) = @_;
	unless (defined $file && -f $file && -r $file) {
		$self->error("Undefined or invalid file.");
		return 0;
	}
	# should be certificate file
	return 1 unless ($file =~ m/\.(crt|pem|der)$/i);

	# $self->bufApp("CHECK FILE: $file");
	
	my $not_after = 0;
	my $not_before = 0;
	my $not_after_str = "";
	my $not_before_str = "";

	# run openssl command...
	my $fd = undef;
	my $cmd = "openssl x509 -noout -startdate -enddate -in '$file'";
	open($fd, "$cmd 2>/dev/null|");
	unless (defined $fd) {
		$self->bufApp("ERROR: Unable to invoke command '$cmd': $!");
		return 0;
	}
	
	my $maxlines = 10;
	my $i = 0;
	while ($i < $maxlines && (my $line = <$fd>)) {
		$i++;
		$line =~ s/^\s+//g;
		$line =~ s/\s+$//g;
		if ($line =~ m/^notBefore=(.+)/) {
			$not_before_str = $1;
			$not_before = $self->_getTime($1);
			# print "parse1 got: $not_before\n";
		}
		elsif ($line =~ m/^notAfter=(.+)/) {
			$not_after_str = $1;
			$not_after = $self->_getTime($1);
		}
	}

	my $c = close($fd);
	unless ($c) {
		# $self->bufApp("Unable to properly terminate openssl: $!; openssl exit status: " . ($? >> 8));
		return 0;
	}
	
	# check not_before and not after
	unless (defined $not_before && defined $not_after) {
		$self->bufApp("FILE: unable to parse x509 certificate expiration date");
		return 0;
	}
	
	# now check da fukkin stuff
	my $ct = time();
	my $offset = SECS_IN_DAY * $self->{days};

	# when is this certificate going to expire?
	# expired certificate?
	if ($ct > $not_after) {
		$self->error("ERROR: Certificate '$file' ALREADY EXPIRED on $not_after_str");
		$self->bufApp($self->error());
		$self->{_is_ok} = 0;
	}
	elsif (($not_after - $offset) < $ct) {
		$self->error("WARNING: Certificate '$file' WILL EXPIRE in less than $self->{days} days on $not_after_str.");
		$self->bufApp($self->error());
		$self->{_is_ok} = 0;
	}
	# not valid certificate?

	return 1;
}

sub _getTime {
	my ($self, $str) = @_;
	return 0 unless (defined $str && length($str) > 0);
	my $r = 0;

	# Apr 19 12:59:12 2007 GMT
	# ->
	# 09 Feb 1994 22:23:32 GMT [HTTP format (no weekday)]
	#print "PARSING: '$str'\n";
	if ($str =~ m/^([a-z]{3})\s+(\d+)\s+(\d+):(\d+):(\d+)\s+(\d+)\s+GMT/i) {
		my $s = "$2 $1 $6 $3:$4:$5 GMT";
		#print "computed string from '$str' => '$s'\n";
		$r = str2time($s);
		$r = 0 unless (defined $r);
	}
	
	return $r;
}

=head2 AUTHOR

Brane F. Gracnar

=head2 SEE ALSO

L<P9::AA::Check>

=cut

1;