#-
# Copyright (c) 2013 Colin Rothwell
# All rights reserved.
#
# This software was developed by Colin Rothwell as part of his summer internship
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

# This is a bit special. It is only meant to work when run in conjunction with
# cherictl.

.set mips64
.set noreorder
.set nobopt
.set noat

        .text
        .global start
        .ent start

start:
    # 12 should be t0: easier to confirm 12 in cherictl.
    li $12, 0 # loop while t0 hasn't been kicked externally.
poll:
    beq $12, $0, poll
    nop

    li $t1, 234 # shouldn't be traced
    add $t1, $t1, $t1
    addi $t1, $t1, 100

	li $t2, 1
	mtc0 $t2, $9, 6 # register 9, sel 6 is the "tracing enabled" register
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	add $t2, $t2, $t2 # something to trace
	add $t2, $t2, $t2 
    li $t2, 0 # set t2 to zero
	mtc0 $t2, $9, 6 # disable tracing
    nop
    nop
    addi $t2, 345 # shouldn't be traced
	ori $t2, 255 # likewise

	# Dump registers on the simulator (gxemul dumps regs on exit)
	mtc0 $at, $26
	nop
	nop

	# Terminate the simulator
	mtc0 $at, $23
end:
	b end
	nop
	.end start
