#-
# Copyright (c) 2011 Jonathan Woodruff
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
# This test runs a loop of multiplying and dividing numbers with a seed from
# -10 to 10.  We just test that the final results are correct.
#

		.global test
test:		.ent test
		li	$s2, 1
		li	$s1, -10
		li	$s6, 1
loop:
		mul	$v0, $s2, $s1
		sw	$v0, 0($sp)
		beqz	$s1, skip_div
		lw	$v0, 0($sp)
		move	$s7, $v0
		div	$0, $v0, $s1
		teq	$s1, $0, 0x7
		mflo	$v1
		move	$t8, $v1
skip_div:
		addiu	$s1, $s1, 1
		move	$v1, $v0
		movz	$v1, $s6, $v0
		sw	$v1, 0($sp)
		slti	$v0, $s1, 10
		bnez	$v0, loop
		lw	$s2, 0($sp)
end:
		jr	$ra
		nop			# branch-delay slot
		.end	test
