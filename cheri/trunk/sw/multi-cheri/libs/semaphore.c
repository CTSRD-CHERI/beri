/*-
 * Copyright (c) 2014 Alexandre Joannou
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
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C (BERI) under one or more contributor
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

#include "semaphore.h"

void semaphore_init(semaphore_t * semaphore, long unsigned int amnt)
{
    *semaphore = amnt;
    asm volatile ("sync           \n");
}

void semaphore_wait(semaphore_t * semaphore)
{
    asm volatile (
        "semaphore_decrement:           \n"
        "lld    $8, 0(%0)               \n"
        "daddiu $9, $8, -1              \n"
        "scd    $9, 0(%0)               \n"
        "beqz   $9, semaphore_decrement \n"
        "wait_others:                   \n"
        "ld     $8, 0(%0)               \n"
        "sync                           \n"
        "bnez   $8, wait_others         \n"
    : /* output operands */
    :"r"(semaphore) /* input operandss */
    :"$8", "$9" /* clobbered registers */);
}

