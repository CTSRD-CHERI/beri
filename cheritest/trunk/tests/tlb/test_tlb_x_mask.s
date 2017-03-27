#-
# Copyright (c) 2016 Michael Roe
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
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		
		#
		# Set up exception handler
		#

		dla	$a0, bev0_handler
		jal	bev0_handler_install
		nop

		#
		# Clear the BEV flag
		#

		jal bev_clear
		nop

		#
		# $a2 will be set to 1 if the exception handler is called
		#

		dli 	$a2, 0

		#
		# $a3 will hold the value of the cause register
		#

		dli	$a3, 0

		#
		# Configure the TLB with 2 wired entries
		#

		dli	$t0, 2
		mtc0	$t0, $6		# Wired

		mtc0	$zero, $0	# Index
		dmtc0	$zero, $2	# TLB EntryLo0
		dmtc0	$zero, $3	# TLB EntryLo1
		dli	$t0, 5		# ASID to use
		dmtc0	$t0, $10	# TLB EntryHi

		#
		# Initialize the first TLB entry with a valid entry
		#

		mtc0	$zero, $5	# PageMask
		tlbwi
		

		#
		# Set CP0.PageMask to an invalid value (2K page size, which
		# is not allowed by the ISA).
		#

		dli	$t0, 0x1 << 13
		mtc0	$t0, $5		# PageMask

		#
		# Read it back to see if PageMask was changed
		#

		mfc0	$a0, $5		# PageMask

		#
		# Write the invalid entry into the TLB
		#

		tlbwi

		#
		# Read back the TLB entry to see if it was written
		#

		mtc0	$zero, $5	# PageMask
		dmtc0	$zero, $2	# EntryLo0
		dmtc0	$zero, $3	# EntryLo1
		dmtc0	$zero, $10	# EntryHi

		dli	$t0, 0
		mtc0	$t0, $0
		tlbr

		mfc0	$a1, $5		# PageMask

		#
		# Restore the TLB to a valid value
		#

		mtc0	$zero, $0	# Index
		dmtc0	$zero, $2	# TLB EntryLo0
		dmtc0	$zero, $3	# TLB EntryLo1
		mtc0	$zero, $5	# PageMask
		dli	$t0, 5		# ASID to use
		dmtc0	$t0, $10	# TLB EntryHi
		tlbwi

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

  		.ent bev0_handler
bev0_handler:
		li	$a2, 1
		mfc0	$a3, $13	# Cause Register
		dmfc0	$a5, $14	# EPC
		daddiu	$k0, $a5, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop
		nop
		nop
		nop
		eret
		.end bev0_handler
 
