#-
# Copyright (c) 2015 Michael Roe
# All rights reserved.
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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test the LWL instruction for addresses with different alignments.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dli	$a5, 0

		dla	$t0, data
		dli	$t1, -1
		daddiu	$a0, $t1, 0
		lwl	$a0, 0($t0)
		daddiu	$a1, $t1, 0
		lwl	$a1, 1($t0)
		daddiu	$a2, $t1, 0
		lwl	$a2, 2($t0)
		daddiu	$a3, $t1, 0
		lwl	$a3, 3($t0)

		#
		# LWL at offsets 4 .. 7 should give the same result as for
		# offsets 0 .. 3, but it exercizes different code paths in
		# the L3 formal model because the memory is modelled as
		# 64-bit dwords. It might exercize different code paths in
		# a hardware implementation, too.
		#

		daddiu	$a4, $t1, 0
		lwl	$a4, 4($t0)
		bne	$a4, $a0, fail
		nop	# branch delay slot

		daddiu	$a4, $t1, 0
		lwl	$a4, 5($t0)
		bne	$a4, $a1, fail
		nop

		daddiu	$a4, $t1, 0
		lwl	$a4, 6($t0)
		bne	$a4, $a2, fail
		nop

		daddiu	$a4, $t1, 0
		lwl	$a4, 7($t0)
		bne	$a4, $a3, fail
		nop

		b	pass
		nop	# branch delay slot
fail:
		dli	$a5, 1
pass:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align 3
data:		.word 0x01020304
		.word 0x01020304
