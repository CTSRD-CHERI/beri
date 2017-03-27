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

#include "DMAAsm.h"
#include "DMAControl.h"
#include "mips_assert.h"
#include "mips_tlb.h"

/* This sets the DMA_ADDR macro to the correct value. */
$define_dma

#define DMA_THREAD_COUNT 4
#define THREAD_COUNT $thread_count
static unsigned long next = $seed;

volatile uint8_t *source_addrs[] = { $source_addrs };
volatile uint8_t *dest_addrs[]   = { $dest_addrs };
dma_instruction *dma_program[]   = { $programs };

#define RAND_LIMIT 32767

int myrand(void) {
	next = next * 1103515245 + 12345;
	return ((unsigned)(next/65536) % 32768);
}

int test(void)
{
	int i;
	int active_threads[THREAD_COUNT];
	int active_thread_count = THREAD_COUNT;
	// Threads to switch to
	int thread_index[3], thread[3];

	$set_sources

	for (i = 0; i < THREAD_COUNT; ++i) {
		dma_set_pc(DMA_ADDR, i, dma_program[i]);
		dma_set_source_address(DMA_ADDR, i, (uint64_t)source_addrs[i]);
		dma_set_dest_address(DMA_ADDR, i, (uint64_t)dest_addrs[i]);

		active_threads[i] = i;
	}

	for (i = 0; i < 3; ++i) {
		thread_index[i] = myrand() % active_thread_count;
		thread[i] = active_threads[thread_index[i]];
	}

	for (i = 0; i < THREAD_COUNT; ++i) {
		dma_start_transfer(DMA_ADDR, i);
	}

	while (active_thread_count != 0) {
		// We want to switch threads as aggressively as possible, as
		// that is where failures are more likely to occur. However,
		// we also don't want to switch to inactive threads. My
		// informal solution is to to do three switches in quick
		// succession, wait, and then test for copmleteness.
		dma_switch_to(DMA_ADDR, DMA_THREAD_COUNT, thread[0]);
		dma_switch_to(DMA_ADDR, DMA_THREAD_COUNT, thread[1]);
		dma_switch_to(DMA_ADDR, DMA_THREAD_COUNT, thread[2]);

		int wait_periods = myrand() % 20;
		for (i = 0; i < wait_periods; ++i) {
			DEBUG_NOP();
			DEBUG_NOP();
			DEBUG_NOP();
			DEBUG_NOP();
		}

		// To remove a thread from being active, we copy the last
		// thread over it, then shrink the area of the array we
		// access.
		
		if (dma_thread_ready(DMA_ADDR, thread[2])) {
			active_threads[thread_index[2]] =
				active_threads[active_thread_count - 1];
			--active_thread_count;
		}

		for (i = 0; i < 3; ++i) {
			thread_index[i] = myrand() % active_thread_count;
			thread[i] = active_threads[thread_index[i]];
		}
	}

	$asserts

	return 0;
}

