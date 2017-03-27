#-
# Copyright (c) 2017 Robert M. Norton
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
# Test that has different behavour depending on whether the fast
# representable bounds check is in use for cincoffset. This
# check is approximate, and hence architecturally visible.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32
# Construct the example capability given in the paper
                dli     $t0, 0x0010000000200000
                csetoffset $c1, $c0, $t0
                dli     $t0, 0x0000000000e01000
                csetbounds $c1, $c1, $t0

# Put the offset near, but still inside, the lower limit of representable bounds. This is expected to work.
                dli     $t0, -0xffff
                cincoffset $c2, $c1, $t0

# Now, attempt to move the offset by one in either direction and by
# zero. Although the result is still in representable bounds
# CHERI's fast representable bounds check is conservatively
# approximate and will fail in the decrement case.
                dli        $t0, 1
                cincoffset $c3, $c2, $t0
                dli        $t0, 0
                cincoffset $c4, $c2, $t0
                dli        $t0, -1
                cincoffset $c5, $c2, $t0

                cgettag    $a0, $c3
                cgetoffset $a1, $c3
                cgettag    $a2, $c4
                cgetoffset $a3, $c4
                cgettag    $a4, $c5
                cgetoffset $a5, $c5

# Put the offset near, but still inside, the upper limit of representable bounds. This is expected to work.
                dli     $t0, 0xfeffef
                cincoffset $c6, $c1, $t0
# Nudge the address into the last representable block without failing the fast representable check.
# This must be done with an increment with no significant bits in the "mantissa" range.
                dli        $t0, 0x01
                cincoffset $c6, $c6, $t0

# Now, attempt to move the offset by one in either direction and by
# zero. Although the result is still in representable bounds
# CHERI's fast representable bounds check is conservatively
# approximate and will fail in the increment and zero cases.
                dli        $t0, 1
                cincoffset $c7, $c6, $t0
                dli        $t0, 0
                cincoffset $c8, $c6, $t0
                dli        $t0, -1
                cincoffset $c9, $c6, $t0

                cgettag    $a6, $c7
                cgetoffset $a7, $c7
                cgettag    $s0, $c8
                cgetoffset $s1, $c8
                cgettag    $s2, $c9
                cgetoffset $s3, $c9

        
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

