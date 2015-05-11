/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
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

#include "armArray.h"

int box_get_jal(int i) {
  return ((i^0xF00B) + 100);
}

int box_get_cjalr(int i) {
  //
  //asm volatile("jalr %0": : "g" (box_get_offset));
  
  int retVal = ((i^0xF00B) + 100);
  asm volatile("CMOVE $c0, $c24");
  asm volatile("CJR $31($c24)");
  asm volatile("move $v0, %0": : "r" (retVal) : "v0");
  return 0;
}

int box_get_ccall(int i) {
  //
  //asm volatile("jalr %0": : "g" (box_get_offset));
  
  int retVal = ((i^0xF00B) + 100);
  asm volatile("CCALL $c1, $c2");
  asm volatile("move $v0, %0": : "r" (retVal) : "v0");
  return 0;
}

int box_get_user(int i) {
  int retVal = ((i^0xF00B) + 100);
  asm volatile("move $v0, %0": : "r" (retVal) : "v0");
  asm volatile("syscall 0; nop; nop; nop; nop; nop; nop; nop; nop;");
  return 0;
}
