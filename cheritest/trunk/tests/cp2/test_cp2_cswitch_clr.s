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

.include "macros.s"
.set mips64
.set noreorder
.set nobopt
.set noat

#
# Macro test that checks whether we can save and restore the complete
# capability register file.  All loads and stores are performed via $c30
# ($kdc).  This replicates the work an operating system would perform in
# order to ensure that an OS would work!
#
# Unlike test_cp2_cswitch, this test clears capability registers between
# store and load to ensure that all fields are being handled properly.
#

		.global test
test:		.ent test
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Ensure all capability registers are set to the default.
    cmove		$c1, $c0
    cmove		$c2, $c0
    cmove		$c3, $c0
    cmove		$c4, $c0
    cmove		$c5, $c0
    cmove		$c6, $c0
    cmove		$c7, $c0
    cmove		$c8, $c0
    cmove		$c9, $c0
    cmove		$c10, $c0
    cmove		$c11, $c0
    cmove		$c12, $c0
    cmove		$c13, $c0
    cmove		$c14, $c0
    cmove		$c15, $c0
    cmove		$c16, $c0
    cmove		$c17, $c0
    cmove		$c18, $c0
    cmove		$c19, $c0
    cmove		$c20, $c0
    cmove		$c21, $c0
    cmove		$c22, $c0
    cmove		$c23, $c0
    cmove		$c24, $c0
    cmove		$c25, $c0
    cmove		$c26, $c0

		#
		# Save out all capability registers but $kcc and $kdc.
		#
		dla	$t0, data
		cscr	$c0, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c1, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c2, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c3, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c4, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c5, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c6, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c7, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c8, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c9, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c10, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c11, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c12, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c13, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c14, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c15, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c16, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c17, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c18, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c19, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c20, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c21, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c22, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c23, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c24, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c25, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c26, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c27, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c28, $t0($c30)

		daddiu	$t0, $t0, 32
		cscr	$c31, $t0($c30)

		#
		# Scrub capability registers in between to make sure that
		# fields are being properly restored.
		#
		dli	$t0, 0xffffffffffffffff
		dli	$t1, 0
		dli	$t2, 0x010101

		csetoffset	$c0, $c0, $t2
		cincbase	$c0, $c0, $t0
		candperm	$c0, $c0, $t1

		csetoffset	$c1, $c1, $t2
		cincbase	$c1, $c1, $t0
		candperm	$c1, $c1, $t1

		csetoffset	$c2, $c2, $t2
		cincbase	$c2, $c2, $t0
		candperm	$c2, $c2, $t1

		csetoffset	$c3, $c3, $t2
		cincbase	$c3, $c3, $t0
		candperm	$c3, $c3, $t1

		csetoffset	$c4, $c4, $t2
		cincbase	$c4, $c4, $t0
		candperm	$c4, $c4, $t1

		csetoffset	$c5, $c5, $t2
		cincbase	$c5, $c5, $t0
		candperm	$c5, $c5, $t1

		csetoffset	$c6, $c6, $t2
		cincbase	$c6, $c6, $t0
		candperm	$c6, $c6, $t1

		csetoffset	$c7, $c7, $t2
		cincbase	$c7, $c7, $t0
		candperm	$c7, $c7, $t1

		csetoffset	$c8, $c8, $t2
		cincbase	$c8, $c8, $t0
		candperm	$c8, $c8, $t1

		csetoffset	$c9, $c9, $t2
		cincbase	$c9, $c9, $t0
		candperm	$c9, $c9, $t1

		csetoffset	$c10, $c10, $t2
		cincbase	$c10, $c10, $t0
		candperm	$c10, $c10, $t1

		csetoffset	$c11, $c11, $t2
		cincbase	$c11, $c11, $t0
		candperm	$c11, $c11, $t1

		csetoffset	$c12, $c12, $t2
		cincbase	$c12, $c12, $t0
		candperm	$c12, $c12, $t1

		csetoffset	$c13, $c13, $t2
		cincbase	$c13, $c13, $t0
		candperm	$c13, $c13, $t1

		csetoffset	$c14, $c14, $t2
		cincbase	$c14, $c14, $t0
		candperm	$c14, $c14, $t1

		csetoffset	$c15, $c15, $t2
		cincbase	$c15, $c15, $t0
		candperm	$c15, $c15, $t1

		csetoffset	$c16, $c16, $t2
		cincbase	$c16, $c16, $t0
		candperm	$c16, $c16, $t1

		csetoffset	$c17, $c17, $t2
		cincbase	$c17, $c17, $t0
		candperm	$c17, $c17, $t1

		csetoffset	$c18, $c18, $t2
		cincbase	$c18, $c18, $t0
		candperm	$c18, $c18, $t1

		csetoffset	$c19, $c19, $t2
		cincbase	$c19, $c19, $t0
		candperm	$c19, $c19, $t1

		csetoffset	$c20, $c20, $t2
		cincbase	$c20, $c20, $t0
		candperm	$c20, $c20, $t1

		csetoffset	$c21, $c21, $t2
		cincbase	$c21, $c21, $t0
		candperm	$c21, $c21, $t1

		csetoffset	$c22, $c22, $t2
		cincbase	$c22, $c22, $t0
		candperm	$c22, $c22, $t1

		csetoffset	$c23, $c23, $t2
		cincbase	$c23, $c23, $t0
		candperm	$c23, $c23, $t1

		csetoffset	$c24, $c24, $t2
		cincbase	$c24, $c24, $t0
		candperm	$c24, $c24, $t1

		csetoffset	$c25, $c25, $t2
		cincbase	$c25, $c25, $t0
		candperm	$c25, $c25, $t1

		csetoffset	$c26, $c26, $t2
		cincbase	$c26, $c26, $t0
		candperm	$c26, $c26, $t1

		csetoffset	$c27, $c27, $t2
		cincbase	$c27, $c27, $t0
		candperm	$c27, $c27, $t1

		csetoffset	$c28, $c28, $t2
		cincbase	$c28, $c28, $t0
		candperm	$c28, $c28, $t1

		csetoffset	$c31, $c31, $t2
		cincbase	$c31, $c31, $t0
		candperm	$c31, $c31, $t1

		#
		# Now reverse the process.
		#
		dla	$t0, data
		clcr	$c0, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c1, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c2, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c3, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c4, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c5, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c6, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c7, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c8, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c9, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c10, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c11, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c12, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c13, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c14, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c15, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c16, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c17, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c18, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c19, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c20, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c21, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c22, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c23, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c24, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c25, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c26, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c27, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c28, $t0($c30)

		daddiu	$t0, $t0, 32
		clcr	$c31, $t0($c30)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end test

		#
		# 32-byte aligned storage for 30 adjacent capability
		# registers.
		#
		.data
		.align 5
data:		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c0
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c1
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c2
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c3
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c4
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c5
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c6
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c7
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c8
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c9
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c10
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c11
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c12
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c13
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c14
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c15
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c16
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c17
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c18
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c19
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c20
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c21
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c22
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c23
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c24
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c25
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c26
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c27
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c28
		.dword	0x0011223344556677, 0x8899aabbccddeeff
		.dword	0x0011223344556677, 0x8899aabbccddeeff	# c31
		.dword	0x0011223344556677, 0x8899aabbccddeeff
