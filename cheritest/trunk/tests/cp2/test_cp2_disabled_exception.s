#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2013 Robert M. Norton
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
# Test to check that a cp2 instruction causes an exception if cp2 is
# not enabled.
#
# Outputs to check:
#
# $a0 - exception counter (should be 1)
# $a1 - cause register from last trap (should be TRAP)
# $a2 - EPC register from last trap (should be 0x10)
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Set up 'handler' as the RAM exception handler.
		#
		jal	bev_clear
		nop
		dla	$a0, exception_handler
		jal	bev0_handler_install
		nop

		#
		# Initialise trap counter.
		#
		dli	$a0, 0

	        # Disable CP2 in status register 
	        mfc0    $at, $12
                li	$t1, 1 << 30
                nor     $t1, $0          # invert to form mask
                and     $at, $at, $t1
	        mtc0    $at, $12
	        nop
	        nop
	        nop
	        nop
	        nop

expected_epc:
                # Attempt to clear tag. This should cause exception
                # as cp2 is disabled.
                ccleartag $c1, $c0

return:
                # Re-enable CP2 in status register 
	        mfc0    $at, $12
                li	$t1, 1 << 30
                or      $at, $at, $t1
	        mtc0    $at, $12

                # Save expected epc for later comparison
                # with a2
                dla     $a3, expected_epc
        
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test


#
# Exception handler. This code assumes that the trap was not in a branch delay slot.
#
		.ent exception_handler
exception_handler:
		daddiu	$a0, $a0, 1	# Increment trap counter        
		dmfc0	$a1, $13	# Get cause register
		dmfc0	$a2, $14        # get EPC

		# Set EPC to continue after exception return
		dla	$k0, return
		dmtc0	$k0, $14
		eret
		.end exception_handler
