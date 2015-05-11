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
# This test checks the initialisation-time defaults for selected CP0
# registers by copying them into general-purpose registers that predicates can
# check directly.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		# Context Register
		dmfc0	$a0, $4

		# Wired Register
		dmfc0	$a1, $6

		# HWREna Register
		dmfc0   $s1, $7
		
		# Count Register
		dmfc0	$a2, $9

		# Compare Register
		dmfc0	$a3, $11

		# Status Register
		dmfc0	$a4, $12

		# Processor Revision Identifier (PRId)
		dmfc0	$a5, $15

		# Config Register
		dmfc0	$a6, $16, 0

		# Config1 Register
		dmfc0	$a7, $16, 1

		# XContext Register
		dmfc0	$s0, $20


		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
