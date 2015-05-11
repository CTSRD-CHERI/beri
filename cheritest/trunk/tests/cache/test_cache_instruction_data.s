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
# Exercise cache instructions
#
# Execute a series of cache instructions that are found in the kernel.  We
# currently don't check if they are correct, but merely check that they don't
# lock up the processor.  Since we have a write-through L1 cache, the only 
# function of the cache instructions is to synchronize L1 instruction and data
# caches.  We don't currently support cache instructions to the L2.
# 
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
		# Calculate a physical address of the count register and 
		# save it in $gp.  Various virtual addreses, to be stored 
		# in $t0, will be generated using it.
		#
		dli	$gp, 0x000000007f800000

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
		# (2) Read via cached address; brings line into data cache.
		#
		ld	$a2, 0($t0)
		
		#
		# (3) series of cache instructions to writeback cache lines from the L1 data.  
		# These should be nops for our L1 data cache which is write-through.
		#
		cache 0x19, 0($t0)
		cache 0x19, 8($t0) 
		cache 0x19, 10($t0) 
		cache 0x19, 18($t0) 
		
		#
		# (4) Read again via cached address.  Should still be in cache and unchanged.
		#
		ld	$a3, 0($t0)
		
		#
		# (4) series of cache instructions to writeback/invalidate data cache lines from data L1.  
		#
		cache 0x1, 0($t0)
		cache 0x1, 8($t0) 
		cache 0x1, 10($t0) 
		cache 0x1, 18($t0) 
		
		#
		# (4) Read again via cached address.  Should come from L2 cache and unchanged.
		#
		ld	$a4, 0($t0)
		
		#
		# (5) series of cache instructions to invalidate data cache lines.  
		#
		cache 0x11, 0($t0)
		cache 0x11, 8($t0) 
		cache 0x11, 10($t0) 
		cache 0x11, 18($t0) 
		
		#
		# (4) Read again via cached address.  Should come from L2 cache and unchanged.
		#
		ld	$a5, 0($t0)
		
		#
		# (7) series of cache instructions to writeback/invalidate data cache lines on a hit.
		# We conservitively just invalidate the index.
		# No need to writeback with a write-through cache.  
		#
		cache 0x15, 0($t0)
		cache 0x15, 8($t0) 
		cache 0x15, 10($t0) 
		cache 0x15, 18($t0) 
		
		ld	$a6, 0($t0)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

# A double word of data that we will load and store via various
# hardware-defined mappings.
dword:		.dword	0x0123456789abcdef
