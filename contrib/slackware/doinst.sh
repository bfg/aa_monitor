#!/bin/sh

# $Id: doinst.sh 771 2008-04-10 12:05:41Z bfg $
# $Date: 2008-04-10 14:05:41 +0200 (Thu, 10 Apr 2008) $
# $Author: bfg $
# $Revision: 771 $
# $LastChangedRevision: 771 $
# $LastChangedBy: bfg $
# $LastChangedDate: 2008-04-10 14:05:41 +0200 (Thu, 10 Apr 2008) $

config() {
	NEW="$1"
	OLD="`dirname $NEW`/`basename $NEW .new`"

	# If there's no config file by that name, mv it over:
	if [ ! -r "$OLD" ]; then
		mv "$NEW" "$OLD"
	elif [ "`cat $OLD | md5sum`" = "`cat $NEW | md5sum`" ]; then # toss the redundant copy
		rm -f "$NEW"
	fi

	# Otherwise, we leave the .new copy for the admin to consider...
}

# install configuration file
config etc/sysconfig/aa_monitor.new

# restart aa_monitor
etc/init.d/aa_monitor restart

# EOF