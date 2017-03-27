#-
# Copyright (c) 2015 Michael Roe
# All rights reserved.
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
# Test the CSetBounds instruction.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dla	$t0, data
		csetoffset $c1, $c0, $t0
		dli	$t1, 4
		csetbounds $c1, $c1, $t1

		#
		# The length should be at least 4 bytes.
		# If capabilities are precise, it should be exactly 4 bytes.
		#

		cgetlen	$a0, $c1

		#
		# The offset should point to the array 'data'
		#

		cgetbase $a1, $c1
		cgetoffset $t1, $c1
		daddu	$a1, $a1, $t1
		dsubu	$a1, $a1, $t0

		#
		# The offset should be greater than zero.
		# If capabilities are precise, it should be zero.
		#

		cgetoffset $a2, $c1
		
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align 3
data:
		.dword 0
