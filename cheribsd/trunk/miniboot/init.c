/*-
 * Copyright (c) 2012 Jonathan Woodruff
 * Copyright (c) 2012 Simon W. Moore
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

#include "../../../cherilibs/trunk/include/parameters.h"
#define BUTTONS (0x900000007F009000ULL)

#define IO_RD_BYTE(x) (*(volatile unsigned char*)(x))
#define IO_RD(x) (*(volatile unsigned long long*)(x))
#define IO_RD32(x) (*(volatile int*)(x))
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

void reset_hdmi_chip(void)
{
	IO_WR_BYTE(HDMI_TX_RESET_N_BASE, 0);
	writeString("Reset HDMI chip");  // debug output and delay all in one...
	IO_WR_BYTE(HDMI_TX_RESET_N_BASE, 1);
}

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

int
hdmi_read_reg(int i2c_addr)
{
	int t, sr;
	// write data: (7-bit address, 1-bit 0=write)
	// command: STA (start condition, bit 7) + write (bit 4)
	sr = i2c_write_data_command(HDMI_I2C_DEV, 0x90);
	sr = i2c_write_data_command(i2c_addr, 0x10);

	// now start the read (with STA and WR bits)
	sr = i2c_write_data_command(HDMI_I2C_DEV | 0x01, 0x90);
	// set RD bit, set ACK to '1' (NACK), set STO bit
	i2c_write_command(0x20 | 0x08 | 0x40);

	for(t=100*I2C_CLK_SCALE,sr=2; (t>0) && ((sr & 0x02)!=0); t--)
		sr = i2c_read_status();
	if(t==0) {
		writeString("READ TIME OUT - sr=");
		writeHex(sr);
		writeString("\n");
	}
	/*
	if((sr & 0x02)!=0)
		writeString("ERROR - transfer is not complete\n");
	if((sr&0x80)==0)
		writeString("ERROR - no nack received\n");
	*/
	return i2c_read_rx_data();
}

void
hdmi_write_reg(int i2c_addr, int i2c_data_byte)
{
	int sr;
	// write data: (7-bit address, 1-bit 0=write)
	// command: STA (start condition, bit 7) + write (bit 4)
	sr = i2c_write_data_command(HDMI_I2C_DEV, 0x90);
	// command=write
	sr = i2c_write_data_command(i2c_addr, 0x10);
	// command=write+STO (stop)
	sr = i2c_write_data_command(i2c_data_byte & 0xff, 0x50);
	/*
	writeString("i2c hdmi write addr=");
	writeHex(i2c_addr);
	writeString(", data=");
	writeHex(i2c_data_byte);
	writeString("\n");
	*/
}

void
configure_hdmi(void)
{
	// set clock scale factor = system_clock_freq_in_Khz / 400
	{
		int j;
		writeString("Setting clock_scale to 0x");
		writeHex(I2C_CLK_SCALE);
		writeString("\n");
		i2c_write_clock_scale(I2C_CLK_SCALE);
		j = i2c_read_clock_scale();
		writeString("clock scale = 0x");
		writeHex(j);
		writeString("\n");
		if(j==I2C_CLK_SCALE)
			writeString(" - passed\n");
		else
			writeString(" - FAILED\n");

		hdmi_write_reg(0x0f, 0); // switch to using lower register bank (needed after a reset?)

		j = hdmi_read_reg(1);
		if(j==0xca)
			writeString("Correct vendor ID\n");
		else {
			writeString("FAILED - Vendor ID=0x");
			writeHex(j);
			writeString(" but should be 0xca\n");
		}

		j = hdmi_read_reg(2) | ((hdmi_read_reg(3) & 0xf)<<8);
		if(j==0x613)
			writeString("Correct device ID\n");
		else {
			writeString("FAILED - Device ID=0x");
			writeHex(j);
			writeString(" but should be 0x613\n");
		}
	}

	// the following HDMI sequence is based on Chapter 2 of
	// the IT6613 Programming Guide

	// HDMI: reset internal circuits via its reg04 register
	hdmi_write_reg(4, 0xff);
	hdmi_write_reg(4, 0x00); // release resets
	// hdmi_write_reg(4, 0x1d); - from reg dump

	// HDMI: enable clock ring
	hdmi_write_reg(61, 0x10);	// seems to read as 0x30 on "correct" version?

	// HDMI: set default DVI mode
	{
		int reg;
		for(reg=0xc0; reg<=0xd0; reg++)
			hdmi_write_reg(reg, 0x00);
	}
	// setting from reg dump - makes any sense?
	hdmi_write_reg(0xc3, 0x08);

	// blue screen:
	// hdmi_write_reg(0xc1, 2);

	// HDMI: write protection of C5 register?	needed?
	hdmi_write_reg(0xf8, 0xff);

	// HDMI: disable all interrupts via mask bits
	hdmi_write_reg(0x09, 0xff);
	hdmi_write_reg(0x0a, 0xff);
	hdmi_write_reg(0x0b, 0xff);
	// ...and clear any pending interrupts
	hdmi_write_reg(0x0c, 0xff);
	hdmi_write_reg(0x0d, 0xff);

	// setup interrupt status reg as per reg dump
	// hdmi_write_reg(0x0e, 0x6e);
	hdmi_write_reg(0x0e, 0x00);	// SWM: better to leave as zero?


	// HDMI: set VIC=3, ColorMode=0, Bool16x9=1, ITU709=0
	// HDMI: set RGB444 mode
	//	hdmi_write_reg(0x70, 0x08); // no input data formatting, but sync embedded
	hdmi_write_reg(0x70, 0x0); // no input data formatting, but sync embedded
	hdmi_write_reg(0x72, 0); // no input data formatting
	hdmi_write_reg(0x90, 0); // no sync generation

	{
		int sum = 0;
		// HDMI: construct AVIINFO (video frame information)
		hdmi_write_reg(0x0f, 1); // switch to using upper register bank
		/*
		if(hdmi_read_reg(0x0f)!=1)
			writeString("ASSERTION ERROR: not using correct register bank (see reg 0x0f)\n");
		*/
		hdmi_write_reg(0x58, 0x10); //=0 for DVI mode	 - (1<<4) // AVIINFO_DB1 = 0?
		sum += 0x10;
			//		hdmi_write_reg(0x59, 8 | (2<<4)); // AVIINFO_DB2 = 8 | (!b16x9)?(1<<4):(2<<4)
			//		sum += (8 | (2<<4));
		hdmi_write_reg(0x59, 0x68); // AVIINFO_DB2 = from reg dump
		sum += 0x68;
		hdmi_write_reg(0x5a, 0); // AVIINFO_DB3 = 0
		hdmi_write_reg(0x5b, 3); // AVIINFO_DB4 = VIC = 3
		sum +=3;
		hdmi_write_reg(0x5c, 0); // AVIINFO_DB5 = pixelrep & 3 = 0
		// 0x5d = checksum - see below
		hdmi_write_reg(0x5e, 0); // AVIINFO_DB6
		hdmi_write_reg(0x5f, 0); // AVIINFO_DB7
		hdmi_write_reg(0x60, 0); // AVIINFO_DB8
		hdmi_write_reg(0x61, 0); // AVIINFO_DB9
		hdmi_write_reg(0x62, 0); // AVIINFO_DB10
		hdmi_write_reg(0x63, 0); // AVIINFO_DB11
		hdmi_write_reg(0x64, 0); // AVIINFO_DB12
		hdmi_write_reg(0x65, 0); // AVIINFO_DB13
 		writeString("check: VIC = 0x");
		writeHex(hdmi_read_reg(0x5b));
		writeString("\n");
		// from docs:		hdmi_write_reg(0x5d, - (sum + 0x82 + 2 + 0x0d));
		// from Teraic code: hdmi_write_reg(0x5d, -sum - (2 + 1 + 13));
		// from reg dump:
		hdmi_write_reg(0x5d, 0xf4);
		writeString("check: checksum = 0x");
		writeHex(hdmi_read_reg(0x5b));
		writeString("\n");
	}
	hdmi_write_reg(0x0f, 0); // switch to using lower register bank
	hdmi_write_reg(0xcd, 3); // enable avi information packet

	// unmute screen? - correct?
	//hdmi_write_reg(0xc1, 0x41);
	hdmi_write_reg(0xc1, 0x00);

	// disable audio
	hdmi_write_reg(0xe0, 0x08);
	// needed? - part of audio format...
	hdmi_write_reg(0xe1, 0x0);

	writeString("Completed HDMI initialisation\n");
	/*
	{
		int reg;
		hdmi_write_reg(0x0f, 0); // switch to using lower register bank
		for(reg=0; reg<0xff; reg++)
			alt_printf("reg[%x] = %x\n",reg,hdmi_read_reg(reg));
		hdmi_write_reg(0x0f, 1); // switch to using upper register bank
		for(reg=0; reg<0xff; reg++)
			alt_printf("reg[b1 %x] = %x\n",reg,hdmi_read_reg(reg));
		hdmi_write_reg(0x0f, 0); // switch to using lower register bank
	}
	*/
}

void
brute_force_write_seq(void)
{

	// set clock scale factor = system_clock_freq_in_Khz / 400
	{
		int j;
		writeString("Setting clock_scale to 0x");
		writeHex(I2C_CLK_SCALE);
		writeString("\n");
		i2c_write_clock_scale(I2C_CLK_SCALE);
		j = i2c_read_clock_scale();
		writeString("clock scale = 0x");
		writeHex(j);
		if(j==I2C_CLK_SCALE)
			writeString(" - passed\n");
		else
			writeString(" - FAILED\n");

		hdmi_write_reg(0x0f, 0); // switch to using lower register bank (needed after a reset?)

		j = hdmi_read_reg(1);
		if(j==0xca)
			writeString("Correct vendor ID\n");
		else {
			writeString("FAILED - Vendor ID=0x");
			writeHex(j);
			writeString(" but should be 0xca\n");
		}

		j = hdmi_read_reg(2) | ((hdmi_read_reg(3) & 0xf)<<8);
		if(j==0x613)
			writeString("Correct device ID\n");
		else {
			writeString("FAILED - Device ID=0x");
			writeHex(j);
			writeString(" but should be 0x613\n");
		}
	}

	hdmi_write_reg(0x5, 0x0);
	hdmi_write_reg(0x4, 0x3d);
	hdmi_write_reg(0x4, 0x1d);
	hdmi_write_reg(0x61, 0x30);
	hdmi_write_reg(0x9, 0xb2);
	hdmi_write_reg(0xa, 0xf8);
	hdmi_write_reg(0xb, 0x37);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0xc9, 0x0);
	hdmi_write_reg(0xca, 0x0);
	hdmi_write_reg(0xcb, 0x0);
	hdmi_write_reg(0xcc, 0x0);
	hdmi_write_reg(0xcd, 0x0);
	hdmi_write_reg(0xce, 0x0);
	hdmi_write_reg(0xcf, 0x0);
	hdmi_write_reg(0xd0, 0x0);
	hdmi_write_reg(0xe1, 0x0);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0xf8, 0xc3);
	hdmi_write_reg(0xf8, 0xa5);
	hdmi_write_reg(0x22, 0x60);
	hdmi_write_reg(0x1a, 0xe0);
	hdmi_write_reg(0x22, 0x48);
	hdmi_write_reg(0xf8, 0xff);
	hdmi_write_reg(0x4, 0x1d);
	hdmi_write_reg(0x61, 0x30);
	hdmi_write_reg(0xc, 0xff);
	hdmi_write_reg(0xd, 0xff);
	hdmi_write_reg(0xe, 0xcf);
	hdmi_write_reg(0xe, 0xce);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x15, 0x9);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x15, 0x9);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x11, 0xa0);
	hdmi_write_reg(0x12, 0x0);
	hdmi_write_reg(0x13, 0x20);
	hdmi_write_reg(0x14, 0x0);
	hdmi_write_reg(0x15, 0x3);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x15, 0x9);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x11, 0xa0);
	hdmi_write_reg(0x12, 0x20);
	hdmi_write_reg(0x13, 0x20);
	hdmi_write_reg(0x14, 0x0);
	hdmi_write_reg(0x15, 0x3);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x15, 0x9);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x11, 0xa0);
	hdmi_write_reg(0x12, 0x40);
	hdmi_write_reg(0x13, 0x20);
	hdmi_write_reg(0x14, 0x0);
	hdmi_write_reg(0x15, 0x3);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x15, 0x9);
	hdmi_write_reg(0x10, 0x1);
	hdmi_write_reg(0x11, 0xa0);
	hdmi_write_reg(0x12, 0x60);
	hdmi_write_reg(0x13, 0x20);
	hdmi_write_reg(0x14, 0x0);
	hdmi_write_reg(0x15, 0x3);
	hdmi_write_reg(0x4, 0x1d);
	hdmi_write_reg(0x61, 0x30);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0xc1, 0x41);
	hdmi_write_reg(0xf, 0x1);
	hdmi_write_reg(0x58, 0x10);
	hdmi_write_reg(0x59, 0x68);
	hdmi_write_reg(0x5a, 0x0);
	hdmi_write_reg(0x5b, 0x3);
	hdmi_write_reg(0x5c, 0x0);
	hdmi_write_reg(0x5e, 0x0);
	hdmi_write_reg(0x5f, 0x0);
	hdmi_write_reg(0x60, 0x0);
	hdmi_write_reg(0x61, 0x0);
	hdmi_write_reg(0x62, 0x0);
	hdmi_write_reg(0x63, 0x0);
	hdmi_write_reg(0x64, 0x0);
	hdmi_write_reg(0x65, 0x0);
	hdmi_write_reg(0x5d, 0xf4);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0xcd, 0x3);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0xf, 0x1);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0x4, 0x1d);
	hdmi_write_reg(0x70, 0x0);
	hdmi_write_reg(0x72, 0x0);
	hdmi_write_reg(0xc0, 0x0);
	hdmi_write_reg(0x4, 0x15);
	hdmi_write_reg(0x61, 0x10);
	hdmi_write_reg(0x62, 0x18);
	hdmi_write_reg(0x63, 0x10);
	hdmi_write_reg(0x64, 0xc);
	hdmi_write_reg(0x4, 0x15);
	hdmi_write_reg(0x4, 0x15);
	hdmi_write_reg(0xc, 0x0);
	hdmi_write_reg(0xd, 0x40);
	hdmi_write_reg(0xe, 0x1);
	hdmi_write_reg(0xe, 0x0);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0x61, 0x0);
	hdmi_write_reg(0xf, 0x0);
	hdmi_write_reg(0xc1, 0x40);
	hdmi_write_reg(0xc6, 0x3);
}
/* ********************************************************************* */

int
main(int argc, char *argv[])

{
	writeString("Mini Bootloader Run\n");
	int j;

	writeString("Test I2C on HDMI chip\n");
	// reset HDMI chip via PIO output pin
	reset_hdmi_chip();

	// enable i2c device but leave interrupts off for now
	i2c_write_control(0x80);

	/*
	{
		int j;
		for(j=0; j<4; j++)
			configure_hdmi();
	}
	*/
	brute_force_write_seq();
	return 0;
}
