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
# This test checks two properties of eret:
#
# (1) It must clear the EXL flag in the status register
# (2) It must jump to EPC without a branch delay slot
#
# In the future, it might be useful to also have an error trap test that works
# with ERL rather than EXL.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Set EXL manually
		mfc0	$a0, $12
		ori	$a0, 1 << 1
		mtc0	$a0, $12
		nop
		nop
		nop
		nop
		nop			# XXX: How many are required here?
		mfc0	$a0, $12	# Saved to let us check EXL stuck

		# Configure a target EPC
		dla	$t0, epc_target
		dmtc0	$t0, $14

		nop			# NOPs to avoid hazard with ERET
		nop			# XXXRW: How many are actually
		nop			# required here?
		nop

		li	$a1, 1		# Should run
		eret
		li	$a2, 2		# Shouldn't run (not a branch delay!)
		li	$a3, 3		# Shouldn't run (eret jumps to new EPC)
epc_target:
		li	$a4, 4		# Should run
		mfc0	$a5, $12	# Status register to check EXL again

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
