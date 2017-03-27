#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2014 Robert M. Norton
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

# Library of assembly functions for:
# Interrupt handlers
# memcpy and memcpy_c
# thread handling: ids / thread barrier functions
#

.set mips64
.set noreorder
.set nobopt
.set noat

.include "macros.s"

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
		sync			# branch-delay slot
		.end memcpy

################################################################################
# Exception handling infrastructure
# Exceptions are handled by stubs which branch to a configurable handler.
# Pointers to the handler functions are stored in an array which is consulted
# by the stub. Stubs are first loaded into the boot bram then copied into the
# exception vectors because dram is not directly loadable.
################################################################################

# Arrays of pointers to handlers which the stubs will jump to on exception
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

#
# set_bev{0,1}_xxx_handler :
# Functions for setting exception handlers. The pointer to the handler is
# passed in a0. Just store it into the relevant entry in the above arrays.
# We use a macro to generate set functions for each exception vector.
#
.macro create_set_handler_func name vector_id
.globl set_bev0_\name
.ent set_bev0_\name
set_bev0_\name :
	dla     $t0, bev0_handler_targets
	jr	$ra
	sd      $a0, \vector_id ($t0)
.end set_bev0_\name
.globl set_bev1_\name
.ent set_bev1_\name
set_bev1_\name:
	dla     $t0, bev1_handler_targets
	jr	$ra
	sd      $a0, \vector_id ($t0)
.end set_bev1_\name
.endm

create_set_handler_func tlb_handler    EXCV_TLB
create_set_handler_func xtlb_handler   EXCV_XTLB
create_set_handler_func cache_handler  EXCV_CACHE
create_set_handler_func common_handler EXCV_COMMON

#
# Position-independent exception handlers that jump to an address specified
# via {bev0, bev1}_handler_targets[n].  Steps on $k0, which is set to one
# of EXCV_XYZ so that tests can check which vector was used.
# We use a macro to create the stub for each exception vector.
.macro create_handler_stub name vector_id
bev0_\name :
		.ent bev0_\name
		dla     $k0, bev0_handler_targets
		ld	$k0, \vector_id ($k0)
		jr	$k0
		add     $k0, $0, \vector_id
		.end bev0_\name
size_bev0_\name = . - bev0_\name
bev1_\name :
		.ent bev1_\name
		dla     $k0, bev1_handler_targets
		ld	$k0, \vector_id ($k0)
		jr	$k0
		add     $k0, $0, \vector_id
		.end bev1_\name
size_bev1_\name = . - bev1_\name
.endm
	create_handler_stub tlb_handler_stub EXCV_TLB
	create_handler_stub xtlb_handler_stub EXCV_XTLB
	create_handler_stub cache_handler_stub EXCV_CACHE
	create_handler_stub common_handler_stub EXCV_COMMON

# macro to generate code to install a handler stub at the exception vector
# Arguments:
# name:    name of stub function to install
# address: exception vector address to copy to
.macro	install_stub name address
	dli	$a0, \address
	dla	$a1, \name
	dli	$a2, size_\name
	jal memcpy
	nop
.endm

# Function to install the bev0 handler stubs at the relevant exception vectors.
# Arguments: none
.global install_bev0_stubs
.ent install_bev0_stubs
install_bev0_stubs:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Install our bev0 handler stubs at the MIPS-specified
		# exception vector addresses.
		install_stub bev0_tlb_handler_stub    0xffffffff80000000
		install_stub bev0_xtlb_handler_stub   0xffffffff80000080
		install_stub bev0_cache_handler_stub  0xffffffffa0000100 # NB same same, but different!
		install_stub bev0_common_handler_stub 0xffffffff80000180

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		jr	$ra
		daddu	$sp, $sp, 32
.end install_bev0_stubs

# As above but for bev1 stubs
# Arguments: None
.global install_bev1_stubs
.ent install_bev1_stubs
install_bev1_stubs:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32
		install_stub bev1_tlb_handler_stub    0xffffffffbfc00200
		install_stub bev1_xtlb_handler_stub   0xffffffffbfc00280
		install_stub bev1_cache_handler_stub  0xffffffffbfc00300
		install_stub bev1_common_handler_stub 0xffffffffbfc00380

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop
.end install_bev1_stubs

# Install a handler for the bev0 common exception vector and also install stubs
# for all bev0 vectors.
# Arguments:
# a0 = pointer to handler function for bev0 common exception vector
		.global bev0_handler_install
		.ent bev0_handler_install
bev0_handler_install:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Store the caller's handler function
		jal     set_bev0_common_handler
		nop

		jal     install_bev0_stubs
		nop

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		sync			# branch-delay slot
		.end bev0_handler_install

# As above but for bev1
		.global bev1_handler_install
		.ent bev1_handler_install
bev1_handler_install:
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32
	
		# Store the caller's handler function
		jal     set_bev1_common_handler
		nop

		jal     install_bev1_stubs
		nop
	
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		sync			# branch-delay slot
		.end bev1_handler_install

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
		b end
		nop
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
	cfromptr $c3, $c0, $a0      # Get the destination capability
	cfromptr $c4, $c0, $a1      # Get the source capability
	b        memcpy_c           # Jump to the capability version
	daddi    $a0, $a2, 0        # Move the length to arg0 (delay slot)
.end smemcpy

#
# Capability Memcpy - copies from one capability to another.  
# __capability void *memcpy_c(__capability void *dst,
#                             __capability void *src,
#                             size_t len)
# dst: $c3
# src: $c4
# len: $4
# Copies len bytes from src to dst.  Returns dst.
		.text
		.global memcpy_c
		.ent memcpy_c
memcpy_c:
	beq      $4, $zero, memcpy_c_return # Only bother if len != 0.  Unlikely to
	                               # be taken, so we make it a forward branch
	                               # to give the predictor a hint.
	# Note: We use v0 to store the base linear address because memcpy() must
	# return that value in v0, allowing memcpy_c() to be tail-called from
	# memcpy().  This is in the delay slot, so it happens even if len == 0.
	CGetBase $v0, $c3            # v0 = linear address of dst
	CGetOffset $at, $c3
	dadd     $v0, $v0, $at
	CGetBase $v1, $c4            # v1 = linear address of src
	CGetOffset $at, $c4
	dadd     $v1, $v1, $at
	andi     $12, $v0, CAP_SIZE/8 - 1      # t4 = dst % 32
	andi     $13, $v1, CAP_SIZE/8 - 1      # t5 = src % 32
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
	andi     $t8, $a0, CAP_SIZE/8 - 1      # t8 = len % 32

fast_path:                       # At this point, src and dst are known to have
                                 # the same alignment.  They may not be 32-byte
                                 # aligned, however.  
	# FIXME: This logic can be simplified by using the power of algebra
	dsub    $v1, $zero, $12
	daddi   $v1, $v1, CAP_SIZE/8
	andi    $v1, $v1, CAP_SIZE/8 - 1      # v1 = number of bytes we need to copy to
	                            # become aligned
	dsub    $a2, $a0, $v1
	daddi   $a2, $a2, -CAP_SIZE/8        # (delay slot)
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
	addi    $at, $zero, -CAP_SIZE/8
	and     $a2, $a2, $at        # a2 = number of 32-byte aligned bytes to copy
	dadd    $a2, $a2, $a1        # ...plus the number already copied.

copy_caps:
	clc     $c5, $a1, 0($c4)
	daddi   $a1, $a1, CAP_SIZE/8
	bne     $a1, $a2, copy_caps
.if (CAP_SIZE != 64)
	csc     $c5, $a1, -CAP_SIZE/8($c3)
	# XXX FIXME: Offsets are 128-bit aligned even when CAP_SIZE=64, so this
	# won't work with 64-bit capabilities.
.endif

	dsub    $v1, $a0, $a2        # Subtract the number of bytes copied from the
	                             # number to copy.  This should give the number
	                             # of unaligned bytes that we still need to copy
	beqzl   $v1, memcpy_c_return  # If we have an aligned copy (which we probably
	                             # do) then return
	nop
	dadd    $v1, $a1, $v1
unaligned_end:
	clb      $a2, $a1, 0($c4)
	daddi    $a1, $a1, 1
	bne      $v1, $a1, unaligned_end
	csb      $a2, $a1, -1($c3)

memcpy_c_return:
	jr       $ra                 # Return value remains in c1
	sync

slow_memcpy_loop:                # byte-by-byte copy
	clb      $a2, $a1, 0($c4)
	daddi    $a1, $a1, 1
	bne      $a0, $a1, slow_memcpy_loop
	csb      $a2, $a1, -1($c3)
	jr       $ra                 # Return value remains in c1
	sync
.end memcpy_c

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
#  Multicore BERI1 and multithreaded BERI2 have sequentially consistent
#  memory, so don't need "sync" memory barrier instruction. We include the
#  sync in case the test library is run against formal models with a more
#  relaxed memory model.

        .ent thread_barrier
        .global thread_barrier
thread_barrier:
        prelude
        bal      get_corethread_id
        nop                          # delay
	sync			     # memory barrier
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
	sync			     # memory barrier
        # Barrier complete
        epilogue
        jr       $ra                 # return
        nop                          # (delay slot)
        .end thread_barrier
