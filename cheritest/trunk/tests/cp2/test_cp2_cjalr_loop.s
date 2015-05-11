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
# Test capability jump and link register
#

sandbox:
		# Put a value in $a0 so that later on we can check that this
		#  subroutine was called
		dli	$a0, 1

		# sandbox should be running with a PCC that gives resticted
		# permissions. Save it to $c2 so that we can check PCC.perms
		# later on.
		cgetpcc $a2($c2)

		# Return from the sandboxed subroutine
		.align 5
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		cjr	$ra($c24)
		nop	# Probably a branch-delay slot

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32
		addiu	$a6, $0, 4

		# Restrict the PCC capability that sandbox will run with.
		# Non_Ephemeral, Permit_Execute, Permit_Load, Permit_Store,
		# Permit_Load_Capability, Permit_Store_Capability, 
		# Permit_Store_Ephemeral_Capability.
loop:
		dli $t1, 0x7f
		candperm $c1, $c0, $t1
		dla $t1, loop
		csetlen $c1, $c1, $t1

		# Save $ra so we can return from this subroutine
		move	$a1, $ra

		dla	$a0, sandbox
		# PC will be savced in $ra
		# PCC will be saved in $c24
		cjalr	$a0($c1)
		# I'm not sure if this a branch delay slot
		nop
		nop

		cgetperm $a3, $c2
		# restore return address
		move $ra, $a1
		
		bnez	$a6, loop
		addiu	$a6, -1		

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align	5                  # Must 256-bit align capabilities
cap1:		.dword	0x0123456789abcdef # uperms/reserved
		.dword	0x0123456789abcdef # otype/eaddr
		.dword	0x0123456789abcdef # base
		.dword	0x0123456789abcdef # length

