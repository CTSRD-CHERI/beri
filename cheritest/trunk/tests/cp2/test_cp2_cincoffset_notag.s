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
# Test that cincoffset will work on non-capability data (i.e. tag unset)
# that just happens to have a set bit in the position that would be the
# sealed bit if it were a valid capability.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Create a sealed capability
		#

		dli	$t0, 1
		csetoffset $c1, $c0, $t0
		dli	$t0, 0x7
		candperm $c2, $c0, $t0
		cseal	$c2, $c2, $c1

		#
		# Read and write the capability with data load/store
		# instructions, clearing the tag bit
		#

		dla	$t0, cap
		cscr	$c2, $t0($c0)
		ld	$t1, 0($t0)
		sd	$t1, 0($t0)
		clcr	$c2, $t0($c0)

		#
		# Now try cincoffset
		#

		cgetoffset $a0, $c2
		dli	$t0, 5
		cincoffset $c2, $c2, $t0
		cgetoffset $t0, $c2
		dsubu	$a1, $t0, $a0

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align 5
cap:		.dword 0
		.dword 0
		.dword 0
		.dword 0
