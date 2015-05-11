#!/bin/sh
# Copyright (c) 2011 Wojciech A. Koszek
# All rights reserved.
# 
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for
# additional information regarding copyright ownership.  BERI licenses this
# file to you under the BERI Hardware-Software License, Version 1.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at:
#
#   http://www.beri-open-systems.org/legal/license-1-0.txt
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
# @BERI_LICENSE_HEADER_END@
# 
# CHERI install script
#
# Requires root priviledges to perform:
#
# 	cp tools/altera.rules in /etc/udev/rules.d
#
# and to run:
#
#	udevadm control --reload-rules
#
UID="`id -u`"

HAS_UDEVD=0
which udevd > /dev/null;
if [ $? -eq 0 ]; then
	HAS_UDEVD=1
fi

HAS_UDEVADM=0
which udevadm > /dev/null;
if [ $? -eq 0 ]; then
	HAS_UDEVADM=1
fi

if [ $HAS_UDEVD -eq 0 ] || [ $HAS_UDEVADM -eq 0 ]; then
	echo "install.sh requires udevd(8) and udevadm(8) to be present";
	echo "Try: sudo apt-get install udev!";
	exit 1;
fi

UDEVD_RUNNING=0
pgrep udevd > /dev/null;
if [ $? -ne 0 ]; then
	echo "install.sh requires udevd(8) to be running";
	echo "Try: /dev/init.d/udev start";
	exit 1;
fi

if [ ! -e /etc/udev/rules.d ]; then
	echo "install.sh expected /etc/udev/rules.d to exist, but it doesn't";
	echo "(not running Ubuntu?)";
	exit 1;
fi

if [ "$UID" != "0" ]; then
	echo "install.sh requires root priviledges to setup the system";
	echo "Try: sudo sh install.sh";
	exit 1;
fi

mkdir -p -m 0755 /usr/share/altera
cp tools/altera.sh /usr/share/altera
cp tools/altera.rules /etc/udev/rules.d/ && udevadm control --reload-rules
if [ $? -ne 0 ]; then
	echo "Problem experienced during the configuration!";
	echo "Your instalation may not be complete!";
	exit 1;
fi

cat <<EOF
-----------------------------------------------------------------------------
Congratulations!

New files necessary to detect Altera DE4/DE2-70 boards has been installed in:

                   /usr/share/altera/altera.sh
                   /etc/udev/rules.d/altera.rules

Your system should be now ready for trying out CHERI.

Please physically disconnect and connect back to your computer the USB cable.
Powering the board on/off doesn't work. You must reconnect the cable by hand.

Good luck!
CHERI team
-----------------------------------------------------------------------------
EOF

