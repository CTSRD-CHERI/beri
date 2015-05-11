#-
# Copyright (c) 2011-2012 Robert N. M. Watson
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

		.text
		.global start
		.ent start
start:
check_pause_switch_0:
		# Check the dipswitch to determine whether we should pause waiting
		# for cherictl or whether we should begin immediatly
		dla	$t0, __dip_switches__
		lbu	$t0, 0($t0)
		andi	$t0, 0x1
		beq	$t0, $0, check_relocate_switch_1
		nop
		
		# Reset the software-controlled button
		dli     $t1, 0x1
triggerloop:
		# Spin until the debug unit sets $t1 to equal 0
		# to trigger us to relocate the kernel and go
		and	$t0, $t1
		andi	$t0, 0x1
		bne	$t0, $0, triggerloop
		nop
		
		# Set up stack and stack frame
		dla	$fp, __sp
		dla	$sp, __sp
		daddu 	$sp, $sp, -32

		# Switch to 64-bit mode -- no effect on CHERI, but required
		# for gxemul.
		mfc0	$at, $12
		or	$at, $at, 0xe0
		mtc0	$at, $12
		
check_relocate_switch_1:
		# Relocate the kernel from flash if switch 0 is on
		dla	$t0, __dip_switches__
		lbu	$t0, 0($t0)
		andi	$t0, 0x2
		bne	$t0, $0, jump_to_c
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
jump_to_c:
        # Enable CP1
        dli $t1, 1 << 29
        or $at, $at, $t1
        mtc0 $at, $12
        nop
        nop
        nop
        nop
        nop
		# Jump to main program in C
		dla $sp, __sp
		jal main
		nop
		# Explicitly clear most registers.  $sp, $fp, and $ra aren't
		# cleared as they are part of our initialised stack.
cleanup:
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
		.end start

		.data

		# Provide empty argument and environmental variable arrays
arg:		.dword	0x0000000000000000
env:		.dword	0x0000000000000000
