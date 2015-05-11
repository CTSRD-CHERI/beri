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
# Test that we can read the CP0 TagLo registwr.
#
# CP0 Config1 is used to determine how many cache sets there are, then
# a loop runs through all index values in range and reads the corresponding
# tag.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dli	$a2, 0			# Set to 1 when test completes

		#
		# Set $a0 to the number of Dcache sets * number of ways
		#

		mfc0	$a0, $16, 1		# Config1
		srl	$a0, $a0, 13		# DCache sets
		andi	$a0, $a0, 0x7

		mfc0	$t0, $16, 1		# Config1
		srl	$t0, $t0, 7		# DCache addociativity
		andi	$t0, $t0, 0x3

		addu	$t0, $a0, $t0
		li	$a0, 64
		sllv	$a0, $a0, $t0

		#
		# Set $a1 to the L2 cache sets * number of ways
		#

		mfc0	$a1, $16, 2		# Config2
		srl	$a1, $a1, 8
		andi	$a1, $a1, 0xf

		mfc0	$t0, $16, 2		# Config2
		andi	$t0, $t0, 0xf		# L2 associativity

		addu	$t0, $a1, $t0
		li	$a1, 64
		sllv	$a1, $a1, $t0

		#
		# Set $a3 to the DCache line size
		#

		mfc0	$t0, $16, 1		# Config1
		srl	$t0, $t0, 10
		andi	$t0, $t0, 0x7
		dli	$a3, 2
		sllv	$a3, $a3, $t0

		#
		# Set $a4 to the L2 cache line size
		#

		mfc0	$t0, $16, 2		# Config2
		srl	$t0, $t0, 4		# SL
		andi	$t0, $t0, 0xf
		dli	$a4, 2
		sllv	$a4, $a4, $t0

		dli	$t1, 0x80000000		# kseg0
		daddi	$t0, $a0, -1
loop1:
		cache	0x5, 0($t1)		# Index Load Tag, L1 data
		mfc0	$v0, $28		# TagLo
		daddu	$t1, $a3		# Increment pointer into cache
		daddi	$t0, $t0, -1
		bgez	$t0, loop1
		nop				# Branvh delay

		#
		# Set $t0 to the number of L2 sets per way - 1
		#

		dli     $t1, 0x80000000		# kseg0
		daddi	$t0, $a1, -1
loop2:
		cache	0x7, 0($t1)		# Index Load Tag, L2 cache
		mfc0	$t1, $28		# TagLo
		daddi	$t0, $t0, -1
		bgez	$t0, loop2
		nop				# Branch delay


end:
		dli	$a2, 1

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
