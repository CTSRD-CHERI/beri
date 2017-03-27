#!/bin/bash
#-
# Copyright (c) 2016 A. Theodore Markettos
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

# Run as many Altera jtagd instances as there are USB JTAG connections.
# Each jtagd believes there is only one USB JTAG port on the system
# and all the others are hidden from it.  This way we can run N copies
# of jtagd and thus work around jtagd's lack of multithreading.
#
# We achieve this using Linux namespaces, finding the device nodes in
# sysfs and forking a new filesystem namespace for each instance of jtagd.
# Each one has an empty directory mounted on top of all the USB ports we
# want to hide from it, so that it believes it's the only USB JTAG
# available.  We can then talk to each jtagd over a loopback socket,
# and so we have sockets to N jtag daemons available to us.
#
# While the namespace manipulation must run as root (ie needs sudo permissions)
# the JTAG daemons are run as an ordinary user.  Adding the ability to execute
# 'unshare' from sudo should be sufficient.  Since this script is able to
# run jtagd as any user, care should be taken not to introduce vulnerabilities.
#
# Because jtagconfig checks if anything is listening on the default port (1309)
# and starts jtagd if it doesn't find anything, we additionally start a jtagd
# of our own on 1309, where we hide the entire USB system from it so it doesn't
# interfere (or hang jtagconfig).  Thus the only ports available are the ones
# using the loopback sockets.


# location of USB devices in sysfs
# must not have trailing slash
SYSUSB=/sys/bus/usb/devices
# Altera vendor ID as reported by sysfs (case matters)
ALTERA_VID=09fb
# location of Quartus tree if not already set
QUARTUS_ROOTDIR="${QUARTUS_ROOTDIR:-/local/ecad/altera/current/quartus}"
# location of Quartus jtag binaries
QUARTUS_BIN="$QUARTUS_ROOTDIR/bin"
# Launch lowest daemon on this port
PORTBASE=1310
# Rewrite our configuation so that jtagconfig can find the new servers
JTAGCONF=$HOME/.jtag.conf
# User to run jtagd as
JTAGUSER=$USER

# set for loop deliminator to be a newline -
# this makes inverse-grepping easier
IFS=$'\n'

# kill all pre-existing jtagd
# - means we can run this script any number of times without side effects
killall jtagd

# search for the symlinks to device nodes that are whole USB devices
PORTS=$(find $SYSUSB -regex "$SYSUSB/[0-9.-]+" | sort)
JTAGS=""

for PORT in $PORTS ; do
	# if we found a port and it has a vendor ID available
	if grep -q $ALTERA_VID $PORT/idVendor ; then
#			echo "Found port $PORT"
			JTAGS="${JTAGS}$IFS${PORT}"
	fi
done

# start a new configuration file
# (this will erase any user settings, sorry)
echo "" > $JTAGCONF


PORT=$PORTBASE
REMOTE=101
for JTAG in $JTAGS ; do
# For each port we found, compute the negation of the set (ie all
# ports except this one)
	IFS=$'\n'
#	echo "JTAG port ${JTAG}"
	# create a list containing everything except $JTAG
	REMAINING=$(echo "$JTAGS" | grep -v $JTAG)
	# then strip out newlines and turn it back into a whitespace-separated list
	REMAINING=${REMAINING/$'\n'}
	# we're done with newline-terminated lists now
	unset IFS

# Launch a shell script in a separate file namespace.  The shell script 
# mounts an empty directory over the top of the ports we want to hide.
# Then we run jtagd and have it listen on a specific port
# List the device nodes so we can see what got hidden (requires terminal colours)

	sudo unshare -m /bin/bash -c "\
		EXCLUDE=\"${REMAINING}\" ; \
		EMPTY=/var/run/emptydir ; \
		for DELETE in \$EXCLUDE ; \
			do echo \"Hiding \${DELETE}\" ; \
			mkdir -p \$EMPTY ; \
			mount --bind \$EMPTY \$DELETE ; \
		done ; \
		ls -l --color $SYSUSB ; \
		runuser -u $JTAGUSER '$QUARTUS_BIN/jtagd' -- --port $PORT --foreground & \
		echo \"Servicing port $JTAG on port $PORT\" ; \
	"

# Now add an entry for this port to the config file
	echo "Remote$REMOTE {" >> $JTAGCONF
	echo "  Host = \"localhost:$PORT\";" >> $JTAGCONF
	echo "  Password = \"password\";" >> $JTAGCONF
	echo "}" >> $JTAGCONF

# Increment the port number for next time
	PORT=$((PORT+1))
	REMOTE=$((REMOTE+1))
	echo
done

# On the default port, start a dummy jtagd where we nuke the whole USB
# subsystem so it can't find any devices, and to whom jtagconfig can chat
# pointlessly to its heart's content

sudo unshare -m /bin/bash -c "\
	EMPTY=/var/run/emptydir ; \
	mkdir -p \$EMPTY ; \
	mount --bind \$EMPTY $SYSUSB ; \
	runuser -u $JTAGUSER '$QUARTUS_BIN/jtagd' -- --port 1309 --foreground & \
	"

