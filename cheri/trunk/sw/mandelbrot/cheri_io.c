/*-
 * Copyright (c) 2012 Robert N. M. Watson
 * Copyright (c) 2014 Michael Roe
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#define IO_RD(x) (*(volatile unsigned long long*)(x))
#define IO_RD32(x) (*(volatile int*)(x))
#define IO_WR(x, y) (*(volatile unsigned long long*)(x) = y)
#define IO_WR_BYTE(x, y) (*(volatile unsigned char*)(x) = y)

/* really should get these from parameters.h */
#define	MIPS_XKPHYS_UNCACHED_BASE	0x9000000000000000
#define	MIPS_XKPHYS_CACHED_NC_BASE	0x9800000000000000

#define	MIPS_PHYS_TO_CACHED(phys)	((phys) | MIPS_XKPHYS_CACHED_NC_BASE)
#define	MIPS_PHYS_TO_UNCACHED(phys)	((phys) | MIPS_XKPHYS_UNCACHED_BASE)

#define	CHERI_JTAG_UART_BASE		0x7f000000

void putchar(int c)
{
  while ((IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE)+4) &
    0xFFFF) == 0) 
  {
    asm("dadd $v0, $v0, $0");
  }
  IO_WR_BYTE(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE), c);
}
