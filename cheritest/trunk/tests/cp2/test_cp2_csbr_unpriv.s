#-
# Copyright (c) 2011 Robert N. M. Watson
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
# Test csbr (store byte via capability, offset by register) using a
# constrained capability.
#

		.global test
test:		.ent test
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Set up $c1 to point at data
		# We want $c1.length to be 8.
		#
		cgetdefault $c1
		dla	$t0, data
		csetoffset $c1, $c1, $t0
		dli	$t1, 8
		csetbounds $c1, $c1, $t1

		dli	$s0, 0
		dli	$t2, 0x01
		csbr	$t2, $s0($c1)
		dli	$s0, 1
		dli	$t2, 0x23
		csbr	$t2, $s0($c1)
		dli	$s0, 2
		dli	$t2, 0x45
		csbr	$t2, $s0($c1)
		dli	$s0, 3
		dli	$t2, 0x67
		csbr	$t2, $s0($c1)
		dli	$s0, 4
		dli	$t2, 0x89
		csbr	$t2, $s0($c1)
		dli	$s0, 5
		dli	$t2, 0xab
		csbr	$t2, $s0($c1)
		dli	$s0, 6
		dli	$t2, 0xcd
		csbr	$t2, $s0($c1)
		dli	$s0, 7
		dli	$t2, 0xef
		csbr	$t2, $s0($c1)

		#
		# Load using regular MIPS instructions for checking.
		#
		dla	$t3, underflow
		ld	$a0, 0($t3)
		dla	$t3, data
		ld	$a1, 0($t3)
		dla	$t3, overflow
		ld	$a2, 0($t3)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align 3
underflow:	.dword	0x0000000000000000
data:		.dword	0x0000000000000000
overflow:	.dword	0x0000000000000000
