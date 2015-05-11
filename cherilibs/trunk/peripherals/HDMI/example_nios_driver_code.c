/*-
 * Copyright (c) 2013 Simon W. Moore
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

/*****************************************************************************
 * Example for NIOS that controls the HDMI chip
 * =====================================================================
 * Simon Moore, Feb 2013
 *
 * N.B. build with "small world" libraries
 *****************************************************************************/


#include "sys/alt_stdio.h"
#include "system.h"
#include "io.h"

// short name base addresses from system.h
#define PLLRECON_BASE    VIDEO_PLL_RECONFIG_AVALONMM_0_BASE
#define I2C_BASE         I2C_AVALON_0_BASE
#define HDMI_TIMING_BASE MKHDMI_DRIVER_0_BASE


/******************************************************************************
 I2C functions to configure the HDMI chip
 ******************************************************************************/

// I2C device number of IT6613 HDMI chip
// note: the device number is the upper 7-bits and bit 0 is left to indicate
//       read or write
#define HDMI_I2C_DEV  0x98

// clock scale factor to get target 100kHz:  scale = system_clock_kHz/(4*100)
#define I2C_CLK_SCALE 25


void
reset_hdmi_chip(void)
{
  IOWR_32DIRECT(HDMI_TX_RESET_N_BASE, 0, 0);
  alt_printf("Reset HDMI chip\n");  // debug output and delay all in one...
  IOWR_32DIRECT(HDMI_TX_RESET_N_BASE, 0, 1);
}


void
i2c_write_reg(int regnum, int data)
{
  IOWR_8DIRECT(I2C_BASE, regnum, data);
}


int
i2c_read_reg(int regnum)
{
  return IORD_8DIRECT(I2C_BASE, regnum);
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
  // alt_printf("i2c write data=%x, command=%x\n",data,command);
  i2c_write_tx_data(data); // device num + write (=0) bit
  i2c_write_command(command);
  sr = i2c_read_status();
  if((sr & 0x02)==0)
    alt_printf("ERROR - I2C should be busy but isn't - sr=%x\n",sr);

  for(t=200*I2C_CLK_SCALE; (t>0) && ((sr & 0x02)!=0); t--)
    sr = i2c_read_status();

  if(t==0)
    alt_putstr("WRITE TIME OUT\n");
  if((sr & 0x02)!=0)
    alt_putstr("ERROR - transfer is not complete\n");
  if((sr&0x80)!=0)
    alt_putstr("ERROR - no ack received\n");
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
  if(t==0)
    alt_printf("READ TIME OUT  -  sr=%x\n",sr);
  if((sr & 0x02)!=0)
    alt_putstr("ERROR - transfer is not complete\n");
  if((sr&0x80)==0)
    alt_putstr("ERROR - no nack received\n");
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
}


void
video_output_timing(void)
{
  int j;
  for(j=0; j<8; j++)
	  alt_printf("video timing parameter %x = 0x%x\n",
			  j,
		     IORD_32DIRECT(HDMI_TIMING_BASE,j*4));
//            IORD_32DIRECT(MKAVALONSTREAM2HDMI36BITRECONFIG_0_BASE,j*4));
		     //			  IORD_32DIRECT(MKAVALONSTREAM2HDMI36BITRECONFIG_0_BASE,j*4));
}


void
brute_force_write_seq(int vic)
{
  int passed = 1;
  // set clock scale factor = system_clock_freq_in_Khz / 400
  {
    int j;
    alt_printf("Setting clock_scale to 0x%x\n",I2C_CLK_SCALE);
    i2c_write_clock_scale(I2C_CLK_SCALE);
    j = i2c_read_clock_scale();
    alt_printf("clock scale = 0x%x",j);
    if(j==I2C_CLK_SCALE)
      alt_printf(" - passed\n");
    else
      alt_printf(" - FAILED\n");

    hdmi_write_reg(0x0f, 0); // switch to using lower register bank (needed after a reset?)

    j = hdmi_read_reg(1);
    if(j==0xca)
      alt_printf("Correct vendor ID\n");
    else {
      alt_printf("FAILED - Vendor ID=0x%x but should be 0xca\n",j);
      passed = 0;
    }
    j = hdmi_read_reg(2) | ((hdmi_read_reg(3) & 0xf)<<8);
    if(j==0x613)
      alt_printf("Correct device ID\n");
    else {
      alt_printf("FAILED - Device ID=0x%x but should be 0x613\n",j);
      passed = 0;
    }
  }
if(passed==0)
	alt_printf("Failed checks so not writing configuration sequence\n");
else
{
  hdmi_write_reg(0x05, 0x0); // interrupt active low, push-pull mode, TXCLK active
  hdmi_write_reg(0x04, 0x3d);//	reg04=0x1d | 0x20 = reset
  hdmi_write_reg(0x04, 0x1d);// reg04=0x1d = wait for function enable
  hdmi_write_reg(0x61, 0x30);// reg61=0x30 ?  manual says to set to 0x10 to enable clock ring
  hdmi_write_reg(0x09, 0xb2);// audio interrupt mask
  hdmi_write_reg(0x0a, 0xf8);// more interrupt masks
  hdmi_write_reg(0x0b, 0x37);// more interrupt masks
                             // strange that 0x0e isn't set - set later

  hdmi_write_reg(0x0f, 0x00);// ----------- LOWER BANK SWITCH
  hdmi_write_reg(0xc9, 0x00);// pg 43 - disable null packets (default)
  hdmi_write_reg(0xca, 0x00);// disable ACP packet ?
  hdmi_write_reg(0xcb, 0x00);// ??????
  hdmi_write_reg(0xcc, 0x00);// ??????
  hdmi_write_reg(0xcd, 0x00);// disable AVI Infoframe packets (default)
  hdmi_write_reg(0xce, 0x00);// disable audio infoframe packets (default)
  hdmi_write_reg(0xcf, 0x00);// ??????
  hdmi_write_reg(0xd0, 0x00);// disable MPEG infofram packets (default)
  hdmi_write_reg(0xe1, 0x00);// standard I2S audio, not full packet mode

  hdmi_write_reg(0x0f, 0x00);// ----------- LOWER BANK SWITCH
  hdmi_write_reg(0xf8, 0xc3);// see pg 24 - start of seq...
  hdmi_write_reg(0xf8, 0xa5);// ...to enable password reg and write protection disabled
  // strange - manual suggests that regC5 then written to
  hdmi_write_reg(0x22, 0x60);// see pg 34 - part of HDCP authentication?
  hdmi_write_reg(0x1a, 0xe0);// no idea!
  hdmi_write_reg(0x22, 0x48);// ????
  hdmi_write_reg(0xf8, 0xff);// enable the write protection of regC5

  hdmi_write_reg(0x04, 0x1d);// wait for function enable? (pg 2)
  hdmi_write_reg(0x61, 0x30);// enable clock ring
  hdmi_write_reg(0x0c, 0xff);// clear interrupts
  hdmi_write_reg(0x0d, 0xff);// clear interrupts
  hdmi_write_reg(0x0e, 0xcf);// system status - disable interrupts and clear?...
  hdmi_write_reg(0x0e, 0xce);// ...then disable clear action
  hdmi_write_reg(0x10, 0x01);// pg 6 - Reg_MasterSel = PC (rather than HDCP as default)
  hdmi_write_reg(0x15, 0x09);// DCC FIFO clear

  hdmi_write_reg(0x0f, 0x00);// ---------- LOWER BANK SWITCH

  hdmi_write_reg(0x10, 0x01);// pg 6 - Reg_MasterSel = PC (rather than HDCP as default)
  hdmi_write_reg(0x15, 0x09);// DCC FIFO clear
  hdmi_write_reg(0x10, 0x01);// pg 6 - Reg_MasterSel = PC (rather than HDCP as default)
  hdmi_write_reg(0x11, 0xa0);// pg 6 - PC DDC request slave address: 0xA0 = access Rx EDIO
  hdmi_write_reg(0x12, 0x00);// register address=0
  hdmi_write_reg(0x13, 0x20);// regsiter R/W byte number
  hdmi_write_reg(0x14, 0x00);// EDIO segment=0
  hdmi_write_reg(0x15, 0x03);// RDDC_Req=EDIO read

  hdmi_write_reg(0x10, 0x01);// repeat of the above with different register address
  hdmi_write_reg(0x15, 0x09);
  hdmi_write_reg(0x10, 0x01);
  hdmi_write_reg(0x11, 0xa0);
  hdmi_write_reg(0x12, 0x20);// but regsister address=20
  hdmi_write_reg(0x13, 0x20);
  hdmi_write_reg(0x14, 0x00);
  hdmi_write_reg(0x15, 0x03);

  hdmi_write_reg(0x10, 0x01);// repeat
  hdmi_write_reg(0x15, 0x09);
  hdmi_write_reg(0x10, 0x01);
  hdmi_write_reg(0x11, 0xa0);
  hdmi_write_reg(0x12, 0x40);// but register address=40
  hdmi_write_reg(0x13, 0x20);
  hdmi_write_reg(0x14, 0x00);
  hdmi_write_reg(0x15, 0x03);

  hdmi_write_reg(0x10, 0x01);// repeat
  hdmi_write_reg(0x15, 0x09);
  hdmi_write_reg(0x10, 0x01);
  hdmi_write_reg(0x11, 0xa0);
  hdmi_write_reg(0x12, 0x60);// but register address=60
  hdmi_write_reg(0x13, 0x20);
  hdmi_write_reg(0x14, 0x00);
  hdmi_write_reg(0x15, 0x03);

  { // set video resolution via the VIC
    hdmi_write_reg(0x04, 0x1d);// function enable?
    hdmi_write_reg(0x61, 0x30);// change AVI info frame
    hdmi_write_reg(0x0f, 0x00);// ---------- LOWER BANK SWITCH
    hdmi_write_reg(0xc1, 0x41);// colour depth = bits[6:4]=100 (binary) = 8/8/8 bit colour bit[0]=1 means AVI mute
  
    hdmi_write_reg(0x0f, 0x01);// ---------- UPPER BANK SWITCH
    hdmi_write_reg(0x58, 0x10);// reg158='00' = RGB444, setup AVI infoA frame (bit 4=1)
    int reg158 = 0x10;// reg158='00' = RGB444, setup AVI infoA frame (bit 4=1)
    int reg159 = 0x68;// ACI info frame setup 
    int reg15a = 0x00;
    int reg15b = vic;// VIC=3 - see page 15
    int reg15c = 0x00;
    int reg15e = 0x00;
    int reg15f = 0x00;
    int reg160 = 0x00;
    int reg161 = 0x00;
    int reg162 = 0x00;
    int reg163 = 0x00;
    int reg164 = 0x00;
    int reg165 = 0x00;
    // checksum calculation - see page 42
    int checksum = 0-(reg158+reg159+reg15a+reg15b+reg15c+
		      reg15e+reg15f+reg160+reg161+reg162+reg163+reg164+reg165+
		      0x82 + 2 + 0x0d);
    checksum &= 0xff;
    hdmi_write_reg(0x58, reg158);
    hdmi_write_reg(0x59, reg159);
    hdmi_write_reg(0x5a, reg15a);
    hdmi_write_reg(0x5b, reg15b);
    hdmi_write_reg(0x5c, reg15c);
    // skip - checksum at the end
    hdmi_write_reg(0x5e, reg15e);
    hdmi_write_reg(0x5f, reg15f);
    hdmi_write_reg(0x60, reg160);
    hdmi_write_reg(0x61, reg161);
    hdmi_write_reg(0x62, reg162);
    hdmi_write_reg(0x63, reg163);
    hdmi_write_reg(0x64, reg164);
    hdmi_write_reg(0x65, reg165);
    hdmi_write_reg(0x5d, checksum);
    alt_printf("checksum = %x\n",checksum);
  }

  hdmi_write_reg(0x0f, 0x00);// ---------- LOWER BANK SWITCH
  hdmi_write_reg(0xcd, 0x03);// enable AVI infoframe packet for each field (pg 41)

  hdmi_write_reg(0x0f, 0x00);// ---------- LOWER BANK SWITCH
  hdmi_write_reg(0x0f, 0x01);// ---------- UPPER BANK SWITCH (read occured inbetween?)

  hdmi_write_reg(0x0f, 0x00);// ---------- LOWER BANK SWITCH
  hdmi_write_reg(0x04, 0x1d);// function enable?
  hdmi_write_reg(0x70, 0x00);// input data format = RGB, sync seperate
  hdmi_write_reg(0x72, 0x00);// no colour space conversion or dithering (pg 12)
  hdmi_write_reg(0xc0, 0x00);// default DVI mode?
  hdmi_write_reg(0x04, 0x15);// reg04 from 1b to 15 - bit[3]=0 which reg62-reg67 set (pg 19)
  hdmi_write_reg(0x61, 0x10);// reset AFE (what ever that is!)
  hdmi_write_reg(0x62, 0x18);// TMDS Clock < 80MHz (pg 19)
  hdmi_write_reg(0x63, 0x10);// TMDS Clock < 80MHz
  hdmi_write_reg(0x64, 0x0c);// TMDS Clock < 80MHz
  hdmi_write_reg(0x04, 0x15);// reg04 from 1b to 15 - bit[3]=0 which reg62-reg67 set (pg 19)
  hdmi_write_reg(0x04, 0x15);// reg04 from 1b to 15 - bit[3]=0 which reg62-reg67 set (pg 19)
  hdmi_write_reg(0x0c, 0x00);// clear interrupts...
  hdmi_write_reg(0x0d, 0x40);// ...cont
  hdmi_write_reg(0x0e, 0x01);// make interrupt clear active
  hdmi_write_reg(0x0e, 0x00);// remove interrupt clear active

  hdmi_write_reg(0x0f, 0x00);// ---------- LOWER BANK SWITCH
  hdmi_write_reg(0x61, 0x00);// release reset on AFE?
  hdmi_write_reg(0x0f, 0x00);// ---------- LOWER BANK SWITCH
  hdmi_write_reg(0xc1, 0x40);// unmute HDMI and leave 8/8/8 bit colour mode
  hdmi_write_reg(0xc6, 0x03);// enable general control packet and send for every field
}
}


/******************************************************************************
 Reconfigurable PLL helper functions
 ******************************************************************************/

void
pll_reconfig_write
	(int type,
	 int parameter,
	 int val)
{
	IOWR_32DIRECT(PLLRECON_BASE, ((parameter<<4) | type)*4, val);
}

int
pll_reconfig_read
	(int type,
	 int parameter)
{
	return IORD_32DIRECT(PLLRECON_BASE, ((parameter<<4) | type)*4);
}



void
pll_reconfig_update(void)
{
	IOWR_32DIRECT(PLLRECON_BASE, (1<<7)*4, 0);
}


int
pll_reconfig_done(void)
{
	return IORD_32DIRECT(PLLRECON_BASE, (1<<7)*4);
}

void
pll_timing_params(int m, int n, int c0)
{
  int high_count, low_count, t;

  // initial divisor
  high_count = (n+1)/2;
  low_count = n-high_count;
  t=0;
  pll_reconfig_write(t, 0, high_count);
  pll_reconfig_write(t, 1, low_count);
  pll_reconfig_write(t, 4, n==1 ? 1 : 0); // bypass
  pll_reconfig_write(t, 5, (n&0x1)==1 ? 1 : 0); // odd/even
  alt_printf("Initial divisor        n=%x   high=%x low=%x\n",n,high_count,low_count);

  // initial multiplier
  high_count = (m+1)/2;
  low_count = m-high_count;
  t=1;
  pll_reconfig_write(t, 0, high_count);
  pll_reconfig_write(t, 1, low_count);
  pll_reconfig_write(t, 4, m==1 ? 1 : 0); // bypass
  pll_reconfig_write(t, 5, (m&0x1)==1 ? 1 : 0); // odd/even
  alt_printf("Initial multiplier     m=%x   high=%x low=%x\n",m,high_count,low_count);

  // clock divisor
  high_count = (c0+1)/2;
  low_count = c0-high_count;
  t=4;
  pll_reconfig_write(t, 0, high_count);
  pll_reconfig_write(t, 1, low_count);
  pll_reconfig_write(t, 4, c0==1 ? 1 : 0); // bypass
  pll_reconfig_write(t, 5, (c0&0x1)==1 ? 1 : 0); // odd/even
  alt_printf("Clock output divisor  c0=%x   high=%x low=%x\n",c0,high_count,low_count);

  alt_printf("Triggering PLL reconfigure...\n");
  pll_reconfig_update();
  int done=pll_reconfig_done();
  alt_printf("PLL reconfig done=%x\n",done);
  done=pll_reconfig_done();
  alt_printf("PLL reconfig done=%x\n",done);
  done=pll_reconfig_done();
  alt_printf("PLL reconfig done=%x\n",done);
}


void
video_mode_640_480_60Hz(void)
{
  // this works for 640 x 480
  IOWR_32DIRECT(HDMI_TIMING_BASE, 0*4, 640); // xres
  IOWR_32DIRECT(HDMI_TIMING_BASE, 1*4, 62); // hsync_pulse_width
  IOWR_32DIRECT(HDMI_TIMING_BASE, 2*4, 60); // hsync_back_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 3*4, 16); // hsync_front_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 4*4, 480); // yres
  IOWR_32DIRECT(HDMI_TIMING_BASE, 5*4, 6); // vsync_pulse_width
  IOWR_32DIRECT(HDMI_TIMING_BASE, 6*4, 30); // vsync_back_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 7*4, 9); // vsync_front_porch

  pll_timing_params(1, 2, 1);
}



void
video_mode_1280_1024_60Hz(void)
{
  IOWR_32DIRECT(HDMI_TIMING_BASE, 0*4, 1280); // xres
  IOWR_32DIRECT(HDMI_TIMING_BASE, 1*4, 112); // hsync_pulse_width
  IOWR_32DIRECT(HDMI_TIMING_BASE, 2*4, 248); // hsync_back_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 3*4, 48); // hsync_front_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 4*4, 1024); // yres
  IOWR_32DIRECT(HDMI_TIMING_BASE, 5*4, 3); // vsync_pulse_width
  IOWR_32DIRECT(HDMI_TIMING_BASE, 6*4, 38); // vsync_back_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 7*4, 1); // vsync_front_porch
  // works at 108MHz
  pll_timing_params(54, 25, 1);
}



void
video_mode_1600_1200_60Hz(void)
{
  IOWR_32DIRECT(HDMI_TIMING_BASE, 0*4, 1600); // xres
  IOWR_32DIRECT(HDMI_TIMING_BASE, 1*4, 112); // hsync_pulse_width
  IOWR_32DIRECT(HDMI_TIMING_BASE, 2*4, 248); // hsync_back_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 3*4, 48); // hsync_front_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 4*4, 1200); // yres
  IOWR_32DIRECT(HDMI_TIMING_BASE, 5*4, 3); // vsync_pulse_width
  IOWR_32DIRECT(HDMI_TIMING_BASE, 6*4, 38); // vsync_back_porch
  IOWR_32DIRECT(HDMI_TIMING_BASE, 7*4, 1); // vsync_front_porch
  pll_timing_params(12, 2, 2);
}



int
main()
{ 
  alt_putstr("Test I2C on HDMI chip\n");
  // reset HDMI chip via PIO output pin
  reset_hdmi_chip();

  // enable i2c device but leave interrupts off for now
  i2c_write_control(0x80);

  video_output_timing();

  brute_force_write_seq(3);

  int t, p, v;
  for(t=0; t<8; t++)
	  for(p=0; p<8; p++) {
		  v = pll_reconfig_read(t,p);
		  v = pll_reconfig_read(t,p);
		  alt_printf("type=%x  parameter=%x  val=%x\n",
				  t, p, v);
	  }

  video_mode_640_480_60Hz();

  char c;
  while(1) {
	  alt_printf("\n\nmenu:\n");
	  alt_printf("1 -  640 x  480\n");
	  alt_printf("2 - 1280 x 1024\n");
	  alt_printf("3 - 1600 x 1200\n");
	  do {
		  c = alt_getchar();
	  } while((c<'1') || (c>'3'));
	  switch(c) {
	  case '1' : video_mode_640_480_60Hz(); break;
	  case '2' : video_mode_1280_1024_60Hz(); break;
	  case '3' : video_mode_1600_1200_60Hz(); break;
	  default  : break;
	  }
  }

  return 0;
}
