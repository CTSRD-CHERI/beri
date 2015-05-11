#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2013 Alan A. Mujumdar
# Copyright (c) 2014 Michael Roe
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
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
# Test PIC0 
#
# Disable all interrupt sources except source 2, which is forwarded to
# irq 4. Write to the PIC to set source 2, then check that source 2 is set in
# the PIC's interrupt pending register and IP6 is set in CP0 cause register.
# (Forwarding the interrupt to irq 4 should cause IP6 to be set, as IP0 and
# IP1 are reserved for software interrupts).
#
		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

	        dli     $a0, 0x900000007f804000 # PIC_BASE 
		sd	$zero, 0($a0)		# disable source 0
		sd	$zero, 8($a0)		# disable source 1
   	 	dli     $t0, 0x80000004         # enable source 2, forward to irq 4
  	 	sd      $t0, 16($a0)         
		sd	$zero, 24($a0)		# disable source 3
		sd	$zero, 32($a0)		# disable source 4
	        dadd    $a1, $a0, 0x2000        # PIC_IP_READ_BASE 
	        li      $t0, 4                         
	        sd      $t0, 128($a1)           # set source 2
	        ld      $a2, 0($a1)             # read interrupt pending 

		#
		# Pipeline hazard: the interrupt might not
		# show up in CP0.Cause immediately, as the
		# CPU is pipelined and the write to the PIC
		# has to make its way through the memory
		# system.
		#

		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		mfc0    $a3, $13                # read cause reg    
		srl	$a3, $a3, 8		# interrupt pending bits
		andi	$a3, $a3, 0xff
		sd      $t0, 256($a1)           # clear source 2   
		ld      $a4, 0($a1)             # read interrupt pending  

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop				# branch-delay slot
		.end	test
