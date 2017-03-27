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

#
# Tests to exercise the conditional GPR move instructions.
#

		.text
		.global start
		.ent start
start:     
		# First enable CP1 
		mfc0 $t0, $12
		dli $t1, 1 << 29
		or $t0, $t0, $t1
		mtc0 $t0, $12
		nop
		nop
		nop

		# Individual tests
		
		# MOVN.S (True)
		lui $t1, 0x4100
		mtc1 $t1, $f4
		mtc1 $zero, $f3
		movn.s $f3, $f4, $t1
		mfc1 $a0, $f3
		
		# MOVN.D (True)
		lui $t2, 0x4000
		dsll $t2, $t2, 32
		dmtc1 $t2, $f7
		dmtc1 $zero, $f3
		movn.d $f3, $f7, $t2
		dmfc1 $a1, $f3
		
		# MOVN.S (False)
		lui $t1, 0x4100
		mtc1 $t1, $f4
		mtc1 $zero, $f3
		movn.s $f3, $f4, $zero
		mfc1 $a2, $f3
		
		# MOVN.D (False)
		lui $t2, 0x4000
		dsll $t2, $t2, 32
		dmtc1 $t2, $f7
		dmtc1 $zero, $f3
		movn.d $f3, $f7, $zero
		dmfc1 $a3, $f3
		
		# MOVZ.S (True)
		lui $t1, 0x4100
		mtc1 $t1, $f4
		mtc1 $zero, $f3
		movz.s $f3, $f4, $zero
		mfc1 $s0, $f3
		
		# MOVZ.D (True)
		lui $t2, 0x4000
		dsll $t2, $t2, 32
		dmtc1 $t2, $f7
		movz.d $f3, $f7, $0
		dmfc1 $s1, $f3
		
		# MOVZ.S (False)
		lui $t1, 0x4100
		mtc1 $t1, $f4
		mtc1 $zero, $f3
		movz.s $f3, $f4, $t1
		mfc1 $s2, $f3
		
		# MOVZ.D (False)
		lui $t2, 0x4000
		dsll $t2, $t2, 32
		dmtc1 $t2, $f7
		dmtc1 $zero, $f3
		movz.d $f3, $f7, $t2
		dmfc1 $s3, $f3
		
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
		
		
