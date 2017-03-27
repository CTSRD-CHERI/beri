#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2013 Michael Roe
# Copyright (c) 2015 SRI International
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

.include "macros.s"
.set mips64
.set noreorder
.set nobopt

#
# Check that various operations interrupt the capability versions of
# load linked + store conditional double word.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Set up nop exception handler.
		#

		jal	bev_clear
		nop
		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		#
		# Uninterrupted access; check to make sure the right value
		# comes back.
		#

		dla	$t1, word
		csetoffset	$c1, $c0, $t1
		cllb	$a0, $c1
		cscb	$a0, $a0, $c1
		clbr	$a1, $zero($c1)

		#
		# Check to make sure we are allowed to increment the loaded
		# number, so we can do atomic arithmetic.
		#

		cllb	$a2, $c1
		daddiu	$a2, $a2, 1
		cscb	$a2, $a2, $c1
		lb	$a3, 0($t1)

		#
		# Trap between cllb and cscb; check to make sure that the
		# cscbr not only returns failure, but doesn't store.
		#

		cllb	$a4, $c1
		tnei	$zero, 1
		cscb	$a4, $a4, $c1

		# Load a byte from double word storage
		dla	$t0, dword
		csetoffset	$c2, $c0, $t0
		cllb	$s0, $c2
		
		# Load bytes with sign extension
		dla	$t0, positive
		csetoffset	$c3, $c0, $t0
		cllb	$s1, $c3
		dla	$t0, negative
		csetoffset	$c4, $c0, $t0
		cllb	$s2, $c4

		# Load bytes without sign extension 
		cllbu	$s3, $c3
		cllbu	$s4, $c4

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test


#
# No-op exception handler to return back after the tnei and confirm that the
# following sc fails.  This code assumes that the trap isn't from a branch-
# delay slot.

#
		.ent bev0_handler
bev0_handler:
		dmfc0	$k0, $14	# EPC
		daddiu	$k0, $k0, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop			# NOPs to avoid hazard with ERET
		nop			# XXXRW: How many are actually
		nop			# required here?
		nop
		eret
		.end bev0_handler

		.data
dword:		.dword	0xfedcba9876543210
positive:	.byte	0x7f
negative:	.byte	0xff
word:		.word	0xffffffff
