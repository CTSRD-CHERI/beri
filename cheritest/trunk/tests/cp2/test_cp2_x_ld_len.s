#-
# Copyright (c) 2012, 2015 Michael Roe
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
# Test that ld raises an exception if the load goes outside of C0.len.
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
		
		sync

		# $a2 will be set to 1 if the exception handler is called
		dli	$a2, 0

		#
		# Save c0
		#

		cgetdefault   $c1


		dla	$t0, data
		csetoffset $c2, $c1, $t0
		dli	$t0, 3
		csetbounds $c2, $c2, $t0

		csetdefault $c2

		dli     $a0, 0
		ld      $a0, 0($zero) # This should raise a C2E exception

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
		dli	$a2, 1
		cgetcause $a3
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


