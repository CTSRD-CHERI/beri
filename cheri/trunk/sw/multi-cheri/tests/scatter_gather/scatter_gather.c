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

#include "scatter_gather.h"
#include "core.h"
#include "uart.h"
#include "fifo.h"

#define MAX_TOKEN 50

static fifo_t scatter_to_process;
static fifo_t process_to_gather;

static int end_scatter_gather;

static void scatter()
{
    unsigned long int nb_token = 0;
    while (nb_token < MAX_TOKEN)
    {
        // display critical section //
        uart_lock_acquire();
        uart_puts("scatter on core ");
        uart_putd(core_id());
        uart_puts(" - generating token ");
        uart_putd(nb_token);
        uart_putc('\n');
        uart_lock_release();
        // display critical section //
        fifo_enqueue(&scatter_to_process, nb_token);
        nb_token++;
    }
    // display critical section //
    uart_lock_acquire();
    uart_puts("scatter on core ");
    uart_putd(core_id());
    uart_puts(" - END\n");
    uart_lock_release();
    // display critical section //
}

static void process()
{
    while (end_scatter_gather == 0)
    {
        unsigned int tmp_token;
        if(fifo_dequeue_non_blocking(&scatter_to_process, &tmp_token))
        {
            fifo_enqueue(&process_to_gather, tmp_token);
            // display critical section //
            uart_lock_acquire();
            uart_puts("process on core ");
            uart_putd(core_id());
            uart_puts(" - processing token ");
            uart_putd(tmp_token);
            uart_putc('\n');
            uart_lock_release();
            // display critical section //
        }
    }
    // display critical section //
    uart_lock_acquire();
    uart_puts("process on core ");
    uart_putd(core_id());
    uart_puts(" - END\n");
    uart_lock_release();
    // display critical section //
}

static void gather()
{
    unsigned long int nb_token = 0;
    while (nb_token != MAX_TOKEN)
    {
        unsigned int tmp_token = fifo_dequeue(&process_to_gather);
        nb_token++;
        // display critical section //
        uart_lock_acquire();
        uart_puts("gather on core ");
        uart_putd(core_id());
        uart_puts(" - consuming token ");
        uart_putd(tmp_token);
        uart_putc('\n');
        uart_lock_release();
        // display critical section //
    }
    // display critical section //
    uart_lock_acquire();
    uart_puts("gather on core ");
    uart_putd(core_id());
    uart_puts(" - END\n");
    uart_lock_release();
    // display critical section //
    end_scatter_gather = 1;
}

void scatter_gather_init (test_function_t * mtest)
{
    if (core_total() < 3)
    {
        uart_puts("scatter-gather test requires at least 3 cores\n");
        core_abort();
    }

    uart_puts("scatter-gather test initializing ...\n");
    mtest[0] = &scatter;
    uart_puts("scatter function on core 0...\n");
    int i;
    for (i = 1; i < core_total()-1; i++)
    {
        mtest[i] = &process;
        uart_puts("process function on core ");
        uart_putd(i);
        uart_puts("...\n");
    }
    mtest[core_total()-1] = &gather;
    uart_puts("gather function on core ");
    uart_putd(core_total()-1);
    uart_puts("...\n");

    fifo_init(&scatter_to_process);
    uart_puts("scatter -> process fifo initialized\n");

    fifo_init(&process_to_gather);
    uart_puts("process -> gather fifo lock initialized\n");

    uart_lock_init();
    uart_puts("uart lock initialized\n");

    end_scatter_gather = 0;
    uart_puts("end variable initialized\n");
}
