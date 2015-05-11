#-
# Copyright (c) 2013 Michael Roe
# All rights reserved.
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
# Test double-precision division when the FPU is in 32-bit mode
#
		.text
		.global start
		.ent start
start:     
		mfc0 $t0, $12
		dli $t1, 1 << 29	# Enable CP1
		or $t0, $t0, $t1    
		li $t1, 1 << 26		# Put FPU into 32 bit mode
		nor $t1, $t1, $t1
		and $t0, $t0, $t1
		mtc0 $t0, $12 
		nop
		nop
		nop

		
		# load 3456.3 into $f12
		lui $t0, 0x40ab
		ori $t0, $t0, 0x0099
		mtc1 $t0, $f13
		lui $t0, 0x9999
		ori $t0, $t0, 0x999a
		mtc1 $t0, $f12
		# load 12.45 into $f14
		lui $t0, 0x4028
		ori $t0, $t0, 0xe666
		mtc1 $t0, $f15
		lui $t0, 0x6666
		ori $t0, $t0, 0x6666
		mtc1 $t0, $f14
		div.d $f12, $f12, $f14
		mfc1 $a0, $f12
		mfc1 $a1, $f13


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
