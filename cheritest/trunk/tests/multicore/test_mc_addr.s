#-
# Copyright (c) 2017 Michael Roe
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
# Test of reading *ptr after reading ptr. In the POWER memory model, this
# is guaranteed not to be reordered in a multicore system.
#
# Core 0 reads ptr, then reads *ptr to discover the status of the block
# pointed to by ptr. If its value is 1, the block is waiting to be processed
# and core 0 sets it to 2.
#
# Core 1 sets the status of a block to 1 (waiting to be processed), invokes
# SYNC, sets ptr to point to the block, and then waits for *ptr to be set
# to 2 by core 0.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32


		#
		# At the beginning, all threads other than thread zero will
		# be spinning on reset_barrier. Thread zero will call
		# other_threads_go to start the other threads running; other
		# threads skip this part.
		#

		dmfc0	$t0, $15, 7		# Thread Id ...
		andi	$t1, $t0, 0xffff	# ... in bottom 16 bits
		bnez	$t1, not_thread0	# If we're not thread zero
		nop				# Branch delay slot
		
		dmfc0	$t0, $15, 6		# Core Id ...
		andi	$t1, $t0, 0xffff	# ... in bottom 16 bits
		beqz	$t1, core0		# If we're core zero
		nop				# Branch delay slot

		daddi	$t1, $t1, -1
		beqz	$t1, core1		# If we're core 1
		nop

		b	other_core
		nop

core0:
		jal	other_threads_go
		nop				# Branch delay slot

		dla	$a0, ptr
		dli	$a1, 0			# Becomes 1 if test fails
		dli	$a3, 0			# Count of blocks processed

L0:
		#
		# If ptr == NULL, it hasn't been initialized yet
		#

		ld	$a2, 0($a0)
		beqz	$a2, L0
		nop

		dli	$t1, 1024		# Number of times round loop
L1:
		ld	$a2, 0($a0)
		
		#
		# If there was a SYNC here, it would obviously work.
		# The point of the test is that -- with the POWER memory
		# model -- it works even if there isn't a SYNC here.
		#

		ld	$t0, 0($a2)

		#
		# If *ptr == 0, then *ptr is an invalid block and we've seen
		# a memory coherence violation. End the test with an error.
		#

		beqz	$t0, fail
		nop

		#
		# If *ptr == 1, then *ptr is a block waiting to be processed
		# and we set *ptr = 2 to indicate that it has been processed.
		#

		daddi	$t0, $t0, -1
		bnez	$t0, L2
		nop

		dli	$t0, 2
		sd	$t0, 0($a2)
		sync


		#
		# Increment the number of blocks we've processed
		#

		daddi	$a3, $a3, 1
L2:
		daddi	$t1, $t1, -1
		bnez	$t1, L1
		nop

		b	end
		nop

fail:
		dli	$a1, 1
		b	end
		nop

core1:
		dla	$a0, ptr
		dli	$a1, 10
L6:
		dla	$t0, block1
		sd	$zero, 0($t0)
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
		dli	$t1, 1
		sd	$t1, 0($t0)
		sync
		sd	$t0, 0($a0)
		sync

L3:
		ld	$t1, 0($t0)
		daddi	$t1, $t1, -2
		bnez	$t1, L3
		nop

		dla	$t0, block2
		sd	$zero, 0($t0)
		sync
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		dli	$t1, 1
		sd	$t1, 0($t0)
		sync
		sd	$t0, 0($a0)
		sync
		
L4:
		ld	$t1, 0($t0)
		daddi	$t1, $t1, -2
		bnez	$t1, L4
		nop

		daddi	$a1, $a1, -1
		bnez	$a1, L6
		nop
not_thread0:
other_core:
end:

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data

		.align 5
ptr:		.dword 0

		.align 5
block1:		.dword 0

		.align 5
block2:		.dword 0
