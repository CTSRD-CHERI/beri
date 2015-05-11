#-
# Copyright (c) 2011-2013 Robert N. M. Watson
# Copyright (c) 2013 Robert M. Norton
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

        NUM_STES=8
        
#
# "simboot" micro-loader, which does minimal CPU initialisation and then jumps
# to a plausible kernel start address.
#

		.text
		.global start
		.ent start
start:
		# Set up stack and stack frame
		dla	$fp, __sp
		dla	$sp, __sp
		daddu 	$sp, $sp, -32

		# Switch to 64-bit mode -- no effect on CHERI, but required
		# for gxemul.
		mfc0	$at, $12
		or	$at, $at, 0xe0
		mtc0	$at, $12

                dmfc0   $t0, $15            # load processor ID register, d prevents sign extension
                srl     $t0, 24             # shift down thread id

		# SPIN OTHER CORE >>
		#core_other:
		#mfc0   $t0, $15, 6
		#srl    $t1, $t0, 16
		#daddu  $t1, $t1, 1
		#andi   $t0, $t0, 0xFFFF
		#bnez   $t0, core_other
		#nop
		# SPIN OTHER CORE <<

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
        
		# Explicitly clear most registers.  $sp, $fp, and $ra aren't
		# cleared as they are part of our initialised stack.
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
                ld   $t0, 0($t1)         # get entry_addr
        .rept 100
                nop                      # nops to avoid ll/sc live lock caused by repeatedly replacing cacheline
        .endr
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
                ld   $t0, 0($t1)         # get entry_addr
        .rept 100
                nop                      # nops to avoid ll/sc live lock caused by repeatedly replacing cacheline
        .endr
                beq  $t0, $t2, 1b        # loop while entry_addr == 1
                ld   $a0, 8($t1)         # load argument (branch delay!)
                jr   $t0                 # jump to entry_addr
                nop
        
		.end start

		.data

		# Provide empty argument and environmental variable arrays
arg:		.dword	0x0000000000000000
env:		.dword	0x0000000000000000
