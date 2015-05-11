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
# Check that all the cores in the system are alive and function correctly
#

		.global start
start:
		# Get the total number of cores
		mfc0    $t0, $15, 6
		srl     $t1, $t0, 16
		daddu   $t1, $t1, 1
		# Get core ID
		andi    $t0, $t0, 0xFFFF

		# Generate shared memory address. Used by all cores
		dli     $t2, 0x9800000000A00000
		dli     $t8, 0x9800000000B00000

		# Initialise registers
		dli     $a0, 0
		dli     $a1, 0
		dli     $a2, 0
		dli     $a3, 0
		dli     $a4, 0
		dli     $a5, 0
		dli     $a6, 0
		dli     $a7, 0
		dli     $t9, 0

		# Set a branch comparison values
		dli     $t3, 1234
		dli     $a2, 100 
		dli     $a6, 150  

		# Core 0 executes code different to other cores
		addu    $t0, $t0, 1
		beq     $t0, $t1, core_last
		subu    $t0, $t0, 1
		bnez    $t0, core_other
		nop

core_0:
		# Core 0 increments a counter
		addu    $a1, $a1, 1
		ld      $a0, 0($t2)		# This is done to match
						# the number of instructions
						# all other cores execute
		bne     $a1, $a2, core_0
		nop
		j       dump			# Once the count value has been 
		sd      $t3, 0($t2)		# reached, the RegFile is dumped
						# The core also updates a shared
						# value so other cores can break

core_last:
		addu    $a1, $a1, 1
		ld      $a0, 0($t2)	
		bne     $a1, $a6, core_last
		nop

core_other:		
		addu    $a1, $a1, 1		# Increment counter
		ld      $a0, 0($t2)		
		bne     $a0, $t3, core_other	# Check if Core 0 has updated the
		nop				# shared memory value

dump:
		# Dump registers in the simulator
		mtc0    $v0, $26 
		nop
		j       finish
		sd      $t0, 0($t8)                

finish:
		ld      $t9, 0($t8)		# Wait for other cores to finish  
		addu    $t9, $t9, 1		
		bne     $t1, $t9, finish	
		nop	
                mtc0    $v0, $23 

end:
		b       end
		nop
