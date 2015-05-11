#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2014 Michael Roe
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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test the case where there is a store instruction immediately after a
# software interrupt. The store should be cancelled. This is a regression
# test for a pipeline bug in CHERI1.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Set up exception handler.
		#
		jal	bev_clear
		nop
		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		#
		# Clear registers we'll use when testing results later.
		#
		dli	$a0, 0
		dli	$a1, 0
		dli	$a2, 0
		dli	$a3, 0
		dli	$a4, 0
		dli	$a5, 0
		dli	$a6, 0

		#
		# Enable software interrupts
		#

		mfc0	$t0, $12
		ori	$t0, 0x3e1
		mtc0	$t0, $12
		nop
		nop
		nop
		nop
		nop

		dli	$a0, 0x9800000000001000 # Address to store things
		sd	$0,  0($a0)		# Initialize the location to 0
		dli	$t0, 0x9000000000000000 # Load an uncached address to force cache misses.
		ld	$t1, 0($t0)
		nop
		nop
		nop
		nop

		#
		# Trigger a software interrupt by writing to bit IP0
		# (interrupt pending) of the CP0 cause register.
		#

		li	$t0, 0x100
		mtc0	$t0, $13

		#
		# The following store should be cancelled when the software
		# interrupt fires.
		#

		sd	$a0, 0($a0)

		#
		# Check that the store didn't happen.
		#

		ld	$a1, 0($a0)

return:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

#
# Our actual exception handler, which tests various properties.  This code
# assumes that the trap wasn't in a branch-delay slot (and the test code
# checks BD as well), so EPC += 4 should return control after the victim.
#
		.ent bev0_handler
bev0_handler:	
		dli	$k0, 0xFFFF00FF
		dmfc0	$a5, $13	# Cause register
		and	$k0, $a5, $k0	# # Clear interrupts in the cause register
		dmtc0	$k0, $13
		dmfc0	$a5, $14	# EPC
		daddiu	$k0, $a5, 4	# EPC += 4 to bump PC forward on ERET to skip the victim
		dmtc0	$k0, $14
		nop			# NOPs to avoid hazard with ERET
		nop			# XXXRW: How many are actually
		nop			# required here?
		nop
		eret
		.end bev0_handler
