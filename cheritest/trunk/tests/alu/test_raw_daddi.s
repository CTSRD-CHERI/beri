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
# Simple test for daddi -- not intended to rigorously check arithmetic
# correctness, rather, register behaviour and instruction interpretation.
# Overflow is left to higher-level tests, as exceptions are implied.
#

		.global start
start:
		#
		# daddi with independent input and output; preserve input for
		# test framework so we can check it wasn't improperly
		# modified.
		#
		dli	$a0, 1
		daddi	$a1, $a0, 1

		#
		# daddi with input as the output
		#
		dli	$a2, 1
		daddi	$a2, $a2, 1

		#
		# Feed output of one straight into the input of another.
		#
		dli	$a3, 1
		daddi	$a3, $a3, 1
		daddi	$a3, $a3, 1

		#
		# check that immediate is sign-extended
		#
		dli	$a4, 1
		daddi	$a4, $a4, -1

		#
		# simple exercises for signed arithmetic
		#
		dli	$a5, 1
		daddi	$a5, $a5, -1	# to zero

		dli	$a6, -1
		add	$a6, $a6, -1	# to negative

		dli	$a7, -1
		daddi	$a7, $a7, 2	# to positive

		dli	$s0, 1
		add	$s0, $s0, -2	# to negative

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop
