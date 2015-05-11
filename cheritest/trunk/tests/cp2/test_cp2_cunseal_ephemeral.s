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
# Test cunseal with an ephemeral capability
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

		cmove    $c1, $c0
		dla      $t0, sandbox
		csettype $c1, $c1, $t0
		# Permissions Permit_Seal, Permit_Set_Type, Permit_Load,
                # Permit_Execute, Non_Ephemeral
		dli      $t0, 0x187
		candperm $c1, $c1, $t0

		csealcode $c2, $c1

		#
		# Make $c1 ephemeral
		# Permissions Permit_Set_Type and Permit_Seal
		#
		dli      $t0, 0x180
		candperm $c1, $c1, $t0

		#
		# Unseal $c2 with an ephemeral capability
		# Result in $c3 should also be ephemeral
		#
                cunseal  $c3, $c2, $c1

		cgetperm $a0, $c3	

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

