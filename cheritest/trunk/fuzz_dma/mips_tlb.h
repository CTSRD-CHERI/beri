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

#ifndef MIPS_TLB_H
#define MIPS_TLB_H

volatile inline void
add_tlb_mapping(uint64_t virtual_pn, uint64_t physical_pn_0,
		uint64_t physical_pn_1)
{
	// Important CP0 Registers
	// Page Mask: 	R5,  S0
	// EntryLo0 	R2,  S0
	// EntryLo1	R3,  S0
	// EntryHi	R10, S0

	uint64_t page_mask = 0;
	uint64_t entry_hi = virtual_pn << 12;
	// | 7 sets Valid, Dirty (Writeble) and Global bit so that ASID
	// comparison is skipped
	uint64_t entry_lo0 = (physical_pn_0 << 6) | 7;
	uint64_t entry_lo1 = (physical_pn_1 << 6) | 7;

	asm ("dmtc0 %0, $5"  : : "r"(page_mask));
	asm ("dmtc0 %0, $2"  : : "r"(entry_lo0));
	asm ("dmtc0 %0, $3"  : : "r"(entry_lo1));
	asm ("dmtc0 %0, $10" : : "r"(entry_hi));
	asm ("tlbwr");
}

#endif
