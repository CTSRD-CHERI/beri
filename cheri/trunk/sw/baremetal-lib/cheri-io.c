/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2014 Jonathan Woodruff
 * Copyright (c) 2013 A. Theodore Markettos
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

/*
 * CHERI cheri-io.c
 *
 * Text input and output routines using the Altera jtagUART
 *
 * This file should be imported to any function wanting to read or print
 * to the UART.
  */

#include "parameters.h"

#define IO_RD(x) (*(volatile unsigned long long*)(x))
#define IO_RD32(x) (*(volatile int*)(x))
#define IO_WR(x, y) (*(volatile unsigned long long*)(x) = y)
#define IO_WR_BYTE(x, y) (*(volatile unsigned char*)(x) = y)

//HACK : Forces ld to output a data section which in turn causes it to output a .bss section 
//filled with 0s in the raw binary (Currently don't init .bss at startup so this is needed for correct operation)
int makeBss = 1;

void __writeUARTChar(char c)
{
	//Code for SOPC Builder serial output
	while ((IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE)+4) &
	    0xFFFF) == 0) {
		asm("dadd $v0, $v0, $0");
	}
	//int i;
	//for (i=0;i<10000;i++);
	IO_WR_BYTE(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE), c);
}

void __writeString(char* s)
{
	while(*s)
	{
		__writeUARTChar(*s);
		++s;
	}
}

void __writeHex(unsigned long long n)
{
	unsigned int i;
	for(i = 0;i < 16; ++i)
	{
		unsigned long long hexDigit = (n & 0xF000000000000000L) >> 60L;
//		unsigned long hexDigit = (n & 0xF0000000L) >> 28L;
		char hexDigitChar = (hexDigit < 10) ? ('0' + hexDigit) : ('A' + hexDigit - 10);
		__writeUARTChar(hexDigitChar);
		n = n << 4;
	}
}

void __writeDigit(unsigned long long n)
{
	unsigned int i;
	unsigned int top;
	char tmp[32];
	char str[32];
	
	for(i = 0;i < 32; ++i) str[i] = 0;
	i = 0;
	while(n > 0) {
		tmp[i] = '0' + (n % 10);
		n /= 10;
		i = i + 1;
	}
	if (i!=0) i--;
	top = i;
	while(i > 0) {
		str[top - i] = tmp[i];
		i--;
	}
	str[top] = tmp[0];
	__writeString(str);
}


char __readUARTChar()
{
	int i;
	char out;
	//Code for SOPC Builder serial output
	i = IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));
//	while((i >> 16) == 0) 
	while((i & 0x00800000) == 0)
	{
		i = IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));
		/*
		__writeHex(i);
		__writeString(" and the char:");
		out = (char)i;
		__writeUARTChar(out);
		__writeString("\n");
		*/
	}
	
//	while(i&0x80 == 0) {i = IO_RD(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));}
	i = i >> 24;
	out = (char)i;
	return out;
}
