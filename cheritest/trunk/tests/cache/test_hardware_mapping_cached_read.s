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
# Exercise cached and uncached hardware direct maps:
#
# (1) Cached read from data address
# (2) Uncached write to data address
# (3) Cached read from data address
#
# Assuming that the cache is implemented (possibly not true for ISA simulators
# but generally true of hardware).  We attempt to check the CP0 config
# register 'DC' and 'SC' fields to determine if a cache should be present,
# which will help the test case determine if this test should fail (or not).
#
# xkphys addresses are used.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Retrieve CP0 config register so that test cases can
		# determine expected behaviour for our instruction sequence.
		#
		mfc0	$s1, $16

		#
		# Calculate a physical address and save it in $gp.  Various
		# virtual addreses, to be stored in $t0, will be generated
		# using it.
		#
		dla	$gp, dword
		dli	$t0, 0x00ffffffffffffff
		and	$gp, $gp, $t0

		#
		# Read via uncached address.
		#
		dli	$t0, 0x9000000000000000
		daddu	$t0, $gp, $t0
		ld	$a0, 0($t0)

		#
		# (1) Read via cached address; brings line into data cache.
		#
		dli	$t0, 0x9800000000000000
		daddu	$t0, $gp, $t0
		ld	$a1, 0($t0)

		#
		# (2) Write via uncached address; should not affect data cache
		# line.
		#
		dli	$t0, 0x9000000000000000
		daddu	$t0, $gp, $t0
		dli	$t1, 0xafafafafafafafaf
		sd	$t1, 0($t0)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

# A double word of data that we will load and store via various
# hardware-defined mappings.
dword:		.dword	0x0123456789abcdef
