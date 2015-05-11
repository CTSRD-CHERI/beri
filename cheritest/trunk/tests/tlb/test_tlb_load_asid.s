#-
# Copyright (c) 2012 Robert M. Norton
# All rights reserved.
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

# Simple TLB test which configures a TLB entry for lowest virtual
# page in xuseg with two different ASIDs and attempts to load via
# both of them.

.set mips64
.set noreorder
.set nobopt
        
.global test
test:   .ent    test
		dli     $k0, 0x0
 		dmtc0	$k0, $5                 # Write 0 to page mask i.e. 4k pages
		dla     $a0, testdata1		# Load address of testdata in bram
		dla     $a1, testdata2		# Load address of testdata in bram

		# Set up TLB entry for testdata1
		dmtc0	$zero, $0		        # TLB index = 0
		li      $t0, 1			      # ASID=1
		dmtc0	$t0, $10		        # TLB HI address (BRAM) Virtual address (first page, ASID=1) 63:62 == 00 means kernel user address space
		and     $a2, $a0, 0xffffffe000	# Get physical page (PFN) of testdata (40 bits less 13 low order bits)
		dsrl    $a2, $a2, 6		   # Put PFN in correct position for EntryLow
		or      $a2, 0x12   		   # Set valid and uncached bits
		dmtc0	$a2, $2			        # TLB EntryLow0 = a2 (Low half of TLB entry for even virtual address (VPN))
		dmtc0	$zero, $3		        # TLB EntryLow1 = 0 (invalid)
		tlbwi				              # Write Indexed TLB Entry
	
		# Set up TLB entry for testdata2
		li      $t0, 1
		dmtc0	$t0, $0			# TLB index = 1
		li      $t0, 2 			# ASID=2
		dmtc0	$t0, $10		# TLB HI address (BRAM) Virtual address (first page, ASID=2) 63:62 == 00 means kernel user address space
		and     $a3, $a1, 0xffffffe000	# Get physical page (PFN) of testdata (40 bits less 13 low order bits)
		dsrl    $a3, $a3, 6		# Put PFN in correct position for EntryLow
		or      $a3, 0x12   		# Set valid and uncached bits
		dmtc0	$a3, $2			# TLB EntryLow0 = a3 (Low half of TLB entry for even virtual address (VPN))
		dmtc0	$zero, $3		# TLB EntryLow1 = 0 (invalid)
		tlbwi				# Write Indexed TLB Entry	

		li      $t0, 2
		dmtc0   $t0, $10                # ASID=2
    nop
    nop
    nop
    nop
    nop
    nop
		ld      $a4, 0($0)		# Test read from virtual address.

		li      $t0, 1
		dmtc0   $t0, $10                # ASID=1
    nop
    nop
    nop
    nop
    nop
    nop
		ld      $a5, 0($0)		# Test read from virtual address.
	
		jr      $ra
		nop
.end    test
	
	.data
	.align 13 # Align to the start of an even page for easy access
testdata1:
	.dword 0xfedcba9876543210
	.align 13 # Put testdata2 at start of next even page.
testdata2:
	.dword 0x0123456789abcdef
