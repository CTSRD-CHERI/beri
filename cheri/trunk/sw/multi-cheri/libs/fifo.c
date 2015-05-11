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

#include "fifo.h"
#include "lock.h"
#include "core.h"

void fifo_init(fifo_t * fifo)
{
    unsigned int i;
    for (i = 0; i < DEPTH; i++)
        fifo->data[i] = 0;
    fifo->read_idx = 0;
    fifo->write_idx = 0;
    fifo->fill_state = 0;
    lock_init(&fifo->lock);
}

void fifo_enqueue(fifo_t * fifo, unsigned int data)
{
    unsigned int done = 0;
    while(!done)
    {
        lock_acquire(&fifo->lock);
        if (fifo->fill_state < DEPTH)
        {
            fifo->data[fifo->write_idx] = data;
            fifo->write_idx = (fifo->write_idx + 1) % DEPTH;
            fifo->fill_state++;
            done = 1;
        }
        lock_release(&fifo->lock);
        core_delay(core_random()%500);
    }
}

int fifo_enqueue_non_blocking(fifo_t * fifo, unsigned int data)
{
    int done = 0;
    lock_acquire(&fifo->lock);
    if (fifo->fill_state < DEPTH)
    {
        fifo->data[fifo->write_idx] = data;
        fifo->write_idx = (fifo->write_idx + 1) % DEPTH;
        fifo->fill_state++;
        done = 1;
    }
    lock_release(&fifo->lock);
    return done;
}

unsigned int fifo_dequeue(fifo_t * fifo)
{
    unsigned int done = 0;
    unsigned ret = 0;
    while(!done)
    {
        lock_acquire(&fifo->lock);
        if (fifo->fill_state > 0)
        {
            ret = fifo->data[fifo->read_idx];
            fifo->read_idx = (fifo->read_idx + 1) % DEPTH;
            fifo->fill_state--;
            done = 1;
        }
        lock_release(&fifo->lock);
        core_delay(core_random()%500);
    }
    return ret;
}

int fifo_dequeue_non_blocking(fifo_t * fifo, unsigned int * buf)
{
    int done = 0;
    lock_acquire(&fifo->lock);
    if (fifo->fill_state > 0)
    {
        *buf = fifo->data[fifo->read_idx];
        fifo->read_idx = (fifo->read_idx + 1) % DEPTH;
        fifo->fill_state--;
        done = 1;
    }
    lock_release(&fifo->lock);
    return done;
}
