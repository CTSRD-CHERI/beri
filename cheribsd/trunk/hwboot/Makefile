#-
# Copyright (c) 2012 Robert N. M. Watson
# Copyright (c) 2012-2013 Jonathan Woodruff
# Copyright (c) 2013 Bjoern A. Zeeb
# Copyright (c) 2015 A. Theodore Markettos
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

#
# Execute tests on local hardware or on chericloud
#

BERICTL=berictl
CLOUDCTL=cloudctl.sh

ALTERA_JTAG_CABLE=$(shell expr $(FPGA_BOARD) + 1)
ifdef TIMEOUT
TIMEOUT_FLAGS=-t $(TIMEOUT)
endif

.DUMMY=all
all:	run

run:	consolecloud

# version that just uses berictl without chericloud script

.PHONY:	all native loadsof loadbin boot terminal

native:	terminal

loadsof:
	$(BERICTL) $(BERICTL_FLAGS) -c $(ALTERA_JTAG_CABLE) loadsof $(FPGA_SOF)
	echo "Done berictl loadsof (returned $?)"
	
loadbin:	loadsof
	$(BERICTL) $(BERICTL_FLAGS) -c $(ALTERA_JTAG_CABLE) loadbin $(KERNEL) 0x100000
	echo "Done berictl loadbin (returned $?)"
	
boot:	loadbin
	$(BERICTL) $(BERICTL_FLAGS) -c $(ALTERA_JTAG_CABLE) boot
	echo "Done berictl boot (returned $?)"

terminal:	boot
	$(BERICTL) $(BERICTL_FLAGS) -c $(ALTERA_JTAG_CABLE) console


# use the chericloud script on top of berictl

.PHONY:	cloud reprogram loadkernel bootcloud

reprogram:
	$(CLOUDCTL)  $(FPGA_BOARD) reprogram $(FPGA_SOF)

loadkernel:	reprogram
	$(CLOUDCTL)  $(FPGA_BOARD) loadkernel $(KERNEL)
	
bootcloud:	loadkernel
	$(CLOUDCTL)  $(FPGA_BOARD) boot

consolecloud:
	$(CLOUDCTL) $(TIMEOUT_FLAGS) $(FPGA_BOARD) console

cloud:	consolecloud



clean:
