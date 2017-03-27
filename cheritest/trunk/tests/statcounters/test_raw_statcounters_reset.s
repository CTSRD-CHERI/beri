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

#
# Test the reset values of the stat counters
#

.include "statcounters_macros.s"

THRESHOLD = 100

.macro checkstatcounter counter_group, counter_offset
    getstatcounter 6, \counter_group, \counter_offset # a2 gets the counter's value
    sltiu   $a5, $a2, THRESHOLD # a5 <= 1 if a2 less than threshold, 0 otherwise
    sll     $v0, $v0, 1         # shift v0 left by one
    or      $v0, $v0, $a5       # or a5 in the lsb of v0
.endm

.set mips64
.set noreorder
.set nobopt
.set noat

.global start
start:

    resetstatcounters  # reset stat counters

    move    $v0, $zero # init result bit vector to all 0s

    checkstatcounter ICACHE, WRITE_HIT
    checkstatcounter ICACHE, WRITE_MISS
    checkstatcounter ICACHE, READ_HIT
    checkstatcounter ICACHE, READ_MISS
    checkstatcounter ICACHE, PFTCH_HIT
    checkstatcounter ICACHE, PFTCH_MISS
    checkstatcounter ICACHE, EVICT
    checkstatcounter ICACHE, PFTCH_EVICT

    checkstatcounter DCACHE, WRITE_HIT
    checkstatcounter DCACHE, WRITE_MISS
    checkstatcounter DCACHE, READ_HIT
    checkstatcounter DCACHE, READ_MISS
    checkstatcounter DCACHE, PFTCH_HIT
    checkstatcounter DCACHE, PFTCH_MISS
    checkstatcounter DCACHE, EVICT
    checkstatcounter DCACHE, PFTCH_EVICT

    checkstatcounter L2CACHE, WRITE_HIT
    checkstatcounter L2CACHE, WRITE_MISS
    checkstatcounter L2CACHE, READ_HIT
    checkstatcounter L2CACHE, READ_MISS
    checkstatcounter L2CACHE, PFTCH_HIT
    checkstatcounter L2CACHE, PFTCH_MISS
    checkstatcounter L2CACHE, EVICT
    checkstatcounter L2CACHE, PFTCH_EVICT

    checkstatcounter MIPSMEM, BYTE_READ
    checkstatcounter MIPSMEM, BYTE_WRITE
    checkstatcounter MIPSMEM, HWORD_READ
    checkstatcounter MIPSMEM, HWORD_WRITE
    checkstatcounter MIPSMEM, WORD_READ
    checkstatcounter MIPSMEM, WORD_WRITE
    checkstatcounter MIPSMEM, DWORD_READ
    checkstatcounter MIPSMEM, DWORD_WRITE
    checkstatcounter MIPSMEM, CAP_READ
    checkstatcounter MIPSMEM, CAP_WRITE

    checkstatcounter TAGCACHE, WRITE_HIT
    checkstatcounter TAGCACHE, WRITE_MISS
    checkstatcounter TAGCACHE, READ_HIT
    checkstatcounter TAGCACHE, READ_MISS
    checkstatcounter TAGCACHE, PFTCH_HIT
    checkstatcounter TAGCACHE, PFTCH_MISS
    checkstatcounter TAGCACHE, EVICT
    checkstatcounter TAGCACHE, PFTCH_EVICT

    checkstatcounter L2CACHEMASTER, READ_REQ
    checkstatcounter L2CACHEMASTER, WRITE_REQ
    checkstatcounter L2CACHEMASTER, WRITE_REQ_FLIT
    checkstatcounter L2CACHEMASTER, READ_RSP
    checkstatcounter L2CACHEMASTER, READ_RSP_FLIT
    checkstatcounter L2CACHEMASTER, WRITE_RSP

    checkstatcounter TAGCACHEMASTER, READ_REQ
    checkstatcounter TAGCACHEMASTER, WRITE_REQ
    checkstatcounter TAGCACHEMASTER, WRITE_REQ_FLIT
    checkstatcounter TAGCACHEMASTER, READ_RSP
    checkstatcounter TAGCACHEMASTER, READ_RSP_FLIT
    checkstatcounter TAGCACHEMASTER, WRITE_RSP

    # Dump registers in the simulator
    mtc0 $v0, $26
    nop
    nop

    # Terminate the simulator
    mtc0 $v0, $23
    end:
    b end
    nop
