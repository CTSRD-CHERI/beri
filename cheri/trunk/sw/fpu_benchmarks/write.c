/*-
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Colin Rothwell as part of his final year
 * undergraduate project.
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

#ifdef MIPS
#include "../../../../cherilibs/trunk/include/parameters.h"

#define IO_RD32(x) (*(volatile int*)(x))
#define IO_WR_BYTE(x, y) (*(volatile unsigned char*)(x) = y)

void writeUARTChar(char c)
{
	//Code for SOPC Builder serial output
	while ((IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE)+4) &
	    0xFFFF) == 0) {
		asm("add $v0, $v0, $0");
	}
	IO_WR_BYTE(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE), c);
}

void writeString(char* s)
{
	while(*s)
	{
		writeUARTChar(*s);
		++s;
	}
}

inline static char charForHexDigit(unsigned char hexDigit) {
    return (hexDigit < 10) ? ('0' + hexDigit) : ('A' + hexDigit - 10);
}

void writeHexDigits(unsigned long long n, unsigned char digits) {
    const long topQuartetShift = (digits - 1) * 4;
    unsigned int i;
	for(i = 0; i < digits; ++i)
	{
		unsigned long long hexDigit = (n & 0xFL << topQuartetShift) >> topQuartetShift;
		writeUARTChar(charForHexDigit(hexDigit));
		n = n << 4;
	}
}

void writeHex(unsigned long long n) {
    writeHexDigits(n, 16);
}    

void writeHexByte(unsigned char b)
{
    for (int i = 0; i < 1 << 11; ++i) {
        asm("nop");
    }
    writeHexDigits(b, 2);
}

void writeDigit(unsigned long long n)
{
	unsigned int i;
	unsigned int top;
	char tmp[17];
	char str[17];
	
	for(i = 0; i < 17; ++i)
        str[i] = 0;

	i = 0;
	while(n > 0) {
		tmp[i] = '0' + (n % 10);
		n /= 10;
		++i;
	}

    if (i > 0)
        --i;
    else
        tmp[0] = '0';

	top = i;
	while(i > 0) {
		str[top - i] = tmp[i];
		--i;
	}
	str[top] = tmp[0];
	writeString(str);
}

void writeFloat(float point, char* name, int scale) {
    writeString(name); writeString(" * "); writeDigit(scale); writeString(" = "); 
    if (point < 0) {
        writeString("-");
        point = -point;
    }
    writeDigit((int)(point * (float)scale));
    writeString(".\n");
}

/*char readUARTChar()*/
/*{*/
	/*int i;*/
	/*char out;*/
	/*i = IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));*/
	/*while((i & 0x00800000) == 0)*/
	/*{*/
		/*i = IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));*/
	/*}*/
	
	/*i = i >> 24;*/
	/*out = (char)i;*/
	/*return out;*/
/*}*/
#else

#include <stdio.h>

void writeString(char* s) {
    printf("%s", s);
}

void writeDigit(unsigned long long i) {
    printf("%llu", i);
}

void writeHex(unsigned long long i) {
    printf("%llx", i);
}

void writeHexByte(unsigned char b) {
    printf("%.2hhX", b);
}

void writeFloat(float point, char* name, int scale) {
    printf("%s = %f (%s * %d = %d)\n", name, point, name, scale, (int)(point * scale));
}

#endif

