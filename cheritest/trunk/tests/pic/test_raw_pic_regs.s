#-
# Copyright (c) 2014 Jonathan Woodruff
# All rights reserved.
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

# Very basic test that PIC registers contain correct initial values and can
# be written and read back.      

	
.set mips64
.set noreorder
.set nobopt
	
		.global start
start:
    # Load PIC base address
		dli   $a0, 0x900000007f804000
    # Test PIC control registers
    li    $t0, 127
    # $s0==0 means control registers read ok.  This is default.
    li    $s0, 0
control_reg_loop:
    sll   $t1, $t0, 3
    daddu $t1, $a0, $t1
    ld    $t1, 0($t1)
    beq   $t1, $0, control_reg_skip_fail
    nop
    addi  $s0, $s0, 1
control_reg_skip_fail:
    bne   $t0, $0, control_reg_loop
    addi  $t0, $t0, -1
    
    # Test PIC read registers
    dli   $a0, 0x900000007f806000
    li    $t0, 15
    # $s1==0 means read registers read ok.  This is default.
    li    $s1, 0
read_reg_loop:
    daddu $t1, $a0, $t0
    lbu   $t1, 0($t1)
    beq   $t1, $0, read_reg_skip_fail
    nop
    addi  $s1, $s1, 1
read_reg_skip_fail:
    bne   $t0, $0, read_reg_loop
    addi  $t0, $t0, -1
	
		# Test setting PIC interrupt
		# Enable soft interrupt 1
		dli   $a0, 0x900000007f804000 + 8*64
		ori   $t0, $0, 0x1
		sll   $t0, $t0, 31
		sd    $t0, 0($a0)
		# Load read address
    dli   $a0, 0x900000007f806008
    ld    $t0, 0($a0)
    # Load set address
    dli   $a1, 0x900000007f806000 + 136
    ori   $t0, $t0, 0x1
    sd    $t0, 0($a1)
    ld    $s2, 0($a0)
    # Load clear address
    dli   $a1, 0x900000007f806000 + 264
    sd    $t0, 0($a1)
    ld    $s3, 0($a0)
    
		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop
    
		# Terminate the simulator
    mtc0 $s0, $23
end:
		b end
		nop
