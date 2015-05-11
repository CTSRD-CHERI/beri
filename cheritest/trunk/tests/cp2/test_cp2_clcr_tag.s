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
# Test that if we store a capability to memory, a later reload contains the
# same capability field values.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Tweak capability type field so that we can tell if base and
		# offset are in the right order.
		#
		dli	$t2, 0x1
		csetoffset	$c2, $c2, $t2

		#
		# Store at cap1 in memory.
		#
		# XXXRW: Fix to use indexed address syntax once available.
		#
		dla	$t0, cap1
		dli	$t1, 0xFFFFFFFF00000000
		and	$t0, $t0, $t1
		clcr	$c16, $t0($c0)
		cscr	$c2, $t0($c0)

		#
		# Load back into another capability register
		#
		clcr	$c3, $t0($c0)
		
		#
		# Invalidate the line in the L1
		#
		daddi	$t1, $t0, 16384
		cscr	$c16, $t1($c0)
  
		#
		# Load from the L2 into another capability register
		#
		clcr	$c4, $t0($c0)
		
		#
		# Invalidate the line in the L1 & L2
		#
		dli	$t1, 16384*4
		dadd	$t1, $t0, $t1
		cscr	$c16, $t1($c0)
  
		#
		# Load from the DRAM into another capability register
		#
		clcr	$c5, $t0($c0)

		#
                # Invalidate the line in the tag cache & L1 & L2
                #
		dli	$t1, 16384*512
		dadd	$t1, $t0, $t1
                cscr    $c16, $t1($c0)

                #
                # Load both tag and data from the DRAM into capability register
                #
                clcr    $c6, $t0($c0)
  
		#
		# Extract various values into general-purpose registers for
		# checking.
		#
		cgettag  $a0, $c3
		cgettag  $a1, $c4
		cgettag  $a2, $c5
		cgettag  $a3, $c6

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align	5		# Must 256-bit align capabilities
cap1:		.dword	0x0123456789abcdef	# uperms/reserved
		.dword	0x0123456789abcdef	# otype/eaddr
		.dword	0x0123456789abcdef	# base
		.dword	0x0123456789abcdef	# length
