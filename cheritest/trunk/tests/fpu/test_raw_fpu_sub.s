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
# Tests to exercise the subtraction ALU instruction.
#

		.text
		.global start
		.ent start
start:     
		# First enable CP1 
		dli $t1, 1 << 29
		or $at, $at, $t1    # Enable CP1    
		mtc0 $at, $12 
		nop
		nop
		nop
		nop
		nop

		# Individual tests
		# START TEST
		
		# SUB.D
		lui $t0, 0x4000
		dsll $t0, $t0, 32   # 2.0
		lui $t1, 0x3FF0
		dsll $t1, $t1, 32
		dmtc1 $t0, $f15
		dmtc1 $t1, $f16
		sub.D $f11, $f15, $f16
		dmfc1 $s0, $f11
 
		# SUB.S
		lui $t0, 0x4000     # 2.0
		lui $t1, 0x4080     # 4.0
		dmtc1 $t0, $f5
		dmtc1 $t1, $f6
		sub.S $f5, $f5, $f6
		dmfc1 $s1, $f5

		# Loading (75, -32)
		add $s2, $0, $0
		ori $s2, $s2, 0x4296
		dsll $s2, $s2, 32
		ori $s2, $s2, 0xC200
		dsll $s2, $s2, 16
		dmtc1 $s2, $f0
		# Loading (50, -64)
		add $s2, $0, $0
		ori $s2, $s2, 0x4248
		dsll $s2, $s2, 32
		ori $s2, $s2, 0xC280
		dsll $s2, $s2, 16
		dmtc1 $s2, $f1
		# Performing operation
		sub.ps $f0, $f0, $f1
		dmfc1 $s2, $f0

		# SUB.PS (QNaN)
		lui $t2, 0x7F81
		dsll $t2, $t2, 32   # QNaN
		ori $t1, $0, 0x4000
		dsll $t1, $t1, 16   # 2.0
		or $t2, $t2, $t1
		dmtc1 $t2, $f13
		sub.PS $f13, $f13, $f13
		dmfc1 $s3, $f13
		
		# SUB.S (Denorm)
		lui $t0, 0x0100
		ctc1 $t0, $f31      # Enable flush to zero on denorm.
		lui $t1, 0x1
		dmtc1 $t1, $f22
		sub.S $f22, $f22, $f22
		dmfc1 $s4, $f22        


		# END TEST
       
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
		
		
