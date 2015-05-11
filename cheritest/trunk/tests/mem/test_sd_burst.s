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
# Test a burst of sequential stores to memory from registers.  Repeat multiple
# times so that the sequence runs from the instruction cache at least once.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dli	$k0, 8

		dla	$gp, dword

		dli	$s0, 0x0123456789abcdef
		dli	$s1, 0x0123456789abcdef
		dli	$s2, 0x0123456789abcdef
		dli	$s3, 0x0123456789abcdef
		dli	$s4, 0x0123456789abcdef
		dli	$s5, 0x0123456789abcdef
		dli	$s6, 0x0123456789abcdef
		dli	$s7, 0x0123456789abcdef

		dli	$t0, 0x0123456789abcdef
		dli	$t1, 0x0123456789abcdef
		dli	$t2, 0x0123456789abcdef
		dli	$t3, 0x0123456789abcdef

		dli	$a0, 0x0123456789abcdef
		dli	$a1, 0x0123456789abcdef
		dli	$a2, 0x0123456789abcdef
		dli	$a3, 0x0123456789abcdef
		dli	$a4, 0x0123456789abcdef
		dli	$a5, 0x0123456789abcdef
		dli	$a6, 0x0123456789abcdef
		dli	$a7, 0x0123456789abcdef

loop:
		sd	$s0, 0($gp)
		sd	$s1, 8($gp)
		sd	$s2, 16($gp)
		sd	$s3, 24($gp)
		sd	$s4, 32($gp)
		sd	$s5, 40($gp)
		sd	$s6, 48($gp)
		sd	$s7, 56($gp)

		sd	$t0, 64($gp)
		sd	$t1, 72($gp)
		sd	$t2, 80($gp)
		sd	$t3, 88($gp)

		sd	$a0, 96($gp)
		sd	$a1, 104($gp)
		sd	$a2, 112($gp)
		sd	$a3, 120($gp)
		sd	$a4, 128($gp)
		sd	$a5, 136($gp)
		sd	$a6, 144($gp)
		sd	$a7, 152($gp)

		ld	$a0, 0($gp)
		ld	$a1, 8($gp)
		ld	$a2, 16($gp)
		ld	$a3, 24($gp)
		ld	$a4, 32($gp)
		ld	$a5, 40($gp)
		ld	$a6, 48($gp)
		ld	$a7, 56($gp)

		ld	$t0, 64($gp)
		ld	$t1, 72($gp)
		ld	$t2, 80($gp)
		ld	$t3, 88($gp)

		ld	$a0, 96($gp)
		ld	$a1, 104($gp)
		ld	$a2, 112($gp)
		ld	$a3, 120($gp)
		ld	$a4, 128($gp)
		ld	$a5, 136($gp)
		ld	$a6, 144($gp)
		ld	$a7, 152($gp)

		# Loop until zero
		daddiu	$k0, $k0, -1
		bne	$k0, $zero, loop
		nop			# branch-delay slot

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
dword:		.dword	0x0000000000000000	# 0
		.dword	0x0000000000000000	# 8
		.dword	0x0000000000000000	# 16
		.dword	0x0000000000000000	# 24
		.dword	0x0000000000000000	# 32
		.dword	0x0000000000000000	# 40
		.dword	0x0000000000000000	# 48
		.dword	0x0000000000000000	# 56
		.dword	0x0000000000000000	# 64
		.dword	0x0000000000000000	# 72
		.dword	0x0000000000000000	# 80
		.dword	0x0000000000000000	# 88
		.dword	0x0000000000000000	# 96
		.dword	0x0000000000000000	# 104
		.dword	0x0000000000000000	# 112
		.dword	0x0000000000000000	# 120
		.dword	0x0000000000000000	# 128
		.dword	0x0000000000000000	# 136
		.dword	0x0000000000000000	# 144
		.dword	0x0000000000000000	# 152
