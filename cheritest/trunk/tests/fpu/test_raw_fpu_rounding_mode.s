#-
# Copyright (c) 2016 Michael Roe
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
# Test that the FPU supports the "round towards +infinity" rounding mode,
# also known as RP or FE_UPWARDS.
#

		.global start
start:
		mfc0 $t0, $12
		li $t1, 1 << 29			# Enable CP1
		or $t0, $t0, $t1    
		mtc0 $t0, $12 

		#
		# Set rounding mode to FE_UPWARD
		#

		cfc1 $t0, $31
		dli $t1, 0x3
		nor $t1, $t1, $t1
		and $t0, $t0, $t1
		dli $t1, 0x2
		or $t0, $t0, $t1
		ctc1 $t0, $31
		nop
		nop
		nop

		dli $t0, 0x4b800000	# 2^24
		mtc1 $t0, $f0

		lui $t0, 0x3f80		# 1.0
		mtc1 $t0, $f1

		add.s $f0, $f0, $f1

		mfc1 $a0, $f0
		
		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop
