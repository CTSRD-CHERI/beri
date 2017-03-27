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
#include "stdint.h"

dma_instruction dma_program_physical[] = {
	DMA_OP_TRANSFER(TS_BITS_64),
	DMA_OP_STOP
};

// Let's arbitrarily map virtual pages 40 and 41 to physical pages 0x10011 and
// 0x10073. They are high so we know they're in DRAM. Let's put the program into
// physical page 0x10011, and the data in 0x10073.

#define PHYSICAL_START	((volatile void *)0x9000000000000000)
#define PHYS_P0_START	((volatile void *)(PHYSICAL_START + (0x10011 << 12)))
#define PHYS_P1_START	((volatile void *)(PHYSICAL_START + (0x10073 << 12)))
#define VIRT_P0_START	((volatile void *)(40 << 12))
#define VIRT_P1_START	((volatile void *)(41 << 12))

int test(void) {
	add_tlb_mapping(40, 0x10011, 0x10073);

	*(volatile uint64_t *)PHYS_P0_START = *(uint64_t *)(dma_program_physical);
	*(volatile uint64_t *)PHYS_P1_START = 0xFEEDBEDE;

	dma_set_pc(DMA_VIRT, 0, VIRT_P0_START);
	dma_set_source_address(DMA_VIRT, 0, (uint64_t)VIRT_P1_START);
	dma_set_dest_address(DMA_VIRT, 0, (uint64_t)(VIRT_P1_START + 8));

	dma_start_transfer(DMA_VIRT, 0);

	while (!dma_thread_ready(DMA_VIRT, 0)) {
		DEBUG_NOP();
		DEBUG_NOP();
		DEBUG_NOP();
		DEBUG_NOP();
	}

	assert(*(volatile uint64_t *)(PHYS_P1_START + 8) == 0xFEEDBEDE);

	return 0;
}
