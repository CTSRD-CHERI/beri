#-
# Copyright (c) 2012, 2014 Robert M. Norton
# Cipyright (c) 2014 Michael Roe
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

#
# Test that trying to load a capability clears the tag if the
# 'disable capability load' bit is set in the TLB entry for the page.
# Note that this used to throw an exception but ISA was changed to allow
# copying data using clc/csc in no-cap regions.
#

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
		
		#
		# Install exception handler
		#

		dla	$a0, exception_handler
		jal 	bev0_handler_install
		nop

		#
                # To test user code we must set up a TLB entry.
		#
	
		#
		# Write 0 to page mask i.e. 4k pages
		#

 		dmtc0	$zero, $5               

		dmtc0	$zero, $0		# TLB index 
		dmtc0	$zero, $10		# TLB entryHi

		dla	$a2, cap
		andi	$a2, 0x1fff

		dla     $a1, testcode		# Load address of testcode
		and     $a0, $a1, 0xffffffe000	# Get physical page (PFN) of testcode (40 bits less 13 low order bits)
		dsrl    $a0, $a0, 6		# Put PFN in correct position for EntryLow
		#
		# Set global, valid and dirty bits, cached noncoherent
		#

		ori     $a0, $a0, 0x1f  	

		#
		# Set the 'disable capability load' bit
		#

		dli	$t0, 0x1
		dsll	$t0, $t0, 62
		or	$a0, $a0, $t0

		dmtc0	$a0, $2			# TLB EntryLow0
		daddu 	$a0, $a0, 0x40		# Add one to PFN for EntryLow1
		dmtc0	$a0, $3			# TLB EntryLow1
		tlbwi				# Write Indexed TLB Entry

		dli	$a5, 0			# Initialise test flags
		li      $a6, 1
		li      $a0, 0

	and     $k0, $a1, 0xfff		# Get offset of testcode within page.
	        dmtc0   $k0, $14		# Put EPC
                dmfc0   $t2, $12                # Read status
                ori     $t2, 0x12               # Set user mode, exl
                and     $t2, 0xffffffffefffffff # Clear cu0 bit
                dmtc0   $t2, $12                # Write status
                nop
		nop
                nop
	        eret                            # Jump to test code
                nop
                nop

the_end:	
		ld	$ra, 8($sp)
		ld	$fp, 0($sp)
		jr      $ra
		daddu	$sp, $sp, 16
.end    test
	
testcode:
		nop
		dli	$a5, 1			# Set the test flag

		#
		# Check that non-capability loads and stores work
		#

		ld 	$t0, 0($a2)

		dli	$a5, 2

		dli	$t0, 0xdead
		sd	$t0, 0($a2)

		dli	$a5, 3

		#
		# Store a valid capability to 'cap'
		#

		dli	$t0, 64
		cincbase $c1, $c0, $t0
		csetlen	$c1, $c1, $t0
		cscr	$c1, $a2($c0)

		dli	$a5, 4

		#
		# Clear $c2 so we can tell if the clcr suceeded
		#

		cmove	$c2, $c0

		#
		# This should not raise an exception but tag of c2
		# should be cleared
		#

		clcr	$c2, $a2($c0)

		cgetbase $a3, $c2
		cgetlen  $a4, $c2
		cgettag  $a6, $c2
	
		dli	$a5, 5

		# Return to kernel mode to finish test
		syscall	0
		nop

exception_handler:
		#
		# Check to see if the capability load succeeded
		# exception handler should not be called for clc,
		# but will be called for syscall to end test.
		# increment a0 to count number of exceptions
		add     $a0, 1
		li      $a5, 6
		dmfc0   $a7, $13                # Read cause
		dla	$t0, the_end
		jr	$t0
		nop

		.data
		.align 5
cap:
		.dword 0x0123
		.dword 0x4567
		.dword 0x89ab
		.dword 0xcdef
