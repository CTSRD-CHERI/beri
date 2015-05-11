#-
# Copyright (c) 2012 Ben Thorner
# Copyright (c) 2013 Colin Rothwell
# All rights reserved.
#
# This software was developed by Ben Thorner as part of his summer internship
# and Colin Rothwell as part of his final year undergraduate project.
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

		.text
		.global start
		.ent start

start:
		# Enable CP1
		mfc0 $t0, $12
		dli $t1, 1 << 29
		or $t0, $t0, $t1
		mtc0 $t0, $12
		nop
		nop
		nop
		nop
		nop

		# BEGIN TESTS

		dla $t0, preload
		ldc1 $f0, 0($t0)
		dmfc1 $s0, $f0

		dla $t0, loc1
		lui $t1, 0xBED0
		dsll $t1, 32
		dmtc1 $t1, $f0
		sdc1 $f0, 0($t0)
		ldc1 $f1, 0($t0)
		dmfc1 $s1, $f1
		lui $t1, 0x1212
		dsll $t1, 32
		dmtc1 $t1, $f0
		sdc1 $f0, 8($t0)
		ldc1 $f2, 8($t0)
		dmfc1 $s2, $f2

		# END TESTS

		# Dump registers on the simulator (gxemul dumps regs on exit)
		mtc0 $at, $26
		nop
		nop

		# Terminate the simulator
		mtc0 $at, $23
end:
		b end
		nop
		.end start
		

		.data
preload:	.dword   0x0123456789abcdef
loc1:		.dword   0x0000000000000000
loc2:		.dword   0x0000000000000000
