#-
# Copyright (c) 2011 William M. Morland
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
# Unit test that stores partial words to, and the loads full words from,
# memory.
#
		.text
		.global start
start:
		dli	$a0, 0xfedcba98
		dla	$t0, dword
		swr	$a0, 0($t0)
		ld	$a0, 0($t0)

		dli	$a1, 0xfedcba98
		swr	$a1, 4($t0)
		ld	$a1, 0($t0)

		dli	$a2, 0xfedcba98
		swr	$a2, 2($t0)
		ld	$a2, 0($t0)

		dli	$a3, 0xfedcba98
		swr	$a3, 7($t0)
		ld	$a3, 0($t0)

		dli	$a4, 0xfedcba98
		swr	$a4, 5($t0)
		ld	$a4, 0($t0)

		# Dump registers in the simulator
		mtc0	$v0, $26
		nop
		nop

		# Terminate the simulator
		mtc0	$v0, $23
end:
		b	end
		nop

		.data
dword:		.dword 0x0000000000000000
