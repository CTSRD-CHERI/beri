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

.macro cclearregs regset regmask
                .word (0x12 << 26) | (0xf << 21) | (\regset << 16) | (\regmask)
.endm   

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32
1:

                # clear gplo16
                cclearregs 0, 0xffff
                move    $0,  $0
                move    $1,  $1
                move    $2,  $2
                move    $3,  $3
                move    $4,  $4
                move    $5,  $5
                move    $6,  $6
                move    $7,  $7
                move    $8,  $8
                move    $9,  $9
                move    $10, $10
                move    $11, $11
                move    $12, $12
                move    $13, $13
                move    $14, $14
                move    $15, $15

                # clear gphi16 except sp
                cclearregs 1, 0xdfff
                move    $16, $16
                move    $17, $17
                move    $18, $18
                move    $19, $19
                move    $20, $20
                move    $21, $21
                move    $22, $22
                move    $23, $23
                move    $24, $24
                move    $25, $25
                move    $26, $26
                move    $27, $27
                move    $28, $28
                move    $29, $29
                move    $30, $30
                move    $31, $31

                # clear caplo16 except c0
                cclearregs 2, 0xfffe
                cmove   $c0, $c0
                cmove   $c1, $c1
                cmove   $c2, $c2
                cmove   $c3, $c3
                cmove   $c4, $c4
                cmove   $c5, $c5
                cmove   $c6, $c6
                cmove   $c7, $c7
                cmove   $c8, $c8
                cmove   $c9, $c9
                cmove   $c10, $c10
                cmove   $c11, $c11
                cmove   $c12, $c12
                cmove   $c13, $c13
                cmove   $c14, $c14
                cmove   $c15, $c15

                # clear caphi16
                cclearregs 3, 0xffff
                cmove   $c16, $c16
                cmove   $c17, $c17
                cmove   $c18, $c18
                cmove   $c19, $c19
                cmove   $c20, $c20
                cmove   $c21, $c21
                cmove   $c22, $c22
                cmove   $c23, $c23
                cmove   $c24, $c24
                cmove   $c25, $c25
                cmove   $c26, $c26
                cmove   $c27, $c27
                cmove   $c28, $c28
                cmove   $c29, $c29
                cmove   $c30, $c30
                cmove   $c31, $c31
                
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
