#-
# Copyright (c) 2012 Michael Roe
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
# Perform a few basic tests involving capability register length: query the
# starting length of $c2, reduce the length, and query it again.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		dla	$t0, cap1
		cmove   $c1, $c0
                cscr     $c1, $t0($c0)
                clcr     $c2, $t0($c0)
                cgettag $a0, $c2
                ccleartag $c1, $c0
                cscr     $c1, $t0($c0)
                clcr     $c2, $t0($c0)
                cgettag $a1, $c2
                
                # Exercise a potential victim buffer in the tag cache.
                dla	$t1, cap1-0x4000000	# A conflicting address
                dla	$t2, cap1+0x1000	# A different address
                cmove	$c1, $c0
                # Store a valid cap to an address that conflicts with one in the cache.
                cscr	$c1, $t1($c0)
                # Load data from the old address, swapping with the victim buffer.
                clcr	$c2, $t0($c0)
                # Load another address, evicting the victim buffer
		clcr	$c3, $t2($c0)
		# Load the evicted address to see if it has the tag set
		clcr	$c1, $t1($c0)
		cgettag	$a2, $c1

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.data
		.align	5                  # Must 256-bit align capabilities
cap1:		.dword	0x0123456789abcdef # uperms/reserved
		.dword	0x0123456789abcdef # otype/eaddr
		.dword	0x0123456789abcdef # base
		.dword	0x0123456789abcdef # length

