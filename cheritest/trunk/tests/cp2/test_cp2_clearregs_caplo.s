#-
# Copyright (c) 2015 Robert M. Norton
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

#
# Test cclear regs instruction
#

                .global test
test:           .ent test
                daddu   $sp, $sp, -32
                sd      $ra, 24($sp)
                sd      $fp, 16($sp)
                daddu   $fp, $sp, 32
                
                # Ensure all capability registers are set to the default.
                cmove		$c1, $c0
                cmove		$c2, $c0
                cmove		$c3, $c0
                cmove		$c4, $c0
                cmove		$c5, $c0
                cmove		$c6, $c0
                cmove		$c7, $c0
                cmove		$c8, $c0
                cmove		$c9, $c0
                cmove		$c10, $c0
                cmove		$c11, $c0
                cmove		$c12, $c0
                cmove		$c13, $c0
                cmove		$c14, $c0
                cmove		$c15, $c0
                cmove		$c16, $c0
                cmove		$c17, $c0
                cmove		$c18, $c0
                cmove		$c19, $c0
                cmove		$c20, $c0
                cmove		$c21, $c0
                cmove		$c22, $c0
                cmove		$c23, $c0
                cmove		$c24, $c0
                cmove		$c25, $c0
                cmove		$c26, $c0

                # clear caplo16 even regs except c0
		cclearlo	0x5554

                # Write a non-zero value to some of the cleared registers to ensure it
                # sticks.
                cmove   $c4,  $c0
                cmove   $c10, $c0

.include        "tests/cp2/clearregs_common.s"
                
                ld      $fp, 16($sp)
                ld      $ra, 24($sp)
                daddu   $sp, $sp, 32
                jr      $ra
                nop                     # branch-delay slot
                .end    test
