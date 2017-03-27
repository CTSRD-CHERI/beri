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
# Unit test that stores double words to, and then loads double words from,
# memory using store conditional.  Interruption behaviour is deferred to a
# higher-level test.
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
		lld 	$k0, 0($gp)
		
		# Store and load a double word into double word storage
		dli	$a0, 0xfedcba9876543210
		scd	$a0, 0($gp)			# @dword
		ld	$a1, 0($gp)

		# Store and load double with sign extension
		daddiu	$gp, $gp, 8			# @positive
		lld 	$k0, 0($gp)
		dli	$a2, 1
		scd	$a2, 0($gp)
		ld	$a3, 0($gp)

		daddiu	$gp, $gp, 8			# @negative
		lld 	$k0, 0($gp)
		dli	$a4, -1
		scd	$a4, 0($gp)
		ld	$a5, 0($gp)

		# Store and load double words at non-zero offsets
		daddiu	$gp, $gp, 8			# @val1
		lld 	$k0, 8($gp)
		dli	$a6, 2
		scd	$a6, 8($gp)
		ld	$a7, 8($gp)

		daddiu	$gp, $gp, 8			# @val2
		lld 	$k0, -8($gp)
		dli	$s0, 1
		scd	$s0, -8($gp)
		ld	$s1, -8($gp)
		
		# Initialize link register to a different address.
		lld 	$k0, 0($gp)
		# Fail to store and load a double word into double word storage
		dli	$s2, 0x0123456789abcdef
		scd	$s2, -32($gp)			# @dword
		ld	$s3, -32($gp)

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
positive:	.dword	0x0000000000000000
negative:	.dword	0x0000000000000000
val1:		.dword	0x0000000000000000
val2:		.dword	0x0000000000000000
