/* Copyright 2016 Matthew Naylor
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream
 * Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
 * license agreements.  See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.  BERI licenses this
 * file to you under the BERI Hardware-Software License, Version 1.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at:
 *
 *   http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 */

.set noreorder

  # Get core id
  mfc0   $t0, $15, 6
  andi   $t0, $t0, 0xffff

  # Get thread id and number of threads
  mfc0   $t1, $15, 7
  srl    $t2, $t1, 16
  addi   $t2, $t2, 1       # Num threads
  andi   $t1, $t1, 0xffff  # Thread id

  # Compute instance id
  mul    $t0, $t0, $t2     # Instance id = core id * num threads
  add    $t0, $t0, $t1     #             + thread id
  
  # Set stack pointer to DRAM_TOP - (instance id * 1M)
  dla    $sp, DRAM_TOP
  dmul   $t0, $t0, 0x100000
  dsubu  $sp, $sp, $t0

  # Dump registers
  # mtc0   $zero, $26

  daddu $sp, $sp, -32    # Allocate 32 bytes of stack space

  dla   $t9, main
  jal   $t9
  nop

  #mtc0  $zero, $23       # Terminate simulator

  b .
  nop
