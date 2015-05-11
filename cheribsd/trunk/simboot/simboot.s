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

switch_cached:
		dla	$t0, get_corethread_id
		dli	$t1, 0x9800000000000000
		or	$t0, $t0, $t1
		jr	$t0
		nop

#
# Get an ID in range [0, num cores * num threads)  which combines the current
# core and threadID i.e. a unique identifier for this hw thread in the whole
# system. ID is current core ID * num threads + current thread ID
#
get_corethread_id:
		mfc0  $t0, $15          # prid register
		and   $t0, $t0, 0xff00  # Mask processor ID
		xor   $t1, $t1, 0x8900  # ID for gxemul
		beq   $t0, $t1, core_zero # done if on gxemul
		li    $v0, 0            # one core on gxemul (delay)
		dmfc0 $t0, $15, 6       # t0 = core ID / max core
		and   $v0, $t0, 0xffff  # v0 = current core ID
		dmfc0 $t0, $15, 7       # t0 = thread ID / num threads
		srl   $v1, $t0, 16      # v1 = max thread ID
		add   $v1, 1            # v1 = num threads
		and   $t0, $t0, 0xffff  # t0 = thread ID
		mul   $v0, $v0, $v1     # v0 = current core * num threads
		add   $v0, $t0          # v0 = current core * num threads + thread ID
		bnez  $v0, not_core_zero
		nop

core_zero:
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
		# Initialise the spin table for this core/thread below the kernel entry address at 0x100000.
		# We assume that by the time core 0 gets around to writing an entry_addr for the other cores,
		# they will each have initialised their spin table entries. This is likely as core 0 has a
		# a lot of work to do (trigger loop, relocate kernel, boot kernel...)
		# The layout of an entry is:
		# 64-byte entry_addr (initialised to 1 meaining invalid/keep spinning)
		# 64-byte argument
		# 64-byte rsvd1/pir (not used)
		# 64 byte rsvd2 (to pad to 256 bits)

		# Compute offset for spin table entry (note that core 0 does not have an entry)
		sll  $t0, $v0, 5

		dla  $t1, __spin_table_top__
		dsub $t0, $t1, $t0 # t0 = address of spin table entry for this core/thread

		li   $t1, 1
		sd   $t1, 0($t0)
		sd   $0,  8($t0)
		sd   $0, 16($t0)
		sd   $0, 24($t0)

		# On CPUs with a relaxed memory model, we want the above
		# writes to the spin table to become visible to other cores.
		# A sync instruction will probably work on typical
		# implementations (and multicore BERI1 has sequentially
		# consistent memory), but the MIPS ISA definition of sync
		# does not appear to guarantee that it will work.
		sync

spin_table_loop:
.rept 100
		# nops prevent us from pumelling a small number of cachlines,
		# thereby potentially disrupting ll/sc on other cores
		nop
.endr
		ld   $t2, 0($t0)         # get entry_addr
		beq  $t1, $t2, spin_table_loop # loop while entry_addr == 1
		nop

		# On CPU's with a relaxed memory model, we want any reads
		# that happen after here (e.g. the kernel on core N reading its
		# variables) to happen after any writes before the write that
		# kicked the spin table (e.g. the kernel on core 0 initializing
		# variables). So we should have a sync here.
		sync
		jr   $t2                 # jump to entry_addr
		ld   $a0, 8($t0)         # load argument (branch delay)
.end start

.data
		# Provide empty argument and environmental variable arrays
arg:		.dword	0x0000000000000000
env:		.dword	0x0000000000000000
