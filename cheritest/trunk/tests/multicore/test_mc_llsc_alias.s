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
# Test for cache line aliasing with load linked/store conditional.
#
# Core 0 repeatedly does a load linked/store conditional, while the other
# cores write to a variable that shares the same cache line. This will cause
# the store conditional to fail on BERI1 and other MIPS ISA implementations
# that have a block size of 16 bytes or more for LL/SC. This is permitted
# by the MIPS ISA, which allows the block size to be anything.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dmfc0	$t0, $15, 7		# Thread Id ...
		andi	$t0, $t0, 0xffff	# ... in bottom 16 bits
		bnez	$t0, not_core_zero	# If we're not thread zero
		nop	# branch delay slot

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

		dla	$a0, mutex

		#
		# Try to load linked/store conditional 1000 times
		#

		dli	$t0, 1000

loop0:
		lld	$a2, 0($a0)
		nop
		nop
		nop
		nop
		nop
		scd	$a2, 0($a0)

		#
		# End the test if one of them fails
		#

		beqz	$a2, end
		nop

		daddi	$t0, $t0, -1
		bnez	$t0, loop0
		nop

		dla	$t0, done
		dli	$t1, 1
		sd	$t1, 0($t0)

		b	end
		nop

not_core_zero:

		#
		# All other cores do this bit
		#

		dla	$a0, alias
		dla	$a1, done
loop1:
		sd	$zero, 0($a0)
		ld	$t0, 0($a1)
		beqz	$t0, loop1
		nop			# branch delay slot

end:

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align 5
mutex:		.dword 0
alias:		.dword 0

		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0
		.dword 0

done:		.dword 0
