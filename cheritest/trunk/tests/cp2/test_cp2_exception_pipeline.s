#-
# Copyright (c) 2011 Robert M. Norton
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
# These are regression tests to check that CP2 operations which entered the
# pipeline after an exception is triggered are correctly squashed and do
# not update any CP2 state. Earlier version of the CHERI prototype did not
# handle this correctly.
#
# For each test, an instruction which causes an exception is immediately followed
# by a capability operation. Check to see that the capability
# state is not updated, even though capability modification instruction will
# have entered the pipeline.

		.global test
test:		.ent test
		daddu	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32
	
		#
		# Set up exception handler.
		#
		jal	bev_clear
		nop
		dla	$a0, bev0_handler
		jal	bev0_handler_install
                nop
	
		# Test cincbase
		dli	$t0, 0x100
		syscall	0
		# The following instruction should NOT be executed because the
		# handler will return to syscall + 8
		cincbase	$c2, $c2, $t0  # not executed

		# Test csetlen
		dli	$t1, 0x100
		syscall 0
		csetlen	$c3, $c3, $t1  # not executed

		# Test candperm
		dli	$t2, 0x100
		syscall 0
		candperm	$c4, $c4, $t2  # not executed

		# Test csetoffset
		dli	$t3, 0x100
		syscall 0
		csetoffset	$c5, $c5, $t3  # not executed

		# Create a test capability for loading and storing
		dla		$t0, data
		cincbase	$c6, $c0, $t0
		dli     	$t0, 32
		csetlen		$c6, $c6, $t0
		dli		$t0, 0x1ff
		candperm	$c6, $c6, $t0
		dli		$t0, 0
		csetoffset	$c6, $c6, $t0
		
		# Test cscr
		dla	$t0, data
	        syscall 0
		cscr	$c6, $t0($c0) # not executed
		# If cscr was properly squashed these loads will load the
	        # test values below, otherwise they will get the stored capability
		ld	$a0, ($t0)
		ld	$a1, 8($t0)
		ld	$a2, 16($t0)
		ld	$a3, 24($t0)

		# store the test capability
		cscr	$c6, $t0($c0)
	
		# Test clcr
 		syscall 0
		clcr	$c7, $t0($c0) # not executed

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

# The exception handler just returns to the instruction two after the faulting one.

		.ent bev0_handler
bev0_handler:
		dmfc0	$k0, $14	# EPC
		daddiu	$k0, $k0, 8 	# EPC += 8 to bump PC forward on ERET N.B. 8 because we wish to skip instruction after svc!
		dmtc0	$k0, $14
		nop			# NOPs to avoid hazard with ERET
		nop			# XXXRW: How many are actually
		nop			# required here?
		nop
		eret
		.end bev0_handler

		.data
		.align  5
data:		.dword	0xfeedbeefdeadbeef
		.dword	0xfeedbeefdeadbeef
		.dword	0xfeedbeefdeadbeef
		.dword	0xfeedbeefdeadbeef
