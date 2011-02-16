package P9::AA::Protocol::FCGI;

# $Id: FCGI.pm 2322 2011-02-10 19:12:03Z bfg $
# $Date: 2011-02-10 20:12:03 +0100 (Thu, 10 Feb 2011) $
# $Author: bfg $
# $Revision: 2322 $
# $LastChangedRevision: 2322 $
# $LastChangedBy: bfg $
# $LastChangedDate: 2011-02-10 20:12:03 +0100 (Thu, 10 Feb 2011) $
# $URL: https://svn.interseek.com/repositories/admin/aa_monitor/trunk/lib/Noviforum/Adminalert/Protocol/FCGI.pm $

use strict;
use warnings;

use IO::Handle;

use Net::FastCGI::IO qw(:all);
use Net::FastCGI::Protocol qw(:all);
use Net::FastCGI::Constant qw(:common :type :flag :role :protocol_status);

use P9::AA::Log;
use P9::AA::Protocol::CGI;

use vars qw(@ISA);
@ISA = qw(P9::AA::Protocol::CGI);

our $VERSION = 0.10;
my $log = P9::AA::Log->new();

#
# code in this method is almost ***COMPLETELY STOLEN*** from:
#
# https://github.com/miyagawa/Plack/blob/master/lib/Plack/Handler/Net/FastCGI.pm
#
# Authors: Christian Hansen and Tatsuhiko Miyagawa
#
sub process {
	my ($self, $sock, undef, $ts) = @_;

    my ( $current_id,  # id of the request we are currently processing
         $stdin,       # buffer for stdin
         $stdout,      # buffer for stdout
         $stderr,      # buffer for stderr
         $params,      # buffer for params (environ)
         $output,      # buffer for output
         $done,        # done with connection?
         $keep_conn ); # more requests on this connection?

    ($stdin, $stdout, $stderr) = ('', '', '');

    while (!$done) {
        my ($type, $request_id, $content) = read_record($sock)
          or last;

        if ($request_id == FCGI_NULL_REQUEST_ID) {
            if ($type == FCGI_GET_VALUES) {
                my $query = parse_params($content);
                my %reply = map { $_ => $self->{values}->{$_} }
                            grep { exists $self->{values}->{$_} }
                            keys %$query;
                $output = build_record(FCGI_GET_VALUES_RESULT,
                    FCGI_NULL_REQUEST_ID, build_params(\%reply));
            }
            else {
                $output = build_unknown_type_record($type);
            }
        }
        elsif ($current_id
            && $request_id != $current_id
            && $type != FCGI_BEGIN_REQUEST) {
            # ignore inactive requests (FastCGI Specification 3.3)
        }
        elsif ($type == FCGI_ABORT_REQUEST) {
            $current_id = 0;
            ($stdin, $stdout, $stderr, $params) = ('', '', '', '');
        }
        elsif ($type == FCGI_BEGIN_REQUEST) {
            my ($role, $flags) = parse_begin_request_body($content);
            if ($current_id || $role != FCGI_RESPONDER) {
                $output = build_end_request_record($request_id, 0, 
                    $current_id ? FCGI_CANT_MPX_CONN : FCGI_UNKNOWN_ROLE);
            }
            else {
                $current_id = $request_id;
                $keep_conn  = ($flags & FCGI_KEEP_CONN);
            }
        }
        elsif ($type == FCGI_PARAMS) {
            $params .= $content;
        }
        elsif ($type == FCGI_STDIN) {
            $stdin .= $content;

            unless (length $content) {
                open(my $in, '<', \$stdin)
                  || die(qq/Couldn't open scalar as fh: '$!'/);

                open(my $out, '>', \$stdout)
                  || die(qq/Couldn't open scalar as fh: '$!'/);

                open(my $err, '>', \$stderr)
                  || die(qq/Couldn't open scalar as fh: '$!'/);

                $self->_processStreams(parse_params($params), $in, $out, $err, $ts);

                $done   = 1;
                # unless $keep_conn;
                $output = build_end_request($request_id, 0,
                    FCGI_REQUEST_COMPLETE, $stdout, $stderr);

                # prepare for next request
                $current_id = 0;
                ($stdin, $stdout, $stderr, $params) = ('', '', '', '');
            }
        }
        else {
            warn(qq/Received an unknown record type '$type'/);
        }

        if ($output) {
            print {$sock} $output
              || die(qq/Couldn't write: '$!'/);


            $output = '';
        }
    }
    
    return 1;
}

sub _processStreams {
    my($self, $env, $stdin, $stdout, $stderr, $ts) = @_;

	# populate environment...
	map { $ENV{$_} = $env->{$_} } keys %{$env};

	# process as normal CGI :P
	return $self->SUPER::process($stdin, $stdout, $ts);

}

1;