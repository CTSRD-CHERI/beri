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
# representable bounds check is in use for csetoffset. This
# check is approximate, and hence architecturally visible.
#

.global test
test:           .ent test
        daddu   $sp, $sp, -32
        sd      $ra, 24($sp)
        sd      $fp, 16($sp)
        daddu   $fp, $sp, 32
# Construct the example capability given in the paper
        dli     $t0, 0x0010000000200000
        csetoffset $c1, $c0, $t0
        dli     $t0, 0x0000000000e01000
        csetbounds $c1, $c1, $t0

# Attempt to set the offset into the UPPER "imprecision hazard" zone
# -- within representable bounds but might fail with fast
# representable bounds check
        dli        $t0, 0xFEFFF0
        csetoffset $c2, $c1, $t0
        cgettag    $a0, $c2
        cgetoffset $a1, $c2
        cgetbase   $a2, $c2

# Attempt to set the offset into the LOWER "imprecision hazard" zone
# This works even with fast representable bounds check
        dli        $t0, -0xFFFF
        csetoffset $c3, $c1, $t0
        cgettag    $a3, $c3
        cgetoffset $a4, $c3
        cgetbase   $a5, $c3

# Similar to above except that we do it in two stages -- the first
# one should work but the second will fail the fast representable
# bounds check. This could be a bit suprising...
        dli        $t0, -0xFFFE
        csetoffset $c4, $c1, $t0
        cgettag    $a6, $c4
        cgetoffset $a7, $c4
        cgetbase   $s0, $c4

        dli        $t0, -0xFFFF
        csetoffset $c5, $c4, $t0
        cgettag    $s1, $c5
        cgetoffset $s2, $c5
        cgetbase   $s3, $c5

        
        ld      $fp, 16($sp)
        ld      $ra, 24($sp)
        daddu   $sp, $sp, 32
        jr      $ra
        nop                     # branch-delay slot
.end    test

