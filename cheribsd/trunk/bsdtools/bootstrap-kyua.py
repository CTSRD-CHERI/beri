#!/usr/bin/env python
#-
# Copyright (c) 2016 SRI International
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

import os
import pexpect
import sys

ALMOST_BOOTED="Starting background file system checks in 60 seconds"
BOOT_FAILURE="Enter full pathname of shell or RETURN for /bin/sh"
LOGIN="login:"
OS_HALTED="The operating system has halted."
PROMPT="root@beri1:"

def main():
	global ALMOST_BOOTED, BOOT_FAILURE, LOGIN, OS_HALTED, PROMPT

	qemu=os.getenv("QEMU_CMD", "qemu-system-cheri128m")
	kernel=os.getenv("QEMU_KERNEL", "cheribsd128-cheri128-malta64-kernel")
	diskimg=os.getenv("QEMU_DISKIMAGE", "qemu-boot.img")

	child = pexpect.spawn('%(qemu)s -M malta -kernel %(kernel)s -hda %(diskimg)s -m 2048 -nographic' % {'qemu': qemu, 'kernel': kernel, 'diskimg': diskimg})
	child.logfile = sys.stdout
	i = child.expect([pexpect.TIMEOUT, ALMOST_BOOTED, BOOT_FAILURE], timeout=10*60)
	if i == 0: # Timeout
		print "timeout before booted"
		print(str(child))
		sys.exit(1)
	elif i == 0: # start up scripts failed
		print "start up scripts failed to run"
		sys.exit(1)
	print("===> nearly booted")

	i = child.expect([pexpect.TIMEOUT, LOGIN], timeout=30)
	if i == 0: # Timeout
		print "timeout awaiting login prompt"
		print(str(child))
		sys.exit(1)
	print("===> got login prompt")

	child.sendline("root")
	i = child.expect([pexpect.TIMEOUT, PROMPT], timeout=60)
	if i == 0: # Timeout
		print "timeout awaiting command prompt"
		print(str(child))
		sys.exit(1)
	print("===> got command prompt")

	child.sendline("env ASSUME_ALWAYS_YES=yes REPOS_DIR=/etc/pkg-cache pkg bootstrap")
	i = child.expect([pexpect.TIMEOUT, PROMPT], timeout=5 * 60)
	if i == 0: # Timeout
		print "timeout awaiting pkg bootstrap"
		print(str(child))
		sys.exit(1)
	print("===> bootstrapped pkg")

	child.sendline("env ASSUME_ALWAYS_YES=yes REPOS_DIR=/etc/pkg-cache pkg install kyua")
	i = child.expect([pexpect.TIMEOUT, PROMPT], timeout=10 * 60)
	if i == 0: # Timeout
		print "timeout awaiting kyua install"
		print(str(child))
		sys.exit(1)
	print("===> installed kyua")

	child.sendline("halt")
	i = child.expect([pexpect.TIMEOUT, OS_HALTED], timeout=2 * 60)
	if i == 0: # Timeout
		print "timeout waiting for shutdown"
		print(str(child))
		sys.exit(1)
	print("===> shutdown cleanly")

	sys.exit(0)

if __name__ == "__main__":
	main()
