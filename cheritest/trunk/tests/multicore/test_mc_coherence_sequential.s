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
# Test sequential consistency on a multicore configuration:
# Core 1 writes a '1' to x and then to y.
# Core 0 reads y until it is non zero, then reads x. The result should be 1.
#
# This test is not required to work according to the MIPS ISA, because it
# does not contain 'sync' instructions and memory is not required to be
# sequentially consistent. However, it is expected to work on a multicore
# CHERI1.
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

		dla	$t2, x
		dla	$t0, y


		#
		# Wait for y to become non-zero
		#

loop:
		ld	$t1, 0($t0)
		beqz	$t1, loop
		nop

		#
		# Read x and stash the result in 'result'
		#
		# NB: No 'sync' here: generic MIPS might reorder the reads
		#

		ld	$t0, 0($t2)
		dla	$t1, result
		sd	$t0, 0($t1)

		#
		# Make sure the write to result is flushed to memory
		# before we called thread_barrier
		#

		sync	

		b	end
		nop

not_core_zero:

		dli	$a0, 1
		dla	$t0, x
		dla	$t1, y

		sd	$a0, 0($t0)

		#
		# NB: No 'sync' instruction here
		# Generic MIPS might reorder the writes
		#

		sd	$a0, 0($t1)

end:

		dla	$a0, end_barrier
		jal	thread_barrier
		nop

		# Probably need 'sync' here...
		sync

		dla	$a0, result
		ld	$a0, 0($a0)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
x:		.align 3
		.dword 0

		#
		# Some padding so that x and y probably aren't in the same
		# cache line.
		#

		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0


y:		.align 3
		.dword 0

result:		.align 3
		.dword 0

end_barrier:
		mkBarrier

