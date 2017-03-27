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
#include "stdint.h"

#ifdef DMAMODEL
#include "DMAModelSimple.h"
#include "ModelAssert.h"
#else
#include "DMAControl.h"
#include "mips_assert.h"
#endif

uint32_t source[6] = { 0xA, 0xB, 0xC, 0xD, 0xE, 0xF };
uint32_t dest[6] = {0, 0, 0, 0, 0, 0};

dma_instruction dma_program[4];

int test(void)
{
	dma_program[0] = dma_op_set(LOOP_REG_0, 4);
	dma_program[1] = dma_op_transfer(TS_BITS_32);
	dma_program[2] = dma_op_loop(LOOP_REG_0, 1);
	dma_program[3] = dma_op_stop();

	dma_set_pc(DMA_PHYS, 0, dma_program);
	dma_set_source_address(DMA_PHYS, 0, (uint64_t)source);
	dma_set_dest_address(DMA_PHYS, 0, (uint64_t)dest);

	dma_start_transfer(DMA_PHYS, 0);

	while (!dma_thread_ready(DMA_PHYS, 0)) {
		asm("nop");
		asm("nop");
		asm("nop");
		asm("nop");
	}

	assert(dest[0] == 0xA);
	assert(dest[1] == 0xB);
	assert(dest[2] == 0xC);
	assert(dest[3] == 0xD);
	assert(dest[4] == 0xE);
	assert(dest[5] == 0);

	return 0;
}

#ifdef DMAMODEL
int main()
{
	test();
	return 0;
}
#endif
