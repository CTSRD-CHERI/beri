#-
# Copyright (c) 2012 Robert M. Norton
# Copyright (c) 2012 Jonathan Woodruff
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

# Simple TLB test which configures a TLB entry for the lowest virtual
# page in the xuseg and attempts a load via it.

.set mips64
.set noreorder
.set nobopt

.global test
test:   .ent    test
		li	$t0, 1			# Load counter so that we execute the following test twice,
						# to check for tlb probe speed.
		# Fill in a tlb entry and write it
probe_test_start:
 		dmtc0	$zero, $5       	# Write 0 to page mask i.e. 4k pages
 		li	$a0, 0x6
		dmtc0	$a0, $0			# TLB index 
		dmtc0	$zero, $10		# TLB HI address
	
		dla     $a0, testdata		# Load address of testdata in bram
		and     $a1, $a0, 0xffffffe000	# Get physical page (PFN) of testdata (40 bits less 13 low order bits)
		dsrl    $a2, $a1, 6		# Put PFN in correct position for EntryLow
		or      $a2, 0x13   		# Set valid and global bits, uncached
		dmtc0	$a2, $2			# TLB EntryLow0 = k0 (Low half of TLB entry for even virtual address (VPN))
		daddu 	$a3, $a2, 0x40		# Add one to PFN for EntryLow1
		dmtc0	$a3, $3			# TLB EntryLow1 = k0 (Low half of TLB entry for odd virtual address (VPN))
		tlbwi				# Write Indexed TLB Entry
		
		li	$a0, 0
		dmtc0	$a0, $0			# TLB Index
		li	$a0, 0x2000
		dmtc0	$a0, $10		# EntryHi
		tlbwi

		li	$a0, 1
		dmtc0	$a0, $0
		li	$a0, 0x4000
		dmtc0	$a0, $10
		tlbwi

		li	$a0, 2
		dmtc0	$a0, $0
		li	$a0, 0x6000
		dmtc0	$a0, $10
		tlbwi

		li	$a0, 3
		dmtc0	$a0, $0
		li	$a0, 0x8000
		dmtc0	$a0, $10
		tlbwi

		li	$a0, 4
		dmtc0	$a0, $0
		li	$a0, 0xa000
		dmtc0	$a0, $10
		tlbwi

		li	$a0, 5
		dmtc0	$a0, $0
		li	$a0, 0xc000
		dmtc0	$a0, $10
		tlbwi

		nop
		nop
		nop
		nop
		
		# Clear the tlb registers
		dmtc0	$zero, $5       	# 0 page mask
		dmtc0	$zero, $0       	# 0 index
		dmtc0	$zero, $10       	# 0 EntryHi
		dmtc0	$zero, $2       	# 0 EntryLo0
		dmtc0	$zero, $3       	# 0 EntryLo1

		nop
		nop
		
		# TLB probe.  EntryHi (virtual address of zero) should match.
		tlbp				
		nop
		nop
		nop
		nop
		mfc0	$a0, $0			# Read index, which should be six
		
		# Search TLB for another value
		li $a1, 0xffff
		dmtc0 $a1, $10
		
		nop
		nop
		
		tlbp
		nop
		nop
		nop
		nop
		mfc0	$a1, $0			# Read index, which should be negative
		
		bnez	$t0, probe_test_start
		daddi	$t0, -1

		jr      $ra
		nop
.end    test
	
	.data
	.align 5
testdata:
	.dword 0xfedcba9876543210
