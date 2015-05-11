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

.include "macros.s"

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Test that csc/clc load or store the tag bit atomically with the associated
# data, even on multicore.
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

		dli	$a0, 1000	# Number of times round the loop
		dla	$a1, cap
		dli	$a2, 0		# Will be set to 1 if test fails

		#
		# Wait for the other cores to start writing to cap
		#

wait:
		clcr	$c1, $a1($c0)
		cbtu	$c1, wait
		nop
	
		dli	$t1, 1		# Expected offset in vslid capability
loop0:
		clcr	$c1, $a1($c0)
		cbtu	$c1, tag_not_set
		nop
		cgetoffset $t0, $c1
		beq	$t0, $t1, tag_not_set
		nop

		#
		# If the tag is set, and the offset is not equal to $t1,
		# then either the store or the load wasn't atomic, so the
		# test fails.
		#

		dli	$a2, 1

tag_not_set:
		bnez	$a0, loop0
		daddi	$a0, $a0, -1

		dla	$a0, stop
		dli	$t0, 1
		sd	$t0, 0($a0)

		dli	$t0, 1000
delay_loop:
		bnez	$t0, delay_loop
		daddi	$t0, $t0, -1

		b	end
		nop

not_core_zero:

		#
		# All cores do this bit
		#

		dla	$a0, stop
		dla	$a1, cap
		dli	$t0, 1
		csetoffset $c1, $c0, $t0
		cfromptr $c2, $c0, $zero
loop1:
		cscr	$c1, $a1($c0)
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		cscr	$c2, $a1($c0)
		ld	$t0, 0($a0)
		beqz	$t0, loop1
		nop

end:

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data

		.align 3
stop:
		.dword 0

cap:		.align 5
		.dword 0
		.dword 0
		.dword 0
		.dword 0


