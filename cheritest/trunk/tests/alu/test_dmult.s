#-
# Copyright (c) 2011 William M. Morland
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

#
# Test which tries the 64-bit doubleword multiplication operator with each
# combination of positive and negative arguments.  Results are stored in hi
# (remainder) and lo (quotient).
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dli	$t0, 0x0fedcba987654321
		dli	$t1, 0x0101010101010101 
		#$zero prevents assembler adding checking instructions
		dmult	$t0, $t1
		mfhi	$a0
		mflo	$a1

		dli	$t0, 0xf0123456789abcdf
		dli	$t1, 0xfefefefefefefeff
		dmult	$t0, $t1
		mfhi	$a2
		mflo	$a3

		dli	$t0, 0xf0123456789abcdf
		dli	$t1, 0x0101010101010101 
		dmult	$t0, $t1
		mfhi	$a4
		mflo	$a5

		dli	$t0, 0x0fedcba987654321
		dli	$t1, 0xfefefefefefefeff
		dmult	$t0, $t1
		mfhi	$a6
		mflo	$a7

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
