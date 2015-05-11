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
# Unit test that stores words to, and then loads words from, memory.
#
		.text
		.global start
start:
		# Store and load a word into double word storage
		dli	$a0, 0xfedcba98
		dla	$t3, dword
		sw	$a0, 0($t3)
		lwu	$a0, 0($t3)

		# Store and load words with sign extension
		dli	$a1, 1
		dla	$t3, positive
		sw	$a1, 0($t3)
		lw	$a1, 0($t3)

		dli	$a2, -1
		dla	$t3, negative
		sw	$a2, 0($t3)
		lw	$a2, 0($t3)

		# Store and load words without sign extension
		dli	$a3, 1
		dla	$t3, positive
		sw	$a3, 0($t3)
		lwu	$a3, 0($t3)

		dli	$a4, -1
		dla	$t3, negative
		sw	$a4, 0($t3)
		lwu	$a4, 0($t3)

		# Store and load words at non-zero offsets
		dla	$t0, val1
		dli	$a5, 2
		sw	$a5, 4($t0)
		lw	$a5, 4($t0)

		dla	$t1, val2
		dli	$a6, 1
		sw	$a6, -4($t1)
		lw	$a6, -4($t1)

		# Dump registers in the simulator
		mtc0	$v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop

		.data
dword:		.dword	0x0000000000000000
positive:	.word	0x00000000
negative:	.word	0x00000000
val1:		.word	0x00000000
val2:		.word	0x00000000
