#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2014 Robert M. Norton
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
# Very basic test which checks that register forwarding works as it
# should for arithmetic and load instructions.
#

	.global	test
test:	.ent	test
	daddu 	$sp, $sp, -32
	sd	$ra, 24($sp)
	sd	$fp, 16($sp)
	daddu	$fp, $sp, 32

	dla     $t2, testdata
	# initialise loop counter
	li      $t0, 1
	# initial value
	li      $t1, 1
loop:
	# Test arith -> arith forwarding
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	add     $t1, $t1, $t1
	nop
	nop
	nop
	nop
	nop
	nop
	add     $t1, $t1, $t1
	nop
	nop
	nop
	nop
	nop
	add     $t1, $t1, $t1
	nop
	nop
	nop
	nop
	add     $t1, $t1, $t1
	nop
	nop
	nop
	add     $t1, $t1, $t1
	nop
	nop
	add     $t1, $t1, $t1
	nop
	add     $t1, $t1, $t1
	add     $t1, $t1, $t1
	move    $a0, $t1

	# test load -> arith forwarding
	li      $t1, 0
	ld      $t3, 0($t2)
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	add     $t1, $t1, $t3
	li      $t3, 0
	ld      $t3, 0($t2)
	nop
	nop
	nop
	nop
	nop
	nop
	add     $t1, $t1, $t3
	li      $t3, 0
	ld      $t3, 0($t2)
	nop
	nop
	nop
	nop
	nop
	add     $t1, $t1, $t3
	li      $t3, 0
	ld      $t3, 0($t2)
	nop
	nop
	nop
	nop
	add     $t1, $t1, $t3
	li      $t3, 0
	ld      $t3, 0($t2)
	nop
	nop
	nop
	add     $t1, $t1, $t3
	li      $t3, 0
	ld      $t3, 0($t2)
	nop
	nop
	add     $t1, $t1, $t3
	li      $t3, 0
	ld      $t3, 0($t2)
	nop
	add     $t1, $t1, $t3
	li      $t3, 0
	ld      $t3, 0($t2)
	add     $t1, $t1, $t3

	bnez    $t0, loop
	li      $t0, 0

	ld	$fp, 16($sp)
	ld	$ra, 24($sp)
	daddu	$sp, $sp, 32
	jr	$ra
	nop			# branch-delay slot
	.end	test

.data
.align 5
testdata:
	.dword 1