/*-
 * Copyright (c) 2011-2012 Robert N. M. Watson
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

__stack_size__ = 0x400; /* 1k stack */
__kernel_load_offset__ = 0x100000;
__flash_kernel_location_uncached__ = 0x9000000076000000;
__flash_kernel_location_cached__ = 0x9800000076000000;
__max_kernel_size__ = 0x2000000; /* 32 megabyte kernel max */
__flash_kernel_top__ = __flash_kernel_location_cached__ + __max_kernel_size__;
__cached_base__ = 0xffffffff80000000;
__mem_size__ = 0x3F000000 - __kernel_load_offset__;
__sp = __cached_base__ + __mem_size__ - __stack_size__;
__os_memory_size__ = __mem_size__ - __stack_size__;
__os_elf_header__ = __cached_base__ + __kernel_load_offset__;
__dip_switches__ = 0x900000007f009000;
__spin_table_top__ =  __cached_base__ + __kernel_load_offset__;

SECTIONS
{
	. = 0x9000000040000000;

	.text ALIGN(0x8): { *(.text) } 
	.bss  ALIGN(0x8): { *(.bss) }
	.data ALIGN(0x8): {*(.data) }
 
	__heap = ALIGN(0x8);	/* 64-bit aligned heap pointer */
	__bss_start = ADDR(.bss);
	__bss_end = ALIGN(__bss_start + SIZEOF(.bss), 0x8);
}
