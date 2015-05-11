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

uint8_t source1[] = { 0xBE };
uint8_t dest1[]   = { 0 };

dma_instruction dma_program1[] = {
	DMA_OP_TRANSFER(TS_BITS_8),
	DMA_OP_STOP
};

uint64_t source2[] = { 0xDEADBEEF };
uint64_t dest2[]   = { 0 };

dma_instruction dma_program2[] = {
	DMA_OP_TRANSFER(TS_BITS_64),
	DMA_OP_STOP
};

int test(void)
{
	dma_set_pc(DMA_PHYS, 0, dma_program1);
	dma_set_source_address(DMA_PHYS, 0, (uint64_t)source1);
	dma_set_dest_address(DMA_PHYS, 0, (uint64_t)dest1);

	dma_start_transfer(DMA_PHYS, 0);

	//We can set up the new transfer whilst the old transfer is happening.

	dma_set_pc(DMA_PHYS, 0, dma_program2);
	dma_set_source_address(DMA_PHYS, 0, (uint64_t)source2);
	dma_set_dest_address(DMA_PHYS, 0, (uint64_t)dest2);

	while (!dma_thread_ready(DMA_PHYS, 0)) {
		DEBUG_NOP();
		DEBUG_NOP();
		DEBUG_NOP();
		DEBUG_NOP();
	}

	dma_start_transfer(DMA_PHYS, 0);

	while (!dma_thread_ready(DMA_PHYS, 0)) {
		DEBUG_NOP();
		DEBUG_NOP();
		DEBUG_NOP();
		DEBUG_NOP();
	}

	assert(dest1[0] == 0xBE);
	assert(dest2[0] == 0xDEADBEEF);

	return 0;
}

#ifdef DMAMODEL
int main()
{
	test();
	return 0;
}
#endif
