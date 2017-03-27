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
# Test coherence of the intruction and data caches.
#
# This test uses self-modifying code to sum the numbers from 0 to 15,
# patching the number to be added into an add immediate instruction each
# time around the loop.
#
# The MIPS specification does not require the I and D caches to be coherent,
# so a MIPS_conforming CPU is not required to pass this test.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		li	$a0, 15
		dli	$a1, 0
		dla	$a2, L2
		lw	$a3, 0($a2)

L1:
		or	$a4, $a3, $a0
		sw	$a4, 0($a2)
		cache	0x19, 0($a2)	# Flush writeback DCache to memory
		nop # Ensure that DCache flush reaches memory before ICache makes request.
		nop
		nop
		nop
		cache	0x10, 0($a2)	# Invalidate ICache for address $a2
		lw	$a5, 0($a2)
		nop
		nop
		nop
		nop
		nop
		nop
		nop
L2:		addi	$t0, $zero, 0
		dadd	$a1, $a1, $t0
		bgtz	$a0, L1
		addi	$a0, $a0, -1

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align 3
		.word 0
