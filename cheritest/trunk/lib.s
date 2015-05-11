#-
# Copyright (c) 2011 Robert N. M. Watson
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

# Contants used by lib.s to refer to exception vectors 
EXCV_TLB=0
EXCV_XTLB=8
EXCV_CACHE=16
EXCV_COMMON=24
EXCV_INT=32
EXCV_NUM=5
	
#
# POSIX-like void *memcpy(dest, src, len), arguments taken as a0, a1, a2,
# return value via v0.  Uses t0 to hold the in-flight value.
#

		.text
		.global memcpy
		.ent memcpy
memcpy:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		move	$v0, $a0	# Return initial value of dest.

memcpy_loop:
		# Check up front -- length could start out as zero.
		beq	$a2, $zero, memcpy_done
		nop

		lb	$t0, 0($a1)
		sb	$t0, 0($a0)

		# Increment dest and src, decrement len.
		daddiu	$a0, 1
		daddiu	$a1, 1
		daddiu	$a2, -1

		b memcpy_loop
		nop			# branch-delay slot

memcpy_done:

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end memcpy

#
# Functions to install exception handlers for general-purpose exceptions when
# BEV=0 and BEV=1.  The handler to install is at address a0, and will be
# jumped to unconditionally.
#
# This function invokes memcpy(), which will stomp on a2, t0, and v0.
#

		.data
bev0_handler_targets:
	.rept EXCV_NUM
		.dword	unhandled_exception
	.endr
bev1_handler_targets:
	.rept EXCV_NUM
		.dword	unhandled_exception
	.endr
		.text
.global set_bev0_tlb_handler
.ent set_bev0_tlb_handler
# Set handler for TLB Refill exception when BEV=0
set_bev0_tlb_handler:	
#		dla     $t0, bev0_handler_targets
		sd      $a0, EXCV_TLB($t0)
		jr	$ra
		nop # branch-delay slot
.end set_bev0_tlb_handler

.global set_bev1_tlb_handler
.ent set_bev1_tlb_handler
# Set handler for TLB Refill exception when BEV=1
set_bev1_tlb_handler:	
		dla     $t0, bev1_handler_targets
		sd      $a0, EXCV_TLB($t0)
		jr	$ra
		nop # branch-delay slot
.end set_bev1_tlb_handler

.global set_bev0_xtlb_handler
.ent set_bev0_xtlb_handler
# Set handler for XTLB Refill exception when BEV=0
set_bev0_xtlb_handler:	
		dla     $t0, bev0_handler_targets
		sd      $a0, EXCV_XTLB($t0)
		jr	$ra
		nop # branch-delay slot
.end set_bev0_xtlb_handler

.global set_bev1_xtlb_handler
.ent set_bev1_xtlb_handler
# Set handler for XTLB Refill exception when BEV=1
set_bev1_xtlb_handler:	
		dla     $t0, bev1_handler_targets
		sd      $a0, EXCV_XTLB($t0)
		jr	$ra
		nop # branch-delay slot
.end set_bev1_xtlb_handler

.global set_bev0_cache_handler
.ent set_bev0_cache_handler
# Set handler for cache error exception when BEV=0
set_bev0_cache_handler:	
		dla     $t0, bev0_handler_targets
		sd      $a0, EXCV_CACHE($t0)
		jr	$ra
		nop # branch-delay slot
.end set_bev0_cache_handler

.global set_bev1_cache_handler
.ent set_bev1_cache_handler
# Set handler for cache error exception when BEV=1
set_bev1_cache_handler:	
		dla     $t0, bev1_handler_targets
		sd      $a0, EXCV_CACHE($t0)
		jr	$ra
		nop # branch-delay slot
.end set_bev1_cache_handler

.global set_bev0_common_handler
.ent set_bev0_common_handler
# Set handler for common exception vector when BEV=0
set_bev0_common_handler:	
		dla     $t0, bev0_handler_targets
		sd      $a0, EXCV_COMMON($t0)
		jr	$ra
		nop # branch-delay slot
.end set_bev0_common_handler

.global set_bev1_common_handler
.ent set_bev1_common_handler
# Set handler for common exception vector when BEV=1
set_bev1_common_handler:	
		dla     $t0, bev1_handler_targets
		sd      $a0, EXCV_COMMON($t0)
		jr	$ra
		nop # branch-delay slot
.end set_bev1_common_handler

	
.global install_bev0_stubs
.ent install_bev0_stubs
install_bev0_stubs:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Install our bev0_handler_stub at the MIPS-specified
		# exception vector address.
		dli	$a0, 0xffffffff80000000
		dla	$a1, bev0_tlb_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, $a2, 2	# Convert to byte count
		jal memcpy
		nop

		dli	$a0, 0xffffffff80000080
		dla	$a1, bev0_xtlb_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, $a2, 2	# Convert to byte count
		jal memcpy
		nop

		dli	$a0, 0xffffffffa0000100 # NB same same, but different!
		dla	$a1, bev0_cache_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, $a2, 2	# Convert to byte count
		jal memcpy
		nop
	
		dli	$a0, 0xffffffff80000180
		dla	$a1, bev0_common_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, $a2, 2	# Convert to byte count
		jal memcpy
		nop			# branch-delay slot

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot		
.end install_bev0_stubs

.global install_bev1_stubs
.ent install_bev1_stubs
install_bev1_stubs:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Install our bev1_handler_stub at the MIPS-specified
		# exception vector address.
		dli	$a0, 0xffffffffbfc00200
		dla	$a1, bev1_tlb_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, $a2, 2	# Convert to byte count
		jal memcpy
		nop

		dli	$a0, 0xffffffffbfc00280
		dla	$a1, bev1_xtlb_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, $a2, 2		# Convert to byte count
		jal memcpy
		nop

		dli	$a0, 0xffffffffbfc00300
		dla	$a1, bev1_cache_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, $a2, 2		# Convert to byte count
		jal memcpy
		nop
	
		dli	$a0, 0xffffffffbfc00380
		dla	$a1, bev1_common_handler_stub
		dli	$a2, 9 		# 32-bit instruction count
		dsll	$a2, $a2, 2	# Convert to byte count
		jal memcpy
		nop			# branch-delay slot

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot		
.end install_bev1_stubs
	
		.global bev0_handler_install
		.ent bev0_handler_install
bev0_handler_install:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Store the caller's handler in bev0_handler_target to be
		# found later by bev0_handler_stub.
		jal     set_bev0_common_handler
		nop

		jal     install_bev0_stubs
		nop

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end bev0_handler_install

		.global bev1_handler_install
		.ent bev1_handler_install
bev1_handler_install:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32
	
		# Store the caller's handler in bev1_handler_target to be
		# found later by bev1_handler_stub.
		jal     set_bev1_common_handler
		nop

		jal     install_bev1_stubs
		nop
	
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end bev1_handler_install

#
# Position-independent exception handlers that jump to an address specified
# via {bev0, bev1}_handler_targets[n].  Steps on $k0, which is set to one
# of EXCV_XYZ so that tests can check which vector was used.

		.ent bev0_tlb_handler_stub
bev0_tlb_handler_stub:
		dla     $k0, bev0_handler_targets
		ld	$k0, EXCV_TLB($k0)
		jr	$k0
		add     $k0, $0, EXCV_TLB
		.end bev0_tlb_handler_stub
		.ent bev1_tlb_handler_stub
bev1_tlb_handler_stub:
		dla     $k0, bev1_handler_targets
		ld	$k0, EXCV_TLB($k0)
		jr	$k0
		add     $k0, $0, EXCV_TLB
		.end bev1_tlb_handler_stub
		.ent bev0_xtlb_handler_stub
bev0_xtlb_handler_stub:	
		dla     $k0, bev0_handler_targets
		ld	$k0, EXCV_XTLB($k0)
		jr	$k0
		add     $k0, $0, EXCV_XTLB
		.end bev0_xtlb_handler_stub
		.ent bev1_xtlb_handler_stub
bev1_xtlb_handler_stub:
		dla     $k0, bev1_handler_targets
		ld	$k0, EXCV_XTLB($k0)
		jr	$k0
		add     $k0, $0, EXCV_XTLB
		.end bev1_xtlb_handler_stub
		.ent bev0_cache_handler_stub
bev0_cache_handler_stub:
		dla     $k0, bev0_handler_targets
		ld	$k0, EXCV_CACHE($k0)
		jr	$k0
		add     $k0, $0, EXCV_CACHE
		.end bev0_cache_handler_stub
		.ent bev1_cache_handler_stub
bev1_cache_handler_stub:
		dla     $k0, bev1_handler_targets
		ld	$k0, EXCV_CACHE($k0)
		jr	$k0
		add     $k0, $0, EXCV_CACHE
		.end bev1_cache_handler_stub
		.ent bev0_common_handler_stub
bev0_common_handler_stub:
		dla     $k0, bev0_handler_targets
		ld	$k0, EXCV_COMMON($k0)
		jr	$k0
		add     $k0, $0, EXCV_COMMON
		.end bev0_common_handler_stub
		.ent bev1_common_handler_stub
bev1_common_handler_stub:
		dla     $k0, bev1_handler_targets
		ld	$k0, EXCV_COMMON($k0)
		jr	$k0
		add     $k0, $0, EXCV_COMMON
		.end bev1_common_handler_stub

	
#
# Configure post-boot exception vectors by clearing the BEV bit in the CP0
# status register.  Stomps on t0 and t1.
#
		.text
		.global bev_clear
		.ent bev_clear
bev_clear:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		mfc0	$t0, $12
		dli	$t1, 1 << 22	# BEV bit
		nor	$t1, $t1, $t1
		and	$t0, $t0, $t1
		mtc0	$t0, $12

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end bev_clear

#
# Default handler for exceptions which just dies horribly. 
#
		.text
		.global unhandled_exception
		.ent unhandled_exception
unhandled_exception:
		b .
		mtc0 $at, $23        
		.end unhandled_exception

#
# __assert(line number)
# Leaves the line number in v0 (and a0), dumps registers and aborts the
# simulator.
# 
		.text
		.global __assert_fail
		.ent __assert_fail
__assert_fail:
		# Store the first argument in v0.  On a successful test result, the
		# test will return 0 (in v0), so a non-zero value here on exit means
		# that the test failed.
		dadd $v0, $a0, $zero
		# Store -1 in v1 so it's easy to visually spot that a test failed from
		# a register dump
		daddi $v1, $zero, 0xffff
		# TODO: Export the registers and die when not running in the simulator.
		# Dump MIPS registers
		mtc0 $at, $26
		# Dump capability registers
		.if(TEST_CP2 == 1)
		  mtc2 $k0, $0, 6
		.else
		  nop
		.endif
		# Kill the simulator
		mtc0 $at, $23
.end __assert_fail


# C-compatible memcpy, wrapping the capability version
# Note: This is currently called smemcpy (simple memcpy) so that we don't need
# to remove the old memcpy yet.  It's also important to remember that some of
# the assembly functions here may not respect the ABI in terms of the caller /
# callee-save registers, and so expect memcpy() to clobber fewer registers than
# this does.
# void *memcpy(void *dst,
#              void *src,
#              size_t len)
# dst: $c1
# src: $c2
# len: $4
.text
.global smemcpy
.ent smemcpy 
smemcpy:
	CIncBase $c3, $c0, $a0      # Get the destination capability
	CIncBase $c4, $c0, $a1      # Get the source capability
	b        cmemcpy            # Jump to the capability version
	daddi    $a0, $a2, 0        # Move the length to arg0 (delay slot)
.end smemcpy

#
# Capability Memcpy - copies from one capability to another.  
# __capability void *cmemcpy(__capability void *dst,
#                            __capability void *src,
#                            size_t len)
# dst: $c3
# src: $c4
# len: $4
# Copies len bytes from src to dst.  Returns dst.
		.text
		.global cmemcpy 
		.ent cmemcpy 
cmemcpy:
	beq      $4, $zero, cmemcpy_return  # Only bother if len != 0.  Unlikely to
	                               # be taken, so we make it a forward branch
	                               # to give the predictor a hint.
	# Note: We use v0 to store the base linear address because memcpy() must
	# return that value in v0, allowing cmemcpy() to be tail-called from
	# memcpy().  This is in the delay slot, so it happens even if len == 0.
	CGetBase $v0, $c3            # v0 = linear address of dst
	CGetBase $v1, $c4            # v1 = linear address of src
	andi     $12, $v0, 0x1f      # t4 = dst % 32
	andi     $13, $v1, 0x1f      # t5 = src % 32
	daddi    $a1, $zero, 0       # Store 0 in $a1 - we'll use that for the
	                             # offset later.

	bne      $12, $13, slow_memcpy_loop
	                             # If src and dst have different alignments, we
	                             # have to copy a byte at a time because we
	                             # don't have any multi-byte load/store
	                             # instruction pairs with different alignments.
	                             # We could do something involving shifts, but
	                             # this is probably a sufficiently uncommon
	                             # case not to be worth optimising.
	andi     $t8, $a0, 0x1f      # t8 = len % 32

fast_path:                       # At this point, src and dst are known to have
                                 # the same alignment.  They may not be 32-byte
                                 # aligned, however.  
	# FIXME: This logic can be simplified by using the power of algebra
	dsub    $v1, $zero, $12
	daddi   $v1, $v1, 32
	andi    $v1, $v1, 0x1f      # v1 = number of bytes we need to copy to
	                            # become aligned
	dsub    $a2, $a0, $v1
	daddi   $a2, $a2, -32        # (delay slot)
	bltz    $a2, slow_memcpy_loop# If we are copying more bytes than the number
	                             # required for alignment, plus at least one
	                             # capability more, continue in the fast path
	nop
	beqzl   $v1, aligned_copy    # If we have an aligned copy (which we probably
	                             # do) then skip the slow part
	
	dsub    $a2, $a0, $a1        # $12 = amount left to copy (delay slot, only
	                             # executed if branch is taken)
unaligned_start:
	clb      $a2, $a1, 0($c4)
	daddi    $a1, $a1, 1
	bne      $v1, $a1, unaligned_start 
	csb      $a2, $a1, -1($c3)

	dsub     $a2, $a0, $a1        # $12 = amount left to copy
aligned_copy:
	addi    $at, $zero, 0xFFE0
	and     $a2, $a2, $at        # a2 = number of 32-byte aligned bytes to copy
	dadd    $a2, $a2, $a1        # ...plus the number already copied.

copy_caps:
	clc     $c5, $a1, 0($c4)
	daddi   $a1, $a1, 32
	bne     $a1, $a2, copy_caps
	csc     $c5, $a1, -32($c3)

	dsub    $v1, $a0, $a2        # Subtract the number of bytes copied from the
	                             # number to copy.  This should give the number
	                             # of unaligned bytes that we still need to copy
	beqzl   $v1, cmemcpy_return  # If we have an aligned copy (which we probably
	                             # do) then return
	nop
	dadd    $v1, $a1, $v1
unaligned_end:
	clb      $a2, $a1, 0($c4)
	daddi    $a1, $a1, 1
	bne      $v1, $a1, unaligned_end
	csb      $a2, $a1, -1($c3)

cmemcpy_return:
	jr       $ra                 # Return value remains in c1
	nop

slow_memcpy_loop:                # byte-by-byte copy
	clb      $a2, $a1, 0($c4)
	daddi    $a1, $a1, 1
	bne      $a0, $a1, slow_memcpy_loop
	csb      $a2, $a1, -1($c3)
	jr       $ra                 # Return value remains in c1
	nop
.end cmemcpy

#
# Get the ID of the current thread. Reads CP0 register 15, select 7
# (processor ID, so needs appropriate privilege).
# Args: None
# Returns: (Up to) 16-bit thread ID
#
        global_func get_thread_id
        dmfc0    $v0, $15, 7         # load processor ID register, select 7
        jr       $ra                 # return
        and      $v0, $v0, 0xffff    # mask off max thread id
        .end get_thread_id

#
# Get the maximum ID of any thread on this CPU i.e. the number hw threads-1.
# Reads CP0 register 15, select 7 (processor ID, so needs appropriate privilege).
# Args: None
# Returns: (Up to) 16-bit max thread ID
#
        global_func get_max_thread_id
        dmfc0    $v0, $15, 7         # load processor ID register, select 7
        jr       $ra                 # return
        srl      $v0, $v0, 16        # top 16 bits contain max thread ID
        .end get_max_thread_id

# As get_thread_id, but for core number
        global_func get_core_id
        dmfc0    $v0, $15, 6         # load processor ID register, select 6
        jr       $ra                 # return
        and      $v0, $v0, 0xffff    # mask off max core id
        .end get_core_id
# As get_max_thread_id, but for max core number
        global_func get_max_core_id
        dmfc0    $v0, $15, 6         # load processor ID register, select 6
        jr       $ra                 # return
        srl      $v0, $v0, 16        # top 16 bits contain max core ID
        .end get_max_core_id

#
# Get an ID in range [0, num cores * num threads)  which combines the current
# core and threadID i.e. a unique identifier for this hw thread in the whole
# system. Also returns, in $v1, the maximum such ID.
# Args: None
# Returns: in v0: current core ID * num threads + current thread ID
#          in v1: num cores * num threads - 1
# Clobbers: t0, t1, t2, t3
#
        global_func get_corethread_id
	mfc0  $t0, $15	        # prid register
	and   $t0, $t0, 0xff00  #
	xor   $t0, $t0, 0x8900  #
        li    $v1, 1            # one core on gxemul
	beqz  $t0, 1f           # return if on gxemul 
        li    $v0, 0            # return 0 on gxemul
        dmfc0 $t0, $15, 6       # t0 = core ID / max core
        srl   $t1, $t0, 16      # t1 = max core ID
        add   $t1, 1            # t1 = num cores
        and   $v0, $t0, 0xffff  # v0 = current core ID
        dmfc0 $t0, $15, 7       # t0 = thread ID / num threads
        srl   $v1, $t0, 16      # v1 = max thread ID
        add   $v1, 1            # v1 = num threads
        and   $t0, $t0, 0xffff  # t0 = thread ID
        mul   $v0, $v0, $v1     # v0 = current core * num threads 
        add   $v0, $t0          # v0 = current core * num threads + thread ID
        mul   $v1, $v1, $t1     # v1 = num cores * num threads
1: 
        jr    $ra               # return
        sub   $v1, 1            # v1 = num cores * num threads - 1 (delay)
        .end get_corethread_id
        
#
#  Wait for all threads to reach a certain point. This is done using per thread
#  counters. On entry to the barrier we increment this thread's counter then loop
#  waiting for all other threads' counters to equal or exceed our own. Does not
#  handle wrapping of the 8-bit counters. Needs sufficient privilege to access
#  the current thread ID.
#  Args: $a0 - A pointer to an array of bytes (one per thread) to use as counters 
#      -- typically allocated using the mkBarrier macro.
#  Returns: The value of the counter (i.e. the number of times the barrier has been called so far)
#  Clobbers: t0,t1,t2,t3,v0,v1        
#
        .ent thread_barrier
        .global thread_barrier
thread_barrier:
        prelude
        bal      get_corethread_id
        nop                          # delay
        dadd     $t1, $a0, $v0       # address of flag for this thread
        lbu      $v0, 0($t1)         # load flag value
        add      $v0, 1              # increment
        sb       $v0, 0($t1)         # store new value
barrier_loop:
        move     $t0, $v1            # Number of threads
        dadd     $t1, $a0, $t0       # address of first counter
thread_loop:
        lbu      $t2, 0($t1)         # load counter value
        subu     $t3, $v0, $t2       # difference of counters
        bgtz     $t3, barrier_loop   # loop again if some thread has not reached barrier
        subu     $t0, 1              # decrement thread counter (delay slot)
        bgez     $t0, thread_loop    # next thread
        dadd     $t1, $a0, $t0       # address of next counter  (delay slot)
        # Barrier complete
        epilogue
        jr       $ra                 # return
        nop                          # (delay slot)
        .end thread_barrier
