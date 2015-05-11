#-
# Copyright (c) 2011 William M. Morland
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
# Test the SRLV (Shift Right Logical Variable) instruction.
#

		.global start
start:
		li	$t0, 0x76543210
		li	$t1, 0
		srlv	$a0, $t0, $t1
		li	$t1, 1
		srlv	$a1, $t0, $t1
		li	$t1, 16
		srlv	$a2, $t0, $t1
		li	$t1, 31
		srlv	$a3, $t0, $t1

		li	$t0, 0xfedcba98
		li	$t1, 0
		srlv	$a4, $t0, $t1
		li	$t1, 1
		srlv	$a5, $t0, $t1
		li	$t1, 16
		srlv	$a6, $t0, $t1
		li	$t1, 31
		srlv	$a7, $t0, $t1

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop
