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
		mfc0 $t0, $12
		dli $t1, 1 << 29	# Enable CP1
		or $t0, $t0, $t1
		dli $t1, 1 << 26        # Put FPU into 64 bit mode
		or $t0, $t0, $t1
		mtc0 $t0, $12
		nop
		nop
		nop


		# BEGIN TESTS
		dla $t0, word1
		dla $t1, double1
		li $t2, 4 # word single offset
		li $t3, 8 # double single offset

		lui $a0, 0xABCD
		lui $a1, 0x4321
		mtc1 $a0, $f0
		mtc1 $a1, $f1
		swxc1 $f0, $0($t0)
		swxc1 $f1, $t2($t0)
		lwxc1 $f2, $0($t0)
		lwxc1 $f3, $t2($t0)
		mfc1 $s0, $f2
		mfc1 $s1, $f3

		lui $a0, 0xFEED
		dsll $a0, $a0, 32
		lui $a1, 0xFACE
		dsll $a1, $a1, 16 
		dmtc1 $a0, $f0
		dmtc1 $a1, $f1
		sdxc1 $f0, $0($t1)
		sdxc1 $f1, $t3($t1)
		ldxc1 $f2, $0($t1)
		ldxc1 $f3, $t3($t1)
		dmfc1 $s2, $f2
		dmfc1 $s3, $f3
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
word1:      	.word   0x00000000
word2:		.word   0x00000000
double1:	.dword  0x0000000000000000
double2:	.dword  0x0000000000000000
