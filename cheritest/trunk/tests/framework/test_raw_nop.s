#-
# Copyright (c) 2011 Robert N. M. Watson
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

		.global start
start:
		# Set all registers to known values so that we can check they
		# are unmodified after the NOP.
		dli	$zero, 0		# no-op
		dli	$at, 1
		dli	$v0, 2
		dli	$v1, 3
		dli	$a0, 4
		dli	$a1, 5
		dli	$a2, 6
		dli	$a3, 7
		dli	$a4, 8
		dli	$a5, 9
		dli	$a6, 10
		dli	$a7, 11
		dli	$t0, 12
		dli	$t1, 13
		dli	$t2, 14
		dli	$t3, 15
		dli	$s0, 16
		dli	$s1, 17
		dli	$s2, 18
		dli	$s3, 19
		dli	$s4, 20
		dli	$s5, 21
		dli	$s6, 22
		dli	$s7, 23
		dli	$t8, 24
		dli	$t9, 25
		dli	$k0, 26
		dli	$k1, 27
		dli	$gp, 28
		dli	$sp, 29
		dli	$fp, 30
		dli	$ra, 31

		# Perform a NOP; we can then check if any registers changed.
		nop

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop
