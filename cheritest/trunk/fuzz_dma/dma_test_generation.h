/*-
 * Copyright (c) 2015 Colin Rothwell
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

#ifndef DMA_TEST_GENERATION_H
#define DMA_TEST_GENERATION_H

#include "DMAAsm.h"
#include "DMAModel.h"

static unsigned long next = 1;
#define RAND_LIMIT 32767

int myrand();
void mysrand(unsigned _seed);


struct transfer_record;

struct transfer_record {
	dma_address source;
	dma_address destination;
	enum transfer_size size;

	struct transfer_record *next;
};

struct transfer_record *list_transfers(dma_instruction *_program);
void free_transfer_list(struct transfer_record *_current);

dma_instruction *generate_random_dma_program(unsigned int _seed);

#endif
