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

#ifndef _MULTI_CHERI_FIFO_
#define _MULTI_CHERI_FIFO_

#include "lock.h"

#define DEPTH 32

typedef struct
{
    unsigned int read_idx;
    unsigned int write_idx;
    unsigned int data[DEPTH];
    unsigned int fill_state;
    lock_t lock;
} fifo_t;

void fifo_init(fifo_t * fifo);
void fifo_enqueue(fifo_t * fifo, unsigned int data);
int fifo_enqueue_non_blocking(fifo_t * fifo, unsigned int data);
unsigned int fifo_dequeue(fifo_t * fifo);
int fifo_dequeue_non_blocking(fifo_t * fifo, unsigned int * buf);

#endif
