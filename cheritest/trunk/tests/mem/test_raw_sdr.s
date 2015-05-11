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

		.global start
start:
		dla	$a0, dword

		dli	$a1, 0xfedcba9876543210
		sdr	$a1, 0($a0)
		ld	$a1, 0($a0)

		dli	$a2, 0xfedcba9876543210
		sdr	$a2, 1($a0)
		ld	$a2, 0($a0)

		dli	$a3, 0xfedcba9876543210
		sdr	$a3, 2($a0)
		ld	$a3, 0($a0)

		dli	$a4, 0xfedcba9876543210
		sdr	$a4, 3($a0)
		ld	$a4, 0($a0)

		dli	$a5, 0xfedcba9876543210
		sdr	$a5, 4($a0)
		ld	$a5, 0($a0)

		dli	$a6, 0xfedcba9876543210
		sdr	$a6, 5($a0)
		ld	$a6, 0($a0)

		dli	$a7, 0xfedcba9876543210
		sdr	$a7, 6($a0)
		ld	$a7, 0($a0)

		dli	$t0, 0xfedcba9876543210
		sdr	$t0, 7($a0)
		ld	$t0, 0($a0)

		dli	$t1, 0xfedcba9876543210
		sdr	$t1, 8($a0)
		ld	$t1, 8($a0)

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
dword:		.dword 0x0000000000000000
