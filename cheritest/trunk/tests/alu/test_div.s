#-
# Copyright (c) 2011 William M. Morland
# Copyright (c) 2012 Jonathan Woodruff
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
# Test which tries the 32-bit division operator with each combination
# of positive and negative arguments.  Results are 32-bit numbers
# (sign-extended to 64-bits) which are stored in hi (remainder) and lo
# (quotient).
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		li	$t0, 123
		li	$t1, 24
		#$zero prevents assembler adding checking instructions
		div	$zero, $t0, $t1
		mfhi	$a0
		mflo	$a1

		li	$t0, -123
		li	$t1, -24
		div	$zero, $t0, $t1
		mfhi	$a2
		mflo	$a3

		li	$t0, -123
		li	$t1, 24
		div	$zero, $t0, $t1
		mfhi	$a4
		mflo	$a5

		li	$t0, 123
		li	$t1, -24
		div	$zero, $t0, $t1
		mfhi	$a6
		mflo	$a7

		# The result of the following is undefined
		# (only way to produce integer divide overflow).
		# Useful to test that cheri does not blow up,
		# don't really care about result. gxemul crashes!
		li      $t0, 0x80000000
		li      $t1, 0xffffffff
		div     $zero, $t0, $t1
		mfhi    $s0
		mflo	$s1
		
		# Below is a case found in the freeBSD kernel,
		# mult followed immediatly by div.
		li	$t0, 25
		li	$t1, 4
		li	$t2, 5
		mul	$t0, $t1, $t0
		div	$zero, $t0, $t2
		mfhi	$s2
		mflo	$s3

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
