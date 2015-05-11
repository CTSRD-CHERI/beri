#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2012 Robert M. Norton
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
# Test the watchpoint functionality for store accesses.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Set up exception handler.
		#
		jal	bev_clear
		nop
		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		#
		# Clear registers we'll use when testing results later.
		#
		dli	$a0, 0
		dli	$a1, 0
		dli	$a2, 0
		dli	$a3, 0
		dli	$a4, 0
		dli	$a5, 0
		dli	$a6, 0
		dli	$a7, 0
		dli	$s0, 0
		dli	$s1, 0

		#
		# Save the desired EPC value for this exception so we can
		# check it later.
		#
		dla	$a0, testdata
		# Make a watch point at this address
		ori	$a1, $a0, 1     # Set write watch bit
		dmtc0	$a1, $18        # Set watchLo
                dli     $t0, 0x40000000 # Set global bit, zero mask
                dmtc0   $t0, $19        # Set watchHi
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		#
		# Trigger watch 
		#
desired_epc:
		sd      $t0, 0($a0)

                # Note that a load should NOT trigger the watchpoint.
                ld      $t0, 0($a0)        

		#
		# Exception return.
		#
		li	$a1, 1
		mfc0	$a6, $12	# Status register after ERET

                dmfc0   $a6, $18        # Read back watchLo
                dla     $a7, desired_epc

return:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

#
# Our actual exception handler, which tests various properties.  This code
# assumes that the overflow wasn't in a branch-delay slot (and the test code
# checks BD as well), so EPC += 4 should return control after the overflow
# instruction.
#
		.ent bev0_handler
bev0_handler:
		li	$a2, 1
		mfc0	$a3, $12	# Status register
		mfc0	$a4, $13	# Cause register
		dmfc0	$a5, $14	# EPC
		daddiu	$k0, $a5, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop			# NOPs to avoid hazard with ERET
		nop			# XXXRW: How many are actually
		nop			# required here?
		nop
		eret
		.end bev0_handler

.data
testdata:
        .dword 0xdeadbeefdeadbeef
