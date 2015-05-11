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
# Similar to test_hardware_mappings.s, only the data we want to read via
# various mappings is written as part of the test, rather than statically
# initialised.  The same hardware-defined mapped regions are used:
#
## 0xffff ffff a000 0000 - ckseg1 (unmapped, uncached)
## 0xffff ffff 8000 0000 - ckseg0 (unmapped, cached)
##
## 0x9000 0000 0000 0000 - xkphys (unmapped, uncached)
## 0x9800 0000 0000 0000 - xkphys (unmapped, cached, noncoherent)
## 0xa000 0000 0000 0000 - xkphys (unmapped, cached, coherent exclusive)
## 0xa800 0000 0000 0000 - xkphys (unmapped, cached, coherent exclusive on
##                         write)
## 0xb000 0000 0000 0000 - xkphys (unmapped, cached, coherent update on write)
#
# This test is interested only in whether desired data appears at each
# mapping, not its specific caching properties.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Calculate the physical address of the memory we will be
		# working with, which can then be offset by various segment
		# bases.  Store this in $gp for reuse.
		#
		dla	$gp, dword
		dli	$t0, 0x00ffffffffffffff		# Uncached
		and	$gp, $gp, $t0			# Physical

		#
		# Write out a new value via the unmapped, uncached region, in
		# the hopes that later reads will see it.
		#
		dli	$t0, 0x9000000000000000
		daddu	$t0, $gp, $t0
		dli	$t1, 0x0123456789abcdef
		sd	$t1, 0($t0)

		#
		# Test various mappings to see if we get back the right data.
		# Start with 64-bit mappings from R4000.
		#
		dli	$t0, 0x9000000000000000		# xkphys uncached
		daddu	$t0, $gp, $t0
		ld	$a2, 0($t0)

		dli	$t0, 0x9800000000000000		# xkphys cached,
		daddu	$t0, $gp, $t0			# noncoherent
		ld	$a3, 0($t0)

		dli	$t0, 0xa000000000000000		# xkphys cached,
		daddu	$t0, $gp, $t0			# exclusive
		ld	$a4, 0($t0)

		dli	$t0, 0xa800000000000000		# xkphys cached,
		daddu	$t0, $gp, $t0			# exclusive on write
		ld	$a5, 0($t0)

		dli	$t0, 0xb000000000000000		# xkphys cached,
		daddu	$t0, $gp, $t0			# update on write
		ld	$a6, 0($t0)

		#
		# Store constant in lower 512MB to prepare for 32 bit mapping
		# tests.
		#
		# XXXRW: This test incorrectly assumes that there is memory to
		# be found at ~0x4000 before the unit test start address.
		# To make this test more reliable, we should ideally use a
		# start address in the base 512M of physical memory.  Possible
		# failure modes here include overwriting arbitrary portions of
		# test memory.
		#
		lui	$t0, 0x4000
		dsubu	$gp, $gp, $t0

		dli	$t0, 0x9000000000000000
		daddu	$t0, $gp, $t0
		sd	$a2, 0($t0)

		#
		# Also test historic MIPS ckseg0 and ckseg1, also present in
		# R4000.
		#
		dli	$t0, 0xffffffffa0000000		# ckseg1, uncached
		daddu	$t0, $gp, $t0
		ld	$a0, 0($t0)

		dli	$t0, 0xffffffff80000000		# ckseg0, cached
		daddu	$t0, $gp, $t0
		ld	$a1, 0($t0)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

# A double word of data that we will load via various hardware-defined
# mappings
dword:		.dword 0x0000000000000000
