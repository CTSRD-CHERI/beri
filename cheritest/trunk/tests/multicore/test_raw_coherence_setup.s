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
		# Check total number of cores
		#
		mfc0	$t0, $15, 6
		srl     $t1, $t0, 16
		daddu   $a1, $t1, 1

		#
		# Check core ID
		#
		andi    $a0, $t0, 0xFFFF

		#
		# Test memory location in cached space
		#
		dli     $t2, 0x9800000000100000
		lw      $t3, 0($t2)
		daddu   $a2, $zero, $t3

		#
		# Write to cached mem location and test
		#
		sw      $a0, 0($t2) 
		lw      $a3, 0($t2)

		#
		# Dump registers in the simulator
		#
		mtc0    $v0, $26 

		#
		# Wait for other cores to perfrom RegDump
		#
		dli     $t8, 200	# Spin for 200 cycles
		dli     $t9, 0
spin:
		addu    $t9, $t9, 1
		nop
		bne     $t9, $t8, spin
		nop		 

		#
                # Terminate the simulator 
		#
                mtc0    $v0, $23 

end:
		b       end
		nop
