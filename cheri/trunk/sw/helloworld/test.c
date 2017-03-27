/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2014 Jonathan Woodruff
 * Copyright (c) 2011 Steven J. Murdoch
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2012 Benjamin Thorner
 * Copyright (c) 2013-2014 A. Theodore Markettos
 * Copyright (c) 2013 Philip Withnall
 * Copyright (c) 2013 Alan Mujumdar
 * Copyright (c) 2015 Alexandre Joannou
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
 * BERI test.c
 *
 * Basic test interface and routines for BERI.
 */ 

#include "../../../../cherilibs/trunk/include/parameters.h"
#include "comlib.c"

#define TLB_ALIAS_BASE (0x0000000050000000ULL)
#define SGDMA_DESCR (0x9000000008000000ULL)
#define SGDMA_SLAVE (0x9000000008010000ULL)
#define BUTTONS (0x900000007F009000ULL)

#define IO_RD(x) (*(volatile unsigned long long*)(x))
#define IO_RD32(x) (*(volatile int*)(x))
#define IO_WR(x, y) (*(volatile unsigned long long*)(x) = y)
#define IO_WR32(x, y) (*(volatile int*)(x) = y)
#define IO_WR_BYTE(x, y) (*(volatile unsigned char*)(x) = y)
//#define rdtscl(dest) __asm__ __volatile__("mfc0 %0,$9; nop" : "=r" (dest))

#define DIVIDE_ROUND(N, D) (((N) + (D) - 1) / (D))

extern void __writeString(char* s);
extern void __writeHex(unsigned long long n);
extern void __writeDigit(unsigned long long n);
extern char __readUARTChar();
extern void __writeUARTChar(char c);

unsigned int contextDone = 0;

volatile int globalReset = 0;

// ADDED >>
#define SORT_SIZE (128)
//int makeBss = 1;
// ADDED <<

inline unsigned int getCycleCount()
{
    static unsigned int last = 0;
    unsigned int counter;
    unsigned int ret;

    asm volatile (
        "mfc0    %0, $9     \n"
        : "=r"(counter) : );

    ret = counter - last;
    last = counter;
    return ret;
}

inline unsigned int getInstCount()
{
    static unsigned int last = 0;
    unsigned int counter;
    unsigned int ret;

    asm volatile (
        "mfc0    %0, $9, 4  \n"
        : "=r"(counter) : );

    ret = counter - last;
    last = counter;
    return ret;
}

inline void printCPI ()
{
    __writeString("CPI (*1000): ");
    __writeDigit((getCycleCount()*1000) / getInstCount());
    __writeString("\n");
}

int CoProFPTestEval(long in, long out, int t_num, int err) {
    if (in != out) {
        __writeHex(t_num);
        __writeString(" < FPU co-processor test failed\n\t");
        __writeHex(in);
        __writeString(" < expected\n\t");
        __writeHex(out);
        __writeString(" < got \n");
        return -1;
    } return (err != 0) ? -1 : 0;
}

void in(int num) { 
    asm("and $t0, $a0, $a0");
}

int out() { 
    asm("and $v0, $t0, $t0");
}

void CoProFPTest() {
    int t_num = 1;
    int err = 0;
    // Test RI instructions
    asm("li $t0, 9");
    asm("mtc1 $t0, $f1");
    asm("mfc1 $t1, $f1");
    asm("and $t0, $t1");
    err = CoProFPTestEval(9,out(),t_num++,err);
    asm("lui $t0, 18");
    asm("dsll $t0, $t0, 16");
    asm("ori $t0, 7");
    asm("dmtc1 $t0, $f5");
    asm("dmfc1 $t1, $f5");
    asm("and $t0, $t1");
    err = CoProFPTestEval(((long)18 << 32) + 7,out(),t_num++,err);
    asm("li $t0, 0xFFF3F");
    asm("ctc1 $t0, $f25");
    asm("cfc1 $t1, $f25");
    asm("and $t0, $t1");
    err = CoProFPTestEval(0x3F,out(),t_num++,err);
    asm("li $t0, 0xFFF1");
    asm("ctc1 $t0, $f26");
    asm("cfc1 $t1, $f26");
    asm("and $t0, $t1");
    err = CoProFPTestEval(0xF070,out(),t_num++,err);
    asm("li $t0, 0xFFF86");
    asm("ctc1 $t0, $f28");
    asm("cfc1 $t1, $f28");
    asm("and $t0, $t1");
    err = CoProFPTestEval(0xF86,out(),t_num++,err);
    asm("lui $t0, 0x0003");
    asm("ori $t0, 0xFFFF");
    asm("ctc1 $t0, $f31");
    asm("cfc1 $t1, $f31");
    asm("and $t0, $t1");
    err = CoProFPTestEval(0x0003FFFF,out(),t_num++,err);
    asm("cfc1 $t0, $f26");
    err = CoProFPTestEval(0x0003F07C,out(),t_num++,err);
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0,out(),t_num++,err);
    asm("cfc1 $t0, $f28");
    err = CoProFPTestEval(0xF83,out(),t_num++,err);
    // Absolute value
    asm("lui $t0, 0x87FF");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f11");
    asm("abs.D $f11, $f11");
    asm("dmfc1 $t0, $f11");
    err = CoProFPTestEval(0x07FF000000000000,out(),t_num++,err);
    asm("lui $t0, 0x8FFF");
    asm("mtc1 $t0, $f12");
    asm("abs.S $f12, $f12");
    asm("mfc1 $t0, $f12");
    err = CoProFPTestEval(0x0FFF0000,out(),t_num++,err);
    asm("lui $t0, 0xBF80");
    asm("dsll $t0, $t0, 32");
    asm("ori $t1, $0, 0x4000");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f15");
    asm("abs.PS $f15, $f15");
    asm("dmfc1 $t0, $f15");
    err = CoProFPTestEval(0x3F80000040000000,out(),t_num++,err);
    asm("lui $t2, 0x7F81");
    asm("dsll $t2, $t2, 32");
    asm("ori $t1, $0, 0x4000");
    asm("dsll $t1, $t1, 16");
    asm("or $t2, $t2, $t1");
    asm("dmtc1 $t2, $f13");
    asm("abs.PS $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7F81000040000000,out(),t_num++,err);
    asm("lui $t0, 0x0100");
    asm("mtc1 $t0, $f31");
    asm("lui $t1, 0x0001");
    asm("dmtc1 $t1, $f22");
    asm("abs.S $f22, $f22");
    asm("dmfc1 $t0, $f22");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Addition
    asm("li $t1, 0x0");
    asm("mtc1 $t1, $f31");
    asm("lui $t2, 0x3FF0");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("add.D $f13, $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x4000000000000000,out(),t_num++,err);
    asm("lui $t0, 0x3F80");
    asm("mtc1 $t0, $f14");
    asm("add.S $f14, $f14, $f14");
    asm("mfc1 $t0, $f14");
    err = CoProFPTestEval(0x40000000,out(),t_num++,err);
    asm("lui $t0, 0x3F80");
    asm("dsll $t0, $t0, 32");
    asm("ori $t1, $0, 0x4000");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f15");
    asm("add.PS $f15, $f15, $f15");
    asm("dmfc1 $t0, $f15");
    err = CoProFPTestEval(0x4000000040800000,out(),t_num++,err);
    asm("lui $t2, 0x7FF1");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("add.D $f13, $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);
    asm("lui $t0, 0x0100");
    asm("mtc1 $t0, $f31");
    asm("lui $t1, 0x0001");
    asm("mtc1 $t1, $f22");
    asm("add.S $f22, $f22, $f22");
    asm("mfc1 $t0, $f22");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Subtraction
    asm("li $t2, 0x0");
    asm("mtc1 $t2, $f31");
    asm("lui $t0, 0x4000");
    asm("dsll $t0, $t0, 32");
    asm("lui $t1, 0x3FF0");
    asm("dsll $t1, $t1, 32");
    asm("dmtc1 $t0, $f15");
    asm("dmtc1 $t1, $f16");
    asm("sub.D $f11, $f15, $f16");
    asm("dmfc1 $t0, $f11");
    err = CoProFPTestEval(0x3FF0000000000000,out(),t_num++,err);
    asm("lui $t0, 0x4000");
    asm("lui $t1, 0x4080");
    asm("dmtc1 $t0, $f5");
    asm("dmtc1 $t1, $f6");
    asm("sub.S $f5, $f5, $f6");
    asm("dmfc1 $t0, $f5");
    err = CoProFPTestEval(0xC0000000,out(),t_num++,err);
    asm("lui $t0, 0x4000");
    asm("dsll $t0, $t0, 32");
    asm("ori $t1, $0, 0x4080");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f5");
    asm("lui $t0, 0x4000");
    asm("dsll $t0, $t0, 32");
    asm("ori $t1, $0, 0x3F80");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f6");
    asm("sub.PS $f5, $f5, $f6");
    asm("dmfc1 $t0, $f5");
    err = CoProFPTestEval(0x0000000040400000,out(),t_num++,err);
    asm("lui $t2, 0x7FF1");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("sub.D $f13, $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);
    asm("lui $t0, 0x0100");
    asm("mtc1 $t0, $f31");
    asm("lui $t1, 0x0001");
    asm("mtc1 $t1, $f22");
    asm("sub.S $f22, $f22, $f22");
    asm("mfc1 $t0, $f22");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Negation
    asm("lui $t0, 0x0530");
    asm("mtc1 $t0, $f4");
    asm("neg.S $f5, $f4");
    asm("dmfc1 $t0, $f5");
    err = CoProFPTestEval(0x85300000,out(),t_num++,err);
    asm("lui $t0, 0x8220");
    asm("ori $t0, $t0, 0x5555");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f6");
    asm("neg.D $f6, $f6");
    asm("dmfc1 $t0, $f6");
    err = CoProFPTestEval(0x0220555500000000,out(),t_num++,err);
    asm("lui $t0, 0xBF80");
    asm("dsll $t0, $t0, 32");
    asm("ori $t1, $0, 0x4000");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f15");
    asm("neg.PS $f15, $f15");
    asm("dmfc1 $t0, $f15");
    err = CoProFPTestEval(0x3F800000C0000000,out(),t_num++,err);
    asm("lui $t2, 0x7FF1");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("neg.D $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);
    asm("lui $t0, 0x0100");
    asm("mtc1 $t0, $f31");
    asm("lui $t1, 0x0001");
    asm("mtc1 $t1, $f22");
    asm("neg.S $f22, $f22");
    asm("mfc1 $t0, $f22");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Multiplication
    asm("lui $t3, 0x4000");
    asm("dsll $t3, $t3, 32");
    asm("dmtc1 $t3, $f29");
    asm("mul.D $f27, $f29, $f29");
    asm("dmfc1 $t0, $f27");
    err = CoProFPTestEval(0x4010000000000000,out(),t_num++,err);
    asm("lui $t2, 0x4080");
    asm("mtc1 $t2, $f20");
    asm("mul.S $f20, $f20, $f20");
    asm("dmfc1 $t0, $f20");
    err = CoProFPTestEval(0x41800000,out(),t_num++,err);
    asm("lui $t0, 0x4040");
    asm("dsll $t0, $t0, 32");
    asm("ori $t1, $0, 0xBF80");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f20");
    asm("lui $t0, 0x40A0");
    asm("dsll $t0, $t0, 32");
    asm("ori $t1, $0, 0xBF80");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f1");
    asm("mul.PS $f6, $f1, $f20");
    asm("dmfc1 $t0, $f6");
    err = CoProFPTestEval(0x417000003F800000,out(),t_num++,err);
    asm("lui $t2, 0x7FF1");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("mul.D $f13, $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);
    asm("lui $t0, 0x0100");
    asm("mtc1 $t0, $f31");
    asm("lui $t1, 0x0001");
    asm("mtc1 $t1, $f22");
    asm("mul.S $f22, $f22, $f22");
    asm("mfc1 $t0, $f22");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Division
    asm("lui $t0, 0xFFF0");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f9");
    asm("dmtc1 $0, $f8");
    asm("div.D $f7, $f9, $f8");
    asm("dmfc1 $t0, $f7");
    err = CoProFPTestEval(0xFFF0000000000000,out(),t_num++,err);
    asm("lui $t0, 0x41A0");
    asm("mtc1 $t0, $f10");
    asm("lui $t0, 0x40A0");
    asm("mtc1 $t0, $f11");
    asm("div.S $f10, $f10, $f11");
    asm("mfc1 $t0, $f10");
    err = CoProFPTestEval(0x40800000,out(),t_num++,err);
    asm("lui $t2, 0x7FF1");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("div.D $f13, $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);
    asm("lui $t0, 0x0100");
    asm("mtc1 $t0, $f31");
    asm("lui $t0, 0x3F80");
    asm("mtc1 $t0, $f21");
    asm("lui $t1, 0x0001");
    asm("mtc1 $t1, $f22");
    asm("div.S $f22, $f22, $f21");
    asm("mfc1 $t0, $f22");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Square root
    asm("lui $t0, 0x4280");
    asm("mtc1 $t0, $f17");
    asm("sqrt.S $f17, $f17");
    asm("mfc1 $t0, $f17");
    err = CoProFPTestEval(0x41000000,out(),t_num++,err);
    asm("lui $t0, 0x8000");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f17");
    asm("sqrt.D $f17, $f17");
    asm("dmfc1 $t0, $f17");
    err = CoProFPTestEval(0x8000000000000000,out(),t_num++,err);
    asm("lui $t2, 0x7FF1");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("sqrt.D $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);
    // Reciprocal square root
    asm("lui $t0, 0x4080");
    asm("mtc1 $t0, $f23");
    asm("rsqrt.S $f22, $f23");
    asm("mfc1 $t0, $f22");
    err = CoProFPTestEval(0x3F000000,out(),t_num++,err);
    asm("lui $t0, 0x0");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f3");
    asm("rsqrt.D $f3, $f3");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x7FF0000000000000,out(),t_num++,err);
    asm("lui $t2, 0x7FF1");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("rsqrt.D $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);
    // Reciprocal
    asm("lui $t0, 0x4030");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f19");
    asm("recip.D $f19, $f19");
    asm("dmfc1 $t0, $f19");
    err = CoProFPTestEval(0x3FB0000000000000,out(),t_num++,err);
    asm("lui $t0, 0");
    asm("mtc1 $t0, $f19");
    asm("recip.S $f19, $f19");
    asm("mfc1 $t0, $f19");
    err = CoProFPTestEval(0x7F800000,out(),t_num++,err);
    asm("lui $t0, 0x0100");
    asm("ctc1 $t0, $f31");
    asm("lui $t0, 0x7F7F");
    asm("mtc1 $t0, $f7");
    asm("recip.S $f7, $f7");
    asm("mfc1 $t0, $f7");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("lui $t2, 0x7FF1");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f13");
    asm("sqrt.D $f13, $f13");
    asm("dmfc1 $t0, $f13");
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);
    // Comparison
    asm("mtc1 $0, $f31");
    asm("lui $t0, 0x4000");
    asm("mtc1 $t0, $f3");
    asm("lui $t0, 0x3F80");
    asm("mtc1 $t0, $f4");
    asm("lui $t0, 0x4000");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f13");
    asm("ori $t1, $0, 0x3F80");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f23");
    asm("lui $t0, 0x3FF0");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f14");
    asm("ori $t1, $0, 0x4000");
    asm("dsll $t1, $t1, 16");
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f24");
    // Comparison (False)
    asm("c.f.S $f3, $f3");
    asm("mfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.f.D $f13, $f14");
    asm("mfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.f.PS $f3, $f3");
    asm("mfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Comparison (Unordered)
    asm("lui $t0, 0x7F81");
    asm("mtc1 $t0, $f5");
    asm("c.un.S $f3, $f5");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("lui $t0, 0x7FF1");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f15");
    asm("c.un.D $f15, $f15");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.un.PS $f5, $f5");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.un.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.un.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.un.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Comparison (Equal)
    asm("c.eq.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.eq.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.eq.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    asm("mtc1 $0, $f31");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("c.eq.S $f3, $f4");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.eq.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.eq.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Comparison (Unordered or Equal)
    asm("lui $t0, 0x7F81");
    asm("mtc1 $t0, $f5");
    asm("c.ueq.S $f3, $f5");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("lui $t0, 0x7FF1");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f15");
    asm("c.ueq.D $f15, $f15");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ueq.PS $f5, $f5");
    asm("cfc1 $t0, $f25");
    asm("mtc1 $0, $f31");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("c.ueq.S $f3, $f4");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ueq.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ueq.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ueq.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ueq.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ueq.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    asm("mtc1 $0, $f31");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    // Comparison (Less Than)
    asm("c.olt.S $f4, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.olt.D $f14, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.olt.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    asm("mtc1 $0, $f31");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.olt.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.olt.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.olt.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Comparison (Unordered or Less Than)
    asm("c.ult.S $f4, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ult.D $f14, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ult.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    asm("mtc1 $0, $f31");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ult.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ult.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ult.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("lui $t0, 0x7F81");
    asm("mtc1 $t0, $f5");
    asm("c.ult.S $f3, $f5");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("lui $t0, 0x7FF1");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f15");
    asm("c.ult.D $f15, $f15");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ult.PS $f5, $f5");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ult.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ult.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ult.PS $f24, $f23");
    asm("cfc1 $t0, $f25");
    asm("mtc1 $0, $f31");
    err = CoProFPTestEval(0x2,out(),t_num++,err);
    // Comparison (Less Than or Equal)
    asm("c.ole.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ole.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ole.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f31");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("c.ole.S $f3, $f4");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f31");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ole.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ole.PS $f24, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f31");
    err = CoProFPTestEval(0x2,out(),t_num++,err);
    asm("c.ole.S $f4, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ole.D $f14, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ole.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f31");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    // Comparison (Unordered or Less Than or Equal)
    asm("c.ule.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ule.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ule.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f31");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("c.ule.S $f3, $f4");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ule.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ule.PS $f24, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f31");
    err = CoProFPTestEval(0x2,out(),t_num++,err);
    asm("c.ule.S $f4, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ule.D $f14, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ule.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f31");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("lui $t0, 0x7F81");
    asm("ctc1 $t0, $f5");
    asm("c.ule.S $f3, $f5");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("lui $t0, 0x7FF1");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f15");
    asm("c.ule.D $f15, $f15");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ule.PS $f5, $f5");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    // Branches
    asm("ctc1 $0, $f31");
    asm("li $t2, 4");
    asm("mtc1 $t2, $f3");
    asm("li $t1, 3");
    asm("bc1f 12");
    asm("and $t0, $t0, $t0");
    asm("mtc1 $t1, $f3");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x4,out(),t_num++,err);
    asm("ctc1 $0, $f31");
    asm("li $t2, 4");
    asm("mtc1 $t2, $f3");
    asm("li $t1, 3");
    asm("bc1t 12");
    asm("and $t0, $t0, $t0");
    asm("mtc1 $t1, $f3");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("li $t0, 0");
    asm("li $t2, 4");
    asm("mtc1 $t2, $f4");
    asm("li $t1, 3");
    asm("lui $t0, 0x0080");
    asm("ctc1 $t0, $f31");
    asm("bc1f 12");
    asm("and $t0, $t0, $t0");
    asm("mtc1 $t1, $f4");
    asm("mfc1 $t0, $f4");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("li $t0, 0");
    asm("li $t2, 4");
    asm("mtc1 $t2, $f4");
    asm("li $t1, 3");
    asm("bc1t 12");
    asm("and $t0, $t0, $t0");
    asm("mtc1 $t1, $f4");
    asm("mfc1 $t0, $f4");
    err = CoProFPTestEval(0x4,out(),t_num++,err);
    // Pair manipulation
    asm("lui $t0, 0x3F80");
    asm("mtc1 $t0, $f7");
    asm("lui $t0, 0x4000");
    asm("mtc1 $t0, $f8");
    asm("pll.PS $f7, $f7, $f8");
    asm("dmfc1 $t0, $f7");
    err = CoProFPTestEval(0x3F80000040000000,out(),t_num++,err);
    asm("lui $t0, 0xBF80");
    asm("mtc1 $t0, $f13");
    asm("lui $t0, 0x3F80");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f23");
    asm("plu.PS $f14, $f13, $f23");
    asm("dmfc1 $t0, $f14");
    err = CoProFPTestEval(0xBF8000003F800000,out(),t_num++,err);
    asm("lui $t0, 0x7F80");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f5");
    asm("li $t0, 0");
    asm("mtc1 $t0, $f6");
    asm("pul.PS $f5, $f5, $f6");
    asm("dmfc1 $t0, $f5");
    err = CoProFPTestEval(0x7F80000000000000,out(),t_num++,err);
    asm("puu.PS $f5, $f5, $f23");
    asm("dmfc1 $t0, $f5");
    err = CoProFPTestEval(0x7F8000003F800000,out(),t_num++,err);
    // MOV
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("mov.S $f3, $f4");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x41000000,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("mov.D $f3, $f7");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000000000000,out(),t_num++,err);
    asm("pul.PS $f5, $f7, $f4");
    asm("mov.PS $f3, $f5");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000041000000,out(),t_num++,err);
    // MOVN
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("movn.S $f3, $f4, $t1");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x41000000,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("movn.D $f3, $f7, $t2");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000000000000,out(),t_num++,err);
    asm("pul.PS $f5, $f7, $f4");
    asm("movn.PS $f3, $f5, $t2");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000041000000,out(),t_num++,err);
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("dmtc1 $0, $f3");
    asm("movn.S $f3, $f4, $0");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("dmtc1 $0, $f3");
    asm("movn.D $f3, $f7, $0");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("dmtc1 $0, $f3");
    asm("pul.PS $f5, $f7, $f4");
    asm("movn.PS $f3, $f5, $0");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // MOVZ
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("movz.S $f3, $f4, $0");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x41000000,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("movz.D $f3, $f7, $0");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000000000000,out(),t_num++,err);
    asm("pul.PS $f5, $f7, $f4");
    asm("movz.PS $f3, $f5, $0");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000041000000,out(),t_num++,err);
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("dmtc1 $0, $f3");
    asm("movz.S $f3, $f4, $t1");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("dmtc1 $0, $f3");
    asm("movz.D $f3, $f7, $t2");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("dmtc1 $0, $f3");
    asm("pul.PS $f5, $f7, $f4");
    asm("movz.PS $f3, $f5, $t2");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // MOVF
    asm("ctc1 $0, $f31");
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("movf.S $f3, $f4, $fcc3");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x41000000,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("movf.D $f3, $f7, $fcc2");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000000000000,out(),t_num++,err);
    asm("pul.PS $f5, $f7, $f4");
    asm("movf.PS $f3, $f5, $fcc0");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000041000000,out(),t_num++,err);
    asm("lui $t0, 0x0F80");
    asm("ctc1 $t0, $f31");
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("dmtc1 $0, $f3");
    asm("movf.S $f3, $f4, $fcc3");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("dmtc1 $0, $f3");
    asm("movf.D $f3, $f7, $fcc2");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("dmtc1 $0, $f3");
    asm("pul.PS $f5, $f7, $f4");
    asm("movf.PS $f3, $f5, $fcc0");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // MOVT
    asm("lui $t0, 0x0F80");
    asm("ctc1 $t0, $f31");
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("movt.S $f3, $f4, $fcc3");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x41000000,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("movt.D $f3, $f7, $fcc2");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000000000000,out(),t_num++,err);
    asm("pul.PS $f5, $f7, $f4");
    asm("movt.PS $f3, $f5, $fcc0");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x4000000041000000,out(),t_num++,err);
    asm("ctc1 $0, $f31");
    asm("lui $t1, 0x4100");
    asm("mtc1 $t1, $f4");
    asm("dmtc1 $0, $f3");
    asm("movt.S $f3, $f4, $fcc3");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("lui $t2, 0x4000");
    asm("dsll $t2, $t2, 32");
    asm("dmtc1 $t2, $f7");
    asm("dmtc1 $0, $f3");
    asm("movt.D $f3, $f7, $fcc2");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("dmtc1 $0, $f3");
    asm("pul.PS $f5, $f7, $f4");
    asm("movt.PS $f3, $f5, $fcc0");
    asm("dmfc1 $t0, $f3");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Conversion (not migrated to the unit tests)
    asm("lui $t0, 0x3F80");
    asm("mtc1 $t0, $f4");
    asm("cvt.D.S $f4, $f4");
    asm("dmfc1 $t0, $f4");
    err = CoProFPTestEval(0x3FF0000000000000,out(),t_num++,err);
    asm("li $t0, 3");
    asm("mtc1 $t0, $f23");
    asm("cvt.D.W $f23, $f23");
    asm("dmfc1 $t0, $f23");
    err = CoProFPTestEval(0x4008000000000000,out(),t_num++,err);
    asm("li $t0, 1");
    asm("dsll $t0, $t0, 32");
    asm("dmtc1 $t0, $f23");
    asm("cvt.D.L $f23, $f23");
    asm("dmfc1 $t0, $f23");
    err = CoProFPTestEval(0x41F0000000000000,out(),t_num++,err);
    if (err == 0) __writeString("\tAll tests passed");
}

int ll(int * ldAddr)
{
	asm("ll $v0, 0($a0)");
}

int sc(int * stAddr, int stValue)
{
	asm("sc $a1, 0($a0)");
	asm("move $v0, $a1");
}

int testNset(int * stAddr, int stValue)
{
	asm("ll $v0, 0($a0)");
	asm("sc $a1, 0($a0)");
	asm("move $v0, $a1");
}

int debugTlb()
{
	asm("mtc0 $0, $25");
}

int debugRegs()
{
	asm("mtc0 $0, $26");
}

int cp0Regs()
{
	asm("mtc0 $0, $27");
}

int getCoreID()
{
	asm("mfc0 $v0, $15, 1");
}

void delay()
{
	int i = 0;
	while(i < 2000){i++;}
}

void EchoTest()
{
	char c=0;
	__writeString("Press '.' to finish\n");
	do
	{
		c = __readUARTChar();
		__writeUARTChar(c);
	} while (c != '.');
}

int main(void)
{
	int i;
	int j;
	int data;
	int data2=0;
	char in = 0;
	i = 0x0000000004000500;
	int numBad = 1;
	short leds = 0;

	//__writeStringLoopback("Stack TLB entry setup.\n");
	__writeString("UART serial interface TLB entry setup.\n");
	__writeString("  MMU setup.\n");
	//debugTlb();
	//cp0Regs();
	
//	causeTrap();
//	__writeString("Came back from trap and still alive :)\n");

//	sysCtrlTest();
//	data = rdtscl(5);


	__writeString("************************************\n");
	__writeString("Hello World from the BERI/CHERI CPU!\n");
	__writeString("************************************\n\n");
	__writeString("This is a simple program to indicate the CPU is alive.\n");
	__writeString("It's C code running in the CPU bootloader ROM using the UART to communicate with the host\n");
	__writeString("You can find the source code in cheri/trunk/sw/helloworld/test.c\n");

	while(in != 'Q') 
	{
		if (in != '\n') {
			//if (coreid == 0)
			{
			globalReset = 0;
			__writeString("\n Menu:\n");
			__writeString("   \"E\" for terminal echo test.\n");
			__writeString("   \"D\" for multiply and divide test.\n");
			__writeString("   \"M\" for eternal memory test.\n");
			__writeString("   \"l\" to invert LEDs (FPGA only).\n");
//			__writeString("   \"F\" for floating point co-processor test (requires build with 'make COP1=1' enable FPU).\n");
			__writeString("   \"Q\" to quit.\n");
			}
		}

		in = __readUARTChar();
		__writeUARTChar(in);
		__writeString("\n");

		if (in == 'E') {
			__writeString("Terminal echo test\n");
			EchoTest();
		}
		

//		if (in == 'F') {
//			__writeString("Floating Point co-processor test\n");
//			__writeString("(will hang if no FPU present)\n");
//			CoProFPTest();
//		}
		
		if (in == 'D') {
			numBad = 1;
			__writeString("Multiply and divide test.\n");
			for (i = -10; i < 10; i++) {
				data = numBad * i;
				__writeHex(numBad);
				__writeString(" * ");
				__writeHex(i);
				__writeString(" = ");
				__writeHex(data);
				__writeString("\n");
				if (i!=0) data2 = data / i;
				__writeHex(data);
				__writeString(" / ");
				__writeHex(i);
				__writeString(" = ");
				__writeHex(data2);
				__writeString("\n");
				__writeString("\n");
				if (data == 0) data = 1;
				numBad = data;
			}
		}
		
		if (in == 'M') {
            printCPI();
			__writeString("Memory test:\n");
			__writeString("Please wait while the DRAM is tested...\n");
			__writeString("(failures may not directly imply hardware faults)\n");
			i = 0;
			while(1) 	{
				int idx = 0;
				for (j=0; j<0x4000; j++) {
					idx = i+j;
					((volatile int *)DRAM_BASE)[idx] = DRAM_BASE + (idx<<2);
				}
				for (j=0; j<0x4000; j++) {
					idx = i+j;
					data = ((volatile int *)DRAM_BASE)[idx];
					if (data != (int)(DRAM_BASE + (idx<<2))) {
						//__writeHex((int)(DRAM_BASE + (idx<<2))); 
						//__writeString(" = ");
						//__writeHex(data);
						//__writeString("?\n");
						numBad++;
					}
				}
        
				__writeHex((int)(DRAM_BASE + (idx<<2))); 
				__writeString(" = ");
				__writeHex(data);
				__writeString("?\n");
				if (numBad == 0) {
					__writeString("All good! \n");
				} else {
					__writeHex(numBad);
					__writeString(" addresses were bad :(\n");
					numBad = 0;
				}
                printCPI();
				
				i+=0x4000;
				if (i > 0x07000000) i = 0;
			}
		}
		
		if (in == 'l') {
			__writeString("LED invert. May hang if no LEDs present. LEDS=");
			leds = ~leds;
			__writeHex(leds);
			__writeString("\n");
			IO_WR(CHERI_LEDS,leds);
		}
	}

	return 0;
}

