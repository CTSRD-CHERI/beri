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
# Exercise an unconditional trap instruction and validate a variety of
# assumptions about the exception handling environment.  This version of the
# test runs in the early boot environment (BEV=1), and we specifically check
# for the case where the (BEV=0) handler is exercised.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Install a dummy handler, which should not be invoked, in the
		# RAM exception handler.
		#
		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		#
		# Set up 'handler' as the ROM exception handler.
		#
		dla	$a0, bev1_handler
		jal	bev1_handler_install
		nop

		#
		# Set CP0.Status.BEV, so the ROM handler will be called
		#
		mfc0	$t0, $12
		dli	$t1, 1 << 22
		or	$t0, $t0, $t1
		mtc0	$t0, $12
		nop
		nop
		nop
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

		#
		# Save the desired EPC value for this exception so we can
		# check it later.
		#
		dla	$a0, desired_epc

		#
		# Trigger exception.
		#
desired_epc:
		teq	$zero, $zero

		#
		# Exception return.
		#
		li	$a1, 1
		mfc0	$a7, $12	# Status register after ERET

return:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

#
# Our actual exception handler, which tests various properties.  This code
# assumes that the trap wasn't in a branch-delay slot (and the test code
# checks BD as well), so EPC += 4 should return control after the trap
# instruction.
#
		.ent bev1_handler
bev1_handler:
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
		.end bev1_handler

#
# If the wrong handler is invoked, escape quickly, leaving behind a calling
# card.
#
# XXXRW: Should have the linker calculate the length for us.
#
		.ent bev0_handler
bev0_handler:
		li	$a6, 1
		b	return
		nop
		.end bev0_handler
