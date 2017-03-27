#-
# Copyright (c) 2015 Michael Roe
# All rights reserved.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
# project, funded by EPSRC grant EP/K008528/1.
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
# Short block comment describing the test: what instruction/behaviour are we
# investigating; what properties are we testing, what properties are deferred
# to other tests?  What might we want to test as well in the future?
#

		.global start
start:
		# Enable CP1
	        mfc0    $at, $12
		dli	$t1, 1 << 29	# Enable CP1
		or      $at, $at, $t1 	
		dli	$t1, 1 << 26	# Put FPU into 64 bit mode
		or	$at, $at, $t1
	        mtc0    $at, $12
	        nop
	        nop
	        nop
	        nop
	        nop
	        
		#
		# Load $t0 with a value that is not a sign-extension of a 32-bit
		# value
		#

		li	$t0, 0x8000
		dsll	$t0, $t0, 16

		#
		# Clear all 64 bits of $f0
		#

		dmtc1	$zero, $f0

		#
		# Do a 32-bit move of $t0 into $f0. The upper bits of $f0 are
		# undefined according to the MIPS ISA.
		#

		mtc1	$t0, $f0

		#
		# Read all 64 bits of $f0, including the undefined upper bits.
		#

		dmfc1	$a0, $f0

		#
		# Repeat, clearing $f0 to all 1's first
		#

		dli	$t1, -1
		dmtc1	$t1, $f0
		mtc1	$t0, $f0
		dmfc1	$a1, $f0
		

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop
