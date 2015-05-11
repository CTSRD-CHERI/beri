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

#include "mips_assert.h"
#include "DMAAsm.h"
#include "DMAControl.h"
#include "stdint.h"
#include "stdbool.h"

// Test that interrupt 31 (the DMA engine) can be mapped to a MIPS interrupt
// input.
// This doesn't test complex IRQ semantics. There are Bluespec unit tests for
// that.

uint64_t * PIC_DMA_CONFIG_REG = (uint64_t *)0x900000007f8040f8;
uint64_t * PIC_IP_READ_BASE   = (uint64_t *)(0x900000007f804000 + (8 * 1024));

dma_instruction dma_program[] = {
	DMA_OP_STOP
};

static inline bool get_dma_irq()
{
	return (*PIC_IP_READ_BASE) & (1 << 31);
}

int test(void)
{
	*PIC_DMA_CONFIG_REG = (1 << 31); // enanble PIC IRQ

	assert(get_dma_irq() == false);

	dma_set_pc(DMA_PHYS, 0, dma_program);

	dma_write_control(DMA_PHYS, 0, DMA_START_TRANSFER | DMA_ENABLE_IRQ);

	while (!dma_thread_ready(DMA_PHYS, 0)) {
		DEBUG_NOP();
		DEBUG_NOP();
		DEBUG_NOP();
		DEBUG_NOP();
	}

	assert(get_dma_irq() == true);

	dma_write_control(DMA_PHYS, 0, DMA_CLEAR_IRQ);

	DEBUG_NOP();
	DEBUG_NOP();
	DEBUG_NOP();
	DEBUG_NOP();

	assert(get_dma_irq() == false);

	return 0;
}
