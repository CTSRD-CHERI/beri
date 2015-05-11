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

# Multi-threaded test for inter-thread interrupts via the PIC.
# Thread 0 sends an interrupt to thread 1, which sends an interrupt
# to thread 0 in return.

.include "macros.s"
        
.set mips64
.set noreorder
.set nobopt

.global test
test:   .ent    test
	daddu 	$sp, $sp, -32
	sd	$ra, 24($sp)
	sd	$fp, 16($sp)
	daddu	$fp, $sp, 32

        # address of the PIC, for later
        dla     $s7, 0x900000007f804000

        # enable interrupts
        dmfc0   $t0, $12       # get status register
        or      $t0, 0xc01    # unmask interrupt 0/1 and enable interrupts
        and     $t0, ~0x6      # clear ERL, EXL
        dmtc0   $t0, $12       # set status register
        
        jal     get_thread_id
        nop
        bnez    $v0, thread1
        nop

thread0:
        # Activate thread 1
        jal     other_threads_go
        nop

	#
	# Set up exception handlers.
	#
	jal	bev_clear
	nop

        # Handler for thread 0
        dla	$a0, bev0_handler
	jal	bev0_handler_install
	nop

        # Handler for thread 1 -- note that we don't clear bev for thread 1
        # so we have a handler for each thread
	dla	$a0, bev1_handler
	jal	bev1_handler_install
	nop

        # Configure the PIC
        dli     $t0, 0x80000100
        sd      $t0, 16($s7)     # enable int 2 and forward to thread 1 irq 0
        dli     $t0, 0x80000001
        sd      $t0, 24($s7)     # enable int 3 and forward to thread 0 irq 1

        # Synchronise with thread 1
        dla    $a0, my_barrier
        jal    thread_barrier

        # A small loop to ensure thread 1 has had time to reach expected_epc
        li      $t0, 20
1:      
        bgtz    $t0, 1b
        subu    $t0, 1

        # trigger int 2 -> thread 1
        li      $t0, 4
        sd      $t0, 8320($s7)

expected_epc0:
        b      .              # wait to be interrupted
        mfc0   $a2, $13       # read cause (for debugging)
        
the_end:
        dla    $s2, expected_epc0
        dla    $s3, expected_epc1
        
        dla    $a0, my_barrier
        jal    thread_barrier
        nop
       
	ld	$fp, 16($sp)
	ld	$ra, 24($sp)
	jr      $ra
	daddu	$sp, $sp, 32
.end    test
	
thread1:
        # Synchronise with thread 0
        dla    $a0, my_barrier
        jal    thread_barrier
        nop

expected_epc1:
        b      .              # wait to be interrupted
        mfc0   $a2, $13       # read cause (for debugging)

after_interrupt_t1:
        li     $t0, 8
        sd     $t0, 8320($s7) # Trigger int 3 -> thread 0
        
        j      the_end
        nop

#
# Exception handlers
#
        .ent bev0_handler
bev0_handler:	
	dmfc0	$s0, $13	# Cause register
	dmfc0	$s1, $14	# EPC
	        
        b       the_end
        nop
	.end bev0_handler
        
	.ent bev1_handler
bev1_handler:	
	dmfc0	$s0, $13	# Cause register
	dmfc0	$s1, $14	# EPC
	        
        b       after_interrupt_t1
        nop
	.end bev1_handler

.data
my_barrier:
        mkBarrier
