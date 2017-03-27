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

#include "core.h"

unsigned int core_id()
{
    unsigned int id;

    asm volatile (
        ".set push          \n"
        ".set mips32r2      \n"
        "rdhwr    %0, $0    \n"
        ".set pop           \n"
        : "=r"(id) : );

    return id;

}

unsigned int core_total()
{
    unsigned int total;

    asm volatile (
        ".set push          \n"
        ".set mips32r2      \n"
        "rdhwr    %0, $30   \n"
        ".set pop           \n"
        : "=r"(total) : );

    return total + 1;
}

unsigned int core_counter()
{
    unsigned int counter;

    asm volatile (
        ".set push          \n"
        ".set mips64        \n"
        "dmfc0    %0, $9    \n"
        ".set pop           \n"
        : "=r"(counter) : );

    return counter;
}

unsigned int core_counter_res()
{
    unsigned int counter_res;

    asm volatile (
        ".set push          \n"
        ".set mips32r2      \n"
        "rdhwr    %0, $3    \n"
        ".set pop           \n"
        : "=r"(counter_res) : );

    return counter_res;
}

unsigned int core_random()
{
    //return core_counter() ^ 0x1D3F5EE20F7AF96FUL;
    return core_counter() & 0x1D3F5EE20F7AF96FUL;
}

void core_delay(unsigned int delay)
{
    asm volatile (
        "delay_loop :               \n"
        "beq    $0, %0, delay_loop  \n"
        "daddi  %0, %0, -1          \n"
        : : "r"(delay) );
}

unsigned int core_instruction_count()
{
    // FIXME
    unsigned int inst_count;

    asm volatile (
        ".set push          \n"
        ".set mips32r2      \n"
        "rdhwr    %0, $2    \n"
        ".set pop           \n"
        : "=r"(inst_count) : );

    return inst_count;
}

void core_abort()
{
    asm volatile ("syscall": : );
}

void core_sync()
{
    asm volatile ("sync": : );
}
