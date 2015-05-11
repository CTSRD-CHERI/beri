#-
# Copyright (c) 2014 Alexandre Joannou
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C (BERI) under one or more contributor
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

.text

reset :
    b       init
    nop

#####################
## syscall handler ##
#####################

syscall_start :
    # cause in register 1
    mfc0    $1, $13
    # dump register file
    mtc0    $at, $26
    # stop simulator
    mtc0    $at, $23
syscall_end :
    nop


#############
## memcopy ##
#############

memcopy :
    beq     $a2, $zero, memcopy_end
	nop
    lb      $t0, 0($a1)
	sb      $t0, 0($a0)
	daddiu	$a0, 1
	daddiu	$a1, 1
	daddiu	$a2, -1
	b       memcopy
	nop
memcopy_end :
    jr      $ra
    nop	

init :

    # prepare status register
	mfc0    $k0, $12            # get the current status register
    li      $k1, 0xF0000000     # prepare the bits to set (see MIPS status register description)
    or      $k0, $k0, $k1       # set the bits
    mtc0    $k0, $12            # store it back

    # load CP0 register 15 (shadow 6 , core ID and amount of cores)
    mfc0    $k0, $15, 6
    # get the total number of cores in $k1
	srl     $k1, $k0, 16
	daddu   $k1, $k1, 1
    # get the core ID in $k0
	andi    $k0, $k0, 0xFFFF

    # get the memory chunk size reserved for this core
    dla     $t0, PRIVATE_DRAM_SIZE
    ddivu   $t0, $k1
    mflo    $t0                             # t0 <= chunck_size
    daddi   $t0, $t0, -1                    # align on 64 bits (((x-1)>>3)<<3)+8
    dsrl    $t0, 3                          #
    dsll    $t0, 3                          #
    daddi   $t0, 8                          #

    # set private stack pointer
    dmultu  $k0, $t0                        # bottom of the private chunk
    mflo    $t1
    dla     $t2, DRAM_BASE                  # t2 <= DRAM_BASE
    dla     $t3, MIPS_XKPHYS_CACHED_NC_BASE # t3 <= MIPS_XKPHYS_CACHED_NC_BASE 
    or      $t2, $t2, $t3                   # t2 <= DRAM_BASE physical mapped
    daddu   $t1, $t1, $t2                   # t1 <= private chunk base
    daddi   $t1, $t1, -1                    # align on 64 bits (((x-1)>>3)<<3)+8
    dsrl    $t1, 3                          #
    dsll    $t1, 3                          #
    daddi   $t1, 8                          #
    daddu   $sp, $t1, $t0                   # sp <= private stack base
    move    $fp, $sp                        # fp <= private frame pointer

    # TODO smthg to initialize interrupt vector / syscall / exceptions
    dla     $a0, MIPS_GENERAL_EXP_BASE      # dest
    dla     $a1, syscall_start              # src
    dli     $a2, syscall_end-syscall_start  # len
    jal     memcopy
    nop

gotomain :

    dla     $t9, main
    dla     $t8, MIPS_XKPHYS_CACHED_NC_BASE # t8 <= MIPS_XKPHYS_CACHED_NC_BASE 
    or      $t9, $t9, $t8                   # t2 <= DRAM_BASE physical mapped
    # jump in kernel mode
    #jal     $t9
    #nop
    # jump in user mode
    dla     $ra, end                        # ra <= end
    dmtc0   $t9, $14                        # EPC <= main
    eret

end :

    syscall
    nop
