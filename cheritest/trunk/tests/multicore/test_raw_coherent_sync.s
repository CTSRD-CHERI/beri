#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2013 Alan A. Mujumdar
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
# Exercise cache instructions
#
# Execute a series of cache instructions that are found in the kernel.  We
# currently don't check if they are correct, but merely check that they don't
# lock up the processor.  Since we have a write-through L1 cache, the only 
# function of the cache instructions is to synchronize L1 instruction and data
# caches.  We don't currently support cache instructions to the L2.
# 
#

		.global start
start:
		#
		# Initialise registers
		#
		dli     $a0, 0
		dli     $a1, 0
		dli     $a2, 0
		dli     $a3, 0
		dli     $a4, 0
		dli     $a5, 0
		dli     $a6, 0
		dli     $a7, 0
		dli     $t0, 0
		dli     $t1, 0
		dli     $t2, 0
		dli     $t3, 0
		dli     $t8, 0
		dli     $t9, 0
		dli     $k0, 0
		dli     $k1, 0
		dli     $s0, 0
		dli     $s1, 0
		dli     $s2, 0
		dli     $s3, 0
		dli     $s4, 0
		dli     $s5, 0
		dli     $s6, 0
		dli     $s7, 0

		#
		# Check core ID and total core number 
		#
		mfc0	$t0, $15, 6
		srl     $t1, $t0, 16
		daddu   $t1, $t1, 1
		andi    $t0, $t0, 0xFFFF


		#
		# Set memory addresses and loop counters
		#
		dli     $t2, 0x9800000000100000
		dli     $t3, 0x9800000000200000
		dli     $s0, 0x9800000000300000
		dli     $a0, 0xFFF
		dli     $a1, 0xABC
		dli     $a2, 0xB
		dli     $a6, 0xFF

		#
		# Calculate shared value
		#
calc:
		daddu   $t8, $t8, $t9
		daddu   $t9, $t9, 1
		bne     $t9, $t1, calc
		nop

		#
		# Branch cores based on ID
		#
		bnez    $t0, core_other
		sd      $zero, 0($s0) 

core_0:
		daddu   $a3, $a3, 1
		bne     $a0, $a3, core_0
		nop
		j       finish
		sd      $a2, 0($t3)

core_other:		
		ld      $a3, 0($t2)
		sd      $a1, 0($t2)
		ld      $a4, 0($t3)
		daddu   $a7, $a7, 1
		bne     $a4, $a2, core_other
		nop
		j       finish
		nop

finish:
		# Dump registers in the simulator
		mtc0    $v0, $26 

		# Add core ID to shared register
llsc:
		lld     $s1, 0($s0)
		daddu   $s1, $s1, $t0 
		scd     $s1, 0($s0)
		beqz    $s1, llsc
		nop 

spin:
		ld      $s2, 0($s0)
		bne     $t8, $s2, spin
		nop
/*
		daddu   $a5, $a5, 1
		bne     $a6, $a5, spin
		nop		
*/
                # Terminate the simulator 
                mtc0    $v0, $23 

end:
		b       end
		nop
