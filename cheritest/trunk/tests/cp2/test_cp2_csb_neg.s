#-
# Copyright (c) 2013 Michael Roe
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
# Test csbi with a negative immediate offset
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Make $c1 a capability for the variable 'data'
		#

		dla $t0, data
		cincbase $c1, $c0, $t0

		#
		# Store a value in array 'data' using a negative offset
		#
		dli	$t1, 42
		dli     $t0, 8
		csb	$t1, $t0, -8($c1)

		#
		# Load from 'data' to check the correct value was written
		#

		dla	$t0, data
		clbr	$a0, $t0($c0)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align	5		# 256-bit align
		.dword	0x0
		.dword	0x0
		.dword	0x0
underflow:	.dword	0x0123456789abcdef
data:		.dword	0x0123456789abcdef
overflow:	.dword	0x0123456789abcdef	# check for overflow
		.dword	0x0
		.dword	0x0
		.dword	0x0
