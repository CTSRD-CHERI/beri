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
 * BERI comlib.c
 *
 * Some routines used by test.c.
 */

#include "../../../../cherilibs/trunk/include/parameters.h"

#define DRAM_BASE (0x9800000000000000)
#define IO_RD(x) (*(volatile unsigned long long*)(x))
#define IO_RD32(x) (*(volatile int*)(x))
#define IO_WR(x, y) (*(volatile unsigned long long*)(x) = y)
#define IO_WR32(x, y) (*(volatile int*)(x) = y)
#define IO_WR_BYTE(x, y) (*(volatile unsigned char*)(x) = y)

char * heap = (char *)DRAM_BASE;

inline int getCount()
{
        int count;
        asm volatile("dmfc0 %0, $9": "=r" (count));
        return count;
}

void * malloc(unsigned long size) {
  void * rtnPtr = heap;
  if (heap < (char *)0x9800000010000000) heap += size;
  else heap = (char *)DRAM_BASE;
  rtnPtr = (char *) ((long long)rtnPtr & 0xFFFFFFFFFFFFFFF0);
  return rtnPtr;  
}

void free(void * ptr) {
  
}
