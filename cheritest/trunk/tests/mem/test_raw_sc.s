#-
# Copyright (c) 2011 Robert N. M. Watson
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
# Unit test that stores words to, and then loads words from, memory using
# store conditional.  Interruption behaviour is deferred to a higher-level
# test.
#

		.text
		.global start
start:
                # Avoid a race in multithreaded mode by only continuing
                # with a single thread
                dmfc0   $k0, $15
                srl     $k0, 24
                and     $k0, 0xff  # get thread ID
thread_spin:    bnez    $k0, thread_spin # spin if not thread 0
                nop
        
		#
		# Store conditional only works against addresses in cached
		# memory.  Calculate a cached address for our data segment,
		# and store pointer in $gp.
		#

		dla	$gp, dword
		dli	$a0, 0x00000000FFFFFFFF
		and $gp, $gp, $a0
		dli	$t0, 0x9800000000000000		# Cached, non-coherenet
		daddu	$gp, $gp, $t0

		# Initialize link register to the store address.
		ll 	$k0, 0($gp)
		
		# Store and load a word into double word storage
		dli	$a0, 0xfedcba98
		sc	$a0, 0($gp)			# @dword
		lwu	$a1, 0($gp)

		# Store and load words with sign extension
		daddiu	$gp, $gp, 8			# @positive
		ll 	$k0, 0($gp)
		dli	$a2, 1
		sc	$a2, 0($gp)
		lw	$a3, 0($gp)

		daddiu	$gp, $gp, 4			# @negative
		ll 	$k0, 0($gp)
		dli	$a4, -1
		sc	$a4, 0($gp)
		lw	$a5, 0($gp)

		# Store and load words at non-zero offsets
		daddiu	$gp, $gp, 4			# @val1
		ll 	$k0, 4($gp)
		dli	$a6, 2
		sc	$a6, 4($gp)
		lw	$a7, 4($gp)

		daddiu	$gp, $gp, 4			# @val2
		ll 	$k0, -4($gp)
		dli	$s0, 1
		sc	$s0, -4($gp)
		lw	$s1, -4($gp)
		
		# Initialize link register to a different address.
		ll 	$k0, 16($gp)
		# Fail to store and load a word into word storage
		dli	$s2, 0x01234567
		sc	$s2, -20($gp)			# @dword
		lwu	$s3, -20($gp)

		# Dump registers in the simulator
		mtc0	$v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0 $v0, $23
end:
		b end
		nop

		.data
dword:		.dword	0x0000000000000000
positive:	.word	0x00000000
negative:	.word	0x00000000
val1:		.word	0x00000000
val2:		.word	0x00000000
