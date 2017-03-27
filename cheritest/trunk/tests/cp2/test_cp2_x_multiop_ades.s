#-
# Copyright (c) 2015 Michael Roe
# Copyright (c) 2015 SRI International
# All rights reserved.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
# project, funded by EPSRC grant EP/K008528/1.
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

.include "macros.s"
.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test that the store via capability operations raise an exception
# if the address is not correctly aligned.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Clear the BEV flag
		#

		jal	bev_clear
		nop

		#
		# Set up exception handler
		#

		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		#
		# $a1 will be set non-zero if get an unexpected exception
		#

		dli	$a1, 0

		#
		# Count of number of exceptions
		#

		dli	$a2, 0

		#
		# Make $c1 a capability for the array 'data'.
		# 'data' is 160=128+32 bytes long so that it's large enough
		# to contain an unaligned store of a capability across a cache
		# line without causing the length check to fail.
		#
		# The size of a capability depends on whether we're using
		# 128-bit or 256-bit capabilities. The size of a cache
		# line can also vary. Here, I'm assuming thats it's 128 bytes
		# on CHERI256 and 64 bytes on CHERI128.
		#

		cgetdefault $c1
		dla	$t0, data
		csetoffset $c1, $c1, $t0
		dla	$t0, 160
		csetbounds $c1, $c1, $t0

		#
		# Try some CP2 instructions
		#

		#
		# Stores
		#

		dli	$t1, 127	# unaligned, probably spans cache line

		cscr	$c2, $t1($c1)
		# csbr will work at any alignment
		cshr	$t0, $t1($c1)
		cswr	$t0, $t1($c1)
		csdr	$t0, $t1($c1)
		csetoffset $c3, $c1, $t1
		csch	$t0, $t2, $c3
		cscw	$t0, $t2, $c3
		cscd	$t0, $t2, $c3
		cscc	$t0, $c1, $c3

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.ent bev0_handler
bev0_handler:
		daddiu	$a2, $a2, 1

		mfc0	$k0, $13	# Cause register
		srl	$k0, $k0, 2
		andi	$k0, $k0, 0x1f
		addi	$k0, $k0, -5	# address error in store
		beqz	$k0, expected_exception
		nop			# Branch delay slot

		#
		# If we get an exception we didn't expected, mark the
		# test as failed by setting $a1
		#

		dli	$a1, 1

expected_exception:

		dmfc0	$a5, $14	# EPC
		daddiu	$k0, $a5, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop
		nop
		nop
		nop
		eret
		.end bev0_handler


		.data
		.align	7	# NB: Cache line aligned
data:

		.rept	160
		.byte	0
		.endr
