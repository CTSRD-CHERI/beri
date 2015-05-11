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
# Tests to exercise the pairwise merging instructions.
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
		nop

		# Individual tests
		
		# PLL.PS
		lui $t0, 0x3F80
		mtc1 $t0, $f7
		lui $t0, 0x4000
		mtc1 $t0, $f8
		pll.PS $f7, $f7, $f8
		dmfc1 $a0, $f7
		
		# PLU.PS
		lui $t0, 0xBF80
		mtc1 $t0, $f13
		lui $t0, 0x3F80
		dsll $t0, $t0, 32
		dmtc1 $t0, $f23
		plu.PS $f14, $f13, $f23
		dmfc1 $a1, $f14
		
		# PUL.PS
		lui $t0, 0x7F80
		dsll $t0, $t0, 32
		dmtc1 $t0, $f5
		mtc1 $0, $f6
		pul.PS $f5, $f5, $f6
		dmfc1 $a2, $f5
		
		# PUU.PS
		puu.PS $f5, $f5, $f23
		dmfc1 $a3, $f5
		
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
