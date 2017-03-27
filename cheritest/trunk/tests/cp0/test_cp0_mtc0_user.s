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

# Test that MTC0 is not accessible from user mode when the coprocessor
# enable bit is not set.

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

                # To test user code we must set up a TLB entry.
	
 		dmtc0	$zero, $5               # Write 0 to page mask i.e. 4k pages
		dmtc0	$zero, $0		# TLB index 
		dmtc0	$zero, $10		# TLB entryHi

		dla     $a0, testcode		# Load address of testcode
		and     $a2, $a0, 0xffffffe000	# Get physical page (PFN) of testcode (40 bits less 13 low order bits)
		dsrl    $a3, $a2, 6		# Put PFN in correct position for EntryLow
		or      $a3, 0x13   		# Set valid and global bits, uncached
		dmtc0	$a3, $2			# TLB EntryLow0
		daddu 	$a4, $a3, 0x40		# Add one to PFN for EntryLow1
		dmtc0	$a4, $3			# TLB EntryLow1
		tlbwi				# Write Indexed TLB Entry

		dli	$a5, 0			# Initialise test flag
	
		and     $k0, $a0, 0xfff		# Get offset of testcode within page.
	        dmtc0   $k0, $14		# Put EPC
                dmfc0   $t2, $12                # Read status
                ori     $t2, 0x12               # Set user mode, exl
                and     $t2, 0xffffffffefffffff # Clear cu0 bit
                dmtc0   $t2, $12                # Write status
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
		add	$a5, 1			# Set the test flag
                mtc0   $zero, $12               # Attempt to set status register, should cause exception

exception_handler:
                dmfc0   $a6, $12                # Read status
                dmfc0   $a7, $13                # Read cause
		dla	$t0, the_end
		jr	$t0
		nop
