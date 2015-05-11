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

#include "shared_array.h"
#include "core.h"
#include "uart.h"

#define ARRAY_TYPE unsigned long long
#define ARRAY_SIZE 2000
#define NB_RUN 10000

static ARRAY_TYPE test_array[ARRAY_SIZE];
static unsigned long long counter_array[MAX_CORE];

static poke_array()
{
    ARRAY_TYPE dummy = 0;
    while (counter_array[core_id()] < NB_RUN)
    {
        test_array[counter_array[core_id()]] = core_id();
        dummy = test_array[counter_array[core_id()]] = core_id();
        dummy++;
        counter_array[core_id()]++;
        uart_putc('A'+core_id());
    }
}

void shared_array_init (test_function_t * mtest)
{
    uart_puts("shared array test initializing ...\n");
    unsigned long long i;
    for (i = 0; i < core_total(); i++)
    {
        mtest[i] = &poke_array;
        counter_array[i] = 0;
        uart_puts("poke_array function on core ");
        uart_putd(i);
        uart_puts(" ( ");
        uart_putc('A'+i);
        uart_puts(" ) ...\n");
    }

    uart_puts("initializing shared array\n");
    for (i = 0; i < ARRAY_SIZE; i++)
    {
        test_array[i] = 0;
        uart_putc('.');
    }
    uart_putc('\n');
    uart_puts("====================================\n");
}
