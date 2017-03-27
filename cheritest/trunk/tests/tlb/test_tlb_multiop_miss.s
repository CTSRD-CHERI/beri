#-
# Copyright (c) 2014, 2016 Michael Roe
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
# project, funded by EPSRC grant EP/K008528/1.
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
# Test several different instructions causing a page miss
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Set up a handler for TLB misses
		#

		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		#
		# Find out how many TLB entries there are
		#

		mfc0	$a0, $16, 1	# Config1
		srl	$a0, $a0, 25
		andi	$a0, $a0, 0x3f
		addi	$a0, $a0, 1

		#
		# Set the number of wired TLB entries to 0
		#

		mtc0	$zero, $6	# TLB Wired

		#
		# Set the page size to 4K
		#

		mtc0	$zero, $5	# TLB Page Mask

		#
		# Loop through the TLB, clearing it
		#

		dmtc0	$zero, $2	# TLB EntryLo0
		dmtc0	$zero, $3	# TLB EntryLo1

		dli	$a3, 1 << 13	# VPN2 field in EntryHi
		dli	$a2, 5		# ASID to use for TLB entries

		dli	$a1, 0
loop:
		dmtc0	$a2, $10	# TLB EntryHi
		mtc0	$a1, $0		# TLB Index

		tlbwi

		addi	$a1, $a1, 1
		dadd	$a2, $a2, $a3
		bne	$a1, $a0, loop
		nop			# Branch delay slot

		dli	$a0, 0
		dli	$a1, 0
		dli	$a2, 0		# Use a2 to count the number of exceptions

		#
		# These should raise an exception
		#

		lb	$t0, 0($zero)
		lh	$t0, 0($zero)
		lw	$t0, 0($zero)
		ld	$t0, 0($zero)
		lwl	$t0, 0($zero)
		lwr	$t0, 0($zero)
		ldl	$t0, 0($zero)
		ldr	$t0, 0($zero)

		sb	$zero, 0($zero)
		sh	$zero, 0($zero)
		sw	$zero, 0($zero)
		sd	$zero, 0($zero)
		swl	$zero, 0($zero)
		swr	$zero, 0($zero)
		sdl	$zero, 0($zero)
		sdr	$zero, 0($zero)

		#
		# Reset the counter and try floating point loads and stores
		#

		move	$a0, $a2
		dli	$a2, 0

		mfc0	$t0, $16, 1
		andi	$t0, $t0, 0x1
		beqz	$t0, no_fpu
		nop

		mfc0	$t0, $12	# Status
		dli	$t1, 1 << 29	# Enable FPU
		or	$t0, $t0, $t1
		dli	$t1, 1 << 26	# FPU in 64-bit mode
		or	$t0, $t0, $t1
		mtc0	$t0, $12

		lwc1	$f0, 0($zero)
		ldc1	$f0, 0($zero)
		swc1	$f0, 0($zero)
		sdc1	$f0, 0($zero)

		move	$a1, $a2
no_fpu:
		
		dli	$a2, 0

		mfc0    $t0, $16, 1
		andi	$t0, 0x40
		beqz	$t0, no_cp2
		nop
		
		clbi	$t0, 0($c0)
		clhi	$t0, 0($c0)
		clwi	$t0, 0($c0)
		cldi	$t0, 0($c0)
		csbi	$zero, 0($c0)
		cshi	$zero, 0($c0)
		cswi	$zero, 0($c0)
		csdi	$zero, 0($c0)

		cllb	$t0, $c0
		cllh	$t0, $c0
		cllw	$t0, $c0
		clld	$t0, $c0
		cllc	$c1, $c0

no_cp2:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.ent bev0_handler
bev0_handler:
		daddiu	$a2, $a2, 1	# Count the number of exceptions
		dmfc0	$k0, $14	# EPC
		daddiu	$k0, $k0, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop
		nop
		nop
		nop
		eret
		.end bev0_handler
