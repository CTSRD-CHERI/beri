#-
# Copyright (c) 2014 Michael Roe
# All rights reserved.
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

#
# Test for pipeline hazard when a floating point compare is immediately
# followed by a conditional branch. In the MIPS III specification, this is
# not rqquired to work (there must be at least one instruction between the
# compare and the branch, or the behaviour is undefined). In MIPS IV, this
# is required to work.
#
		.text
		.global start
		.ent start
start:     
		mfc0 $t0, $12
		lui $t1, 0x2000		# Enable CP1
		or $t0, $t0, $t1    
		mtc0 $t0, $12 
		nop
		nop
		nop

		
		li $a0, 0

		lui $t0, 0x3f80 	# 1.0
		mtc1 $t0, $f12

		lui $t0, 0x4000		# 2.0	
		mtc1 $t0, $f14

		c.eq.s $f14, $f12
		nop
		nop
		nop
		c.eq.s $f12, $f12
		bc1t L1
		nop	# branch delay slot
		dli $a0, 1
L1:

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
