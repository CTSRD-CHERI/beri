#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2013 Alan A. Mujumdar
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
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
# Exercise cache instructions
#
# Execute a series of cache instructions that are found in the kernel.  We
# currently don't check if they are correct, but merely check that they don't
# lock up the processor.  Since we have a write-through L1 cache, the only 
# function of the cache instructions is to synchronize L1 instruction and data
# caches.  We don't currently support cache instructions to the L2.
# 
#

		.global start

		#
		# Setup one stack per core
		#
                mfc0    $k0, $12 
                li      $k1, 0xF0000000 
                or      $k0, $k0, $k1  
                mtc0    $k0, $12
                dla     $sp, __sp
                mfc0    $t0, $15, 6 
                andi    $t0, $t0, 0xFFFF 
                dli     $k0, 0x400  
                mul     $k0, $k0, $t0
                daddu   $sp, $sp, $k0 
                daddu   $sp, $sp, -64 
                beqz    $t0, pic1 
                nop 

start:		
		nop
pic0:
		#
		# PIC 0 Test
		#
	        dla     $a0, 0x900000007f804000  # PIC_BASE 
   	 	dla     $t0, 0x80000004          # enable irq 2, forward to IP4 
  	 	sd      $t0, 16($a0)         
	        dadd    $a1, $a0, 0x2000         # PIC_IP_READ_BASE 
	        li      $t0, 6                            
	        sd      $t0, 128($a1)            # set irq 2 and 1 
	        ld      $a2, 0($a1)              # read irq pending 
		dmfc0   $a3, $13                 # read cause reg    
		sd      $t0, 256($a1)            # clear irq 2   
		ld      $a4, 0($a1)              # read irq pending  
		j       dump
		nop

pic1:
		nop
		#
		# PIC 1 Test
		#
	        dla     $a0, 0x900000007f808000  # PIC_BASE 
   	 	dla     $t0, 0x80000004          # enable irq 2, forward to IP4 
  	 	sd      $t0, 16($a0)         
	        dadd    $a1, $a0, 0x2000         # PIC_IP_READ_BASE 
	        li      $t0, 6                            
	        sd      $t0, 128($a1)            # set irq 2 and 1 
	        ld      $a2, 0($a1)              # read irq pending 
		dmfc0   $a3, $13                 # read cause reg    
		sd      $t0, 256($a1)            # clear irq 2   
		ld      $a4, 0($a1)              # read irq pending  
		j 	dump
		nop

dump:
		# Dump registers in the simulator
		mtc0    $v0, $26 
		nop
		nop                

                # Terminate the simulator 
                mtc0    $v0, $23 

end:
		b       end
		nop
