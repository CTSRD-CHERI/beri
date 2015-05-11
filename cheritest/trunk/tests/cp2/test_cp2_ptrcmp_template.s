#-
# Copyright (c) 2014 Jonathan Woodruff
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
#
# This file is a template for pointer comparison tests. Concrete tests (e.g. ceq)
# include this template and define the compop macro to the relevant instruction.
# The template constructs capabilities to test various interesting cases:
#
# Tags:
# both unset
# one set, one unset
# both set
#
# Base and Offset:
# both equal,
# bases different, offsets equal
# bases equal, offsets different
# both different, base+offset different
# both different, base+offset equal
#
# For each of the five base/offset cases we test the various combinations of tags.
# For each of these we compare operands in both directions.
# The results are accumulated into registesr a1-a5.
#
# When choosing values for base/offset we use a value which will
# compare differently depending on whether signed or unsigned
# arithmetic is used.
#

.set mips64
.set noreorder
.set nobopt
.set noat

# Given two capabilities in c3 and c4 perform various comparisons
# with tags set/unset and accumulate the answer in a0.
# c5 and c6 are trashsed.
.macro docomparisons
		ccleartag  $c5, $c3
		ccleartag  $c6, $c4

		# Accumulator for answer
		li         $a0, 0
		# both tags set
		cmpop      $v0, $c3, $c4
		add        $a0, $v0
		sll        $a0, 1
		# arguments reversed
		cmpop      $v0, $c4, $c3
		add        $a0, $v0
		sll        $a0, 1
		# one tag unset
		cmpop      $v0, $c5, $c4
		add        $a0, $v0
		sll        $a0, 1
		# arguments reversed
		cmpop      $v0, $c4, $c5
		add        $a0, $v0
		sll        $a0, 1
		# both tags unset
		cmpop      $v0, $c5, $c6
		add        $a0, $v0
		sll        $a0, 1
		# arguments reversed
		cmpop      $v0, $c6, $c5
		add        $a0, $v0
.endm
	
		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Construct two equal capabilities with non-zero base and offset.
		dli        $at, 0x42
		cincbase   $c1, $c0, $at
		cincbase   $c2, $c0, $at
		dli        $at, 0x54
		csetoffset $c1, $c1, $at
		csetoffset $c2, $c2, $at

		# EQUAL CAPABILITIES

		cmove      $c3, $c1
		cmove      $c4, $c2

		docomparisons

		# Stash the answer
		move       $a1, $a0

                # BASES DIFFERENT, OFFSETS EQUAL

		# Give c3 a very large/negative base (offset unchanged)
		dli        $a0, 0x8000000000000000
		cincbase   $c3, $c1, $a0
		dli        $a0, 0x54
		csetoffset $c3, $c3, $a0
		cmove      $c4, $c2

		docomparisons

		# Stash the answer
		move       $a2, $a0

        	# BASES EQUAL, OFFSETS DIFFERENT

		# Give c3 a very large/negative offset
		dli        $a0, 0x8000000000000000
		csetoffset $c3, $c1, $a0
		cmove      $c4, $c2

		docomparisons

		# Stash the answer
		move       $a3, $a0

		# BASES and OFFSETS DIFFERENT, EFFECTIVE ADDRESSES DIFFERENT

		# Give c3 a different base from c4
		dli        $a0, 0x1
		cincbase   $c3, $c1, $a0
		# Give c3 a very large/negative offset
		dli        $a0, 0x8000000000000000
		csetoffset $c3, $c3, $a0
		cmove      $c4, $c2

		docomparisons

		# Stash the answer
		move       $a4, $a0

		# BASES AND OFFSETS DIFFERENT, EFFECTIVE ADDRESSES EQUAL

		# Give c3 a base which adds to offset to give same base+offset as c4 (with wrap around).
		dli        $a0, 0x8000000000000053
		cincbase   $c3, $c1, $a0
		# Give c3 a very large or very negative offset
		dli        $a0, 0x8000000000000001
		csetoffset $c3, $c3, $a0
		cmove      $c4, $c2

		docomparisons

		# Stash the answer
		move       $a5, $a0

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
