#-
# Copyright (c) 2012 Robert M. Norton
# Copyright (c) 2012 David Chisnall
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
		dadd    $s0, $zero, $ra          # Don't save existing s0, init.s doesn't expect it to be preserved

		addi    $a0, $zero, 0            # TLB entry 0
		dla     $a1, testdata            # Physical address testdata
		addi    $a2, $zero, 0x200
		dsll    $a2, 13                  # Virtual address 0x400000
		li	$a3, 0                   # Page mask of 0 (4k page)
		jal     install_tlb_entry
		nop

		addi    $a0, $zero, 1            # TLB entry 1
		dla     $a1, testdata2           # Physical address testdata2
		addi    $a2, $zero, 0x400
		dsll    $a2, 29                  # Virtual address 0x8000000000
		li	$a3, 0                   # Page mask of 0 (4k page)
		jal     install_tlb_entry
		nop

		addi    $a4, $zero, 0x200        # Load testdata via its virtual address into a5
		dsll    $a4, $a4, 13
		ld      $a5, 0($a4)
		addi    $a4, $zero, 0x400        # Load testdata2 via its virtual address into a4
		dsll    $a4, $a4, 29
		ld      $a4, 0($a4)

		jr      $s0
		nop
.end    test
	
	.data
	.align 12                            # Align on 4KB page boundary
testdata:
	.dword 0xfedcba9876543210            # Magic number for the test in page 1
	.space 4088
testdata2:
	.dword 0xba9876543210fead            # Magic number for the test in page 2
