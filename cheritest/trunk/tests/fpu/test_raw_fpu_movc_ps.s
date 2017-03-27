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
		dli $t1, 1 << 29
		or $at, $at, $t1    # Enable CP1    
		mtc0 $at, $12 

		# Individual tests
		
		li $t0, 0x3f80
		dsll $t0, $t0, 32
		ori $t0, $t0, 0x4000
		dsll $t0, $t0, 16
		dmtc1 $t0, $f2

		dli $t2, 1

		# MOVN.PS (True)
		dmtc1 $zero, $f0
		movn.ps $f0, $f2, $t2
		dmfc1 $a0, $f0
		
		# MOVN.PS (False)
		dmtc1 $zero, $f0
		movn.ps $f0, $f2, $zero
		dmfc1 $a1, $f0
		
		# MOVZ.PS (True)
		dmtc1 $zero, $f0
		movz.ps $f0, $f2, $zero
		dmfc1 $a2, $f0
		
		# MOVZ.PS (False)
		dmtc1 $zero, $f0
		movz.ps $f0, $f2, $t2
		dmfc1 $a3, $f0
		
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
