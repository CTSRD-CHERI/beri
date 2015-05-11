#-
# Copyright (c) 2011-2012 Robert N. M. Watson
# Copyright (c) 2012-2013 Jonathan Woodruff
# Copyright (c) 2012 Steven J. Murdoch
# Copyright (c) 2013 Robert M. Norton
# Copyright (c) 2013 Bjoern A. Zeeb
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
# "miniboot" micro-loader, which does minimal CPU initialisation and then
# jumps to a plausible kernel start address.
#

NUM_STES=8
        
		.text
		.global start
		.ent start
start:
init_regs:
		mtc0 $0, $0		# [0] Index Register.
		li $k0, 0x0000001e
		mtc0 $k0, $2		# [2] EntryLo0
		mtc0 $k0, $3		# [3] EntryLo1
		mtc0 $0, $5		# [5] Page Mask
		mtc0 $0, $6		# [6] Wired
		mtc0 $0, $8		# [8] BadVAddr
		mtc0 $0, $10		# [10] EntryHi
		mtc0 $0, $11		# [11] Compare
		li $k0, 0x004000e0	# [12] SR (Status)
		mtc0 $k0, $12
		li $k0, 0x40008000	# [13] Set CAUSE to initial value.
		mtc0 $k0, $13
		mtc0 $0, $14		# [14] EPC
		mtc0 $0, $18		# [18] WatchLo
		mtc0 $0, $19		# [19] WatchHi
		mtc0 $0, $30		# [30] ErrorEPC
# Sweep a large enough memory region to invalidate the entire L1/L2 cache
# (16/64kB).
clear_cache:
		lui $k0, 0x8000	# We must use a kseg0 address (0xffffffff8000000) for the index as per MIPS spec.
		li  $k1, 0x10000-8	# 64kB for L2, so L1 gets some extra cleaning
		add $k1, $k0, $k1	# Compute end address for loop
cache_loop:
		cache 0x0, 0($k0)	# Cache instruction 0x10 == invalidate L1 Instruction
		cache 0x1, 0($k0)	# Cache instruction 0x11 == invalidate L1 Data
		cache 0x3, 0($k0)	# Cache instruction 0x13 == invalidate L2
		bne $k0, $k1, cache_loop
		addi $k0, $k0, 8	# 32 byte lines but we are conservative and do 8

		# Set up stack and stack frame
		dla	$fp, __sp
		dla	$sp, __sp
		daddu 	$sp, $sp, -32

		# Switch to 64-bit mode -- no effect on CHERI, but required
		# for gxemul.
		mfc0	$at, $12
		or	$at, $at, 0xe0
		mtc0	$at, $12

                dmfc0 $t0, $15 # load processor ID register, d prevents sign extension
                srl $t0, 24 # shift down thread id

		# Get Thread ID to determine whether the processor is multi threaded
		# or multicore. We check the total number of threads, if it is zero
		# we check the total number of cores.
                dmfc0   $t0, $15, 7 
                srl     $t8, $t0, 16
                daddu   $t8, $t8, 1 
                andi    $t0, $t0, 0xFFFF
                beqz    $t8, multi_core
                nop

multi_threaded: 
                bnez    $t0, not_thread_zero
                nop

multi_core:
                mfc0    $t0, $15, 6
                srl     $t1, $t0, 16
                daddu   $t1, $t1, 1
                andi    $t0, $t0, 0xFFFF
                bnez    $t0, not_core_zero
                nop

                # Initialise the spin table below the kernel entry address at  0x100000.
                # The layout of an entry is:
                # 64-byte entry_addr
		# 64-byte argument
		# 64-byte rsvd1/pir (not used)
		# 64 byte rsvd2 (to pad to 256 bits)
		
                dla $t0, __spin_table_top__
                li  $t1, 1
                li  $t2, NUM_STES-1
init_spin_table:
                dsub $t0, 32
                sd   $t1, 0($t0)
                sd   $0,  8($t0)
                sd   $0, 16($t0)
                sd   $0, 24($t0)        
                bne  $t2, $0, init_spin_table
                sub  $t2, 1
        
#ifndef ALWAYS_WAIT
check_pause_switch_0:
		# Check the dipswitch to determine whether we should pause waiting
		# for cherictl or whether we should begin immediatly
		dla	$t0, __dip_switches__
		lbu	$t0, 0($t0)
		andi	$t0, 0x1
		beq	$t0, $0, check_relocate_switch_1
		nop
#else
		# Initialize t0 to something meaningful.
		dli	$t0, 0x1
#endif
		# Reset the software-controlled button
		dli     $t1, 0x1
triggerloop:
		# Spin until the debug unit sets $t1 to equal 0
		# to trigger us to relocate the kernel and go
		and	$t0, $t1
		andi	$t0, 0x1
		bne	$t0, $0, triggerloop
		nop

check_relocate_switch_1:
		# Relocate the kernel from flash if switch 0 is on
		dla	$t0, __dip_switches__
		lbu	$t0, 0($t0)
		andi	$t0, 0x2
		bne	$t0, $0, cleanup
		nop

		# Relocate from flash memory into DRAM which will hopefully
		# be a kernel or boot loader.
		dla	$t0, __flash_kernel_location_uncached__

		# Set flash to read mode.
		dli	$t1, 0xff
		sb	$t1, 0($t0)
		dla	$t0, __flash_kernel_location_cached__

		dla	$t1, __os_elf_header__
		dla	$s0, __flash_kernel_top__
		daddi	$t0, $t0, -32
		daddi	$t1, $t1, -32

		# Run copying out of cached memory for performance reasons.
		dla	$s1, mem_copy_loop
		dli	$s2, 0x9800000000000000
		or	$s1, $s1, $s2
		jr	$s1
		nop

		#
		# Copy memory, one 32-byte cache line at a time.
		#
mem_copy_loop:
		daddiu	$t0, $t0, 32
		daddiu	$t1, $t1, 32
		ld	$s4, 0($t0)
		ld	$s5, 8($t0)
		ld	$s6, 16($t0)
		ld	$s7, 24($t0)
		sd	$s4, 0($t1)
		sd	$s5, 8($t1)
		sd	$s6, 16($t1)
		bne	$t0, $s0, mem_copy_loop
		sd	$s7, 24($t1)

		# Explicitly clear most registers.  $sp, $fp, and $ra aren't
		# cleared as they are part of our initialised stack.
cleanup:
    dla $sp, __sp
		dli	$at, 0
		dli	$v0, 0
		dli	$v1, 0
		dli	$a4, 0
		dli	$a5, 0
		dli	$a6, 0
		dli	$a7, 0
		dli	$t0, 0
		dli	$t1, 0
		dli	$t2, 0
		dli	$t3, 0
		dli	$s0, 0
		dli	$s1, 0
		dli	$s2, 0
		dli	$s3, 0
		dli	$s4, 0
		dli	$s5, 0
		dli	$s6, 0
		dli	$s7, 0
		dli	$t8, 0
		dli	$t9, 0
		dli	$k0, 0
		dli	$k1, 0
		dli	$gp, 0
		mthi	$at
		mtlo	$at

		# Certain registers are arguments to the kernel.
		dli	$a0, 0				# zero arguments
		dla	$a1, arg
		dla	$a2, env
		dla	$a3, __os_memory_size__		# memsize

		# Assume that there is 64-bit ELF kernel loaded at a virtual
		# address known to the linker.  Grub through its ELF header to
		# find the actual kernel entry address to jump to (e_entry).
		dla	$at, __os_elf_header__
		ld	$at, 0x18($at)
		jr	$at
		nop

not_core_zero:
                # switch to cached execution -- if we don't we will
                # slow down the other cores with our uncached accesses
                dla  $t1, not_core_zero_cached
                dli  $t2, 0x9800000000000000
                or   $t1,$t2
                jr   $t1
                nop
                
not_core_zero_cached:
                #  $t0 has core ID -- compute address of spin table entry
                sll  $t0, 5              # STEs are 32-byte aligned
                dla  $t1, __spin_table_top__
                dsub $t1, $t0            # t1 == &ste
                li   $t2, 1
1:
.rept 100
                # nops prevent us from pumelling the cachline containing ste,
        	# thereby potentially disrupting ll/sc on other cores
                nop                      
.endr
                ld   $t0, 0($t1)         # get entry_addr        
                beq  $t0, $t2, 1b        # loop while entry_addr == 1
                ld   $a0, 8($t1)         # load argument (branch delay!)
                jr   $t0                 # jump to entry_addr
                nop


not_thread_zero:
                # switch to cached execution -- if we don't we will
                # slow down the other threads with our uncached accesses
                dla  $t1, not_thread_zero_cached
                dli  $t2, 0x9800000000000000
                or   $t1,$t2
                jr   $t1
                nop
                
not_thread_zero_cached:
                #  $t0 has thread ID -- compute address of spin table entry
                sll  $t0, 5              # STEs are 32-byte aligned
                dla  $t1, __spin_table_top__
                dsub $t1, $t0            # t1 == &ste
                li   $t2, 1
1:
.rept 100
                # nops prevent us from pumelling the cachline containing ste,
        	# thereby potentially disrupting ll/sc on other threads
                nop                      
.endr
                ld   $t0, 0($t1)         # get entry_addr        
                beq  $t0, $t2, 1b        # loop while entry_addr == 1
                ld   $a0, 8($t1)         # load argument (branch delay!)
                jr   $t0                 # jump to entry_addr
                nop
         
	        .end start

		.data

		# Provide empty argument and environmental variable arrays
arg:		.dword	0x0000000000000000
env:		.dword	0x0000000000000000
