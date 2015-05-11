#-
# Copyright (c) 2014 Michael Roe
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
# Test lld/scd with a load instruction that aliases to the same cache line
# as the load linked address. According to the MIPS ISA, this is
# UNPREDICTABLE because there is a load between the lld and the scd.
# On BERI, it should work even if the load displaces the cache line that
# was load linked.
#
# This test assumes that the cache is direct mapped, and address x+64K is
# mapped to the same cache line as x.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dla	$a0, mutex
		lld	$a1, 0($a0)
		dli	$a2, 1

		#
		# Load from mutex+64K, displacing mutex from the cache
		#

		dli	$t0, 65536
		daddu	$t0, $t0, $a0
		ld	$t1, 0($t0)

		#
		# The store conditional should still succeed.
		#

		scd	$a2, 0($a0)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data

		.align 3
mutex:		.dword 0

