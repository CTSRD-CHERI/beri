#-
# Copyright (c) 2012, 2016 Michael Roe
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
# Test that various operations raise an exception if C0 does not grant
# Permit_Load.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Clear the BEV flag
		#

		jal	bev_clear
		nop

		#
		# Set up exception handler
		#

		dli	$a0, 0xffffffff80000180
		dla	$a1, bev0_common_handler_stub
		dli	$a2, 12	# instruction count
		dsll	$a2, 2	# convert to byte count
		jal	memcpy
		nop		# branch delay slot	

		# $a2 will be set to 1 if the exception handler is called
		dli	$a2, 0

		#
		# Save c0
		#

		cgetdefault   $c1

		#
		# Make $c0 a write-only capability
		#

		dli     $t0, 0xb # Permit_Load not granted
		candperm $c2, $c1, $t0
		csetdefault $c2

		dla	$t1, data
		dli     $a0, 0
		dli	$a1, 0
		dli	$a2, 0

		#
		# These should raise a C2E exception
		#

		lb	$a0, 0($t1) 
		lh	$a0, 0($t1)
		lw	$a0, 0($t1)
		ld	$a0, 0($t1)
		lwr	$a0, 0($t1)
		lwl	$a0, 0($t1)
		ldr	$a0, 0($t1)
		ldl	$a0, 0($t1)

		#
		# Restore c0
		#

		csetdefault $c1

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.ent bev0_handler
bev0_handler:
		daddiu	$a2, $a2, 1
		mfc0    $k0, $13        # Cause register
                srl     $k0, $k0, 2
                andi    $k0, $k0, 0x1f
                addi    $k0, $k0, -18   # Coprocessor 2 exception
                beqz    $k0, expected_exception
                nop                     # Branch delay slot

                #
                # If we get an exception we didn't expected, mark the
                # test as failed by setting $a1
                #

                dli     $a1, 1

expected_exception:
                cgetcause $k0
                xori    $k0, $k0, 0x1200
                beqz    $k0, expected_cause
		nop

		#
		# If we get a cause code we didn't expect, mark the test
                # as failed by setting $a1
                #

                dli     $a1, 1

expected_cause:

		dmfc0	$a5, $14	# EPC
		daddiu	$k0, $a5, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop
		nop
		nop
		nop
		eret
		.end bev0_handler

		.ent bev0_common_handler_stub
bev0_common_handler_stub:
		dla	$k0, bev0_handler
		jr	$k0
		nop
		.end bev0_common_handler_stub

		.data
		.align	3
data:		.dword	0x0123456789abcdef
		.dword  0x0123456789abcdef


