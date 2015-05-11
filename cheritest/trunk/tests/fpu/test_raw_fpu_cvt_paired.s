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
# Test conversion works in the coprocessor
#
    
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

		# START TEST

		# Convert PS to S
		li $a0, 0xDDDDDDDD
		li $a1, 0x33333333 
		dsll $a0, $a0, 32
		or $a0, $a0, $a1
		dmtc1 $a0, $f0
		cvt.s.pl $f1, $f0
		cvt.s.pu $f2, $f0
		dmfc1 $a0, $f1
		dmfc1 $a1, $f2
 
		# END TEST

		# Dump reigsters and terminate
		mtc0 $at, $26
		nop
		nop
		
		mtc0 $at, $23

end:
		b end
		nop
		.end start
