#-
# Copyright (c) 2011 Robert N. M. Watson
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

#
# Test for reads from aliased memory regions. It works on cheri2 because
# addresses at the same page offset will alias in the caches, but this
# might not work for cheri.
#

		.global test
		.ent test
test:
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

                dla     $a0, page0
                dla     $a1, page1
                dla     $a2, page2

                #
		# Load repeatedly from three aliasing addresses.
                # Do this twice to warm up the icache and sprinkle
		# a couple of stores in just for kicks.
                #

                li      $t0, 1
loop:
                nop
                nop
                nop
                ld      $a3, 0($a0)
                ld      $a4, 0($a1)
                ld      $a5, 0($a0)
                ld      $a6, 0($a1)
                ld      $a7, 0($a2)
                ld      $s0, 0($a0)
                ld      $s1, 0($a1)
                ld      $s2, 0($a1)
                ld      $s3, 0($a2)
                ld      $s4, 0($a2)
                sd      $0,  0($a2)
                ld      $s5, 0($a2)
                sd      $0,  0($a1)
                ld      $s6, 0($a1)
                ld      $s7, 0($a0)
                # reset memory to its original state
                dli     $t1, 0x1011121314151617
                sd      $t1, 0($a1)
                dli     $t1, 0x2021222324252627
                sd      $t1, 0($a2)
                bgtz    $t0, loop
                sub     $t0, 1
        
return:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

.data
page0:  
        .rept 512
        .dword 0x0001020304050607
        .endr
page1:  
        .rept 512
        .dword 0x1011121314151617
        .endr
page2:
        .rept 512
        .dword 0x2021222324252627
        .endr
