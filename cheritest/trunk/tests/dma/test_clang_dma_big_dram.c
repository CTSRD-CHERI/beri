/*-
 * Copyright (c) 2014-2015 Colin Rothwell
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
#include "stdint.h"

#ifdef DMAMODEL
#include "DMAModelSimple.h"
#include "ModelAssert.h"
#else
#include "DMAControl.h"
#include "mips_assert.h"
#endif

// This is as much as we can run on the simulator. Oh well!
const uint64_t size = 0x2000;

// Start offset, so we don't trash the test itself.
uint64_t source     = 0x9000000020000000;
uint64_t dest       = 0x9000000030000000;

// We copy from the bottom 512MiB of memory into the top 512 MiB.
// The program is loop unrolled to minimise the missed cycles due to the loop
// instruction.
// It is unrolled to a total program size of 8 instructions so as to fit
// exactly in a DMA ICache line.
// Loop reg value is size / (5 * 32) - 1

dma_instruction dma_program[] = {
	DMA_OP_SET(LOOP_REG_0, size / (5 * 32) - 1),
	DMA_OP_TRANSFER(TS_BITS_256),
	DMA_OP_TRANSFER(TS_BITS_256),
	DMA_OP_TRANSFER(TS_BITS_256),
	DMA_OP_TRANSFER(TS_BITS_256),
	DMA_OP_TRANSFER(TS_BITS_256),
	DMA_OP_LOOP(LOOP_REG_0, 5),
	DMA_OP_STOP
};

int test(void)
{
#ifdef DMAMODEL
	source = (uint64_t)malloc(size);
	dest = (uint64_t)malloc(size);
#endif
	uint16_t volatile *cursor, count = 0;
	for (cursor = (uint16_t *)source; cursor < (source + size / 2); ++cursor) {
		*cursor = count;
		++count;
	}

	dma_set_pc(DMA_PHYS, 0, dma_program);
	dma_set_source_address(DMA_PHYS, 0, source);
	dma_set_dest_address(DMA_PHYS, 0, dest);

	dma_start_transfer(DMA_PHYS, 0);

	while (!dma_thread_ready(DMA_PHYS, 0)) {
		for (uint32_t stall = 0; stall < 1000; ++stall) {
			DEBUG_NOP();
			DEBUG_NOP();
			DEBUG_NOP();
			DEBUG_NOP();
		}
	}

	count = 0;
	for (cursor = (uint16_t *)dest; cursor < (dest + size / 2); ++cursor) {
		if (*cursor != count) {
			DEBUG_DUMP_REG(10, cursor);
			DEBUG_DUMP_REG(11, *cursor);
			DEBUG_DUMP_REG(12, count);
		}
		assert(*cursor == count);
		++count;
	}

	return 0;

}

#ifdef DMAMODEL
int main()
{
	test();
	return 0;
}
#endif
