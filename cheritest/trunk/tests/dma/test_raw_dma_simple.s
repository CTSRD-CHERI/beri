#-
# Copyright (c) 2014 Colin Rothwell
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
# Unit test for a simple transfer on the DMA engine
#

		.text
		.global start
start:
		# Load address of DMA config register into t0
		dla	$t0, dma_addr # Load address of address of DMA
		ld	$t0, 0($t0) # Load address of DMA

		# Set PC to address of program
		dla	$t1, prog
		sd	$t1, 8($t0)

		# Set source address
		dla	$t1, source
		sd	$t1, 16($t0)

		# Set destination address
		dla	$t1, dest
		sd	$t1, 24($t0)

		# Start execution
		li	$t1, 0x1
		sw	$t1, 4($t0)

		# Poll until completion
poll:
		lw	$t1, 0($t0)
		beq	$t1, $0, poll
		nop

		# Invalidate cache!
		dla	$t1, dest
		cache 0x13, 0($t1)

		# Load result
		dla	$t1, dest
		ld	$s0, 0($t1)

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
		mtc0 $v0, $23
end:
		b end
		nop

		.data
dma_addr:	.dword	0x900000007F900000
prog:		.word	0x26000000 # Transfer 64 bits
 		.word	0x60000000 # Stop
source:		.dword	0x12345678
dest:		.dword	0xDEADBEDE
