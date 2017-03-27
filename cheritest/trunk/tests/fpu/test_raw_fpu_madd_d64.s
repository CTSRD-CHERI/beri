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
# Test MADD.D and MSUB.D with the FPU in 64-bit mode.
#

		.global start
start:
		# Enable CP1
	        mfc0    $at, $12
		dli	$t1, 1 << 29
		or      $at, $at, $t1 	
		dli	$t1, 1 << 26	# Put FPU into 64 bit mode
		or	$at, $at, $t1
	        mtc0    $at, $12
	        nop
	        nop
	        nop
	        nop
	        nop
	        
		li	$t0, 0x3ff0	# 1.0
		dsll	$t0, $t0, 48
		dmtc1	$t0, $f1

		li	$t0, 0x4000	# 2.0
		dsll	$t0, $t0, 48
		dmtc1	$t0, $f2

		li	$t0, 0x4008	# 3.0
		dsll	$t0, $t0, 48
		dmtc1	$t0, $f3

		dmtc1	$zero, $f0
		madd.d	$f0, $f1, $f2, $f3
		dmfc1	$a0, $f0

		dmtc1	$zero, $f0
		msub.d	$f0, $f1, $f2, $f3
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
