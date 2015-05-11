/*-
 * Copyright (c) 2011 Robert N. M. Watson
 * Copyright (c) 2014 Michael Roe
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
__mem_top__ = 0x9000000000008000;

__sp = __mem_top__;
__heap_top__ = __mem_top__ - __stack_size__;
__sp_bottom = __heap_top__;

SECTIONS
{
	. = 0x9000000040000000;

	.text ALIGN(0x8): {
		obj/init_multi.o(.text)
		*(EXCLUDE_FILE (obj/init_multi.o) .text)
	}
	.bss ALIGN(0x8): { *(.bss) }
	.data ALIGN(0x8): { *(.data)}

	__heap = ALIGN(0x8);	/* 64-bit aligned heap pointer */
	__bss_start = ADDR(.bss);
	__bss_end = ALIGN(__bss_start + SIZEOF(.bss), 0x8);
}
