#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2015 Michael Roe
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
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

.include "macros.s"
.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test that if we set non-default values in a capability register, cmove to
# another register, that we can read the same non-default values back.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Load values into c2
		#

		cgetdefault $c2
		dla	$t0, data
		csetoffset $c2, $c2, $t0
		dli	$t0, 8
		csetbounds $c2, $c2, $t0
		dli	$t0, 0xff
		candperm $c2, $c2, $t0
		dli	$t0, 5
		csetoffset $c2, $c2, $t0

		#
		# Move to c3
		#

		cmove	$c3, $c2

		#
		# Extract values
		#

		cgetperm	$a0, $c3
		cgetoffset	$a1, $c3
		cgetbase	$a2, $c3
		cgetlen 	$a3, $c3

		#
		# Compute the difference between $c2.base and $c3.base
		# Should be zero.
		#

		cgetbase	$t0, $c2
		dsubu		$a2, $a2, $t0

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align 5
data:		.dword 0
