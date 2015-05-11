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
# Unit test that stores double words to, and then loads double words from,
# memory.  Unlike shorter loads, there is no distinction between
# sign-extended and unsigned loads, but we do positive and negative
# variations to check all is well.
#
		.text
		.global start
start:
		dli	$a0, 0xfedcba9876543210
		dla	$t3, dword
		sd	$a0, 0($t3)
		ld	$a0, 0($t3)

		# Store and load double with sign extension
		dli	$a1, 1
		dla	$t3, positive
		sd	$a1, 0($t3)
		ld	$a1, 0($t3)

		dli	$a2, -1
		dla	$t3, negative
		sd	$a2, 0($t3)
		ld	$a2, 0($t3)

		# Store and load double words at non-zero offsets
		dla	$t0, val1
		dli	$a3, 2
		sd	$a3, 8($t0)
		ld	$a3, 8($t0)

		dla	$t1, val2
		dli	$a4, 1
		sd	$a4, -8($t1)
		ld	$a4, -8($t1)

        # Store and load to DRAM (uncached TODO: make appropriate cache etc.)
		dla $t0, 0x9000000000000000
		dli	$t1, 0xfedcba9876543210
		sd $t1, 0($t0)
		ld $s0, 0($t0)

		# Dump registers in the simulator
		mtc0	$v0, $26
		nop
		nop

		# Terminate the simulator
			mtc0 $v0, $23
end:
		b end
		nop

		.data
dword:		.dword	0x0000000000000000
positive:	.dword	0x0000000000000000
negative:	.dword	0x0000000000000000
val1:		.dword	0x0000000000000000
val2:		.dword	0x0000000000000000
