#-
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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# All threads return their core/thread id's, and core0 finishes first.
#
# This is mainly a test of the test framework itself, rather than the CPU:
# it tests that the test framework looks at core0's registers, whichever
# core finishes first.

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dmfc0	$t0, $15, 7		# Thread Id ...
		andi	$t0, $t0, 0xffff	# ... in bottom 16 bits
		bnez	$t0, not_core_zero	# If we're not thread zero
		nop				# Branch delay slot

		dmfc0	$t1, $15, 6		# Core Id ...
		andi	$t1, $t1, 0xffff	# ... in bottom 16 bits
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

		b	end
		nop

not_core_zero:

		#
		# Delay loop so core 0 is (probably) first to finish
		#

		dli	$t0, 100
loop:
		daddi	$t0, $t0, -1
		bnez	$t0, loop
		nop

end:

		#
		# All cores do this bit
		#

		#
		# Reload the core/thread id
		# (Core0's call to other_threads_go will have overwritten
		# registers).
		#

		mfc0	$a0, $15, 6	# CoreId
		andi	$a0, $a0, 0xffff
		mfc0	$a1, $15, 1	# ThreadId
		andi	$a1, $a1, 0xffff

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
