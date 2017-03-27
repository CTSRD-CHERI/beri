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

#include "arch.h"

// Code specific to MIPS64 processors

// Instances ==================================================================

inline int get_core_id()
{
  uint64_t x;
  asm volatile("dmfc0 %0, $15, 6": "=r" (x));
  return (int) (x & 0xffff);
}

inline int get_num_cores()
{
  uint64_t x;
  asm volatile("dmfc0 %0, $15, 6": "=r" (x));
  x >>= 16;
  x++;
  return (int) (x & 0xffff);
}

inline int get_thread_id()
{
  uint64_t x;
  asm volatile("dmfc0 %0, $15, 7": "=r" (x));
  return (int) (x & 0xffff);
}

inline int get_threads_per_core()
{
  uint64_t x;
  asm volatile("dmfc0 %0, $15, 7": "=r" (x));
  x >>= 16;
  x++;
  return (int) (x & 0xffff);
}

int arch_get_process_id()
{
  return get_threads_per_core() * get_core_id() + get_thread_id();
}

int arch_get_num_processes()
{
  return get_threads_per_core() * get_num_cores();
}


uint32_t rmw(volatile uint32_t* p, uint32_t wr)
{
  uint32_t rd;
  asm volatile (
      "1:                                \n"
      "ll     %0, 0(%2)                  \n"
      "move   $8, %1                     \n"
      "sc     $8, 0(%2)                  \n"
      "beqz   $8, 1b                     \n"
  : /* output operands */
    "=&r"(rd)
  : /* input operands */
    "r"(wr),
    "r"(p)
  : /* clobbered registers */
    "$8"
  );
  return rd;
}

#if 0
// Hardware counter ===========================================================

uint32_t arch_get_counter()
{
  uint64_t x;
  asm volatile("dmfc0 %0, $9": "=r" (x));
  return (uint32_t) x;
}

// Barrier synchronisation ====================================================

// Shared variables
static volatile uint64_t barrier1 = 0;
static volatile uint64_t barrier2 = 0;

void barrier_wait(
    volatile uint64_t* barrier
  , uint64_t incr_amount
  , uint64_t reach
  )
{
  asm volatile (
      "1:                                \n"
      "lld    $8, 0(%0)                  \n"
      "dadd   $8, $8, %1                 \n"
      "scd    $8, 0(%0)                  \n"
      "beqz   $8, 1b                     \n"
      "2:                                \n"
      "ld     $8, 0(%0)                  \n"
      "bne    $8, %2, 2b                 \n"
      "sync                              \n"
  : /* output operands */
  : /* input operands */
    "r"(barrier),
    "r"(incr_amount),
    "r"(reach)
  : /* clobbered registers */
    "$8"
  );
}

void arch_barrier_up(int numCores)
{
  barrier_wait(&barrier1, 1, numCores);
  barrier_wait(&barrier2, 1, numCores);
}

void arch_barrier_down()
{
  barrier_wait(&barrier1, -1, 0);
  barrier_wait(&barrier2, -1, 0);
}
#endif
