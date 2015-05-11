#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2012 David T. Chisnall
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
# Generic init.s used by low-level CHERI regression tests.  Set up a stack
# using memory set aside by the linker, and allocate an initial 32-byte stack
# frame (the minimum in the MIPS ABI).  Install some default exception
# handlers so we can try and provide a register dump even if things go
# horribly wrong during the test.
#

		.text
		.global start
		.ent start
start:
                jal     get_corethread_id   # v0 = core ID * num threads + thread ID
                nop                         # (delay slot)

#continue:                 
		# Set up stack and stack frame
		dla	$fp, __sp
                sll     $t0, $v0, 10 # Allocate 1k stack per thread. XXX need to fix __heap_top__
                dsubu   $fp, $t0
		daddu 	$sp, $fp, -32
/*
		mfc0    $t0, $15, 1
		andi    $t0, $t0, 0xFFFF
		dli     $k0, 0x400  
		mul     $k0, $k0, $t0  
		daddu   $sp, $sp, $k0  
		daddu   $sp, $sp, -64       
		nop  
*/        
                dla     $a0, reset_barrier
                dla     $ra, all_threads    # cheeky tail call to skip exception handler install on non-zero threads
                bgtz    $v0, thread_barrier # enter barrier and spin if not thread 0
                nop

                # Thread 0 Code
        
		# Install default exception handlers
		dla	$a0, exception_count_handler
		jal 	bev0_handler_install
		nop

		dla	$a0, exception_count_handler
		jal	bev1_handler_install
		nop

all_threads:
	        # Switch to 64-bit mode (no effect on cheri, but required for gxemul)
	        mfc0    $at, $12
	        or      $at, $at, 0xe0
	        # Also enable timer interrupts
	        or      $at, $at, (1 << 15)
	        or      $at, $at, 1
                dli	$t1, 1 << 30
                or      $at, $at, $t1 	# Enable CP2
	        # Clear pending timer interrupts before we enable them
	        mtc0    $zero, $11
	        mtc0    $at, $12

		#
		# Explicitly initialise most registers in order to make the effects
		# of a test on the register file more clear.  Otherwise,
		# values leaked from init.s and its dependencies may hang
		# around.
		#
		dli	$at, 0x0101010101010101 # r1 
		dli	$v0, 0x0202020202020202 # r2 
		dli	$v1, 0x0303030303030303 # r3 
		dli	$a0, 0x0404040404040404 # r4 
		dli	$a1, 0x0505050505050505 # r5 
		dli	$a2, 0x0606060606060606 # r6 
		dli	$a3, 0x0707070707070707 # r7 
		dli	$a4, 0x0808080808080808 # r8 
		dli	$a5, 0x0909090909090909 # r9 
		dli	$a6, 0x0a0a0a0a0a0a0a0a # r10
		dli	$a7, 0x0b0b0b0b0b0b0b0b # r11
		dli	$t0, 0x0c0c0c0c0c0c0c0c # r12
		dli	$t1, 0x0d0d0d0d0d0d0d0d # r13
		dli	$t2, 0x0e0e0e0e0e0e0e0e # r14
		dli	$t3, 0x0f0f0f0f0f0f0f0f # r15
		dli	$s0, 0x1010101010101010 # r16
		dli	$s1, 0x1111111111111111 # r17
		dli	$s2, 0x1212121212121212 # r18
		dli	$s3, 0x1313131313131313 # r19
		dli	$s4, 0x1414141414141414 # r20
		dli	$s5, 0x1515151515151515 # r21
		dli	$s6, 0x1616161616161616 # r22
		dli	$s7, 0x1717171717171717 # r23
		dli	$t8, 0x1818181818181818 # r24
		dli	$t9, 0x1919191919191919 # r25
		dli	$k0, 0x1a1a1a1a1a1a1a1a # r26
		dli	$k1, 0x1b1b1b1b1b1b1b1b # r27
		dli	$gp, 0x1c1c1c1c1c1c1c1c # r28
		# Not cleared: $sp, $fp, $ra
		mthi	$at
		mtlo	$at

		# Invoke test function test() provided by individual tests.
		dla   $25, test
		jalr $25
		nop			# branch-delay slot

		#
		# Check to see if coprocessor 2 (capability unit) is present,
		# and dump out its registers if it is.
		#

		mfc0 $k0, $16, 1	# config1 register
		andi $k0, $k0, 0x40	# CP2 available bit
		beqz $k0, skip_cp2_dump 
		nop
	
		#
		# Dump capability registers in the simulator
		#

		mtc2 $k0, $0, 6
		nop
		nop

skip_cp2_dump:
		
		#
		# On multithreaded/multicore, only core/thread 0 halts 
		# the simulation.
		#
		# We do this check (which alters $k1) before we dump registers,
		# because we want the final register values to be the same
		# in both gxemul and BERI/CHERI.
		#
		# gxemul does not support the BERI-specific CoreId and
		# ThreadId registers, so we also check PrId.
		#

		mfc0 $k0, $15		# PrId
		andi $k0, $k0, 0xff00
		xori $k0, $k0, 0x8900
		beqz $k0, dump_core0
		nop

		mfc0 $k0, $15, 6	# CoreId
		andi $k0, $k0, 0xffff
		bnez $k0, dump_not_core0
		nop

		mfc0 $k0, $15, 7	# ThreadId
		andi $k0, $k0, 0xffff
		bnez $k0, dump_not_thread0
		nop

dump_core0:
		#
		# Load the exception count into k0 so that it is visible 
		# in register dump
		#

		ld      $k0, exception_count

		#
		# Dump registers on the simulator (gxemul dumps regs on exit)
		#
		# We want the final register values to be the same in both
		# gxemul and BERI -- particularly for fuzz tests -- so
		# all modifications to registers should happen before this
		# point.
		#

		mtc0 $at, $26
		nop
		nop

		#
		# Terminate the simulator
		#

		mtc0 $at, $23
end:
		b end
		nop


dump_not_thread0:
dump_not_core0:

		ld $k0, exception_count

		#
		# Dump registers even though core/thread not zero, so we
		# can see all cores in the trace.
		#

		mtc0 $at, $26
		nop
		nop

		#
		# On a multicore or multithreaded CPU, loop until core0
		# finishes its work and kills the simulation. Other cores
		# might reach this point before core0 finishes, and we want
		# core0 to get to the point where it dumps its registers to
		# the trace.
		#

end_not_core0:
		b end_not_core0
		nop
		.end start

		.ent exception_count_handler
exception_count_handler:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
	        sd      $k0,  8($sp)
		daddu	$fp, $sp, 32
	

		# Increment exception counter
	        dla     $ra, exception_count
		ld      $k0, ($ra)
	        addi    $k0, $k0, 1
	        sd      $k0, ($ra)

		# If this is a timer interrupt, then return to the current instruction
		dmfc0	$k0, $13
		andi	$k0, $k0, 0x8000
		beq	$zero, $k0, increment_pc 
		nop
		# Clear the timer interrupt
		mtc0	$zero, $11
		b skip_increment
		nop
increment_pc:
		# Skip the instruction which caused exception and return
		dmfc0	$k0, $14	# EPC
		daddiu	$k0, $k0, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
skip_increment:

	        ld	$ra, 24($sp)
		ld	$fp, 16($sp)
	        ld      $k0,  8($sp)
		daddu	$sp, $sp, 32
		nop			# NOPs to avoid hazard with ERET
		nop			# XXXRW: How many are actually
		nop			# required here?
		nop
		eret
		.end exception_count_handler


# install_tlb_entry(tlb_entry, physical_base, virtual_base, page_mask)
.ent install_tlb_entry
.global install_tlb_entry
install_tlb_entry:
		dmtc0        $a3, $5                 # Write page mask i.e. 0 for 4k pages, 0x3FF for 4M pages
		dmtc0        $a0, $0                 # TLB index
		dmtc0        $a2, $10                # TLB HI address
		dli          $at, 0xfffffff000       # Get physical page (PFN) of the physical address (40 bits less 12 low order bits)
		and          $t1, $a1, $at
		dsrl         $t2, $t1, 6             # Put PFN in correct position for EntryLow
		ori          $t2, $t2, 0x13          # Set valid and global bits, uncached
		dmtc0        $t2, $2                 # TLB EntryLow0
		daddu        $t3, $t2, 0x40          # Add one to PFN for EntryLow1
		dmtc0        $t3, $3                 # TLB EntryLow1
		tlbwi                                # Write Indexed TLB Entry
		nop
		nop
		jr           $ra
	nop
.end install_tlb_entry

#
# By default threads other than thread 0 will enter a barrier on reset.
# This function causes thread 0 to enter the barrier, thereby releasing the
# other threads from their prison.
# Args: None
# Returns: Nothing
.global other_threads_go
.ent other_threads_go        
other_threads_go:
                dla          $a0, reset_barrier      # Load barrier data
                j            thread_barrier          # Tail call to the barrier
                nop                                  # (delay slot)
.end other_threads_go

	        .data
		.align 3
.globl exception_count
exception_count:
		.dword	0x0
reset_barrier:
                mkBarrier
