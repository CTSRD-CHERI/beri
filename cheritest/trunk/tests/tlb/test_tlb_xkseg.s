#-
# Copyright (c) 2014, 2016 Michael Roe
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
# Test that we can map a page into the xkseg region.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
                # Find out how many TLB entries there are
                #

                mfc0    $a0, $16, 1     # Config1
                srl     $a0, $a0, 25
                andi    $a0, $a0, 0x3f
                addi    $a0, $a0, 1

                #
                # Set the number of wired TLB entries to 1
                #

		dli	$t0, 1
                mtc0    $t0, $6       # TLB Wired

                #
                # Set the page size to 4K
                #

		li	$t0, 0x0
                mtc0    $t0, $5       # TLB Page Mask


                #
                # Loop through the TLB
                #

                dli     $a2, 0xc000000000000000  # EntryHi for first TLB entry

		dli	$t0, 0x0 	# Physical address of start of RAM
		dsrl	$t0, $t0, 6	# Shift to position for PFN
		ori	$a3, $t0, 0x1f	# Cached, Dirty, Valid and Global bits set
					# $a3 is EntryL0 for first TLB entry
		
                dli     $a4, 1 << 13    # Amount to increment EntryHi.VPN2
		dli	$a5, 1 << 6	# Amount to increment EntryLo.PFN

                dli     $a1, 0
loop:
                dmtc0   $a2, $10        # TLB EntryHi
                dadd    $a2, $a2, $a4

                dmtc0   $a3, $2		# TLB EntryLo0
		dadd	$a3, $a3, $a5

                dmtc0   $a3, $3		# TLB EntryLo1
		dadd	$a3, $a3, $a5

                mtc0    $a1, $0         # TLB Index

                tlbwi

                addi    $a1, $a1, 1
                bne     $a1, $a0, loop
                nop                     # Branch delay slot

		dli	$a0, 0
		dli	$t0, 0xc000000000000000
		dli	$t1, 0x1234
		sw	$t1, 0($t0)
		lw	$a0, 0($t0)

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test
