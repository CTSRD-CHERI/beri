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

# Simple TLB test which configures a read only TLB entry for the
# lowest virtual page in the xuseg segment and attempts a store via it.

.set mips64
.set noreorder
.set nobopt

.global test
test:   .ent    test
		daddu	$sp, $sp, -16
		sd	$ra, 8($sp)
		sd	$fp, 0($sp)
		daddu	$fp, $sp, 16

		jal     bev_clear
		nop
		
		# Install exception handler
		dla	$a0, exception_handler
		jal 	bev0_handler_install
		nop		

	
 		dmtc0	$zero, $5               # Write 0 to page mask i.e. 4k pages
		dmtc0	$zero, $0		# TLB index 
		dmtc0	$zero, $10		# TLB HI address
	
		dla     $a0, testdata		# Load address of testdata in bram
		and     $a1, $a0, 0xffffffe000	# Get physical page (PFN) of testdata (40 bits less 13 low order bits)
		dsrl    $a2, $a1, 6		# Put PFN in correct position for EntryLow
		or      $a2, 0x13   		# Set valid and global bits, uncached but NOT dirty bit
		dmtc0	$a2, $2			# TLB EntryLow0 = k0 (Low half of TLB entry for even virtual address (VPN))
		daddu 	$a3, $a2, 0x40		# Add one to PFN for EntryLow1
		dmtc0	$a3, $3			# TLB EntryLow1 = k0 (Low half of TLB entry for odd virtual address (VPN))
		tlbwi				# Write Indexed TLB Entry

		dli     $t0, 0x0123456789abcdef # Test data to store
		and     $a4, $a0, 0xfff		# Get offset of testdata within page.

		dli     $a7, -1			# Initalise a7 to non-zero value
		dli     $s0, -1			# Initalise s0 to non-zero value
	
illegal_store:  sd      $t0, 0($a4)		# Store to write protected virtual address

		ld      $a5, 0($a4)             # Load what we just stored.

		ld	$ra, 8($sp)
		ld	$fp, 0($sp)
		jr      $ra
		daddu	$sp, $sp, 16
.end    test

exception_handler:
		dmfc0   $a6, $13		# Cause
		dmfc0   $a7, $14		# EPC
		daddu   $t0, $a7, 4		# Increment EPC
		dmtc0   $t0, $14		# and store it back
		dla     $t0, illegal_store
		xor	$a7, $t0		# Test that EPC has the correct value
		dmfc0   $s0, $8			# BadVAddr
		xor     $s0, $a4		# Test that BadVAddr has correct value
		eret
		nop
	
	.data
	.align 5
testdata:
	.dword 0xfedcba9876543210
