#-
# Copyright (c) 2012 Robert N. M. Watson
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

.include "macros.s"
.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test that a very simple TLB handler using the automatically filled EntryHi will work as expected.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Initialise the in-memory page table to all zeros
		dli     $t0, 0x9800000001000000
		li      $t1, 64
1:
		sd      $0, 0($t0)
		sd      $0, 8($t0)
		dadd    $t0, 16
		bnez    $t1, 1b
		sub     $t1, $t1, 1
        
		jal	bev_clear
		nop

		#
		# Set up 'handler' as the RAM exception handler.
		# Note that we set up both common and xtlb handlers
		# because the first miss (with EXL=1) will go to
		# the common handler but subsequent misses (following eret)
		# will go to xtlb miss.
		#
		dla	$a0, bev0_handler
		jal	set_bev0_common_handler
		nop

		dla	$a0, bev0_handler
		jal	set_bev0_xtlb_handler
		nop
		
		#
		# Set $a7 to some physical page number.  We will increment this on each miss.
		#
		dli		$a7, 0xF

		#
		# Clear registers we'll use when testing results later.
		#
		dli	$a1, 5
		dli	$a2, 0
		dli	$a3, 0
		dli	$a4, 0
		dli	$a5, 0
		dli	$a6, 0
		
		#
		# Do a loop that will write 64 pages of virtual address space,
		# Then read those back and count the number of non-matches.
		#
		dli $a3, 0x40000
		dli $a4, 0
write_loop:
                cscr $c2, $a4($c0)
		daddi $a4, $a4, 64
		bnez $a3, write_loop
		daddi $a3, $a3, -64
		
		dli $a3, 0x40000
read_loop:
		daddi $a4, $a4, -64
                clcr $c2, $a4($c0)
		beq $a5, $a4, skip_add
		nop
		addi $a6, $a6, 1
skip_add:
		daddi $a3, -64
		bnez $a3, read_loop
		nop
	
return:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

#
# Exception handler.  This exception handler sets EPC to the original victim instruction,
# inserts a valid EntryLo for the first physical page of memory, and uses the automatically
# generated EntryHi value to write the TLB.  This is the fast-path, and the general scheme
# used in FreeBSD.
#
		.ent bev0_handler
bev0_handler:
		li	$a2, 1
tlb_stuff:
		tlb_stuff:
		dmfc0	$t0, $20
		dli 	$t3, 0x9800000001000000
		or		$t0, $t0, $t3
		ld		$t1, 0($t0)
		bnez	$t1, skip_new_entry
		nop
		daddi	$a7, 1						# Allocate a new physical page address
		dsll    $a2, $a7, 6                 # Put PFN in correct position for EntryLow
		or		$a2, 0x17					# Set valid and uncached bits
		sd		$a2, 0($t0)
		daddi	$a7, $a7, 1					# Allocate a new physical page address
		dsll    $a2, $a7, 6					# Put PFN in correct position for EntryLow
		or		$a2, 0x17					# Set valid and uncached bits
		sd		$a2, 8($t0)
skip_new_entry:
		ld		$a2, 0($t0)
		dmtc0   $a2, $2						# TLB EntryLow0 = a2 (Low half of TLB entry for even virtual $
		ld		$a2, 8($t0)
		dmtc0   $a2, $3						# TLB EntryLow1 = a2 (Upper half of TLB entry for even virtual $
		nop
		nop
		nop
		nop
		tlbwi							# Write Indexed to ensure a fill on every miss
#		mtc0 $at, $25           # On BERI this is magic instruction to dump TLB contents
		nop
		nop			# NOPs to avoid hazard with ERET
		nop			# XXXRW: How many are actually
		nop			# required here?
		nop
		eret
		.end bev0_handler
