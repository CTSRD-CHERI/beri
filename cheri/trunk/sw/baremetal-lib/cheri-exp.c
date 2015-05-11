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

/*
 * CHERI cheri-exp.c
 *
 * Exception handlers!
 *
 * These routines will be jumped to by the exception stubs in lib.s
 */

extern void __writeString(char* s);
extern void __writeHex(unsigned long long n);
extern void __writeDigit(unsigned long long n);
extern char __box_start;

void * kernelEntry;

void common_handler()
{
  long long val;
  long long op1;
  long long op2;
  long long tmp;
  asm volatile("move %0, $a0":"=r" (op1));
  asm volatile("move %0, $a1":"=r" (op2));
  // On any syscall, switch to user mode and jump to the address in $a0.
  asm volatile("mfc0 %0, $13": "=r" (val));
  val = ((val>>2)&0x1f);
  switch(val) {
    default:
      // EPC
      asm volatile("dmfc0 %0, $14": "=r" (val));
      __writeString("\nException! \nVictim:");
      __writeHex(val);
      val += 4;
      asm volatile("dmtc0 %0, $14": :"r" (val));
      // Cause
      asm volatile("mfc0 %0, $13": "=r" (val));
      val = ((val>>2)&0x1f);
      __writeString("\nCause:");
      __writeDigit(val);
      // Bad Virtual Address
      asm volatile("mfc0 %0, $8": "=r" (val));
      __writeString("\nBad Virtual Address:");
      __writeHex(val);
      // Capability Cause and Register
      asm volatile("CGetCause %0": "=r" (val));
      __writeString("\nCap Cause:");
      val = ((val>>8)&0xff);
      __writeDigit(val);
      asm volatile("CGetCause %0": "=r" (val));
      __writeString("    Cap Reg:");
      val = (val&0xff);
      __writeDigit(val);
      __writeString("\n");
      break;
  }
}

void tlb_handler()
{
  long long *record;
  long long entryLo;
  long long *boxBase;
  long long *badVAddr;
  asm volatile("dli %0, 0x0000000040004000": "=r" (boxBase));
  asm volatile("dmfc0 %0, $8": "=r" (badVAddr));
  if (badVAddr < boxBase) return;
  // EPC
  asm volatile("dmfc0 %0, $20": "=r" (record));
  record = (long long *)((long long)record|0x9800000001000000);
  if (record[0] == 0) {
    asm volatile("mfc0 %0, $10": "=r" (entryLo));
    entryLo = entryLo >> 6;
    // Mask off the bottom configuration bits (6)
    // as well as the least significant PFN .
    entryLo &= ~0x7F;
    // Set up cached, dirty, valid and not global.
    entryLo |= 0x1E;
    // Write the even page entry
    record[0] = entryLo;
    // Write the odd page entry
    entryLo |= 0x40; 
    record[1] = entryLo;
  }
  entryLo = record[0];
  asm volatile("dmtc0 %0, $2": :"r" (entryLo));
  entryLo = record[1];
  asm volatile("dmtc0 %0, $3": :"r" (entryLo));
  asm volatile("tlbwr");
}
