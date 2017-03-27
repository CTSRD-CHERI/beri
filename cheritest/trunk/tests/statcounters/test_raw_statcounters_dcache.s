#-
# Copyright (c) 2015-2017 Alexandre Joannou
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

.include "statcounters_macros.s"

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test the counters for the dcache
#

.global start
start:

    # reset statcounters delay in v1
    dli             $v1,  100
    # dword address in v0
    dla             $v0,  dword
    # test 1 : read miss
    reset_delay     $v1
    ld              $t0, 0($v0)
    delay           $v1
    getstatcounter  6, DCACHE, READ_MISS    # a2 takes the value of counter READ_MISS in group DCACHE
    # test 2 : eviction
    reset_delay     $v1
	cache           0x1, 0($v0)
    delay           $v1
    getstatcounter  7, DCACHE, EVICT        # a3 takes the value of counter EVICT in group DCACHE

    # Dump registers in the simulator
    mtc0 $v0, $26
    nop
    nop

    # Terminate the simulator
    mtc0 $v0, $23
    end:
    b end
    nop

.data
dword:		.dword	0xf00df00dbeefbeef
