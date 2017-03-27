#-
# Copyright (c) 2015 Alexandre Joannou
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
# Test the counters for the mipsmem
#

DELAY_TIME  = 1000

BYTE_TIMES  = 154
HWORD_TIMES = 36
WORD_TIMES  = 222
DWORD_TIMES = 144
CAP_TIMES   = 24

.global start
start:
    # get status reg
    mfc0    $at, $12
    # enable cheri coprocessor
    dli     $t1, 1 << 30
    or      $at, $at, $t1
    mtc0    $at, $12

    resetstatcounters  # reset stat counters
    # wait a bit for counters reset
    dli     $a4, DELAY_TIME
    1:
    bne     $a4, $zero, 1b
    daddi   $a4, -1

    # load and store a byte ...
    dla     $t0, byte1
    # ... BYTE_TIMES times
    dli     $a4, BYTE_TIMES-1
    1:
    flush_nops
    lb      $t1, 0($t0)
    sb      $t1, 0($t0)
    bne     $a4, $zero, 1b
    daddi   $a4, -1
    flush_nops

    # load and store a hword ...
    dla     $t0, hword1
    # ... HWORD_TIMES times
    dli     $a4, HWORD_TIMES-1
    1:
    flush_nops
    lh      $t1, 0($t0)
    sh      $t1, 0($t0)
    bne     $a4, $zero, 1b
    daddi   $a4, -1
    flush_nops

    # load and store a word ...
    dla     $t0, word1
    # ... WORD_TIMES times
    dli     $a4, WORD_TIMES-1
    1:
    flush_nops
    lw      $t1, 0($t0)
    sw      $t1, 0($t0)
    bne     $a4, $zero, 1b
    daddi   $a4, -1
    flush_nops

    # load and store a dword ...
    dla     $t0, dword1
    # ... DWORD_TIMES times
    dli     $a4, DWORD_TIMES-1
    1:
    flush_nops
    ld      $t1, 0($t0)
    sd      $t1, 0($t0)
    bne     $a4, $zero, 1b
    daddi   $a4, -1
    flush_nops

    # load and store a cap ...
    dla     $t0, cap1
    # ... CAP_TIMES times
    dli     $a4, CAP_TIMES-1
    1:
    flush_nops
    clcr	$c1, $t0($c0)
    cscr	$c1, $t0($c0)
    bne     $a4, $zero, 1b
    daddi   $a4, -1
    flush_nops

    # wait a bit for counters update
    dli     $a4, DELAY_TIME
    1:
    bne     $a4, $zero, 1b
    daddi   $a4, -1

    # read counters
    getstatcounter  4,  MIPSMEM, BYTE_READ      # in a0
    getstatcounter  5,  MIPSMEM, BYTE_WRITE     # in a1
    getstatcounter  6,  MIPSMEM, HWORD_READ     # in a2
    getstatcounter  7,  MIPSMEM, HWORD_WRITE    # in a3
    getstatcounter  8,  MIPSMEM, WORD_READ      # in a4
    getstatcounter  9,  MIPSMEM, WORD_WRITE     # in a5
    getstatcounter  10, MIPSMEM, DWORD_READ     # in a6
    getstatcounter  11, MIPSMEM, DWORD_WRITE    # in a7
    getstatcounter  12, MIPSMEM, CAP_READ       # in t0
    getstatcounter  13, MIPSMEM, CAP_WRITE      # in t1

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
.align  0
byte1:  .byte   0xAA
.align  1
hword1: .hword  0xBBBB
.align  2
word1:  .word   0xCCCCCCCC
.align  3
dword1: .dword  0xDDDDDDDDDDDDDDDD
.align	5		# Must 256-bit align capabilities
cap1:	.dword	0x0123456789abcdef	# uperms/reserved
		.dword	0x0123456789abcdef	# otype/eaddr
		.dword	0x0123456789abcdef	# base
		.dword	0x0123456789abcdef	# length
