#-
# Copyright (c) 2011 Robert N. M. Watson
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
# Unit test that loads bytes from memory.
#
		.text
		.global start
start:
		ld $s0, buloc
		lbu $s1, 0($s0)

		# Load a byte from double word storage
		lbu	$a0, dword

		# Load bytes with sign extension
		lb	$a1, positive
		lb	$a2, negative

		# Load bytes without sign extension
		lbu	$a3, positive
		lbu	$a4, negative

		# Load bytes at non-zero offsets
		dla	$t0, val1
		lb	$a5, 1($t0)
		dla	$t1, val2
		lb	$a6, -1($t1)

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
dword:		.dword	0xfedcba9876543210
positive:	.byte	0x7f
negative:	.byte	0xff
val1:		.byte	0x01
val2:		.byte	0x02
buloc:		.dword	0x900000007f002108
