#-
# Copyright (c) 2014-2015 Michael Roe
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
# Test what happens when a divide by zero is followed by a trap if equal
# testing for the divisor being zero. This instruction sequence is often
# used by the GCC and Clang/LLVM compilers. According to the MIPS spec,
# this is _not_ an 'unpredictable operation', but the result of the divison
# is an 'unpredictable result'. That is, the behaviour of the CPU is defined
# by the spec as long as the result isn't used.
#
# Compilers put the division and the test in this order so that the division
# van be done in parallel with the test.
#

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

		dli	$a0, 0
		dli	$a1, 0
		# $a2 will be set to 1 if the exception handler is called
		dli	$a2, 0

		dli	$t0, 0x1234
		mtlo	$t0
		mthi	$t0
		nop
		nop
		nop
		nop
		nop

		dli	$t0, 1
		dli	$t1, 0
		ddiv	$zero, $t0, $t1
		teq	$t1, $zero	# Should trap
		mflo	$a1		# Not reached, as exception handler
		mfhi	$a3		# will return to 'exit'.

exit:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.ent bev0_handler
bev0_handler:
		li	$a2, 1
		dmfc0	$a0, $13	# CP0.Cause
		dmfc0	$a5, $14	# EPC
		dla	$k0, exit
		dmtc0	$k0, $14
		nop
		nop
		nop
		nop
		eret
		.end bev0_handler

		.ent subroutine
subroutine:
		jr	$ra
		nop
		.end subroutine
