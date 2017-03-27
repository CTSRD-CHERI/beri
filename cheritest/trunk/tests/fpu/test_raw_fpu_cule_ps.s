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
# Tests to exercise the comparison (unordered or less than or equal) ALU 
# instructions.
#

		.text
		.global start
		.ent start
start:     
		mfc0 $at, $12
		dli $t1, 1 << 29	# Enable CP1
		or $at, $at, $t1
		dli $t1, 1 << 26	# Put FPU into 64 bit mode
		or $at, $at, $t1
		mtc0 $at, $12 
		nop
		nop
		nop
		nop
		nop
    
		# Clear FCSR

		mtc1 $0, $f31

		# Setup parameters
		    
		lui $t0, 0x4000     # 2.0
		mtc1 $t0, $f3
		lui $t0, 0x3F80     # 1.0
		mtc1 $t0, $f4
		lui $t0, 0x4000     
		dsll $t0, $t0, 32
		dmtc1 $t0, $f13
		ori $t1, $0, 0x3F80
		dsll $t1, $t1, 16
		or $t0, $t0, $t1    # 2.0, 1.0
		dmtc1 $t0, $f23
		lui $t0, 0x3FF0
		dsll $t0, $t0, 32
		dmtc1 $t0, $f14
		ori $t1, $0, 0x4000
		dsll $t1, $t1, 16
		or $t0, $t0, $t1    # 1.0, 2.0
		dmtc1 $t0, $f24

		# Individual tests
		
		# C.ULE.PS (True)
		c.ule.ps $f23, $f23
		cfc1 $s2, $f25
		ctc1 $0, $f31
		
		# C.ULE.PS
		c.ule.ps $f24, $f23
		cfc1 $s5, $f25
		ctc1 $0, $f31
		
		# C.ULE.PS
		c.ule.ps $f23, $f24
		cfc1 $a0, $f25
		ctc1 $0, $f31
		
		# C.ULE.PS (QNaN)
		c.ule.ps $f5, $f5
		cfc1 $a3, $f25
		
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
