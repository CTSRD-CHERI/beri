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

#include "uart.h"
#include "lock.h"
#include "parameters.h"

#define UART_BASE (MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE))

void uart_putc(char c)
{
	while (((UART_BASE+4) & 0xFFFF) == 0)
    {
		asm("dadd $v0, $v0, $0");
	}
	*(char*)(UART_BASE) = c;
}

void uart_putd(unsigned long long d)
{
    char tmp[32];
    unsigned int i;

    if (d == 0)
    {
        uart_putc('0');
    }
    else
	{
        tmp[31] = 0;
        i = 30;
        while (d > 0)
        {
		    tmp[i] = '0' + (d % 10);
		    d /= 10;
		    i--;
	    }
        uart_puts(&(tmp[i+1]));
    }
}

void uart_putx(unsigned long long x)
{
    char tmp[32];
    unsigned int i;
    unsigned int j;

    if (x == 0)
    {
        uart_putc('0');
    }
    else
	{
        tmp[31] = 0;
        i = 30;
        while (x > 0)
        {
            j = x % 16;
            if (j < 10)
		        tmp[i] = '0' + j;
            else
		        tmp[i] = 'a' + j - 10;
		    x /= 16;
		    i--;
	    }
        uart_puts(&(tmp[i+1]));
    }
}

unsigned int uart_puts(char * str)
{
    unsigned int nb_char = 0;
	while(*str)
	{
        uart_putc (*str);
		++str;
        ++nb_char;
	}
    return nb_char;
}

char uart_getc()
{
	int val;
    while (((val = (*(volatile int*)(UART_BASE))) & 0x00800000) == 0);
    val >>= 24;
	return (char) val;
}

static lock_t uart_lock = 0;

void uart_lock_init()
{
    lock_init(&uart_lock);
}

void uart_lock_acquire()
{
    lock_acquire(&uart_lock);
}

void uart_lock_release()
{
    lock_release(&uart_lock);
}

void uart_locked_putc(char c)
{
    lock_acquire(&uart_lock);
    uart_putc(c);
    lock_release(&uart_lock);
}

void uart_locked_putd(unsigned long long d)
{
    lock_acquire(&uart_lock);
    uart_putd(d);
    lock_release(&uart_lock);
}

void uart_locked_putx(unsigned long long x)
{
    lock_acquire(&uart_lock);
    uart_putx(x);
    lock_release(&uart_lock);
}

unsigned int uart_locked_puts(char * str)
{
    lock_acquire(&uart_lock);
    unsigned int nbr = uart_puts(str);
    lock_release(&uart_lock);
    return nbr;
}

char uart_locked_getc()
{
    lock_acquire(&uart_lock);
    char c = uart_getc();
    lock_release(&uart_lock);
    return c;
}
