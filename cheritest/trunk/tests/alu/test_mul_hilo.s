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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test what happens when a MUL instruction (which puts the multiplication
# result in a register) is followed by MFHI/MFLO. According to the MIPS ISA
# specification, the contents of the HI and LO registers are UNPREDICTABLE.
# This is an UNPREDICTABLE result, not an UNPREDICTABLE operation: i.e.
# the spec doesn't define what bits you get from HI and LO, but nothing
# else unexpected should happen, e.g. it must not raise an exception.
#
# This case will occur during normal operation with a typical operating
# system, when a user-space process uses mui, and then a timer interrupt
# happens and the kernel tries to save the user processs' registers,
# including HI and LO. It is vital that (e.g.) MFLO does not cause an
# exception in the kernel.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dli	$t0, 5
		mtlo	$t0
		mthi	$t0
		nop
		nop
		nop
		nop
		nop

		dli	$t0, 2
		dli	$t1, 3
		mul	$a0, $t0, $t1
		nop
		nop
		nop
		nop
		nop
		nop

		mflo	$a1
		mfhi	$a2

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
