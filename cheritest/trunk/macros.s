#-
# Copyright (c) 2013-2015 Robert M. Norton
# Copyright (c) 2015 Jonathan Woodruff
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

# Macro for declaring an exported function. Just saves some typing.
.macro global_func name
        .ent \name
        .global \name
\name :
.endm

# Decrement stack pointer by 32 and save stack and
# frame pointer.
.macro prelude
	daddu	$sp, $sp, -32
	sd	$ra, 24($sp)
	sd	$fp, 16($sp)
	daddu	$fp, $sp, 32
.endm

.macro epilogue
        ld      $ra, 24($sp)
        ld      $fp, 16($sp)
        daddu   $sp, 32
.endm
        
# The maximum number of hw threads (threads*cores) we expect for
# any configuration. This is so that we can allocate a conservative
# amount of space for static per thread structures. May need to
# increase in future.
max_thread_count = 32

# Create the data structure used for thread barriers.
# Should be placed in .data section.
# No particular alignment is required.
.macro mkBarrier
        .rept max_thread_count
        .byte 0
        .endr
.endm

.macro cincbase dest, source, offset
        #cgetoffset $t9, \source
        cgetlen    $at, \source
        dsubu      $at, $at, \offset
        csetoffset \dest, \source, \offset
        csetbounds \dest, \dest, $at
        #csetoffset \dest, \dest, $t9
.endm

.macro csetlen dest, source, offset
        #cgetoffset $at, \source
        #csetoffset \dest, \source, $0
        csetbounds \dest, \source, \offset
        #csetoffset \dest, \dest, $at
.endm
