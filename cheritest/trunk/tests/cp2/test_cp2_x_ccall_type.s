#-
# Copyright (c) 2012-2015 Michael Roe
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
# Test ccall
#

sandbox:
		creturn
		nop

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

		#
		# Set up trap handler for CCall
		#

		dli	$a0, 0xffffffff80000280
		dla	$a1, bev0_ccall_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, 2		# Convert to byte count
		jal memcpy
		nop			# branch-delay slot

                # Make $c1 a template capability for a user-defined type
		# whose otype is 0x1234
		dli	 $t0, 0x1234
		csetoffset $c1, $c0, $t0

                # Make $c2 a data capability for the array at address data
		dla      $t0, data
		cincbase $c2, $c0, $t0
                dli      $t0, 8
                csetlen  $c2, $c2, $t0
		# Permissions Non_Ephemeral, Permit_Load, Permit_Store,
		# Permit_Store.
		dli      $t0, 0xd
		candperm $c2, $c2, $t0

		# Seal data capability $c2 to the offset of $c1, and store
		# result in $c3.
                cseal	 $c3, $c2, $c1

		# Make $c4 a code capability with a different otype
		dla	$t0, sandbox
		csetoffset $c4, $c0, $t0
		dli	$t0, 0x4567
		csetoffset $c1, $c0, $t0
		cseal	 $c4, $c4, $c1

		# $a2 will be set to 1 if the normal trap handler is called,
		# 2 if the ccall trap handler is called.
		dli	$a2, 0

		ccall   $c4, $c3
		nop

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.ent bev0_handler
bev0_handler:
		li	$a2, 1
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

		.ent bev0_ccall_handler
bev0_ccall_handler:
		li      $a2, 2
		cgetcause $a3
		dmfc0   $a5, $14
		daddiu  $k0, $a5, 4 # Bump EPC forward one instruction
		dmtc0   $k0, $14
		nop
		nop
		nop
		nop
		eret
		.end bev0_ccall_handler

		.ent bev0_ccall_handler_stub
bev0_ccall_handler_stub:
		dla     $k0, bev0_ccall_handler
		jr      $k0
		nop
		.end bev0_ccall_handler_stub

		.data
		.align 3
data:		.dword	0xfedcba9876543210
