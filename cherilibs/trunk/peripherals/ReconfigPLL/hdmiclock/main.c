/*-
 * Copyright (c) 2014 Simon Moore
 * Copyright (c) 2014 Ed Maste
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
 * BERI/CHERI test code which uses the reconfigurable PLL as a pixel clock source
 */

#include <sys/endian.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>


void
write_pixelstream_reg(int reg, int val)
{
  printf("NOT doing write_pixelstream_reg[%1d]=%1d\n",reg,val);
  // TODO: this function needs to write to registers on pixelstream to configure resolution, etc.
  // From NIOS code: IOWR_32DIRECT(PIXELSTREAMHDMI_0_BASE, reg*4, val);
}


void
pll_reconfig_write(
                   int fd,
                   int type,
                   int parameter,
                   int val)
{
  int offset = ((parameter<<4) | type)*4;
  // printf("WR PLL[0x%x] = 0x%x\n", offset, val);
  val = htole32(val);
  if(pwrite(fd, &val, sizeof(val), offset) != sizeof(val))
    perror("write");
}


int
pll_reconfig_read(
                  int fd,
                  int type,
                  int parameter)
{
  int offset = ((parameter<<4) | type)*4;
  int val;
  if (pread(fd, &val, sizeof(val), offset) != sizeof(val))
    perror("read");
  val = le32toh(val);
  // printf("RD PLL[0x%x] = 0x%x\n", offset, val);
  return (val);
}


void
pll_reconfig_update(int fd)
{
  // N.B. data written should not matter but set to none zero value to check
  // difference between memory and the status register
  pll_reconfig_write(fd, (1<<7), 0, 0xff);
}


int
pll_reconfig_status(int fd)
{
  return pll_reconfig_read(fd, (1<<7), 0);
}


void
pll_timing_params(int m, int n, int c0)
{
  int altpll_fd = open("/dev/altpll_reconfig", O_RDWR);
  if (altpll_fd == -1)
    perror("open");

  // m=32  n=4  c0=4   55Hz
  // m=54 n=25  c0=1  60Hz
  int high_count, low_count, t;

  // initial divisor
  high_count = (n+1)/2;
  low_count = n-high_count;
  t=0;
  pll_reconfig_write(altpll_fd, t, 0, high_count);
  pll_reconfig_write(altpll_fd, t, 1, low_count);
  pll_reconfig_write(altpll_fd, t, 4, n==1 ? 1 : 0); // bypass
  pll_reconfig_write(altpll_fd, t, 5, (n&0x1)==1 ? 1 : 0); // odd/even
  printf("Initial divisor        n=%d   high=%d low=%d\n",n,high_count,low_count);

  // initial multiplier
  high_count = (m+1)/2;
  low_count = m-high_count;
  t=1;
  pll_reconfig_write(altpll_fd, t, 0, high_count);
  pll_reconfig_write(altpll_fd, t, 1, low_count);
  pll_reconfig_write(altpll_fd, t, 4, m==1 ? 1 : 0); // bypass
  pll_reconfig_write(altpll_fd, t, 5, (m&0x1)==1 ? 1 : 0); // odd/even
  printf("Initial multiplier     m=%d   high=%d low=%d\n",m,high_count,low_count);

  // clock divisor
  high_count = (c0+1)/2;
  low_count = c0-high_count;
  t=4;
  pll_reconfig_write(altpll_fd, t, 0, high_count);
  pll_reconfig_write(altpll_fd, t, 1, low_count);
  pll_reconfig_write(altpll_fd, t, 4, c0==1 ? 1 : 0); // bypass
  pll_reconfig_write(altpll_fd, t, 5, (c0&0x1)==1 ? 1 : 0); // odd/even
  printf("Clock output divisor  c0=%d   high=%d low=%d\n",c0,high_count,low_count);
  
  // set clock divisor c1 to be the same as c0
  t=5;
  pll_reconfig_write(altpll_fd, t, 0, high_count);
  pll_reconfig_write(altpll_fd, t, 1, low_count);
  pll_reconfig_write(altpll_fd, t, 4, c0==1 ? 1 : 0); // bypass
  pll_reconfig_write(altpll_fd, t, 5, (c0&0x1)==1 ? 1 : 0); // odd/even
  printf("Clock output divisor  c1=%d   high=%d low=%d\n",c0,high_count,low_count);
  
  printf("Triggering PLL reconfigure...\n");
  pll_reconfig_update(altpll_fd);
  
  int status = pll_reconfig_status(altpll_fd);
  int initial_status = status;
  int done_timer = 0;
  for(done_timer=0; (status !=0x0d) && (done_timer<10); done_timer++)
    status = pll_reconfig_status(altpll_fd);

  printf("PLL reconfig initial_status=0x%1x status=0x%1x after %d loops\n",initial_status,status,done_timer);
  close(altpll_fd);
}


void
video_pixel_clock(double pclkf_MHz)
{
  double base_clk_KHz = 50000.0;
  int mul=1;
  int div=1;
  double err=1e6;
  int m,d;
  double e;
  int pclk_KHz = (int) (pclkf_MHz * 1000);
  for(m=1; m<64; m++)
    for(d=1; d<64; d++) {
      e = fabs((base_clk_KHz * m / d) - pclk_KHz);
      if(e<err) {
        mul=m;
        div=d;
        err=e;
      }
    }
  int f = (base_clk_KHz * mul) / div;
  printf("Pixel clock=%2.2fMHz  mul=%1d  div=%1d  freq=%1d  error=%1.2f%%\n", pclkf_MHz, mul, div, f, err*0.1);
  pll_timing_params(mul,div,1);
}


// from modeline parameters e.g. generated by gtf:
// Modeline syntax: pclk hdisp hsyncstart hsyncend htotal vdisp vsyncstart vsyncend vtotal [flags]
void
video_mode_line(
                double pclkf,
                int hdisp, 
                int hsyncstart,
                int hsyncend,
                int htotal,
                int vdisp,
                int vsyncstart,
                int vsyncend,
                int vtotal)
{
  int xres = hdisp;
  int hsync_front_porch = hsyncstart - hdisp;
  int hsync_pulse_width = hsyncend - hsyncstart;
  int hsync_back_porch = htotal - hsyncend;

  int yres = vdisp;
  int vsync_front_porch = vsyncstart - vdisp;
  int vsync_pulse_width = vsyncend - vsyncstart;
  int vsync_back_porch = vtotal - vsyncend;

  // first turn the frame buffer off by setting the resolution to zero
  write_pixelstream_reg(0, 0); // xres
  write_pixelstream_reg(4, 0); // yres

  write_pixelstream_reg(3, hsync_front_porch);
  write_pixelstream_reg(1, hsync_pulse_width);
  write_pixelstream_reg(2, hsync_back_porch);

  write_pixelstream_reg(7, vsync_front_porch);
  write_pixelstream_reg(5, vsync_pulse_width);
  write_pixelstream_reg(6, vsync_back_porch);

  video_pixel_clock(pclkf);

  // enable frame buffer by setting the resolution
  write_pixelstream_reg(0, xres);
  write_pixelstream_reg(4, yres);

  int htotal_check = xres+hsync_front_porch+hsync_pulse_width+hsync_back_porch;
  int vtotal_check = yres+vsync_front_porch+vsync_pulse_width+vsync_back_porch;
  // assertion
  if(htotal_check != htotal)
    puts("ERROR video_mode_line: assertion check fail on htotal vs. video parameters");
  if(vtotal_check != vtotal)
    puts("ERROR video_mode_line: assertion check fail on vtotal vs. video parameters");

  printf("resolution = %d x %d\n", xres, yres);
  printf("hsync_front_porch = %d\n", hsync_front_porch);
  printf("hsync_pulse_width = %d\n", hsync_pulse_width);
  printf("hsync_back_porch  = %d\n", hsync_back_porch);
  printf("vsync_front_porch = %d\n", vsync_front_porch);
  printf("vsync_pulse_width = %d\n", vsync_pulse_width);
  printf("vsync_back_porch  = %d\n", vsync_back_porch);
}


int
main (int argc, char *argv[])
{ 
  if(argc!=2) {
    printf("Usage: %s test_number\n", argv[0]);
    return -1;
  }
  int test_case=atoi(argv[1]);
  printf("Running test case %d\n", test_case);
  switch(test_case) {
  case 0:
    // 800x600 at 60Hz refresh mode line:
    video_mode_line(38.25, 800, 832, 912, 1024, 600, 603, 607, 624);
    break;
  case 1:
    // 800x600 49.92 Hz (CVT 0.48M3) hsync: 31.00 kHz; pclk: 30.75 MHz
    // Modeline "800x600_50.00"   30.75  800 824 896 992  600 603 607 621 -hsync +vsync
    video_mode_line(30.75, 800, 824, 896, 992, 600, 603, 607, 621);
    break;
  case 2:
    // 1280 x 1024 mode line:
    video_mode_line(108.88, 1280, 1360, 1496, 1712, 1024, 1025, 1028, 1060);
    break;
  default:
    printf("Unknown test case %d\n", test_case);
    return -1;
  }
  return 0;
}
