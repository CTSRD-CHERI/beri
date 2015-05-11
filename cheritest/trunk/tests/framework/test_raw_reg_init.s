#-
# Copyright (c) 2011 Robert N. M. Watson
# All rights reserved.
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
# This unit tests that registers can be properly initialised from software.
#

		.global start
start:
		move	$at, $zero
		move	$v0, $zero
		move	$v1, $zero
		move	$a0, $zero
		move	$a1, $zero
		move	$a2, $zero
		move	$a3, $zero
		move	$a4, $zero
		move	$a5, $zero
		move	$a6, $zero
		move	$a7, $zero
		move	$t0, $zero
		move	$t1, $zero
		move	$t2, $zero
		move	$t3, $zero
		move	$s0, $zero
		move	$s1, $zero
		move	$s2, $zero
		move	$s3, $zero
		move	$s4, $zero
		move	$s5, $zero
		move	$s6, $zero
		move	$s7, $zero
		move	$t8, $zero
		move	$t9, $zero
		move	$k0, $zero
		move	$k1, $zero
		move	$gp, $zero
		move	$sp, $zero
		move	$fp, $zero
		move	$ra, $zero

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop
