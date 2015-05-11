#-
# Copyright (c) 2012 Ben Thorner
# Copyright (c) 2013 Colin Rothwell
# Copyright (c) 2013 Michael Roe
# All rights reserved.
#
# This software was developed by Ben Thorner as part of his summer internship
# and Colin Rothwell as part of his final year undergraduate project.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
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

# Test conversion works in the coprocessor
    
		.text
		.global start
		.ent start

start:
		# Enable CP1
		dli $t1, 1 << 29
		or $at, $at, $t1
		mtc0 $at, $12
		nop
		nop
		nop
		nop

		li $t0, 1
		mtc1 $t0, $f0
		cvt.s.w $f0, $f0
		mfc1 $a0, $f0

		li $t0, 33558633 # 2 ^ 25 + 4201 - can't maintain precision
		mtc1 $t0, $f1
		cvt.s.w $f1, $f1
		mfc1 $a1, $f1

		li $t0, -23
		mtc1 $t0, $f2
		cvt.s.w $f2, $f2
		mfc1 $a2, $f2

		li $t0, 0
		mtc1 $t0, $f2
		cvt.s.w $f2, $f2
		mfc1 $a3, $f2

		# Dump reigsters and terminate
		mtc0 $at, $26
		nop
		nop
		
		mtc0 $at, $23

end:
		b end
		nop
		.end start
