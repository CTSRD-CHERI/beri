#-
# Copyright (c) 2013 Alan A. Mujumdar
# Copyright (c) 2014 Michael Roe
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
.set noat

#
# Test atomicity of load linked/store conditional pairs.
# Each core runs a loop, adding its own core id plus one to a total.
# (The plus one is so that core zero is adding a non-zero amount, so we'll
# notice if one gets lost).
# The total is checked at the end to make sure we haven't lost any updates.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dmfc0	$t0, $15, 7		# Thread Id ...
		andi	$t1, $t0, 0xffff	# ... in bottom 16 bits
		bnez	$t1, not_core_zero	# If we're not thread zero
		nop	# branch delay slot

		dmfc0	$t0, $15, 6		# Core Id ...
		andi	$t1, $t0, 0xffff	# ... in bottom 16 bits
		bnez	$t1, not_core_zero	# If we're not core zero
		nop				# Branch delay slot

		#
		# Core 0 does this bit
		#

		#
		# Start the other threads/cores running
		#

		jal	other_threads_go
		nop	# branch delay slot

not_core_zero:

		#
		# All cores do this bit
		#

		dli	$t1, 16	# Number of times round the loop
		dla	$a0, total
		dmfc0	$a1, $15, 6
		andi	$a1, $a1, 0xffff
		addi	$a1, $a1, 1

store_loop:
		lld	$t0, 0($a0)
		daddu	$t0, $t0, $a1
		scd	$t0, 0($a0)
		beqz	$t0, store_loop
		nop

		daddi	$t1, $t1, -1
		bnez	$t1, store_loop
		nop
end:

		sync

		dla	$a0, end_barrier
		jal	thread_barrier
		nop

		sync

		dla	$a0, total
		ld	$a0, 0($a0)

		dmfc0	$a1, $15, 6
		srl	$a1, $a1, 16
		

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data

total:		.align 3
		.dword 0

end_barrier:
		mkBarrier

