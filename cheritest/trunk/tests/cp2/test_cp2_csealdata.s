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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test csealdata
#

# In this test, sandbox isn't actually called, but its address is used
# as an otype.
sandbox:
		creturn

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

                # Make $c1 a template capability for a user-defined type
		# whose otype is equal to the address of sandbox.
		dla      $t0, sandbox
		csettype $c1, $c0, $t0

                # Make $c2 a data capability for the array at address data
		dla      $t0, data
		cincbase $c2, $c0, $t0
                dli      $t0, 8
                csetlen  $c2, $c2, $t0
		# Permissions Non_Ephemeral, Permit_Load, Permit_Store,
		# Permit_Store.
		# NB: Permit_Execute must not be included in the set of
		# permissions used here.
		dli      $t0, 0xd
		candperm $c2, $c2, $t0

		# Seal data capability $c2 to the otype of $c1, and store
		# result in $c3.
                csealdata $c3, $c2, $c1

                # $c3.u should be 0
		cgetunsealed $a0, $c3
                # $c3.type should be equal to sandbox
		cgettype $a1, $c3
		dla      $t0, sandbox
		dsubu    $a1, $a1, $t0
                # $c3.base should be equal to data
                cgetbase $a2, $c3
                dla      $t0, data
                dsubu    $a2, $t0
	        # $c3.len should be equal to $c2.len, i.e. 8	
                cgetlen  $a3, $c3
                # $c3.perm should be equal to $c2.perms
		cgetperm $a4, $c3

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align 3
data:		.dword	0xfedcba9876543210
