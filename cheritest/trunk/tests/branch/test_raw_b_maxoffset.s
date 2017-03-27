#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2012 Robert M. Norton
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
# Test a simple forward branch with maximum (positive) offset.  $t0 is
# assigned before the branch, $t1 in the branch-delay slot, $t2 should
# be skipped, and $t3 at the branch target.

		.global start
start:
		li	$a0, 0
		li	$a1, 0
		li	$a2, 0
		li	$a3, 0

		dla $s0, branch        # load the address of the branch
		dli $t0, 0x8000000     # set the distance we want to move the target
		dsub $s1, $s0, $t0     # generate the target address
		lw $s2,16($s0)
		sw $s2,16($s1)
		lw $s2,20($s0)
		sw $s2,20($s1)
		lw $s2,24($s0)
		sw $s2,24($s1)
		lw $s2,28($s0)
		sw $s2,28($s1)
		lw $s2,32($s0)
		sw $s2,32($s1)
		lw $s2,36($s0)
		sw $s2,36($s1)
		lw $s2,40($s0)
		sw $s2,40($s1)
		lw $s2,44($s0)
		sw $s2,44($s1)
		lw $s2,48($s0)
		sw $s2,48($s1)
		lw $s2,52($s0)
		sw $s2,52($s1)
		lw $s2,56($s0)
		sw $s2,56($s1)
		dli $t0, 0x801fff4     # set the distance we want to move the branch, note 4 not c because branch is relative to branch delay slot
		dsub $s1, $s0, $t0     # generate the target address
		lw $s2, 0($s0)         # move the words to the target
		sw $s2, 0($s1)
		lw $s2, 4($s0)
		sw $s2, 4($s1)
		lw $s2, 8($s0)
		sw $s2, 8($s1)
		lw $s2,12($s0)
		sw $s2,12($s1)
		sync
		nop										# some nops to give the data time to propagate
		nop                   # before the instruction fetch.
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		jr $s1                 # jump to the branch
		nop
branch:
		li	$a0, 1
		b	0x1fffc
		li	$a1, 1		# branch-delay slot
		li	$a2, 1
branch_target:
		li	$a3, 1

		# Dump registers in the simulator
		mtc0	$v0, $26

		# Terminate the simulator
		mtc0	$v0, $23
		dla	$t0, end
		jr	$t0
		nop
end:
		b end
		nop
