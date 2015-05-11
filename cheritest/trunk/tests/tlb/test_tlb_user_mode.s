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

# Simple TLB test which configures a TLB entry for the lowest virtual
# page in the user address space and attempts a to execute code in it,
# returning via a system call.

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
	
		#
		# Check to see if we already have a TLB entry for page 0
		#

		dli	$t0, 0x0
		dmtc0	$t0, $10		# TLB EntryHi
		tlbp
		mfc0	$a0, $0			# TLB Index
		srl	$t0, $a0, 31
		bnez	$t0, L1
		nop				# branch delay slot`

		#
		# Clear the existing TLB entry by setting its ASID to
		# a value that won't match (5)
		#

		tlbr
		dli	$t0, 0x5
		dmtc0	$t0, $10
		tlbwi

L1:
		dmtc0   $zero, $10
		tlbp
		dmfc0   $a0, $0  

 		dmtc0	$zero, $5               # Write 0 to page mask i.e. 4k pages
		dmtc0	$zero, $0		# TLB index 
		dmtc0	$zero, $10		# TLB entryHi

		dla     $a0, testcode		# Load address of testdata in bram
		and     $a2, $a0, 0xffffffe000	# Get physical page (PFN) of testcode (40 bits less 13 low order bits)
		dsrl    $a3, $a2, 6		# Put PFN in correct position for EntryLow
		or      $a3, 0x1a   		# Set valid and global bits, cached
		dmtc0	$a3, $2			# TLB EntryLow0
		daddu 	$a4, $a3, 0x40		# Add one to PFN for EntryLow1
		dmtc0	$a4, $3			# TLB EntryLow1
		tlbwi				# Write Indexed TLB Entry

		dli	$a5, 4			# Initialise test flag
	
		and     $k0, $a0, 0xfff		# Get offset of testdata within page.
		jr 	$k0			# Jump to virtual address
		nop

after_syscall:	
		ld	$ra, 8($sp)
		ld	$fp, 0($sp)
		jr      $ra
		daddu	$sp, $sp, 16
.end    test
	
testcode:
        .rept 10
		nop
        .endr
                bgtz    $a5, testcode
		sub	$a5, 1			# Set the test flag
		syscall
		nop

exception_handler:
		dla	$t0, after_syscall
		jr	$t0
		nop
