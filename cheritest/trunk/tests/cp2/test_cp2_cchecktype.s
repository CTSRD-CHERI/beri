#-
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

.include "macros.s"
.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test cchecktype
#

# In this test, sandbox isn't actually called, but its address is used
# in a code capability.
sandbox:
		creturn

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Set up exception handler
		#

		jal	bev_clear
		nop
		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		dli	$a2, 0	# a2 will be set to 1 if an exception happens

		# Make $c1 a template capability for a user-defined type
		# whose identifier is 0x1234 (chosen arbitrarily).
		cgetdefault $c1
		dli      $t0, 0x1234
		csetoffset $c1, $c1, $t0

		# Make c4 a sealed code capability for sandbox
		cgetdefault $c4
		dla	 $t0, sandbox
		csetoffset $c4, $c4, $t0
		cseal	 $c4, $c4, $c1

		# Make $c2 a data capability for the array at address data
		cgetdefault $c2
		dla      $t0, data
		csetoffset $c2, $c2, $t0
		dli      $t0, 0x1000
		csetbounds  $c2, $c2, $t0
		# Permissions Non_Ephemeral, Permit_Load, Permit_Store,
		# Permit_Store.
		# NB: Permit_Execute must not be included in the set of
		# permissions used here, because we want this to be a
		# data capability.
		dli      $t0, 0xd
		candperm $c2, $c2, $t0

		# Seal data capability $c2 with $c1, and store
		# result in $c3.
		cseal 	 $c3, $c2, $c1

		# Check that c4 and c3 have the same otype
		# This should not raise an exception, as the otypes are equal
		cchecktype $c4, $c3

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.ent bev0_handler
bev0_handler:
		li	$a2, 1
		cgetcause $a3
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
		.align 12
data:		.dword	0xfedcba9876543210
