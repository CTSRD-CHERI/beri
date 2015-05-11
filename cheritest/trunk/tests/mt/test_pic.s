#-
# Copyright (c) 2012 Robert M. Norton
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

# Simple TLB test which configures a TLB entry for the lowest virtual
# page in the xuseg segment and attempts a store via it.

.set mips64
.set noreorder
.set nobopt
.set noat

.global test
test:   
        dla     $a0, 0x900000007f804000  # PIC_BASE
        dla     $t0, 0x80000004          # enable irq 2, forward to IP4
        ld      $s0, 8($a0)
        sd      $t0, 16($a0)
        dadd    $a1, $a0, 0x2000         # PIC_IP_READ_BASE        
        li      $t0, 6
        sd      $t0, 128($a1)            # set irq 2 and 1
        ld      $a2, 0($a1)              # read irq pending
        dmfc0   $a3, $13                 # read cause reg
        sd      $t0, 256($a1)            # clear irq 2
        ld      $a4, 0($a1)              # read irq pending
	#jr      $ra
	#nop
        mtc0    $v0, $26 
        nop    
        nop  
        mtc0    $v0, $23   

end:
	b       end
	nop
