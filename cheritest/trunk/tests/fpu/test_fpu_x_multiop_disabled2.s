#-
# Copyright (c) 2013, 2015 Michael Roe
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
# Test that floating point instructions from the MIPS IV ISA raise an exception if the
# FPU is disabled.
#

.set mips64
.set noreorder
.set nobopt
.set noat

.global test
.ent test
test:			
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

		li $a2, 0

		mfc0 $t0, $12
		li $t1, 1 << 29		# Disable CP1
		nor $t1, $t1, $t1
		and $t0, $t0, $t1    
		mtc0 $t0, $12 
		nop
		nop
		nop
		nop
		nop
		nop

		#
		# These instructions should raise an exception because
		# the FPU is disabled.
		#

		movf	$t0, $t1, $fcc0
		movf.d	$f0, $f2, $fcc0
		movf.s	$f0, $f1, $fcc0
		movn.d	$f0, $f1, $t0
		movn.s	$f0, $f1, $t0
		movt	$t0, $t1, $fcc0
		movt.d	$f0, $f2, $fcc0
		movt.s	$f0, $f1, $fcc0
		movz.d	$f0, $f1, $t0
		movz.s	$f0, $f1, $t0

		dla	$t1, data
		sdxc1	$f0, $0($t1)
		ldxc1	$f0, $0($t1)
		swxc1	$f0, $0($t1)
		lwxc1	$f0, $0($t1)
		


		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop
.end test

.ent bev0_handler
bev0_handler:
		daddiu	$a2, $a2, 1

		mfc0	$a3, $13
		srl	$a3, $a3, 2
		andi	$a3, $a3, 0x1f	# ExcCode

		mfc0	$a4, $13
		srl	$a4, $a4, 28
		andi	$a4, $a4, 0x3

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
		.align 3
data:		.dword 0
