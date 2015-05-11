/*-
 * Copyright (c) 2015 Michael Roe
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

#define IO_WR32(x, y) (*(volatile unsigned int *)(x) = y)
#define IO_WR_BYTE(x, y) (*(volatile unsigned char *)(x) = y)

#define MAX_ITER 50

int test(void)
{
unsigned char *text_ptr;
unsigned char *text_base;
unsigned char *lcd_base = (unsigned char *) 0x9000000070000000;
unsigned int *pixel_base = (unsigned int *) 0x9000000070000000;
unsigned int pixel;
int count;
char *cp;
char *hello = "Hello World!";
int i;
int j;
float x;
float y;
float x0;
float y0;
float t;


  IO_WR32(lcd_base + 0x400000, 0x10ff0000);

  text_base = (unsigned char *) (lcd_base + 0x177000);
  for (i=0; i<40*100; i++)
  {
    IO_WR_BYTE(text_base + 2*i, ' ');
    IO_WR_BYTE(text_base + 2*i + 1, 0x0f);
  }

  pixel = 0x00000000;
  for (i=0; i<800*480; i++)
  {
    IO_WR32(pixel_base + i, pixel);
  }

  cp = hello;
  text_ptr = (unsigned char *) (lcd_base + 0x177000);
  while (*cp)
  {
    IO_WR_BYTE(text_ptr, *cp);
    text_ptr++;
    IO_WR_BYTE(text_ptr, 0x0f);
    text_ptr++;
    cp++;
  }

  for (i=0; i<480; i++)
  {
    y0 = ((float) (i - 240))/200.0;
    for (j=0; j<800; j++)
    {
      x0 = ((float) (j - 400))/200.0;
      x = 0.0;
      y = 0.0;
      count = 0;
      while ((x*x + y*y < 4.0) && (count < MAX_ITER))
      {
        t = x*x - y*y + x0;
        y = 2*x*y + y0;
        x = t;
        count++;
      } 

      if (count == MAX_ITER)
      {
        IO_WR32(pixel_base + 800*i + j, 0xffffff00);
      }
    }
  }

  return 0;
}
