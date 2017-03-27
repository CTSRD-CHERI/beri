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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Copy a capability as data, and then read its fields using CGetLen etc.
# This will clear the tag bit, but operating system code (e.g. paging) might
# rely on the other fields being copied correctly.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		cgetdefault $c1
		dla	$t0, data
		csetoffset $c1, $c1, $t0
		dli	$t0, 8
		csetbounds $c1, $c1, $t0
		dli	$t0, 0x3
		candperm $c1, $c1, $t0
		dli	$t0, 5
		csetoffset $c1, $c1, $t0

		dla	$t0, cap1
		cscr	$c1, $t0($c0)

		dla	$t1, cap2
		ld	$t2, 0($t0)
		sd	$t2, 0($t1)
		ld	$t2, 8($t0)
		sd	$t2, 8($t1)
		ld	$t2, 16($t0)
		sd	$t2, 16($t1)
		ld	$t2, 24($t0)
		sd	$t2, 24($t1)

		clcr	$c2, $t1($c0)

		cgettag $a0, $c2

		cgetperm $a1, $c2
		cgetperm $t2, $c1
		xor	$a1, $a1, $t2

		cgetbase $a2, $c2
		cgetbase $t2, $c1
		xor	$a2, $a2, $t2

		cgetlen $a3, $c2
		cgetlen $t2, $c1
		xor	$a3, $a3, $t2

		cgetoffset $a4, $c2
		cgetoffset $t2, $c1
		xor	$a4, $a4, $t2

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data

		.align 3
data:		.dword 0

		.align 5
cap1:		.dword 0
		.dword 0
		.dword 0
		.dword 9

		.align 5
cap2:		.dword 0
		.dword 0
		.dword 0
		.dword 9
