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
		nop
		nop
		nop
		nop
		nop

		# Individual tests
		
		# Clear all FCCs
		ctc1 $0, $f31
		
		li $t1, 0x4100
		dsll $t1, $t1, 32
		ori $t1, $t1, 0x4000
		dsll $t1, $t1, 16

		# MOVF.PS (True)
		dmtc1 $t1, $f5
		dmtc1 $zero, $f3
		movf.ps $f3, $f5, $fcc0
		dmfc1 $a0, $f3
		
		# MOVT.PS (False)
		dmtc1 $t1, $f5
		dmtc1 $zero, $f3
		movt.ps $f3, $f5, $fcc0
		dmfc1 $a1, $f3
		
		# Set FCCs
		lui $t0, 0x0F80
		ctc1 $t0, $f31
		
		# MOVF.PS (False)
		dmtc1 $t1, $f5
		dmtc1 $zero, $f3
		movf.ps $f3, $f5, $fcc0
		dmfc1 $a2, $f3
		
		# MOVT.PS (True)
		dmtc1 $t1, $f5
		dmtc1 $zero, $f3
		movt.ps $f3, $f5, $fcc0
		dmfc1 $a3, $f3
		
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
