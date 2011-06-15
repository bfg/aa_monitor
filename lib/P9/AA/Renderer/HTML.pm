package P9::AA::Renderer::HTML;

use strict;
use warnings;

use HTML::Entities;
use POSIX qw(strftime);

use P9::AA::Config;
use P9::AA::Util;
use P9::AA::Constants qw(:all);
use base 'P9::AA::Renderer';

our $VERSION = 0.20;

=head1 NAME

HTML output renderer.

=cut

sub render {
	my ($self, $data, $resp) = @_;
	# header
	my $buf = $self->renderHeader($data);
	
	# report
	$buf .= $self->renderReport($data);
	
	# messages
	$buf .= $self->renderMessages($data);
	
	# history
	$buf .= $self->renderHistory($data);
	
	# timings
	$buf .= $self->renderTimings($data);
	
	# configuration
	$buf .= $self->renderConfiguration($data);
	
	# general info
	$buf .= $self->renderGeneralInfo($data);
	
	# footer
	$buf .= $self->renderFooter($data);

	# set headers
	$self->setHeader($resp, 'Content-Type', 'text/html; charset=utf-8');
	
	return $buf;
}

sub renderHeader {
	my ($self, $data) = @_;
	my $buf = <<EOF
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
EOF
;
 
	my $h_name = (defined $data->{data}->{module}->{name}) ? encode_entities($data->{data}->{module}->{name}) : '';
	my $h_to_str = '';
	if (defined $data->{data}->{check}->{as_string} && length($data->{data}->{check}->{as_string})) {
		$h_to_str = encode_entities('[' . $data->{data}->{check}->{as_string} . ']');
	}

	my $h_title = 'Module listing';
	if (defined $data->{data}->{module}->{name} && defined $data->{data}->{environment}->{hostname}) {
			$h_title = encode_entities($data->{data}->{module}->{name}) .
			' ' . $h_to_str .
			' @ ' .
			encode_entities($data->{data}->{environment}->{hostname});
	}

	my $h_version = $data->{data}->{module}->{version};
	$h_version = (defined $h_version) ? encode_entities($h_version) : '';
	
	# select background color...
	my $lgreen = 'ECF8E0';
	my $lred = 'F8E0E0';
	my $lorange = 'F6E3CE';
	my $bg_color = $lgreen;
	my $c = $data->{data}->{check};
	if ($c->{success}) {
		$bg_color = ($c->{warning}) ? $lorange : $lgreen;
	} else {
		$bg_color = $lred;
	}

	$buf .= <<EOF
	<title>$h_title</title>
	
	<script type="text/javascript">
//<![CDATA[
  <!--
    function flipflop(id) {
       var e = document.getElementById(id);
       if(e.style.display == '')
          e.style.display = 'none';
       else
          e.style.display = '';
    }

  //-->
  //]]>
	</script>
	<style type="text/css">
/*<![CDATA[*/
  body {
        margin: 0;
        font-family: Arial;
        /* background-color: #F5F5F5; */
        background-color: #$bg_color;
  }

  a,a:visited {
        text-decoration: none;
        color: #fff;
        outline: none;
  }

  div.wrapper {
        width: 800px;
        margin: 0 auto;
        // padding: 0 30px 36px;
        padding: 0 0px 0px;
        position: relative;
  }

  div#header {
        background: #f5f5f5;
        height: 72px;
        border-bottom: 1px solid #eee;
        margin: 0;
  }

  div#header h2 {
        float: left;
        position: relative;
        top: 4px;
        left: 435px;
        border-left: 1px solid #ccc;
        padding-left: 4px;
  }

  div.page-header {
        padding: 0 0 0px;
        margin: 8px 0;
        border-bottom: 1px solid #ddd;
  }

  div.page-header h4 {
        padding: 0;
        margin-bottom: 5px;
        font-size: 16px;
        letter-spacing: 0;
  }

  div.value {
        height: 10px;
  }

  p {
        line-height: 0.6em;
  }

	pre {
  		font-size: 11px;
  		font-family: "Courier New", Courier;
  		color: black;

		margin: 0 0 0 0px;  /*--Left Margin--*/

		padding: 0;
		margin: 0;
		background: #f0f0f0;
		//line-height: 20px; /*--Height of each line of code--*/
		overflow: auto; /*--If the Code exceeds the width, a scrolling is available--*/
		overflow-Y: hidden;  /*--Hides vertical scroll created by IE--*/
		width: 100%;
	}
	pre code {
		margin: 0 0 0 0px;  /*--Left Margin--*/
		padding: 18px 0;
		display: block;
	}

  .kolor,.kolor:visited {
        outline: none;
        width: 775px;
        display: inline-block;
        color: #fff;
        text-decoration: none;
        -moz-border-radius: 5px;
        -webkit-border-radius: 5px;
        border: 1px solid rgba(3, 0, 0, 0.2);
        position: relative;
  }

  .kolor:hover {
        background-color: #111;
        color: #fff;
  }

  .kolor,.kolor:visited {
        font-size: 14px;
        padding: 8px 14px 9px;
  }

  .green.kolor,.green.kolor:visited {
        background-color: #91bd09;
  }

  .green.kolor:hover {
        background-color: #749a02;
  }

  .gray.kolor,.gray.kolor:visited {
        background-color: #fff;
        color: #3384E6;
  }

  .red.kolor,.red.kolor:visited {
        background-color: #e33100;
  }

  .red.kolor:hover {
        background-color: #872300;
  }

  .orange.kolor,.orange.kolor:visited {
        background-color: #ff5c00;
  }

  .orange.kolor:hover {
        background-color: #d45500;
  }

  .blue.kolor,.blue.kolor:visited {
        background-color: #3384E6;
  }

  .blue.kolor:hover {
        background-color: #2D5BB2;
  }

a, a:active {text-decoration: none; color: blue;}
a:visited {color: #48468F;}
a:hover, a:focus {text-decoration: underline; color: red;}
  
	a.cfgitem {
		font-size: 11px;
  		font-family: "Courier New", Courier;
  		color: #48468F;

	}
  
	/* The following is stolen from lighttpd directory listing CSS */
	div.list { background-color: white; border-top: 1px solid #646464; border-bottom: 1px solid #646464; padding-top: 10px; padding-bottom: 14px;}
	div.foot { font: 90% monospace; color: #787878; padding-top: 4px;}
  
  /*]]>*/
	</style>
</head>

<body>
	<div id="wrapper">
		<!--div id="header" align="center"-->
		<h3><center>$h_name $h_to_str / $h_version</center></h3>
	<!--/div-->

	<div class="wrapper">
EOF
;
	return $buf;
}

sub renderReport {
	my ($self, $data) = @_;
	
	my $r = $data->{data}->{check};
	return '' unless (defined $r);

	# header
	my $buf .= <<EOF
<!-- BEGIN CHECK REPORT -->
	<div class="page-header"><h4>Result</h4></div>
	<div class="column-row">	
EOF
;
	# success ?
	if ($r->{success}) {
		$buf .= "\t\t<div class=\"rows\">\n";
		$buf .= "\t\t\t<div class=\"green kolor\" align=\"center\">SUCCESS</div>\n";
		$buf .= "\t\t</div>\n";
		
		# make AA happy
		$buf .= "\n\t\t<!--SEARCH OK-->\n\n";
	} else {
		$buf .= "\t\t<div class=\"rows\">\n";
		$buf .= "\t\t\t<div class=\"red kolor\" align=\"center\">ERROR</div>\n";
		$buf .= "\t\t\t<div class=\"gray kolor\"><pre>\n";
		$buf .= encode_entities($r->{error_message}) . "</pre>\n";
		$buf .= "\t\t</div>\n";		
	}
	if ($r->{warning}) {
		$buf .= "\t\t<div class=\"rows\">\n";
		$buf .= "\t\t\t<div class=\"orange kolor\" align=\"center\">WARNING</div>\n";
		$buf .= "\t\t\t<div class=\"gray kolor\"><pre>\n";
		$buf .= encode_entities($r->{warning_message}) . "</pre>\n";
		$buf .= "\t\t</div>\n";
	}

	# footer
	$buf .= <<EOF
	</div>
<!-- END CHECK REPORT -->

EOF
;	
	return $buf;
}

sub renderMessages {
	my ($self, $data) = @_;
	my $buf = <<EOF
<!-- BEGIN MESSAGES -->
      <div class="page-header"><h4>Messages</h4></div>
      <div class="column-row">
			<div class="rows">
				<div class="gray kolor">
					<pre>
EOF
;

	$buf .= encode_entities($data->{data}->{check}->{messages});

	# add footer
	$buf .= <<EOF
</pre>
				</div>
			</div>
		</div>
<!-- END MESSAGES -->

EOF
;
	return $buf;
}

sub renderConfiguration {
	my ($self, $data) = @_;
	my $buf = <<EOF
<!-- BEGIN CONFIGURATION -->
	<div class="page-header"><h4>Configuration</h4></div>
	<div class="column-row">
		<div class="rows">
EOF
;
	# do the config...
	my $u = P9::AA::Util->new();
	foreach my $key (sort keys %{$data->{data}->{module}->{configuration}}) {
		next unless (defined $key && length($key));
		my $c = $data->{data}->{module}->{configuration}->{$key};
		my $id = $u->newId();
		
		my $hkey = encode_entities($key);
		my $hval = encode_entities($self->renderValTxt($c->{value}));
		my $hdef = encode_entities($self->renderValTxt($c->{default}));
		my $hdesc = encode_entities($self->renderValTxt($c->{description}));
		
		my $len = length($key);
		my $fill = 30 - $len;
		my $fill_str = "&nbsp;" x $fill;

		$buf .= "\t\t<a class=\"cfgitem\" href=\"javascript:flipflop('$id');\">$hkey: $fill_str $hval</a><br/>\n";
		$buf .= "\t\t<div id=\"$id\" style=\"display: none\">\n";
		$buf .= "\t\t\t<pre>\n";
		$buf .= "<font color=\"red\">Description:</font> " . $hdesc . "\n";
		$buf .= "<font color=\"red\">Default:</font> " . $hdef . "</pre>\n";
		$buf .= "\t\t</div>\n";		
	}

	# add footer
	$buf .= <<EOF
		</div>
	</div>
<!-- END CONFIGURATION -->

EOF
;

	return $buf;
}

sub renderTimings {
	my ($self, $data) = @_;
	
	my $t = $data->{data}->{timings};
	my $buf = <<EOF
<!-- BEGIN TIMING -->
	<div class="page-header"><h4>Timing</h4></div>
	<div class="column-row">
			<div class="rows">
				<div class="gray kolor">
					<pre>
EOF
;

	my $fmt = "%-20.20s%s";
	# check duration
	$buf .= sprintf($fmt, "check duration: ",
			encode_entities(sprintf("%-.3f", ($t->{check_duration} * 1000)))) .
			" ms\n";

	# total duration
	$buf .= sprintf($fmt, "total duration: ",
			encode_entities(sprintf("%-.3f", ($t->{total_duration} * 1000)))) .
			" ms\n";
	
	$buf .= "\n";
	# check started
	$buf .= sprintf($fmt, "check started: ",
			encode_entities($self->timeAsString($t->{check_start}))) .
			"\n";
	
	# check finished
	$buf .= sprintf($fmt, "check finished: ",
			encode_entities($self->timeAsString($t->{check_finish}))) .
			"\n";

	# add footer
	$buf .= <<EOF
</pre>
			</div>
		</div>
	</div>
<!-- END TIMING -->

EOF
;

	return $buf;
}

sub renderHistory {
	my ($self, $data) = @_;
	my $h = $data->{data}->{history};
	return '' unless ($h->{changed});
	
	my $time_str = encode_entities(strftime("%d.%m.%Y %H:%M:%S", localtime($data->{data}->{history}->{last_time})));
	my $time_diff = encode_entities(sprintf("%-.3f", $data->{data}->{history}->{time_diff}));
	my $result = $data->{data}->{history}->{last_result_code};
	my $result_str = encode_entities(result2str($result));
	my $msg = '';
	if ($result != CHECK_OK) {
		$msg = "\nLast message:        " . encode_entities($data->{data}->{history}->{last_message});
	}

	my $buf = <<EOF
<!-- BEGIN HISTORY -->
	<div class="page-header"><h4>Check history changed</h4></div>
	<div class="column-row">
		<div class="rows">
			<div class="gray kolor">
				<pre>
Status change since: $time_str [$time_diff second(s) ago]
Last result:         ${result_str}${msg} 
</pre>
			</div>
		</div>
<!-- END HISTORY -->

EOF
;

	return $buf;
}

sub renderGeneralInfo {
	my ($self, $data) = @_;	
	my $sw =
			encode_entities($data->{data}->{environment}->{program_name}) .
			"/" .
			encode_entities($data->{data}->{environment}->{program_version});
	my $host = encode_entities($data->{data}->{environment}->{hostname});

	my $buf = <<EOF
<!-- BEGIN GENERAL INFO -->
	<div class="page-header"><h4></h4></div>
EOF
;;

	# add documentation POD hyperlinks?
	my $cfg = P9::AA::Config->new();
	if ($cfg->get('enable_doc') && $self->uri()) {
		my $u = P9::AA::Util->new();
		my $base_url = $u->getBaseUrl($self->uri());
		$base_url = '' if ($base_url eq '/');
		my $module = $self->renderValTxt($data->{data}->{module}->{name});

		$buf .= '<div class="foot"><center>';
		$buf .= "[<a href='$base_url/doc/P9/README_AA'>readme</a>] " if (defined $base_url);
		if (defined $module && length $module > 0) {
			$buf .= "[<a href='$base_url/doc/P9/AA/Check/$module'>module doc</a>] ";
		} else {
			$buf .= "[<a href='$base_url/doc/P9/AA/Check'>module doc</a>] ";
		}
		$buf .= "[<a href='$base_url/doc/P9/AA/CHANGELOG'>changelog</a>] " if (defined $base_url);
		$buf .= "</center></div>\n";
	}

	$buf .= <<EOF
	<div class="foot"><center><a href='https://github.com/bfg/aa_monitor/wiki'>$sw</a> at $host</center></div>
<!-- END GENERAL INFO -->

EOF
;

	return $buf;
}

sub renderFooter {
	my ($self, $data) = @_;
	my $buf = <<EOF
	</div>
</body>
</html>
EOF
;
	return $buf;
}

=head1 SEE ALSO

L<P9::AA::Renderer>, L<HTML::Entities>

=head1 AUTHOR

Brane F. Gracnar

=cut

1;

# EOF
