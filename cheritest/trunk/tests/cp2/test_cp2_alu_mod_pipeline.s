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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# These are regression tests to check that arithmetic results on
# general-purpose registers are properly forward into CP2 inputs.  A bug
# existed in an earlier version of the CHERI prototype that would have been
# caught by this.
#
# For each test, perform arithmetic on $tX just before using it as an argument
# to a capability modification operation.  We can then check to see if the
# 'before' or 'after' value was used.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Test cincoffset
		dli	$t0, 0
		daddiu	$t0, $t0, 0x100
		cincoffset	$c2, $c2, $t0
		cgetoffset	$a0, $c2

		# Test csetbounds
		dli	$t1, 0
		daddiu	$t1, $t1, 0x100
		csetbounds	$c3, $c3, $t1
		cgetlen	$a1, $c3

		# Test candperm
		dli	$t2, 0
		daddiu	$t2, $t2, 0x100
		candperm	$c4, $c4, $t2
		cgetperm	$a2, $c4

		# Test csetoffset
		dli	$t3, 0
		daddiu	$t3, $t3, 0x100
		csetoffset	$c5, $c5, $t3
		cgetoffset	$a3, $c5

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
