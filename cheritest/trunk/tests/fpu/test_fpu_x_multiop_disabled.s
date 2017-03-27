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
# Test that floating point instructions raise an exception if the FPU
# is disabled.
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
		# Only instructions from the MIPS III ISA are included.
		# Instructions from later revisions of the ISA are in
		# a separate test; on a MIPS III ISA compatible CPU, these
		# might raise an exception for a different reason.
		#

		abs.d	$f0, $f0
		abs.s	$f0, $f0
		add.d	$f0, $f0, $f0
		add.s	$f0, $f0, $f0
		c.f.d	$f0, $f0
		c.f.s	$f0, $f0
		c.un.d	$f0, $f0
		c.un.s	$f0, $f0
		c.eq.d	$f0, $f0
		c.eq.s	$f0, $f0
		c.ueq.d	$f0, $f0
		c.ueq.s	$f0, $f0
		c.olt.d	$f0, $f0
		c.olt.s	$f0, $f0
		c.ult.d	$f0, $f0
		c.ult.s $f0, $f0
		c.ole.d	$f0, $f0
		c.ole.s	$f0, $f0
		c.ule.d $f0, $f0
		c.ule.s	$f0, $f0
		ceil.l.d $f0, $f0
		ceil.l.s $f0, $f0
		ceil.w.d $f0, $f0
		ceil.w.s $f0, $f0
		cvt.d.l	$f0, $f0
		cvt.d.s	$f0, $f0
		cvt.d.w	$f0, $f0
		cvt.l.d	$f0, $f0
		cvt.l.s	$f0, $f0
		cvt.s.l	$f0, $f0
		cvt.s.d	$f0, $f0
		cvt.s.w	$f0, $f0
		cvt.w.d	$f0, $f0
		cvt.w.s	$f0, $f0
		div.d	$f0, $f0, $f0
		div.s	$f0, $f0, $f0
		floor.l.d $f0, $f0
		floor.l.s $f0, $f0
		floor.w.d $f0, $f0
		floor.w.s $f0, $f0
		mov.d	$f0, $f0
		mov.s	$f0, $f0
		mul.d	$f0, $f0
		mul.s	$f0, $f0
		neg.d	$f0, $f0
		neg.s	$f0, $f0
		round.l.d $f0, $f0
		round.l.s $f0, $f0
		round.w.d $f0, $f0
		round.w.s $f0, $f0
		sub.d	$f0, $f0, $f0
		sub.s	$f0, $f0, $f0
		sqrt.d	$f0, $f0
		sqrt.s	$f0, $f0
		trunc.l.d $f0, $f0
		trunc.l.s $f0, $f0
		trunc.w.d $f0, $f0
		trunc.w.s $f0, $f0

		mfc1	$t0, $f0
		mtc1	$zero, $f0
		dmfc1	$t0, $f0
		dmtc1	$zero, $f0
		cfc1	$t0, $f31
		ctc1	$zero, $f31

		dla	$t1, data
		lwc1	$f0, 0($t1)
		swc1	$f0, 0($t1)
		ldc1	$f0, 0($t1)
		sdc1	$f0, 0($t1)

		bc1t	L1
		nop
L1:
		bc1f	L2
		nop
L2:
		bc1tl	L3
		nop
L3:
		bc1fl	L4
		nop
L4:

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
