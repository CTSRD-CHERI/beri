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

ICACHE         = 8
DCACHE         = 9
L2CACHE        = 10
MIPSMEM        = 11
TAGCACHE       = 12
L2CACHEMASTER  = 13
TAGCACHEMASTER = 14

# CacheCore counters
WRITE_HIT   = 0
WRITE_MISS  = 1
READ_HIT    = 2
READ_MISS   = 3
PFTCH_HIT   = 4
PFTCH_MISS  = 5
EVICT       = 6
PFTCH_EVICT = 7

# MIPSMem counters
BYTE_READ   = 0
BYTE_WRITE  = 1
HWORD_READ  = 2
HWORD_WRITE = 3
WORD_READ   = 4
WORD_WRITE  = 5
DWORD_READ  = 6
DWORD_WRITE = 7
CAP_READ    = 8
CAP_WRITE   = 9

# Master interface counters
READ_REQ       = 0
WRITE_REQ      = 1
WRITE_REQ_FLIT = 2
READ_RSP       = 3
READ_RSP_FLIT  = 4
WRITE_RSP      = 5

.macro getstatcounter dest, counter_group, counter_offset
    .word (0x1F << 26) | (0x0 << 21) | (\dest << 16) | (\counter_group << 11) | (\counter_offset << 6) | (0x3B)
.endm

.macro resetstatcounters
    .word (0x1F << 26) | (0x0 << 21) | (0x0 << 16) | (0x7 << 11) | (0x0 << 6) | (0x3B)
.endm

.macro delay x
    bne             \x, $zero, 0
    daddi           \x, -1
.endm

.macro reset_delay x
    resetstatcounters  # reset stat counters
    bne             \x, $zero, 0
    daddi           \x, -1
.endm

.macro flush_nops
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
.endm
