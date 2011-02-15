package Noviforum::Adminalert::Check::FTP;

use strict;
use warnings;

use Net::FTP;
use File::Spec;
use File::Basename;
use File::Temp qw(tempfile);

use Noviforum::Adminalert::Constants;
use base 'Noviforum::Adminalert::Check::_Socket';

our $VERSION = 0.10;

=head1 NAME

FTP service checking module.

=head1 REQUIREMENTS

L<Net::FTP>

=head1 METHODS

This module inherits all methods from L<Noviforum::Adminalert::Check::_Socket>

=cut
sub clearParams {
	my ($self) = @_;
	
	# run parent's clearParams
	return 0 unless ($self->SUPER::clearParams());

	# set module description
	$self->setDescription(
		"FTP service checking module"
	);

	# define additional configuration variables...
	$self->cfgParamAdd(
		'ftp_host',
		'ftp.example.org',
		'FTP server hostname.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'ftp_port',
		21,
		'FTP server listening port.',
		$self->validate_int(1, 65535),
	);
	$self->cfgParamAdd(
		'ftp_user',
		'anonymous',
		'FTP login username.',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'ftp_pass',
		undef,
		'FTP login password.',
		$self->validate_str(200),
	);
	$self->cfgParamAdd(
		'get_file',
		undef,
		'Try to fetch specified file',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'put_dir',
		undef,
		'If specified, upload of small file with randon content will be attempted to specified directory.',
		$self->validate_str(1024),
	);
	$self->cfgParamAdd(
		'remove_after_upload',
		1,
		'Remove temporary file from FTP server after uploading?',
		$self->validate_bool(),
	);


	$self->cfgParamRemove('timeout_connect');

	return 1;
}

# actually performs ping
sub check {
	my ($self) = @_;
	
	# try to connect
	my $ftp = $self->ftpConnect();
	return CHECK_ERR unless (defined $ftp);
	
	# try to fetch directory listing...
	$ftp->binary();
	my $r = $ftp->ls('/');
	unless ($r) {
		return $self->error("Unable to fetch directory listing: " . $ftp->message());
	}
	if ($self->{debug}) {
		$self->bufApp("--- BEGIN DIR LISTING ---");
		$self->bufApp($self->dumpVar($r));
		$self->bufApp("--- END DIR LISTING ---");
	}	
	
	# download file?
	if (defined $self->{get_file} && length $self->{get_file}) {
		$self->bufApp("Fetching file: '$self->{get_file}'");
		my $r = $ftp->get($self->{get_file}, File::Spec->devnull());
		unless ($r) {
			return $self->error(
				"Unable to fetch file '$self->{get_file}: [" .
				$ftp->code() . "]: " .
				$ftp->message()
			);
		}
	}
	
	# upload file?
	if (defined $self->{put_dir} && length($self->{put_dir})) {
		# try to change directory...
		unless ($ftp->cwd($self->{put_dir})) {
			return $self->error(
				"Unable to change directory to '$self->{put_dir}: [" .
				$ftp->code() . "]: " .
				$ftp->message()
			);
		}
		
		# generate small file
		my $file = $self->_generateTestFile();
		return CHECK_ERR unless ($file);
		
		$self->bufApp("Uploading file '$file' to '$self->{put_dir}'");
		unless ($ftp->put($file, basename($file))) {
			unlink($file);
			return $self->error(
				"Unable to upload file to '$self->{put_dir}: [" .
				$ftp->code() . "]: " .
				$ftp->message()
			);
		}
		unlink($file);
		
		# try to remove it
		if ($self->{remove_after_upload}) {
			$self->bufApp("Removing uploaded file from '$self->{put_dir}'");
			unless ($ftp->delete(basename($file))) {
				return $self->error(
					"Unable to remove uploaded file from '$self->{put_dir}: [" .
					$ftp->code() . "]: " .
					$ftp->message()
				);
			}
		}
	}
	
	# disconnect.
	$ftp->quit();

	# this must be success!
	return CHECK_OK;
}

# describes check, optional.
sub toString {
	my ($self) = @_;
	no warnings;
	return $self->{ftp_host} . '/' . $self->{ftp_port};
}

=head2 ftpConnect

 my $conn = $self->ftpConnect(
 	ftp_host => 'ftp.example.com',
 	ftp_port => 21,
 	ftp_user => 'some_user',
 	ftp_pass => 's3cret',
 	%opt
 );

Tries to connect and login to FTP server. Supports L<Net::FTP> connect option parameters.
Returns initialized L<Net::FTP> object on success, otherwise undef.

=cut
sub ftpConnect {
	my ($self, %opt) = @_;
	return undef unless ($self->v6Sock());
	my $o = $self->_getConnectOpt(%opt);
	
	my $host = delete($o->{ftp_host});
	my $port = delete($o->{ftp_port});
	$port = 21 unless (defined $port);
	
	my $user = delete($o->{ftp_user});
	my $pass = delete($o->{ftp_pass});
	
	if ($self->{debug}) {
		$self->bufApp("Connecting to [$host]:$port");
	}
	my $conn = Net::FTP->new(
		$host,
		Port => $port,
		%opt
	);
	unless (defined $conn) {
		$self->error("Error connecting to $host: $@");
		return undef;
	}
	
	# select login credentials
	my @login = ();
	if (defined $user && lc($user) ne 'anonymous' && defined $pass) {
		@login = ($user, $pass);
	} else {
		$user = undef;
		$pass = undef;
	}
	
	{ no warnings; $self->bufApp("  Logging in with username '$user'") if ($self->{debug}) }
	unless ($conn->login(@login)) {
		$self->error(
			"Invalid login credentials. [" .
			$conn->code() . "]: " .
			$conn->message()
		) ;
		return undef;
	}
	
	return $conn;
} 

sub _getConnectOpt {
	my ($self, %opt) = @_;

	my $r = {};
	foreach (
		'ftp_host', 'ftp_port', 'ftp_user', 'ftp_pass',
	) {
		$r->{$_} = $self->{$_};
		$r->{$_} = $opt{$_} if (exists($opt{$_}));
	}
	
	# additional options
	foreach (keys %opt) {
		next if (exists($r->{$_}));
		$r->{$_} = $opt{$_};
	}
	
	return $r;
}

sub _generateTestFile {
	my ($self, $len) = @_;
	# create temporary file
	my ($fd, $file) = tempfile("test-XXXXX", SUFFIX => '.txt');
	unless ($fd) {
		$self->error("Unable to create temporary file: $!");
		return undef;
	} 

	$len = int(rand(4094)) + 100 unless (defined $len && $len > 0);
	my $buf = '';
	for (1 .. $len) {
		$buf .= chr(int(rand(32)) + 48);
	}

	# write to file
	print $fd $buf;
	
	# close
	unless (close($fd)) {
		$self->error("Unable to close temporary file: $!");
		unlink($file);
		return undef;
	}

	return $file;
}

=head1 SEE ALSO

L<Noviforum::Adminalert::Check>, 
L<Net::FTP>

=head1 AUTHOR

Brane F. Gracnar

=cut
1;