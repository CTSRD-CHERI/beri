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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Unit test that stores a series of bytes to memory to test cache store-to-use
# forwarding in sequential cycles.
#
		.text
		.global start
start:
		# Store a series of bytes to a double word.  We do it twice to make sure
		# that the instructions are cached and thus packed together as much as possible.
		# Since we do not load from this location this time, it will be in the L2 cache.
		dla	$a7, dwords
		dli	$a0, 0x00
		dla	$t3, dword
againL2:
# This initial sd causes a cache miss in the L2 that will compact the following byte stores.
		sd  $a7, 0($a7)
		sb	$a0, 0($t3)
		sb	$a0, 1($t3)
		sb	$a0, 2($t3)
		sb	$a0, 3($t3)
		sb	$a0, 4($t3)
		sb	$a0, 5($t3)
		sb	$a0, 6($t3)
		sb	$a0, 7($t3)
		daddi $a7, $a7, 32
		blez $a0, againL2
		addi $a0, $a0, 1
		# Value to test
		ld	$a1, 0($t3)
# Do the same thing for the next word, but since we have just loaded from the line, 
# it will now be in the L1.
startL1:
		dli	$a0, 0x00
againL1:
# This initial ld causes a cache miss in the L1 that will compact the following byte stores.
		ld  $a5, 0($a7)
		sb	$a0, 8($t3)
		sb	$a0, 9($t3)
		sb	$a0,10($t3)
		sb	$a0,11($t3)
		sb	$a0,12($t3)
		sb	$a0,13($t3)
		sb	$a0,14($t3)
		sb	$a0,15($t3)
		daddi $a7, $a7, 32
		blez $a0, againL1
		addi $a0, $a0, 1
		# Value to test
		ld	$a2, 8($t3)

		# Dump registers in the simulator
		mtc0	$v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop

		.data
dword:		.dword	0x0000000000000000
dwords:	    .dword	0x0000000000000000
