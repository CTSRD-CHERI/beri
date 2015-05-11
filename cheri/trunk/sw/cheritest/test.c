/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2013 Jonathan Woodruff
 * Copyright (c) 2011 Steven J. Murdoch
 * Copyright (c) 2011-2013 Robert Watson
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 Philip Withnall
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
#include "../../../../cherilibs/trunk/include/parameters.h"
#include "cap.h"
#include "comlib.c"
#include "quickSort.c"
#include "arrayBench.c"
#include "armArray.c"
#include <stdint.h>
#include <stddef.h>

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

volatile int coreCount = 0;
volatile int globalReset = 0;
volatile int coreFlag = 0;

// ADDED >>
#define SORT_SIZE (128)
//int makeBss = 1;
// ADDED <<

int arithmaticTest()
{
  /*
	asm("move $a0, $0");
	asm("move $a1, $0");
	
	asm("addi $a0, $a0, -10"); 	// a0 = -10
	asm("addiu $a1, $a0, 30"); 	// a1 = 20
	asm("add  $a0, $a0, $a1"); 	// a0 = 10
	asm("addu $a1, $a1, $a0");	// a1 = 30
	asm("and $a1, $a1, $a0");		// a1 = 10
	asm("andi $a0, $a1, 2");		// a0 = 0x02
	asm("sll $a0, $a0, 4");		// a0 = 0x20
	asm("dsllv $a1, $a1, $a0");	// a1 = 0x0A00000000
	asm("dadd $a1, $a1, $a1");	// a1 = 0x1400000000
	asm("daddi $a1, $a1, 20");	// a1 = 0x1400000014
	asm("daddiu $a1, $a1, -10");	// a1 = 0x140000000A
	asm("daddu $a1, $a1, $a1");	// a1 = 0x2800000014
	asm("sra $a0, $a0, 3");		// a0 = 0x04
	asm("ori $a0, $a0, 16");		// a0 = 0x14
	asm("ddiv $a1, $a0");		// lo = 0x0200000001
	asm("mflo $a1");				// a1 = 0x0200000001
	asm("srl $a0, $a0, 4");		// a0 = 0x01
	asm("ddivu $a1, $a0");		// lo = 0x0200000001
	asm("mflo $a1");				// a1 = 0x0200000001
	asm("div $a1, $a0");			// lo = 0x0000000001
	asm("mflo $a1");				// a1 = 0x0000000001
	asm("xori $a1, $a1, 40971");	// a1 = 0xA00A
	asm("xor $a0, $a0, $a1");		// a0 = 0xA00B
	asm("divu $a0, $a1");		// lo = 0x0001
	asm("mflo $a0");				// a0 = 0x0000000001
	asm("dsll $a0, $a0, 20");		// a0 = 0x0000100000
	asm("mult $a0, $a1");		// hi = 0x0A lo = 0x00A00000
	asm("mfhi $a0");				// a0 = 0x000000000A
	asm("dsll32 $a0,$a0,20");		// a0 = 0xA0000000000000
	asm("dmult $a0,$a1");		// hi = 0x6 lo = 0x4064 0000 0000 0000
	asm("mfhi $a0");				// a0 = 0x0000000064
	asm("sub $a0, $a0, $a1");		// a0 = −40870
	asm("dmultu $a0, $a1");		// hi = -1 lo = -0x63CDFC7C
	asm("mflo $a0");				// a0 = -0x63CDFC7C
	asm("sub $a0, $0, $a0");		// a0 =  0x63CDFC7C
	asm("dsra $a1, $a1, 14");		// a1 =  0x2
	asm("dsll32 $a0, $a0, 1");	// a0 =  0xC79BF8F800000000
	asm("dsrav $a0, $a0, $a1");	// a0 =  0xF1E6FE3E00000000
	asm("dsra32 $a0, $a0, 4");	// a0 =  0xFFFFFFFFFF1E6FE3
	asm("dsrl $a0, $a0, 4");		// a0 =  0x0FFFFFFFFFF1E6FE
	asm("mul $a1, $a1, $a1");		// a1 =  0x4
	asm("dsrlv $a0, $a0, $a1");	// a0 =  0x00FFFFFFFFFF1E6F
	asm("dsll32 $a0, $a0, 4");	// a0 =  0xFFF1E6F000000000
	asm("dsrl32 $a0, $a0, 4");	// a0 =  0x000000000FFF1E6F
	asm("dsub $a1, $a0, $a1");	// a1 =  0x000000000FFF1E6B
	asm("multu $a0, $a1");		// hi =  0x0..00FFE3CE, lo = 0x0..66C3BA65
	asm("mflo $a1");				// a1 =  0x0..66C3BA65
	asm("mfhi $a0");				// a0 =  0x0..00FFE3CE
	asm("nor $a0, $a0, $a1");		// a0 =  0xF..99000410
	asm("or $a0, $a0, $a1");		// a0 =  0xF..FFC3BE75
	asm("dsubu $a0, $a0, $a1");	// a0 =  0xFFFFFFFF99000410
	asm("andi $a1, $a1, 4");		// a1 =  0x4;
	asm("sllv $a0, $a0, $a1");	// a0 =  0xF..90004100
	asm("srav $a0, $a0, $a1");	// a0 =  0xF..F9000410
	
	asm("srlv $a0, $a0, $a1");	// a0 =  0x0..0F900041
	
	asm("subu $a0, $a0, $a1");	// a0 =  0x0..0F90003D
	asm("lui $a1, 3984");		// a1 =  0x0F900000
	asm("addi $a1, $a1, 61");		// a1 =  0x0F90003D
	asm("subu $a0, $a0, $a1");	// a0 =  0x0
	                     
	asm("move $v0, $a0");
	*/
}

void in(int num) { 
    asm("and $t0, $a0, $a0");
}

int out() { 
    asm("and $v0, $t0, $t0");
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

void CoProFPTest() {
  /*
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
    err = CoProFPTestEval(0xF83,out(),t_num++,err);*/
    // Absolute value
    /*asm("lui $t0, 0x87FF");
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
    err = CoProFPTestEval(0x7FF1000000000000,out(),t_num++,err);*/
    // Comparison
    /*asm("mtc1 $0, $f31");
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
    err = CoProFPTestEval(0x3,out(),t_num++,err);*/
    // Branches
    /*asm("ctc1 $0, $f31");
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
    err = CoProFPTestEval(0x4,out(),t_num++,err);*/
    // Pair manipulation
    /*asm("lui $t0, 0x3F80");
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
    err = CoProFPTestEval(0x7F8000003F800000,out(),t_num++,err);*/
    // MOV
    /*asm("lui $t1, 0x4100");
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
    */
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

int causeTrap()
{
	asm("addi $v0, $0, 10");
	asm("addi $a0, $0, 0x98");
	asm("dsll32 $a0,$a0,24");	
	asm("tgei $v0, 5");
	asm("sd $0, 10($a0)");
	asm("addi $v0, $0, 20");
}

int setInterrupts()
{
	asm("mfc0 $a0, $12");
	asm("ori $a0, $a0, 0xFF01");
	asm("mtc0 $a0, $12");
	// Turn on Interrupts for loopback uart.
	IO_WR_BYTE(MIPS_PHYS_TO_UNCACHED(CHERI_LOOPBACK_UART_BASE) + 32,
	    0x00000001);
}

void drawRect(int color, int solid, int x, int y, int length, int height)
{
	long offset = y*800 + x;
	long addOff = 0;
	long totOff = 0;
	int i, j;
	
	if (solid) {
		for (i=0; i<height; i++) {
			for (j=0; j<length; j++) {
				addOff = (800*i) + j;
				totOff = (offset+addOff)<<2;
				FBSWR(color, totOff);
			}
		}
	} else {
		// Draw top
		for (i=0; i<length; i++) FBSWR(color, (offset+i)<<2);
		// Draw bottom
		for (i=0; i<length; i++) FBSWR(color, (offset+800*height+i)<<2);
		// Draw left
		for (i=0; i<height; i++) FBSWR(color, (offset+800*i)<<2);
		// Draw right
		for (i=0; i<height; i++) FBSWR(color, (offset+length+800*i)<<2);
	}
}

void draw3DRect(int color, int x, int y, int length, int height)
{
	int darkerColor = 0x0;
	darkerColor |= (color>>1)&0xFF000000;
	darkerColor |= (color>>1)&0x00FF0000;
	darkerColor |= (color>>1)&0x0000FF00;
	int solid = 1;
	// Bottom Shadow
	drawRect(darkerColor, 	solid, x+2, 				y+height-2, 	length-2, 	1);
	// Right Shadow
	drawRect(darkerColor, 	solid, x+length-2, 	y+2, 					1, 					height-2);
	// Body
	drawRect(color, 				solid, x, 					y, 						length-2, 	height-2);
}



/*
void 	dlnC0		(int decVal) 	{asm("mtc2 $a0, $0, 0");}
void 	ibsC0		(int decVal) 	{asm("mtc2 $a0, $0, 1");}
int 	mvlnC0	() 						{asm("mfc2 $v0, $0, 0");}
int 	mvbsC0	() 						{asm("mfc2 $v0, $0, 1");}
int 	mvtpC0	() 						{asm("mfc2 $v0, $0, 2");}
int 	mvpmC0	() 						{asm("mfc2 $v0, $0, 3");}
int 	mvusC0	() 						{asm("mfc2 $v0, $0, 4");}
*/

int getCoreID()
{
	asm("mfc0 $v0, $15, 1");
}

void delay()
{
	int i = 0;
	while(i < 2000){i++;}
}

// ADDED >>
void writeUARTChar(char c)
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

void writeString(char* s)
{
	while(*s)
	{
		writeUARTChar(*s);
		++s;
	}
}

void writeHex(unsigned long long n)
{
	unsigned int i;
	for(i = 0;i < 16; ++i)
	{
		unsigned long long hexDigit = (n & 0xF000000000000000L) >> 60L;
		char hexDigitChar = (hexDigit < 10) ? ('0' + hexDigit) : ('A' + hexDigit - 10);
		writeUARTChar(hexDigitChar);
		n = n << 4;
	}
}


void writeDigit(unsigned long long n)
{
	unsigned int i;
	unsigned int top;
	char tmp[17];
	char str[17];
	
	for(i = 0;i < 17; ++i) str[i] = 0;
	i = 0;
	while(n > 0) {
		tmp[i] = '0' + (n % 10);
		n /= 10;
		i = i + 1;
	}
	i--;
	top = i;
	while(i > 0) {
		str[top - i] = tmp[i];
		i--;
	}
	str[top] = tmp[0];
	writeString(str);
}


char readUARTChar()
{
	int i;
	char out;
	//Code for SOPC Builder serial output
	i = IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));
	while((i & 0x00800000) == 0)
	{
		i = IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));
	}
	
	i = i >> 24;
	out = (char)i;
	return out;
}

void fillArray(int *A, int n, int seed)
{
	int i;
	int val = seed;
	for (i=0; i<n; i++) {
		val = (val << 10) ^ (val + 10);
		A[i] = val;
	}
	//return A;
}

void swapVar(int *A, int i, int j) {
	int t = A[i];
	A[i] = A[j];
	A[j] = t;
}

void bubbleSort(int *A, int n)
{
	int newn;
	int i;
	do {
		newn = 0;
		for (i = 1; i <= n-1; i++) {
			if (A[i-1] > A[i]) {
				swapVar(A, i-1, i);
				/*writeString("Swapped ");
				writeHex(A[i-1]);
				writeString(" and ");
				writeHex(A[i-1]);
				writeString("\n");*/
				newn = i;
			}
		}
		n = newn;
	} while (n != 0);
}

void quickSort(int *arr, int beg, int end)
{
	if (end > beg + 1)
	{
		int piv = arr[beg], l = beg + 1, r = end;
		while (l < r)
		{
			if (arr[l] <= piv)
				l++;
			else {
				/*writeString("Swapped ");
				writeHex(arr[l]);
				writeString(" and ");
				writeHex(arr[r]);
				writeString("\n");*/
				swapVar(arr, l, --r);
			}
		}
		/*writeString("Swapped ");
		writeHex(arr[l]);
		writeString(" and ");
		writeHex(arr[beg]);
		writeString("\n");*/
		swapVar(arr, --l, beg);
		quickSort(arr, beg, l);
		quickSort(arr, r, end);
	}
}

int binarySearch(int *arr, int value, int left, int right) {
      while (left <= right) {
            int middle = (left + right) / 2;
            if (arr[middle] == value)
                  return middle;
            else if (arr[middle] > value)
                  right = middle - 1;
            else
                  left = middle + 1;
      }
      return -1;
}

long long mul(long long A, long long B)
{
	return A*B;
}

long long modExp(long long A, long long B)
{
	long long base,power;
	base=A;
	power=B;
	long long result = 1;
	int i;
	for (i = 63; i >= 0; i--) {
		result = mul(result,result);
		if ((power & (1 << i)) != 0) {
			result = mul(result,base);
		}
	}
	return result;
}
// ADDED <<

int main(void)
{
	int i;
	int j;
	int data;
	int data2=0;
	char in = 0;
	i = 0x0000000004000500;
	int numBad = 1;
	int count;
	long long cpi;
	volatile void *wptr;
	short leds = 0;
	char capInit = 0;

	//mv1kC1(0x9800000040000000, 0x9800000000001000);
	
	//setInterrupts();
	//__writeStringLoopback("Stack TLB entry setup.\n");
	__writeString("Hello World! Have a BERI nice day!\n");
	//debugTlb();
	//cp0Regs();
	
//	causeTrap();
//	__writeString("Came back from trap and still alive :)\n");

//	sysCtrlTest();
//	data = rdtscl(5);

	//int coreid = getCoreID();
/*
	if (coreid == 0)
	{	
		delay();
		coreCount++;
	}
	else
	{
		coreCount++;
	}
*/

	while(in != 'Q') 
	{
		if (in != '\n') {
			//if (coreid == 0)
			{
			globalReset = 0;
			coreFlag = 0;
			__writeString("\n Number of Cores in Use : ");
			__writeHex(coreCount);

			__writeString("\n Menu:\n");
			__writeString("   \"F\" for floating point co-processor test.\n");
			__writeString("   \"L\" for load-linked and store-conditional test.\n");
			__writeString("   \"A\" for arithmetic test result.\n");
			__writeString("   \"B\" array bounds checking benchmark.\n");
			__writeString("   \"D\" for multiply and divide test.\n");
			__writeString("   \"C\" for Count register test.\n");
			__writeString("   \"M\" for eternal memory test.\n");
			//__writeString("   \"N\" for networking test.\n");
			__writeString("   \"V\" for framebuffer test.\n");
			__writeString("   \"K\" for Capability initialization.\n");
			__writeString("   \"l\" to invert LEDs.\n");
			__writeString("   \"T\" for touchscreen test.\n");
			__writeString("   \"q\" for quicksort boundschecking test.\n");
			__writeString("   \"d\" for domain crossing benchmark.\n");
			__writeString("   \"G\" for compositor test.\n");
			__writeString("   \"Q\" to quit.\n");
			}
		}

		in = __readUARTChar();
		__writeUARTChar(in);
		__writeString("\n");
		//__writeHex(in);
		//__writeString("\n");
	
		if (in == 'F') {
			__writeString("Floating Point co-processor test\n");
			CoProFPTest();
		}
		
		if (in == 'L') {
			__writeString("Load-linked and store-conditional test:\n");
			data = 13;
			data = ll(&data);
			data = sc(&data, 14);
			//__writeHex(data);
			__writeString(" < load-linked and store-conditional result (0)\n");
			data = testNset(&data, 14);
			//__writeHex(data);
			__writeString(" < test and set result (1)\n");
		}
		
		if (in == 'A') {
			__writeString("Arithmetic test:\n");
			data = 0;
			data = arithmaticTest();
			__writeHex(data);
			__writeString(" < arithmetic test result (0)\n");
		}
		
		if (in == 'T') {
			int * tX= (int *)0x9000000005000000;
			int * tY= (int *)0x9000000005000004;
			int * tDown= (int *)0x9000000005000008;
			__writeString("X:");
			data = *tX;
			__writeHex(data);
			
			__writeString("   Y:");
			data = *tY;
			__writeHex(data);
			
			__writeString("   Down:");
			data = *tDown;
			__writeHex(data);
			
			__writeString("\n");
		}
	
		if (in == 'G') {
			__writeString("Compositor test:\n");
		}
		
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
			__writeString("Memory test:\n");
			i = 0;
			while(1) 	{
				count = getCount();
        //__writeString("count:");
				//__writeHex(count);
        //__writeString("\n");
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
				cpi = getCount() - count;
        //__writeString("newCount - count:");
				//__writeHex(cpi);
				//__writeString("\n");
        
				__writeHex((int)(DRAM_BASE + (idx<<2))); 
				__writeString(" = ");
				__writeHex(data);
				__writeString("?\n");
				if (numBad == 0) {
					__writeString("All good! \n");
				} else {
					__writeHex(numBad);
					__writeString(" were bad :(\n");
					numBad = 0;
				}
				cpi = (cpi*1000);
        
        //__writeString("diff*1000:");
				//__writeHex(cpi);
       //__writeString("\n");
       
        // 8 instructions in the first loop, 12 in the second.
				cpi = cpi/((8+12)*0x4000);
        
				__writeString("CPI of ");
				__writeDigit(cpi);
				__writeString("\n");
				
				i+=0x4000;
				if (i > 0x07000000) i = 0;
			}
		}
		if (in == 'C') {
			__writeString("Count Register Test:\n");
			for(i=0;i<10;i++) 	{
				data = ((volatile int *)MIPS_PHYS_TO_UNCACHED(CHERI_COUNT))[0];
				__writeHex(data);
				__writeString(", ");
			}
			__writeString("\n");
		}
		
		if (in == 'K') {
			if (capInit==0) {
				FBIncBase(0x9000000004000000);
				long length = FBGetLeng();
				length = length - 800*600*2;
				FBDecLeng(length);
				capInit = 1;
			}
			
			__writeString("C4.base=    ");__writeHex(FBGetBase());__writeString("\n");
			__writeString("C4.length=  ");__writeHex(FBGetLeng());__writeString("\n");
			CapRegDump();

		}
		if (in == 'V') {
			int color = 0x8888;
			int x = 50;
			int y = 50;
			int length = 75;
			int height = 50;
			long frameBuff = 0x9000000004000000;

			
			for (x=200; x<500; x+=100) {
				for (y=300; y<500; y+=75) {
					draw3DRect(color, x, y, length, height);
				}
			}
			
			
			for (i=0; i<(800*600/4); i++) {
				FBSDR(0x0C63F80007E0001F,i<<3);
			}
			
			int offset = y*800 + x;
			int addOff;
			int totOff;
			for (i=0; i<(800*600); i++) {
				((volatile short*)frameBuff)[i] = i;
			}
			for (i=0; i<height; i++) {
				for (j=0; j<length; j++) {
					addOff = (800*i) + j;
					totOff = (offset+addOff);
					((volatile short*)frameBuff)[totOff] = color;
				}
			}
		}
		if (in == 'l') {
			leds = ~leds;
			IO_WR(CHERI_LEDS,leds);
		}
		
		if (in == 'N') {
			wptr = (void *)CHERI_NET_RX;
			i = *(volatile int *)wptr;
			__writeString("After accessing CHERI_NET_RX, read:\n");
			__writeDigit(i);

			i = 0xabcd;
			wptr = (void *)CHERI_NET_TX;
			__writeString("Before writing 123 to CHERI_NET_TX\n");
			*((volatile int *)CHERI_NET_TX) = i;
			__writeString("After writing 123 to CHERI_NET_TX\n");
		}
		
		if (in == 'B') {
		  arrayBench();
		}
		if (in == 'q') {
		  doQuicksort();
		}
		if (in == 'd') {
			armArray();
		}
// ADDED >>
                if (in == 'X') {
			int A[SORT_SIZE];

			writeString("Branch Exercise:\n");
			fillArray(A, SORT_SIZE/2, 1000);
			bubbleSort(A, SORT_SIZE/2);
			writeString("Finished Bubble Sort!\n");
			for (i = 0; i<SORT_SIZE/2; i+= SORT_SIZE/2/32) {
				writeHex(i);
				writeString(" = ");
				writeHex(A[i]);
				writeString("\n");
			}
			fillArray(A, SORT_SIZE, 1234);
			quickSort(A, 0, SORT_SIZE);
			writeString("Finished Quick Sort!\n");
			for (i = 0; i<SORT_SIZE; i+= SORT_SIZE/32) {
				writeHex(i);
				writeString(" = ");
				writeHex(A[i]);
				writeString("\n");
			}
			writeString("Searching for each element...\n");
			for (j = 0; j<4; j++) {
				for (i = 0; i<SORT_SIZE; i++) {
					binarySearch(A, A[i], 0, SORT_SIZE);
				}
			}
			writeString("Searching Done.\n");
			writeString("Starting Modular Eponentiation\n");
			for (i = 0; i<SORT_SIZE/4; i++) {
				writeHex(modExp(i,0xAAAAAAAAAAAAAAAA));
				writeString("\n");
			}
                }
// ADDED <<
		//debugRegs();
	}

	return 0;
}

