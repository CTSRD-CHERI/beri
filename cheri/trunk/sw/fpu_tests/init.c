/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2014 Jonathan Woodruff
 * Copyright (c) 2011 Steven J. Murdoch
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2012 Benjamin Thorner
 * Copyright (c) 2013 A. Theodore Markettos
 * Copyright (c) 2013 Philip Withnall
 * Copyright (c) 2013 Alan Mujumdar
 * Copyright (c) 2013 Colin Rothwell
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

#include "../../../../cherilibs/trunk/include/parameters.h"
#define BUTTONS (0x900000007F009000ULL)
#define USBCONT (0x900000007F100000ULL)

#define IO_RD_BYTE(x) (*(volatile unsigned char*)(x))
#define IO_RD(x) (*(volatile unsigned long long*)(x))
#define IO_RD32(x) (*(volatile int*)(x))
#define IO_RD16(x) (*(volatile short*)(x))
#define IO_WR(x, y) (*(volatile unsigned long long*)(x) = y)
#define IO_WR_BYTE(x, y) (*(volatile unsigned char*)(x) = y)


void writeUARTChar(char c)
{
	//Code for SOPC Builder serial output
	while ((IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE)+4) &
	    0xFFFF) == 0) {
		asm("add $v0, $v0, $0");
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
//		unsigned long hexDigit = (n & 0xF0000000L) >> 28L;
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
	i = IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));
	while((i & 0x00800000) == 0)
	{
		i = IO_RD32(MIPS_PHYS_TO_UNCACHED(CHERI_JTAG_UART_BASE));
	}
	
	i = i >> 24;
	out = (char)i;
	return out;
}


/* ************************************************************************** */
// Helper functions to access I2C
// base address
#define HDMI_TX_RESET_N_BASE (0x900000007F00B080ULL)
#define I2C_BASE (0x900000007F00B000ULL)

// I2C device number of IT6613 HDMI chip
// note: the device number is the upper 7-bits and bit 0 is left to indicate
//       read or write
#define HDMI_I2C_DEV  0x98

// clock scale factor to get target 100kHz:  scale = system_clock_kHz/(4*100)
#define I2C_CLK_SCALE 1250

void
i2c_write_reg(int regnum, int data)
{
	IO_WR_BYTE(I2C_BASE + regnum, data);
}


int
i2c_read_reg(int regnum)
{
	return IO_RD_BYTE(I2C_BASE + regnum);
}


void
i2c_write_clock_scale(int scale)  // scale is 16-bit number
{
	i2c_write_reg(0, scale & 0xff);
	i2c_write_reg(1, scale >> 8);
}


int
i2c_read_clock_scale(void)
{
	return i2c_read_reg(0) | (i2c_read_reg(1)<<8);
}


void i2c_write_control(int d) { i2c_write_reg(2, d); }
void i2c_write_tx_data(int d) { i2c_write_reg(3, d); }
void i2c_write_command(int d) { i2c_write_reg(4, d); }

int i2c_read_control() { return i2c_read_reg(2); }
int i2c_read_rx_data() { return i2c_read_reg(3); }
int i2c_read_status () { return i2c_read_reg(4); }
int i2c_read_tx_data() { return i2c_read_reg(5); }
int i2c_read_command() { return i2c_read_reg(6); }


int
i2c_write_data_command(int data, int command)
{
	int t, sr;
	//writeString("i2c write data=");
	//writeHex(data);
	//writeString(", command=");
	//writeHex(command);
	//writeString("\n");
	i2c_write_tx_data(data); // device num + write (=0) bit
	i2c_write_command(command);
	sr = i2c_read_status();
	if((sr & 0x02)==0){
		//writeString("ERROR - I2C should be busy but isn't - sr=");
		//writeHex(sr);
		//writeString("\n");
	}

	for(t=100*I2C_CLK_SCALE; (t>0) && ((sr & 0x02)!=0); t--)
		sr = i2c_read_status();
	/*
	if(t==0)
		writeString("WRITE TIME OUT\n");
	if((sr & 0x02)!=0)
		writeString("ERROR - transfer is not complete\n");
	if((sr&0x80)!=0)
		writeString("ERROR - no ack received\n");
	*/
	return sr;
}

void in(int num) { 
    asm("and $t0, $a0, $a0");
}

int out() { 
    asm("and $v0, $t0, $t0");
}

int CoProFPTestEval(long in, long out, int t_num, int err) {
    if (in != out) {
        writeHex(t_num);
        writeString(" < FPU co-processor test failed\n\t");
        writeHex(in);
        writeString(" < expected\n\t");
        writeHex(out);
        writeString(" < got \n");
        return -1;
    } 
    return err;
}


void CoProFPTest() {
    int t_num = 1;
    int err = 0;
    // Test RI instructions
    asm("li $t0, 9");
    asm("mtc1 $t0, $f1");
    asm("mfc1 $t1, $f1");
    asm("and $t0, $t0, $t1");
    err = CoProFPTestEval(9,out(),t_num++,err);
    asm("lui $t0, 18");
    asm("dsll $t0, $t0, 16");
    asm("ori $t0, 7");
    asm("dmtc1 $t0, $f5");
    asm("dmfc1 $t1, $f5");
    asm("and $t0, $t0, $t1");
    err = CoProFPTestEval(((long)18 << 32) + 7,out(),t_num++,err);
    asm("li $t0, 0xFFF3F");
    asm("ctc1 $t0, $f25");
    asm("cfc1 $t1, $f25");
    asm("and $t0, $t0, $t1");
    err = CoProFPTestEval(0x3F,out(),t_num++,err);
    asm("li $t0, 0xFFF1");
    asm("ctc1 $t0, $f26");
    asm("cfc1 $t1, $f26");
    asm("and $t0, $t0, $t1");
    err = CoProFPTestEval(0xF070,out(),t_num++,err);
    asm("li $t0, 0xFFF86");
    asm("ctc1 $t0, $f28");
    asm("cfc1 $t1, $f28");
    asm("and $t0, $t0, $t1");
    err = CoProFPTestEval(0xF86,out(),t_num++,err);
    asm("lui $t0, 0x0003");
    asm("ori $t0, 0xFFFF");
    asm("ctc1 $t0, $f31");
    asm("cfc1 $t1, $f31");
    asm("and $t0, $t0, $t1");
    err = CoProFPTestEval(0x0003FFFF,out(),t_num++,err);
    asm("cfc1 $t0, $f26");
    err = CoProFPTestEval(0x0003F07C,out(),t_num++,err);
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0,out(),t_num++,err);
    asm("cfc1 $t0, $f28");
    err = CoProFPTestEval(0xF83,out(),t_num++,err);
    if (err != -1) {
        writeString("RI Tests passed.\n");
    }
    writeString("Testing FIR\n");
    err = 0;
    asm("cfc1 $t0, $f0");
    err = CoProFPTestEval(0x470000, out(), t_num++, err);
    if (err != -1) {
        writeString("FIR Present and correct.\n");
    }
    // Absolute value
    err = 0;
    writeString("Testing Absolute...\n");
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
    if (err != -1) {
        writeString("Absolute passed tests!\n");
    }
    // Addition
    writeString("Testing Addition... \n");
    err = 0;
    asm("lui $t0, 0x3F80");
    asm("mtc1 $t0, $f15");
    asm("add.S $f14, $f15, $f15");
    asm("mfc1 $t0, $f14");
    err = CoProFPTestEval(0x40000000,out(),t_num++,err);

    // ADD.S
    asm("lui $t0, 0x3F80"); // 1.0
    asm("mtc1 $t0, $f14");
    asm("add.S $f14, $f14, $f14");
    asm("dmfc1 $t0,  $f14");
    err=CoProFPTestEval(0x40000000,out(),t_num++,err);
    // ADD.D
    asm("lui $t2, 0x3FF0");
    asm("dsll $t2, $t2, 32"); // 1.0
    asm("dmtc1 $t2, $f13");
    asm("add.D $f13, $f13, $f13");
    asm("dmfc1 $t0,  $f13");
    err=CoProFPTestEval(0x4000000000000000,out(),t_num++,err);
    // ADD.PS
    asm("lui $t0, 0x3F80");
    asm("dsll $t0, $t0, 32"); // 1.0
    asm("ori $t1, $0, 0x4000");
    asm("dsll $t1, $t1, 16"); // 2.0
    asm("or $t0, $t0, $t1");
    asm("dmtc1 $t0, $f15");
    // Loading (-6589.89, 4.89)
    asm("add $s2, $0, $0");
    asm("ori $s2, $s2, 0xC5CD");
    asm("dsll $s2, $s2, 16");
    asm("ori $s2, $s2, 0xEF1F");
    asm("dsll $s2, $s2, 16");
    asm("ori $s2, $s2, 0x409C");
    asm("dsll $s2, $s2, 16");
    asm("ori $s2, $s2, 0x7AE1");
    asm("dmtc1 $s2, $f0");
    // Loading (6589.89, 47.3)
    asm("add $s2, $0, $0");
    asm("ori $s2, $s2, 0x45CD");
    asm("dsll $s2, $s2, 16");
    asm("ori $s2, $s2, 0xEF1F");
    asm("dsll $s2, $s2, 16");
    asm("ori $s2, $s2, 0x423D");
    asm("dsll $s2, $s2, 16");
    asm("ori $s2, $s2, 0x3333");
    asm("dmtc1 $s2, $f1");
    // These are deliberately sequential to test that using one megafunction
    // works properly
    asm("add.ps $f15, $f15, $f15");
    asm("add.ps $f0, $f0, $f1");
    asm("dmfc1 $t0,  $f0");
    err=CoProFPTestEval(0x000000004250C28f,out(),t_num++,err);
    asm("dmfc1 $t0,  $f15");
    err=CoProFPTestEval(0x4000000040800000,out(),t_num++,err);
	err=4;
    if (err != -1) {
        writeString("Addition passed tests!\n");
    }
    // Subtraction
    writeString("Testing Subtraction...\n");
    err = 0;
    asm("lui $t0, 0x4000");
    asm("lui $t1, 0x4080");
    asm("dmtc1 $t0, $f5");
    asm("dmtc1 $t1, $f6");
    asm("sub.S $f5, $f5, $f6");
    asm("dmfc1 $t0, $f5");
    err = CoProFPTestEval(0xFFFFFFFFC0000000,out(),t_num++,err);
	// SUB.D
	asm("lui $t0, 0x4000");
	asm("dsll $t0, $t0, 32"); // 2.0
	asm("lui $t1, 0x3FF0");
	asm("dsll $t1, $t1, 32");
	asm("dmtc1 $t0, $f15");
	asm("dmtc1 $t1, $f16");
	asm("sub.D $f11, $f15, $f16");
	asm("dmfc1 $t0,  $f11");
	err=CoProFPTestEval(0x3FF0000000000000,out(),t_num++,err);
	// SUB.S
	asm("lui $t0, 0x4000"); // 2.0
	asm("lui $t1, 0x4080"); // 4.0
	asm("dmtc1 $t0, $f5");
	asm("dmtc1 $t1, $f6");
	asm("sub.S $f5, $f5, $f6");
	asm("dmfc1 $t0,  $f5");
	err=CoProFPTestEval(0xFFFFFFFFC0000000,out(),t_num++,err);
	// Loading (75, -32)
	asm("add $s2, $0, $0");
	asm("ori $s2, $s2, 0x4296");
	asm("dsll $s2, $s2, 32");
	asm("ori $s2, $s2, 0xC200");
	asm("dsll $s2, $s2, 16");
	asm("dmtc1 $s2, $f0");
	// Loading (50, -64)
	asm("add $s2, $0, $0");
	asm("ori $s2, $s2, 0x4248");
	asm("dsll $s2, $s2, 32");
	asm("ori $s2, $s2, 0xC280");
	asm("dsll $s2, $s2, 16");
	asm("dmtc1 $s2, $f1");
	// Performing operation
	asm("sub.ps $f0, $f0, $f1");
	asm("dmfc1 $t0,  $f0");
	err=CoProFPTestEval(0x41C8000042000000,out(),t_num++,err);

    if (err == 0) {
        writeString("Subtraction tests passed!\n");
    }
    // Negation
    writeString("Testing Negation...\n");
    err = 0;
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
    err = CoProFPTestEval(0xFFF1000000000000,out(),t_num++,err);
    if (err != -1) {
        writeString("Negation tests passed!\n");
    }
    // Multiplication
    writeString("Testing Multiplication...\n");
    err = 0;
    asm("lui $t2, 0x4080");
    asm("mtc1 $t2, $f20");
    asm("mul.S $f20, $f20, $f20");
    asm("dmfc1 $t0, $f20");
    err = CoProFPTestEval(0x41800000,out(),t_num++,err);

	//PS
	// Loading (3, 4.89)
	asm("add $s2, $0, $0");
	asm("ori $s2, $s2, 0x4040");
	asm("dsll $s2, $s2, 32");
	asm("ori $s2, $s2, 0x409C");
	asm("dsll $s2, $s2, 16");
	asm("ori $s2, $s2, 0x7AE1");
	asm("dmtc1 $s2, $f0");
	// Loading (4, 47.3)
	asm("add $s2, $0, $0");
	asm("ori $s2, $s2, 0x4080");
	asm("dsll $s2, $s2, 32");
	asm("ori $s2, $s2, 0x423D");
	asm("dsll $s2, $s2, 16");
	asm("ori $s2, $s2, 0x3333");
	asm("dmtc1 $s2, $f1");
	// Performing operation
	asm("mul.ps $f0, $f0, $f1");
	asm("dmfc1 $t0,  $f0");
	err=CoProFPTestEval(0x4140000043674C08,out(),t_num++,err);

    // MUL.D
    asm("lui $t3, 0x4000");
    asm("dsll $t3, $t3, 32"); // 2.0
    asm("dmtc1 $t3, $f29");
    asm("mul.D $f27, $f29, $f29");
    asm("dmfc1 $t0, $f27");
    err = CoProFPTestEval(0x4010000000000000,out(),t_num++,err);
    if (err != -1) {
        writeString("Multiplication tests passed!\n");
    }

    // Division
    writeString("Testing Division...\n");
    err = 0;
    asm("lui $t0, 0x41A0");
    asm("mtc1 $t0, $f10");
    asm("lui $t0, 0x40A0");
    asm("mtc1 $t0, $f11");
    asm("div.S $f10, $f10, $f11");
    asm("mfc1 $t0, $f10");
    err = CoProFPTestEval(0x40800000,out(),t_num++,err);
    // DIV.D
    // Loading 3456.3
    asm("add $s0, $0, $0");
    asm("ori $s0, $s0, 0x40AB");
    asm("dsll $s0, $s0, 16");
    asm("ori $s0, $s0, 0x0099");
    asm("dsll $s0, $s0, 16");
    asm("ori $s0, $s0, 0x9999");
    asm("dsll $s0, $s0, 16");
    asm("ori $s0, $s0, 0x999A");
    asm("dmtc1 $s0, $f0");
    // Loading 12.45
    asm("add $s0, $0, $0");
    asm("ori $s0, $s0, 0x4028");
    asm("dsll $s0, $s0, 16");
    asm("ori $s0, $s0, 0xE666");
    asm("dsll $s0, $s0, 16");
    asm("ori $s0, $s0, 0x6666");
    asm("dsll $s0, $s0, 16");
    asm("ori $s0, $s0, 0x6666");
    asm("dmtc1 $s0, $f1");
    // Performing operation
    asm("div.d $f0, $f0, $f1");
    asm("dmfc1 $t0, $f0");
    err = CoProFPTestEval(0x407159D4C0000000, out(), t_num++, err);
    if (err == 0) {
        writeString("Division tests passed!\n");
    }
    // Square root
    writeString("Testing square root...\n");
    err = 0;
    asm("lui $t0, 0x4280");
    asm("mtc1 $t0, $f17");
    asm("sqrt.S $f17, $f17");
    asm("mfc1 $t0, $f17");
    err = CoProFPTestEval(0x41000000,out(),t_num++,err);
    // SQRT.D
    // Loading 464.912
    asm("add $s1, $0, $0");
    asm("ori $s1, $s1, 0x407D");
    asm("dsll $s1, $s1, 16");
    asm("ori $s1, $s1, 0x0E97");
    asm("dsll $s1, $s1, 16");
    asm("ori $s1, $s1, 0x8D4F");
    asm("dsll $s1, $s1, 16");
    asm("ori $s1, $s1, 0xDF3B");
    asm("dmtc1 $s1, $f0");
    // Performing operation
    asm("sqrt.d $f0, $f0");
    asm("dmfc1 $t0, $f0");
    err = CoProFPTestEval(0x40358FD340000000, out(), t_num++, err);
    if (err == 0) {
        writeString("Square root tests passed!\n");
    }
    writeString("Testing reciprocal THEN square root...\n");
    asm("lui $t0, 0x4080");
    asm("mtc1 $t0, $f23");
    asm("recip.s $f22, $f23");
    asm("mfc1 $t0, $f22");
    err = CoProFPTestEval(0x3E800000,out(),t_num++,err);
    asm("sqrt.s $f21, $f22");
    asm("mfc1 $t0, $f21");
    err = CoProFPTestEval(0x3F000000,out(),t_num++,err);

    // Reciprocal square root
    writeString("Testing reciprocal square root...\n");
    err = 0;
    asm("lui $t0, 0x4080");
    asm("mtc1 $t0, $f23");
    asm("rsqrt.S $f22, $f23");
    asm("mfc1 $t0, $f22");
    err = CoProFPTestEval(0x3F000000,out(),t_num++,err);
    // RSQRT.D
    // Loading 64
    asm("add $s1, $0, $0");
    asm("ori $s1, $s1, 0x4050");
    asm("dsll $s1, $s1, 48");
    asm("dmtc1 $s1, $f0");
    // Performing operation
    asm("rsqrt.d $f0, $f0");
    asm("dmfc1 $t0, $f0");
    err = CoProFPTestEval(0x3FC0000000000000, out(), t_num++, err);
    if (err == 0) {
        writeString("Reciprocal square root tests passed!\n");
    }
    // Reciprocal.
    writeString("Testing reciprocal...\n");
    err = 0;
    asm("lui $t0, 0");
    asm("mtc1 $t0, $f19");
    asm("recip.S $f19, $f19");
    asm("mfc1 $t0, $f19");
    err = CoProFPTestEval(0x7F800000,out(),t_num++,err);
    asm("lui $t0, 0x3F00");
    asm("mtc1 $t0, $f19");
    asm("recip.S $f19, $f19");
    asm("mfc1 $t0, $f19");
    err = CoProFPTestEval(0x40000000, out(), t_num++, err);
    // RECIP.D
    asm("lui $t0, 0x4030");
    asm("dsll $t0, $t0, 32"); // 16.0
    asm("dmtc1 $t0, $f19");
    asm("recip.D $f19, $f19");
    asm("dmfc1 $t0, $f19");
    err = CoProFPTestEval(0x3FB0000000000000, out(), t_num++, err);
    if (err == 0) {
        writeString("Reciprocal tests passed!\n");
    }
    // Comparison
    writeString("Testing comparison...\n");
    err = 0;
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
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.f.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    writeString("Doing first packed single.\n");
    asm("c.f.PS $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    // Comparison (Unordered)
    asm("lui $t0, 0x7F81");
    asm("mtc1 $t0, $f5");
    asm("ctc1 $0, $f25"); //Reset condition codes.
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
    asm("ctc1 $0, $f25");
    // Comparison (Equal)
    asm("c.eq.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.eq.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.eq.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("c.eq.S $f3, $f4");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.eq.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.eq.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
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
    asm("ctc1 $0, $f31");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("c.ueq.S $f3, $f4");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ueq.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ueq.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ueq.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ueq.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ueq.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
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
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.olt.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.olt.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.olt.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
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
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ult.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ult.D $f13, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ult.PS $f23, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
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
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ult.S $f3, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ult.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ult.PS $f24, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
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
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("c.ole.S $f3, $f4");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ole.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ole.PS $f24, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x2,out(),t_num++,err);
    asm("c.ole.S $f4, $f3");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ole.D $f14, $f13");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x1,out(),t_num++,err);
    asm("c.ole.PS $f23, $f24");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
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
    asm("ctc1 $0, $f25");
    err = CoProFPTestEval(0x3,out(),t_num++,err);
    asm("c.ule.S $f3, $f4");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ule.D $f13, $f14");
    asm("cfc1 $t0, $f25");
    err = CoProFPTestEval(0x0,out(),t_num++,err);
    asm("c.ule.PS $f24, $f23");
    asm("cfc1 $t0, $f25");
    asm("ctc1 $0, $f25");
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
    if (err != -1) {
        writeString("Comparison tests passed!\n");
    }
    // Branches
    writeString("Testing branching...\n");
    err = 0;
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
    if (err != -1) {
        writeString("Branching tests passed!\n");
    }
    // MOV
    writeString("Testing mov...\n");
    err = 0;
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
    if (err != -1) {
        writeString("All mov tests passed!\n");
    }
    writeString("Testing conversion...\n");
    err = 0;
    // Convert to single from word
    asm("li $t0, 1");
    asm("mtc1 $t0, $f0");
    asm("cvt.s.w $f0, $f0");
    asm("dmfc1 $t0, $f0");
    err = CoProFPTestEval(0x3F800000, out(), t_num++, err);
    asm("li $t1, 33558633"); // 2 ^ 25 + 4201 - can't maintain precision
    asm("mtc1 $t1, $f1");
    asm("cvt.s.w $f1, $f1");
    asm("dmfc1 $t0, $f1");
    err = CoProFPTestEval(0x4C00041A, out(), t_num++, err);
    asm("li $t2, -23");
    asm("mtc1 $t2, $f2");
    asm("cvt.s.w $f2, $f2");
    asm("dmfc1 $t0, $f2");
    err = CoProFPTestEval(0xFFFFFFFFC1B80000, out(), t_num++, err);
    // Convert to single from double
    asm("li $s0, 0x3FF00000"); // 1
    asm("dsll $s0, $s0, 32");
    asm("dmtc1 $s0, $f3");
    asm("cvt.s.d $f3, $f3");
    asm("mfc1 $t0, $f3");
    err = CoProFPTestEval(0x3F800000, out(), t_num++, err);
    asm("li $s1, 0x3FC55555"); // ~ 1/6
    asm("dsll $s1, $s1, 32"); // shift top bits to correct place
    asm("li $t3, 0x5530AED6"); // load bottom bits
    asm("or $s1, $s1, $t3");
    asm("dmtc1 $s1, $f4");
    asm("cvt.s.d $f4, $f4");
    asm("mfc1 $t0, $f4");
    err = CoProFPTestEval(0x3e2aaaaa, out(), t_num++, err);
    asm("li $s2, 0xC06D5431"); // -234.6311
    asm("dsll $s2, $s2, 32");
    asm("li $t3, 0xF8A0902E");
    asm("and $s2, $s2, $t3"); // and because it's sign extended
    asm("dmtc1 $s2, $f5");
    asm("cvt.s.d $f5, $f5");
    asm("mfc1 $t0, $f5");
    err = CoProFPTestEval(0xffffffffc36aa188, out(), t_num++, err);
    asm("li $s3, 0x41E1808E"); // large number
    asm("dsll $s3, $s3, 32");
    asm("li $t3, 0x6C666666");
    asm("or $s3, $s3, $t3");
    asm("dmtc1 $s3, $f6");
    asm("cvt.s.d $f6, $f6");
    asm("mfc1 $t0, $f6");
    err = CoProFPTestEval(0x4f0c0473, out(), t_num++, err);
    // Convert to double from single
    asm("li $s4, 0x3F800000"); // 1
    asm("mtc1 $s4, $f7");
    asm("cvt.d.s $f7, $f7");
    asm("dmfc1 $t0, $f7");
    err = CoProFPTestEval(0x3FF0000000000000, out(), t_num++, err);
    asm("li $s5, 0x3E4CCCCD"); // 0.2
    asm("mtc1 $s5, $f8");
    asm("cvt.d.s $f8, $f8");
    asm("dmfc1 $t0, $f8");
    err = CoProFPTestEval(0x3FC99999A0000000, out(), t_num++, err);
    asm("li $s6, 0xC68EE746"); // -18291.636
    asm("mtc1 $s6, $f9");
    asm("cvt.d.s $f9, $f9");
    asm("dmfc1 $t0, $f9");
    err = CoProFPTestEval(0xC0D1DCE8C0000000, out(), t_num++, err);

    if (err != -1) {
        writeString("Conversion Tests Passed!\n");
    }

    writeString("All tests ran.");
}


/* ********************************************************************* */

int main(void)
{
	writeString("Hi!\n");

    /*int j = 0;*/
    /*for (j=0; j<0xFFFF; j+=4) {*/
        /*writeHex(j);*/
        /*writeString(": 0x");*/
        /*writeHex(IO_RD32(USBCONT+j));*/
        /*writeString("\n");*/
    /*}*/
    /*for (j=0x1000; j<0xFFFF; j+=8) {*/
        /*writeHex(j);*/
        /*writeString(": Wrote 0x");*/
        /*IO_WR(USBCONT+j, USBCONT+j);*/
        /*writeHex(IO_RD(USBCONT+j));*/
        /*writeString("\n");*/
    /*}*/

    CoProFPTest();
	
	return 0;
}
