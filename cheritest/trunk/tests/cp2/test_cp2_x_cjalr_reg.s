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
# Test that cjalr raises an exception if don't have permission for the
# reserved register.
#

sandbox2:
		dli     $a0, 1
		cjr     $c24
		nop			# Branch delay slot

sandbox1:
		cmove	$c3, $c24	# Save return capability
		cjalr	$c27, $c24	# Should raise an exception
		nop			# Branch delay slot
		cmove	$c24, $c3	# Restore return capability
		cjr	$c24		# Return from subroutine
		nop			# Branch delay slot

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
		# $a0 will be set to 1 if sandbox is called
		#

		dli     $a0, 0

		#
		# $a2 will be set to 1 if the exception handler is called
		#

		dli	$a2, 0


		#
		# Make $c27 an executable capability for sandbox2
		
		cgetdefault $c27
		dla     $t0, sandbox2
		csetoffset $c27, $c27, $t0

		#
		# Make $c1 an executable capability for sandbox1
		# Discard permission for the reserved registers
		#

		cgetdefault $c1
		dla	$t0, 0x1ff
		candperm $c1, $c1, $t0
		dla	$t0, sandbox1
		csetoffset $c1, $c1, $t0
		
		cjalr   $c1, $c24 	# Call into sandbox1
		nop			# Branch delay slot

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

		.data
		.align	3
data:		.dword	0x0123456789abcdef
		.dword  0x0123456789abcdef


