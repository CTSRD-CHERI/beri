#-
# Copyright (c) 2012 Robert M. Norton
# Copyright (c) 2012 Jonathan Woodruff
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

# Simple TLB test which configures a TLB entry for the lowest virtual
# page in the xuseg and attempts a load via it.

.set mips64
.set noreorder
.set nobopt

.global test
test:   .ent    test
		# TLB write of index 6	
 		dmtc0	$zero, $5       	# Write 0 to page mask i.e. 4k pages
 		li	$a0, 0x6
		dmtc0	$a0, $0			# TLB index
		dli	$a0, 0xc000000000002005
		dmtc0	$a0, $10		# TLB HI address
		li	$a0, 0x3017
		dmtc0	$a0, $2			# TLB EntryLow0 = k0 (Low half of TLB entry for even virtual address (VPN))
		li	$a0, 0x4011
		dmtc0	$a0, $3			# TLB EntryLow1 = k0 (Low half of TLB entry for odd virtual address (VPN))
		tlbwi				# Write Indexed TLB Entry
		
		nop
		nop
		nop
		nop
		
		# Clear the tlb registers
		dmtc0	$zero, $5       	# 0 page mask
		dmtc0	$zero, $0       	# 0 index
		dmtc0	$zero, $10       	# 0 EntryHi
		dmtc0	$zero, $2       	# 0 EntryLo0
		dmtc0	$zero, $3       	# 0 EntryLo1

		nop
		nop
		
		# TLB read of index 6.
		li	$a0, 0x6
		dmtc0	$a0, $0			# TLB index
		nop
		nop
		nop
		tlbr
		
		nop
		nop
		nop
		nop
		nop
		nop
		
		# Gather the results of the tlb read
		dmfc0	$a0, $5       	# 0 page mask
		dmfc0	$a1, $0       	# 0 index
		dmfc0	$a2, $10       	# 0 EntryHi
		dmfc0	$a3, $2       	# 0 EntryLo0
		dmfc0	$a4, $3       	# 0 EntryLo1

		jr      $ra
		nop
.end    test
	
	.data
	.align 5
testdata:
	.dword 0xfedcba9876543210
