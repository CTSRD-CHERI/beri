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
# Tests to exercise the division ALU instruction.
#

		.text
		.global start
		.ent start
start:     
		# First enable CP1 
		mfc0 $at, $12
		dli $t1, 1 << 29	# Enable CP1
		or $at, $at, $t1
		dli $t1, 1 << 26        # Put FPU into 64 bit mode
		or $at, $at, $t1
		mtc0 $at, $12 
		nop
		nop
		nop
		nop
		nop
		    
		# Individual tests
		# START TEST
		
		mtc1 $0, $f31

		# DIV.D

		# Loading 3456.3
		add $s0, $0, $0
		ori $s0, $s0, 0x40AB
		dsll $s0, $s0, 16
		ori $s0, $s0, 0x0099
		dsll $s0, $s0, 16
		ori $s0, $s0, 0x9999
		dsll $s0, $s0, 16
		ori $s0, $s0, 0x999A
		dmtc1 $s0, $f0
		# Loading 12.45
		add $s0, $0, $0
		ori $s0, $s0, 0x4028
		dsll $s0, $s0, 16
		ori $s0, $s0, 0xE666
		dsll $s0, $s0, 16
		ori $s0, $s0, 0x6666
		dsll $s0, $s0, 16
		ori $s0, $s0, 0x6666
		dmtc1 $s0, $f1
		# Performing operation
		div.d $f0, $f0, $f1
		dmfc1 $s0, $f0
		     
		# DIV.S
		lui $t0, 0x41A0     # 20.0
		mtc1 $t0, $f10
		lui $t0, 0x40A0     # 5.0
		mtc1 $t0, $f11
		div.S $f10, $f10, $f11
		mfc1 $s1, $f10
		
		# DIV.D (QNaN)
		lui $t2, 0x7FF1     # QNaN
		dsll $t2, $t2, 32
		dmtc1 $t2, $f13
		div.D $f13, $f13, $f13
		dmfc1 $s3, $f13
		
		# DIV.S (Denorm)
		lui $t0, 0x0100
		ctc1 $t0, $f31      # Enable flush to zero on denorm.
		lui $t0, 0x3F80     # 1.0
		mtc1 $t0, $f21
		lui $t1, 0x0001     # Some denormalised single
		mtc1 $t1, $f22
		div.S $f22, $f22, $f21
		mfc1 $s4, $f22

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
		
