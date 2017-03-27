#-
# Copyright (c) 2012 Michael Roe
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

.include "macros.s"
.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test access to KCC (kernel code capability)
#

sandbox:
		# KCC is $c29
		cgetdefault $c29
		dla $t0, data
		csetoffset $c29, $c29, $t0
		dli $t0, 8
		csetbounds $c29, $c29, $t0
		dli $t0, 0x7f
		candperm $c29, $c29, $t0

		dli $t0, 0
		cldr $a0, $t0($c29)

		cjr $c24
		nop			# branch delay slot

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Restrict the PCC capability that sandbox will run with.
		# Non_Ephemeral, Permit_Execute, Permit_Load, Permit_Store,
		# Permit_Load_Capability, Permit_Store_Capability, 
		# Permit_Store_Ephemeral_Capability, Access_System_Registers.

		dli $t0, 0x7c7f
		candperm $c1, $c0, $t0

		dla     $a0, 0

		dla	$t0, sandbox
		csetoffset $c1, $c1, $t0
		cjalr	$c1, $c24
		nop			# branch delay slot

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align	3
data:		.dword	0x0123456789abcdef


