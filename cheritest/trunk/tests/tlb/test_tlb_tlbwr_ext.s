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
# Test the pseudo-random number generator used by TLBWR.
# In BERI1, it's not very random (intentionally, to make trace comparison
# easy): it decrements by 1 every time TLBWR is called.
#
# This version of the test enables the BERI extended TLB.

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Check that the CPU supports the BERI extended TLB
		#

		dli	$a0, 0
		mfc0	$t0, $16, 5	# Config5
		andi	$t0, $t0, 0x1	# Extended TLB bit
		beqz	$t0, test_failed
		nop			# branch delay slot

		#
		# Find out how many (normal+extended) TLB entries there are,
		# and enable the extended TLB
		#

		mfc0	$a0, $16, 6
		ori	$a0, $a0, 0x4	# Enable extended TLB
		mtc0	$a0, $16, 6
		srl	$a0, $a0, 16
		addi	$a0, $a0, 1

		#
		# Set the number of wired TLB entries to 1
		#

		dli	$t0, 1
		mtc0	$t0, $6	# TLB Wired

		#
		# Set the page size to 4K
		#

		mtc0	$zero, $5	# TLB Page Mask

		#
		# Loop through the TLB, clearing it
		#

		dmtc0	$zero, $2	# TLB EntryLo0
		dmtc0	$zero, $3	# TLB EntryLo1

		dli	$a3, 1 << 13	# VPN2 field in EntryHi
		dli	$a2, 5		# ASID to use for TLB entries

		dli	$a1, 0
loop:
		dmtc0	$a2, $10	# TLB EntryHi
		mtc0	$a1, $0		# TLB Index

		tlbwi

		addi	$a1, $a1, 1
		dadd	$a2, $a2, $a3
		bne	$a1, $a0, loop
		nop			# Branch delay slot

		#
		# Use TLBWR to write a TLB entry for virtual page 1
		#

		dmtc0	$a3, $10	# TLB EntryHi
		tlbwr

		#
		# Find out where it ended up in the TLB
		#

		dmtc0	$a3, $10	# TLB EntryHi
		mtc0	$zero, $0
		tlbp
		mfc0	$a4, $0		# TLB Index

		#
		# Use TLBWR to write page 257. The test assumes that this
		# will hash to the same TLB entry, which will be true if
		# there are 256 extended TLB entries.
		#

		dli	$t2, 0x202000
		nop
		dmtc0	$t2, $10	# TLB EntryHi
		tlbwr

		#
		# Find out where it ended up
		#

		dmtc0	$t2, $10	# TLB EntryHi
		tlbp
		mfc0	$a5, $0		# TLB Index

		#
		# Find out where page 1 was evicted to
		#

		dmtc0	$a3, $10	# TLB EntryHi
		tlbp
		mfc0	$a6, $0		# TLB Index

		#
		# Clear the TLB entry for page 1
		#

		dmtc0	$a2, $10
		dadd	$a2, $a2, $a3
		dmtc0	$zero, $2	# TLB EntryLo0
		dmtc0	$zero, $3	# TLB EntryHi
		tlbwi
		

		#
		# Use TLBWR to put back the TLB entry for page 1
		#

		dmtc0	$a3, $10
		tlbwr

		#
		# Find out where page 257 was evicted to
		#

		dmtc0	$t2, $10
		tlbp
		mfc0	$t3, $0

		#
		# A loop repeatedly replacing page table entries
		#

		dli	$a1, 100

thrash_loop:

		#
		# Clear the TLB entry
		#

		dmtc0	$a2, $10
		dadd	$a2, $a2, $a3
		dmtc0	$zero, $2	# TLB EntryLo0
		dmtc0	$zero, $3	# TLB EntryHi
		tlbwi
		
		#
		# Write back page 257
		#

		dli	$t2, 0x202000
		dmtc0	$t2, $10	# TLB EntryHi
		tlbwr

		#
		# Find out where page 1 was evicted to
		#

		dmtc0	$a3, $10	# TLB EntryHi
		tlbp
		mfc0	$t0, $0		# TLB Index

		#
		# Clear the TLB entry
		#

		dmtc0	$a2, $10
		dadd	$a2, $a2, $a3
		dmtc0	$zero, $2	# TLB EntryLo0
		dmtc0	$zero, $3	# TLB EntryHi
		tlbwi

		#
		# Use TLBWR to put back the TLB entry for page 1
		#

		dmtc0	$a3, $10
		tlbwr

		#
		# Find out where page 257 went
		#

		dmtc0	$t2, $10
		tlbp
		mfc0	$t0, $0

		addi	$a1, $a1, -1
		bnez	$a1, thrash_loop
		nop			# branch delay slot

test_failed:

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
