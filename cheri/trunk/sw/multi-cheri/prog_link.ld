/*-
 * Copyright (c) 2014 Alexandre Joannou
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C (BERI) under one or more contributor
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

MIPS_XKPHYS_CACHED_NC_BASE = 0x9800000000000000;
MIPS_GENERAL_EXP_BASE = 0xFFFFFFFFBFC00380;

PRIVATE_DRAM_SIZE = 0x4000000;
PRIVATE_GLOBAL_SIZE = 0x100000;
DRAM_BASE = 0x0;

SECTIONS
{
    . = 0x9800000040000000;
    .text   : { obj/init.o(.text)
                obj/main.o(.text)
                obj/lock.o(.text) obj/semaphore.o(.text) obj/core.o(.text) obj/uart.o(.text)
                obj/fifo.o(.text) obj/multi_test.o(.text)
                obj/scatter_gather.o(.text) obj/shared_array.o(.text) 
                obj/parallel_sort.o(.text) }
    .bss    : { obj/main.o(.bss) }
    .data   : { obj/main.o(.data) }
    .rodata : { obj/main.o(.rodata*) }
}
