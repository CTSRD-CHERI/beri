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
# Tests to exercise the multiplication ALU instruction.
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

		# MUL.PS (QNaN)
		lui $t2, 0x7F81
		dsll $t2, $t2, 32   # QNaN
		ori $t1, $0, 0x4000
		dsll $t1, $t1, 16   # 2.0
		or $t2, $t2, $t1
		dmtc1 $t2, $f13
		mul.PS $f13, $f13, $f13
		dmfc1 $s3, $f13
		
		# Loading (3, 4.89)
		add $s2, $0, $0
		ori $s2, $s2, 0x4040
		dsll $s2, $s2, 32
		ori $s2, $s2, 0x409C
		dsll $s2, $s2, 16
		ori $s2, $s2, 0x7AE1
		dmtc1 $s2, $f0
		# Loading (4, 47.3)
		add $s2, $0, $0
		ori $s2, $s2, 0x4080
		dsll $s2, $s2, 32
		ori $s2, $s2, 0x423D
		dsll $s2, $s2, 16
		ori $s2, $s2, 0x3333
		dmtc1 $s2, $f1
		# Performing operation
		mul.ps $f0, $f0, $f1
		dmfc1 $s2, $f0
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
