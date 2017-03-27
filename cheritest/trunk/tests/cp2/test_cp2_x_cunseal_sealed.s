#-
# Copyright (c) 2013-2015 Michael Roe
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
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
# Test that cunseal checks for ct not being sealed
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Set up exception handler
		#

		jal	bev_clear
		nop
		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		#
		# $a2 will be set to 1 if the exception handler is called
		#

		dli	$a2, 0

		#
		# $a3 will be set to the capability cause if there is an
		# exception.
		#

		dli	$a3, 0

		#
		# Choose 0x1234 as the otype for sealing capabilities
		#

		dli	$t0, 0x1234
		csetoffset $c1, $c0, $t0

		#
		# Make $c2 a sealed data capability for 'data'
		#

		cgetdefault $c2
		dla	$t0, data
		csetoffset $c2, $c2, $t0
		dli	$t0, 0x1000
		csetbounds $c2, $c2, $t0
		dli	$t0, 3
		candperm $c2, $c2, $t0
		cseal	$c2, $c2, $c1

		#
		# Take the template capability we're using for sealing, and
		# seal it with itself, making it unusable.
		#

		cseal	$c3, $c1, $c1

		#
		# Clear $c4 so we can tell if the following cunseal succeeds
		#

		cmove	$c4, $c0

		#
		# Try to unseal $c2 with a template capability that is itself
		# sealed ($c3). This should raise an exception.
		#

		cunseal $c4, $c2, $c3

		cgetbase $a0, $c4

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.ent bev0_handler
bev0_handler:
		li	$a2, 1
		cgetcause $a3
		dmfc0	$a5, $14	# EPC
		daddiu	$k0, $a5, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop
		nop
		nop
		nop
		eret
		.end bev0_handler


		.data
		.align 12
data:		.dword 0
