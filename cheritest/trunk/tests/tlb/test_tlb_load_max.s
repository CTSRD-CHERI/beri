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

# Simple TLB test which configures a TLB entry for the highest virtual
# page in xkseg/kseg3 and attempts a load via it.

.set mips64
.set noreorder
.set nobopt

.global test
test:   .ent    test
		dli     $k0, 0x0
 		dmtc0	$k0, $5                 # Write 0 to page mask i.e. 4k pages
		dla     $a0, testdata		# Load address of testdata in bram

		dli 	$k0, 0			# TLB index
		dmtc0	$k0, $0			# TLB index = k0

		dli     $a1 , (0xfffffffffffff000) # TLB HI address (top page of kseg3)
		dmtc0	$a1, $10		# TLB HI address = a1

		and     $a2, $a0, 0xffffffe000	# Get physical page (PFN) of testdata (40 bits less 13 low order bits)
		dsrl    $a3, $a2, (12-6)	# Put PFN in correct position for EntryLow
		or      $a3, 0x13   		# Set valid and global bits, uncached
		dmtc0	$zero, $2		# TLB EntryLow0 = invalid
		dmtc0	$a3, $3			# TLB EntryLow1 = a3
		tlbwi				# Write Indexed TLB Entry

		and     $k0, $a0, 0xfff		# Get offset of testdata within page.
		daddu   $k0, $k0, $a1		# Construct an address in kernel user space.
		nop							# Delay for tlb update to take effect
		nop

		ld      $a5, 0($k0)			# Test read from virtual address.

		jr      $ra
		nop
.end    test
	
	.data
	.align 5
testdata:
	.dword 0xfedcba9876543210
