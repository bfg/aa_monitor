#!/bin/sh

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
config etc/aa_monitor/aa_monitor.conf.new

# restart aa_monitor
etc/init.d/aa_monitor restart

# EOF