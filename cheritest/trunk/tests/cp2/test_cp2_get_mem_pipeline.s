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
# Unit tests to confirm that inputs to ALU operations from capability field
# query instructions are handled properly.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dla	$s0, data

		# Test cgetbase
		dli	$t0, 100
		cgetbase	$t0, $c2	# should return 0x0
		sd	$t0, 0($s0)

		# Test cgetlen
		dli	$t1, 100
		cgetlen	$t1, $c2	# should return 0xff...ff
		sd	$t1, 8($s0)

		# Test cgetperm
		dli	$t2, 100
		cgetperm	$t2, $c2	# should return 0x7fff
		sd	$t2, 16($s0)

		# Test cgettype
		dli	$t3, 100
		cgettype	$t3, $c2	# should return 0x0
		sd	$t3, 24($s0)

		nop
		nop
		nop
		nop
		nop
		nop
		nop
		ld	$t0, 0($s0)
		ld	$t1, 8($s0)
		ld	$t2, 16($s0)
		ld	$t3, 24($s0)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
data:		.dword	0x200
		.dword	0x200
		.dword	0x200
		.dword	0x200
