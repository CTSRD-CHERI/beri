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
# Test that we can store a capability to memory.  This test relies on the
# ability to read capability contents using non-capability operations --
# something that we believe will be allowed.
#
# XXXRW: The spec is possibly unclear on what order the dwords within a
# capability are written to memory.  I have assumed that the order of fields
# sequentially increasing dwords in memory is uperms, otype, base, length.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Tweak capability type field so that we can tell if type and
		# base are in the right order.
		#
		dli	$t2, 0x1
		csettype	$c2, $c2, $t2

		#
		# Set the permissions field so we can tell if it is stored
		# at the right palce in memory. The permissions are
		# Non_Ephemeral, Permit_Execute, Permit_Load, Permit_Store,
		# Permit_Store_Capability, Permit_Load_Capability,
		# Permit_Store_Ephemeral.
		#
		dli $t2, 0x7f
		candperm $c2, $c2, $t2

		#
		# Store at cap1 in memory.
		#
		# XXXRW: Fix to use indexed address syntax once available.
		#
		dla	$t0, cap1
		cscr	$c2, $t0($c0)

		#
		# Load back in as general-purpose registers to check values
		#
		# $a0 will be the perms field (0x7f) shifted left one bit,
		# plus the u bit (0x1) giving 0xff.
		ld	$a0, 0($t0)
		ld	$a1, 8($t0)
		ld	$a2, 16($t0)
		ld	$a3, 24($t0)

		# Check that underflow or overflow didn't occur
		dla	$t1, underflow
		ld	$a4, 0($t1)
		dla	$t1, overflow
		ld	$a5, 0($t1)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align	5		# Must 256-bit align capabilities
		.dword	0x0
		.dword	0x0
		.dword	0x0
underflow:	.dword	0x0123456789abcdef
cap1:		.dword	0x0123456789abcdef	# uperms/reserved
		.dword	0x0123456789abcdef	# otype/eaddr
		.dword	0x0123456789abcdef	# base
		.dword	0x0123456789abcdef	# length
overflow:	.dword	0x0123456789abcdef	# check for overflow
		.dword	0x0
		.dword	0x0
		.dword	0x0
