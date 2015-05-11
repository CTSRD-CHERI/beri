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

#
# Simple test for dadd -- not intended to rigorously check arithmetic
# correctness, rather, register behaviour and instruction interpretation.
# Overflow is left to higher-level tests, as exceptions are implied.
#

		.global start
start:
		#
		# dadd with independent inputs and outputs; preserve inputs
		# for test framework so we can check they weren't improperly
		# modified.
		#
		dli	$s3, 1
		dli	$s4, 2
		dadd	$a0, $s3, $s4

		#
		# dadd with first input as the output
		#
		dli	$t0, 1
		dli	$a1, 2
		dadd	$a1, $a1, $t0

		#
		# dadd with second input as the output
		#
		dli	$t0, 1
		dli	$a2, 2
		dadd	$a2, $t0, $a2

		#
		# dadd with both inputs the same as the output
		#
		dli	$a3, 1
		dadd	$a3, $a3, $a3

		#
		# Feed output of one straight into the input of another.
		#
		dli	$t0, 1
		dli	$t1, 2
		dli	$t2, 3
		dadd	$t3, $t0, $t1
		dadd	$a4, $t3, $t2

		#
		# simple exercises for signed arithmetic
		#
		dli	$t0, 1
		dli	$t1, -1
		dadd	$a5, $t0, $t1	# to zero

		dli	$t0, -1
		dli	$t1, -1
		dadd	$a6, $t0, $t1	# to negative

		dli	$t0, -1
		dli	$t1, 2
		dadd	$a7, $t0, $t1	# to positive

		dli	$t0, 1
		dli	$t1, -2
		dadd	$s0, $t0, $t1	# to negative

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop
