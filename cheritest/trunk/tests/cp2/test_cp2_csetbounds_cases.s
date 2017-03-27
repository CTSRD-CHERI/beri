#-
# Copyright (c) 2015 Michael Roe
# Copyright (c) 2016 Jonathan Woodruff
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
# Test the CSetBounds instruction with cases discovered in the wild.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32
		
		# $a0 will be non-zero if any test fails.
		move $a0, $0

		#
		# Case one, found by Robert Watson.
		#

		# Stage 1 setting up the initial capability.

		dli	$t0, 0x1600f4000
		csetoffset $c1, $c0, $t0
		dli	$t1, 0x20000
		csetbounds $c1, $c1, $t1
		# Get and assert that the base and length are what we set.
		cgetbase $v0, $c1
		bne $v0, $t0, error
		nop
		cgetlen $v1, $c1
		bne $v1, $t1, error
		nop
		# Stage 2 attempt the failing csetbounds.
		dli	$t3, 0x1ffe0
		daddu $t0, $t0, $t3 # Add this offset to the previous base to get new base.
		csetoffset $c1, $c1, $t3
		dli	$t1, 0x10
		csetbounds $c1, $c1, $t1
		# Get and assert that the base and length are what we set.
		cgetbase $v0, $c1
		bne $v0, $t0, error
		nop
		cgetlen $v1, $c1
		bne $v1, $t1, error
		nop
		cbtu $c1, error
		nop
		
		#
		# Case two, found by Robert Watson.
		#

		# Stage 1 setting up the initial capability.
		dli	$t0, 0x7fffffe8c0
		csetoffset $c1, $c0, $t0
		dli	$t1, 0x0
		csetbounds $c1, $c1, $t1
		# Get and assert that the base and length are what we set.
		cgetbase $v0, $c1
		bne $v0, $t0, error
		nop
		cgetlen $v1, $c1
		bne $v1, $t1, error
		nop
		# Stage 2 attempt the failing csetbounds.
		dli	$t3, 0x0
		daddu $t0, $t0, $t3 # Add this offset to the previous base to get new base.
		csetoffset $c1, $c1, $t3
		# Get and assert that the base and length are what we set.
		cgetbase $v0, $c1
		bne $v0, $t0, error
		nop
		cbtu $c1, error
		nop
		
		#
		# Case three, found by Jonathan Woodruff.
		#

		# Stage 1 setting up the initial capability.
		dli	$t0, 0x16022e000
		csetoffset $c1, $c0, $t0
		dli	$t1, 0x400000
		csetbounds $c1, $c1, $t1
		# Get and assert that the base and length are what we set.
		cgetbase $v0, $c1
		bne $v0, $t0, error
		nop
		cgetlen $v1, $c1
		bne $v1, $t1, error
		nop
		# Stage 2 attempt the failing inc offsets.
		dli	$t3, 0x7fe940
		cincoffset $c1, $c1, $t3
		dli	$t3, 0xfffffffffffff0e8
		cincoffset $c1, $c1, $t3
		# Get and assert that the base and length are what we set.
		cgetbase $v0, $c1
		bne $v0, $t0, error
		nop
		cgetlen $v1, $c1
		bne $v1, $t1, error
		nop
		cbtu $c1, error
		nop

		#
		# Case four, found by Jonathan Woodruff.
		#

		# Stage 1 setting up the initial capability.
		dli	$t0, 0x160600000
		csetoffset $c1, $c0, $t0
		dli	$t1, 0x300000
		csetbounds $c1, $c1, $t1
		cseal $c1, $c1, $c0
		dla $t2, data
		csc $c1, $t2, 0($c0)
		clc $c1, $t2, 0($c0)
		cunseal $c1, $c1, $c0
		# Get and assert that the base and length are what we set.
		cgetbase $v0, $c1
		bne $v0, $t0, error
		nop
		cgetlen $v1, $c1
		bne $v1, $t1, error
		nop
		
		#
		# Case four, found by Mike Roe and Jon Woodruff.
		#
		# $c12: v:1 s:0 p:00000007 b:00000001600f9000 l:0000000000038000 o:88c0 t:0

		# Stage 1 setting up the initial capability.
		dli	$t0, 0x98000000600f9000
		csetoffset $c1, $c0, $t0
		dli	$t1, 0x38000
		csetbounds $c1, $c1, $t1
		dli $t2, 0x88c0
		csetoffset $c1, $c1, $t2
		# Set up return instruction
		dla $t2, return_to_c17
		ld $t3, 0($t2)
		csd $t3, $0, 0($c1)
		cjalr	$c1,$c17
		nop
		# Get and assert that the base and length are what we set.
		cgetbase $v0, $c1
		bne $v0, $t0, error
		nop
		cgetlen $v1, $c1
		bne $v1, $t1, error
		nop

		b	finally
		nop

error:
		li $a0, 1

finally:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
		
		.align 3
return_to_c17:
		cjr $c17
		nop
		
		
		.data
		.align 5
data:
		.dword 0
		.dword 0
		.dword 0
		.dword 0
