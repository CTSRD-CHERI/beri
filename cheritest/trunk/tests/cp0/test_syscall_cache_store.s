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
# Check for regressions on a bug in which an exception following a store
# triggered a cache bug.  The bug was triggered when pre-exception
# instructions were running out of the cache, so run the store/syscall
# sequence twice.
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
		# Run the test twice, preload address to avoid changing
		# pipeline timing.
		#
		dla	$s8, dword
		dli	$t0, 2

		#
		# Trigger exception.
		#
desired_epc:
		syscall	0

		sd	$v0, 0($s8)
		ld	$v0, 0($s8)

		#
		# We want to trigger the exception twice, ensuring that the
		# second time, the above sd instruction is already cached.
		#
		daddiu	$t0, $t0, -1
		bne	$t0, $zero, desired_epc

		#
		# Exception return.
		#
		li	$a1, 1
		mfc0	$a6, $12	# Status register after ERET

return:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

#
# Our actual exception handler.  This code assumes that the trap wasn't in a
# branch-delay slot (and the test code checks BD as well), so EPC += 4 should
# return control after the trap instruction.
#
		.ent bev0_handler
bev0_handler:
		li	$a2, 1
		dmfc0	$a5, $14	# EPC
		daddiu	$k0, $a5, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop			# NOPs to avoid hazard with ERET
		nop			# XXXRW: How many are actually
		nop			# required here?
		nop
		nop
		nop
		eret
		.end bev0_handler

		.data
dword:		.dword 0x0000000000000000
