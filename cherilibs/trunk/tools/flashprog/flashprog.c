/*-
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

/*****************************************************************************
 * This program reads SREC format memory images and writes them to Intel
 * NOR flash memory.  This has been tested on FreeBSD on the CHERI processor
 * for the Terasic DE4 FPGA board.
 *****************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <err.h>
#include <stdbool.h>
#include <sys/mman.h>
#include <string.h>


/*****************************************************************************
 * read data files
 *****************************************************************************/

static u_int8_t* read_data;
static int read_data_len = -1;
static int read_data_base_addr8b = -1;


inline
int hex2dec(int c)
{
  if(c>='A')
    return c - 'A' + 10;
  else
    return c - '0';
}


inline
int twohex(int c0, int c1)
{
  return hex2dec(c0)<<4 | hex2dec(c1);
}


void
readsrec(char* fn, int savedata)
{
  FILE* fp = fopen(fn,"r");
  char c = 'S';
  int format,len,addr;
  int nextaddr = -1;
  int lenmarker = 1024*1024;
  int j, sum;
  int b[256];
  char line[600];
  int linelen, linepos;

  if(savedata==true)
    printf("Reading from file %s\n",fn);
  else
    printf("Reading from file %s and not saving data\n",fn);

  if(fp==NULL)
    errx(1, "Failed to read %s", fn);

  read_data_base_addr8b = -1;
  read_data_len = 0;

  while(c=='S') {
    if(fgets(line, 600, fp) == NULL) {
      c = ' ';
      linelen = 0;
    } else {
      c = line[0];
      linelen = strlen(line);
    }

    if((c=='S') && (linelen>8)) {
      format = line[1] - ((int) '0');
      len = twohex(line[2], line[3]);

      // N.B. code would support format=1 but not tested so not enabled
      if(!((format==2) || (format==3)))
	errx(1, "SREC format %d not supported", format);

      // collect bytes
      for(j=0, linepos=4; (j<len) && (linepos<(linelen-1)) ; j++) {
	b[j] = twohex(line[linepos], line[linepos+1]);
	linepos += 2;
      }

      if(line[linepos]!='\n')
	errx(1, "End of line missing, e.g. due to wrong length (len=%1d)", len);

      // address according to format (big endian)
      for(j=addr=0; j<=format; j++)
	addr = (addr<<8) | b[j];

      if(read_data_base_addr8b < 0)
	read_data_base_addr8b = addr;

      if((nextaddr>=0) && (addr!=nextaddr))
	errx(1, "none contiguous SREC file");
      nextaddr = addr+((len-1) - (format+1));


      // calculate checksum including sum of checksum
      for(j=0, sum=len; j<len; j++)
	sum += b[j];
      sum = (~sum) & 0xff;
      if(sum!=0)
	errx(1, "SREC checksum fail");

      if(savedata==true)
	for(j=format+1; j<len-1; j++) {
	  read_data[read_data_len] = b[j];
	  read_data_len++;
	}

      if(read_data_len > lenmarker) {
	printf("Read %1d MiB\n", lenmarker>>20);
	lenmarker += 1024*1024;
      }

      /*
      printf("c=%c, format=%1d, len=%2d, addr=0x%08x",c,format,len,addr);
      for(j=format+1; j<len-1; j++)
	printf(" %02x", b[j]);
      putchar('\n');
      */
    }
  }

  fclose(fp);
}



/*****************************************************************************/
static int flashfd;
volatile static u_int16_t *flashmem16;


inline u_int16_t
byteswap(u_int16_t w)
{
  return ((w>>8) & 0xff) | ((w & 0xff)<<8);
}


void
flash_write(u_int64_t offset, u_int16_t d)
{
  flashmem16[offset] = byteswap(d);
}


u_int16_t
flash_read(u_int64_t offset)
{
  return byteswap(flashmem16[offset]);
}


int
flash_read_status(int offset)
{
  flash_write(offset,0x70);
  return flash_read(offset);
}


void
flash_clear_status(int offset)
{
  flash_write(offset,0x50);
}


void
flash_read_mode(int offset)
{
  flash_write(offset,0xff);
}


void unlock_block_for_writes(int offset)
{
  flash_write(offset,0x60); // lock block setup
  flash_write(offset,0xd0); // unlock block
}


void lock_block_to_prevent_writes(int offset)
{
  flash_write(offset,0x60); // lock block setup
  flash_write(offset,0x01); // lock block
}


void
single_write(int offset, int data)
{
  int j;
  int status;

  unlock_block_for_writes(offset);
  flash_write(offset,0x40); // send write command
  flash_write(offset,data);

  status = flash_read_status(offset);
  for(j=0; ((status & 0x80)==0) && (j<0xfff); j++) 
    status = flash_read_status(offset);
  if((status & 0x80)==0)
    warnx("ERROR on write - flash is busy even after 0x%x checks\n",j);

  status = flash_read_status(offset);
  if((status & (1<<3))!=0)
    warnx("Vpp voltage droop error during write, aborted, status=0x%02x\n", status);
  if((status & (3<<4))!=0)
    warnx("Command sequence error during write, aborted, status=0x%02x\n", status);
  if((status & (1<<1))!=0)
    warnx("Block locked during write process, aborted, status=0x%02x\n", status);
  if((status & (1<<5))!=0)
    warnx("write failed at offset 0x%08x, status=0x%02x\n", offset<<1, status);
  lock_block_to_prevent_writes(offset);
  flash_read_mode(offset);
}


void
block_write(int addr16b, int* data) // assumes data is block of length 0x20
{
  int j, f, status;

  unlock_block_for_writes(addr16b);
  flash_write(addr16b,0xe8); // send block write command
  if((flash_read(addr16b) & 0x80)==0)
    warnx("block_write to flash failed - block write not supported by device?");

  flash_write(addr16b,0x1f); // write 0x20 words into buffer
  for(j=0; j<0x20; j++)     // write 32 words of data into buffer
    flash_write(addr16b+j,data[j]);
  flash_write(addr16b,0xd0); // confirm write

  status = flash_read(addr16b);
  for(j=0; ((status & 0x80)==0) && (j<0xfff); j++) 
    status = flash_read(addr16b);
  if((status & 0x80)==0)
    warnx("ERROR on block-write - flash is busy even after 0x%x checks\n",j);

  status = flash_read_status(addr16b);
  if((status & (1<<3))!=0)
    warnx("Vpp voltage droop error during block-write, aborted, status=0x%02x\n", status);
  if((status & (3<<4))!=0)
    warnx("Command sequence error during block-write, aborted, status=0x%02x\n", status);
  if((status & (1<<1))!=0)
    warnx("Block locked during block-write process, aborted, status=0x%02x\n", status);
  if((status & (1<<5))!=0)
    warnx("Block-write failed at offset 0x%08x, status=0x%02x\n", addr16b<<1, status);

  lock_block_to_prevent_writes(addr16b);
  flash_read_mode(addr16b);
  /*
  // read check done at end so it doesn't need to be done here unless we're debugging
  for(j=0; j<0x20; j++) {
    f = flash_read(addr16b+j);
    if(f != data[j])
      warnx("Block-write failed to write[0x%08x] 0x%04x, read back 0x%04x",
	     (addr16b+j)<<1, data[j], f);
  }
  */
}


void erase_block(int addr16b)
{
  int j, status;

  unlock_block_for_writes(addr16b);
  flash_clear_status(addr16b);
  flash_write(addr16b,0x20);
  flash_write(addr16b,0xD0);

  status = flash_read(addr16b);
  for(j=0; ((status & 0x80)==0) && (j<10000000); j++)
    status = flash_read(addr16b);
  if((status & 0x80)==0)
    warnx("Error on erase - flash is busy even after %1d status checks, status=0x%02x\n", j, status);

  status = flash_read_status(addr16b);
  if((status & (1<<3))!=0)
    warnx("Vpp voltage droop error during erease, aborted, status=0x%02x\n", status);
  if((status & (3<<4))!=0)
    warnx("Command sequence error during erase, aborted, status=0x%02x\n", status);
  if((status & (1<<1))!=0)
    warnx("Block locked during erase process, aborted, status=0x%02x\n", status);
  if((status & (1<<5))!=0)
    warnx("Erase failed at addr16b 0x%08x, status=0x%02x\n", addr16b<<1, status);

  lock_block_to_prevent_writes(addr16b);
  flash_clear_status(addr16b);
  flash_read_mode(addr16b);
  flash_read_mode(addr16b);

  j = flash_read(addr16b); 
  if(j!=0xffff)
    warnx("Erase appears to have happened but read back 0x%04x but expecting 0xffff",j);
}


void display_device_info()
{
  int j;
  int r;
  printf("Flash device information:\n");
  flash_write(0, 0x90); // write command
  printf("                  manufacturer code: 0x%04x\n",flash_read(0x00));
  printf("                     device id code: 0x%04x\n",flash_read(0x01));
  printf("                block lock config 0: 0x%04x\n",flash_read(0x02));
  printf("                block lock config 1: 0x%04x\n",flash_read(0x03));
  printf("                block lock config 2: 0x%04x\n",flash_read(0x04));
  printf("             configuration register: 0x%04x\n",flash_read(0x05));
  printf("                    lock register 0: 0x%04x\n",flash_read(0x80));
  printf("                    lock register 1: 0x%04x\n",flash_read(0x89));
  printf("  64-bit factory program protection: 0x%04x 0x%04x 0x%04x 0x%04x\n"
	 ,flash_read(0x84)
	 ,flash_read(0x83)
	 ,flash_read(0x82)
	 ,flash_read(0x81));
  printf("     64-bit user program protection: 0x%04x 0x%04x 0x%04x 0x%04x\n"
	 ,flash_read(0x88)
	 ,flash_read(0x87)
	 ,flash_read(0x86)
	 ,flash_read(0x85));
  printf("    128-bit user program protection: 0x%04x 0x%04x 0x%04x 0x%04x\n"
	 ,flash_read(0x88)
	 ,flash_read(0x87)
	 ,flash_read(0x86)
	 ,flash_read(0x85));
  for(j=0x84; j<=0x109; j+=8) {
    printf("128-bit user program prot. reg[0x%04x]:",(j-0x84)/8);
    for(r=7; r>0; r--)
      printf(" 0x%04x",flash_read((j+r)));
    putchar('\n');
  }
}


int
check_memory(int report)
{
  int offset16b;

  for(offset16b = 0; offset16b < (read_data_len>>1); offset16b++) {
    int w = read_data[offset16b<<1] | (read_data[(offset16b<<1)+1]<<8);
    int addr16b = offset16b + (read_data_base_addr8b>>1);
    int f = flash_read(addr16b);
    if(w != f) {
      if(report)
	printf("memory check fail: addr=0x%08x  from file: 0x%04x  from flash: 0x%04x\n",
	       addr16b<<1, w, f);
      return false;
    }
  }
  return true;
}


// erase blocks that need to be erased
void
erase_sweep(void)
{
  int offset16b;
  int markpoint = 1024*1024 - 1;
  int mb = 0;

  printf("Beginning erase sweep\n");
  for(offset16b = 0; offset16b<(read_data_len>>1); offset16b++) {
    int w = read_data[offset16b<<1] | (read_data[(offset16b<<1)+1]<<8);
    int addr16b = offset16b+(read_data_base_addr8b>>1);
    int f = flash_read(addr16b);
    if((w & f) != w) {
      erase_block(addr16b);
      if(flash_read(addr16b) != 0xffff)
	warnx( "Flash erase doesn't appear to have erased a block");
    }
    if(offset16b>=markpoint) {
      mb++;
      markpoint += 1024*1024/2;
      printf("Erase sweep passed %d MiB\n",mb);
    }
  }
}


void
write_sweep(void)
{
  int offset16b;
  int markpoint = (1024*1024/2)-1;
  int mb = 0;

  printf("Beginning write sweep\n");
  for(offset16b = 0; offset16b<(read_data_len>>1); ) {
    int addr16b = offset16b + (read_data_base_addr8b>>1);
    if(((addr16b & 0x1f) == 0) && ((offset16b+0x1f)<(read_data_len>>1))) {
      // write a block
      int w[32];
      int j, correct;
      for(j=0, correct=true; (j<0x20); j++) {
	int k = (offset16b+j);
	w[j] = read_data[k<<1] | (read_data[(k<<1)+1]<<8);
	correct &= w[j] == flash_read(addr16b+j);
      }
      if(!correct)
	block_write(addr16b,w);
      offset16b += 0x20;
    } else {
      // do single writes
      int w = read_data[offset16b<<1] | (read_data[(offset16b<<1)+1]<<8);
      int f = flash_read(addr16b);
      if(w != f)
	single_write(addr16b, w);
      offset16b++;
    }
    if(offset16b>=markpoint) {
      mb++;
      markpoint += 1024*1024/2;
      printf("Write sweep passed %d MiB\n",mb);
    }
  }
}


int
main(int argc, char *argv[])
{
  if(argc!=2)
    errx(0,"Usage: %s file.srec",argv[0]);

  flashfd = open("/dev/de4flash", O_RDWR | O_NONBLOCK);
  if(flashfd < 0)
    err(1, "open flash");

  flashmem16 = mmap(NULL, 64*1024*1024, PROT_READ | PROT_WRITE, MAP_SHARED, flashfd, 0);
  if (flashmem16 == MAP_FAILED)
    err(1, "mmap flash");

  display_device_info();

  flash_read_mode(0);
  printf("flash status = 0x%02x\n", flash_read_status(0x20000));
  flash_clear_status(0x20000);
  printf("flash status after clear = 0x%02x\n", flash_read_status(0x20000));
  flash_read_mode(0);

  // could parse the file first to see what buffer size is needed but this is too slow
  //  readsrec(argv[1], false);
  // hack - allocate more than enough memory to hold the data to be read
  read_data = (u_int8_t*) malloc(64*1024*1024 * sizeof(u_int8_t));
  readsrec(argv[1], true);
  if(read_data_len<1)
    err(1, "readsrec - read no SREC data");

  printf("srec file start address=0x%08x  length=0x%08x\n",
	 read_data_base_addr8b, read_data_len);

  if(check_memory(false) == true)
    printf("Memory already holds the right data - exiting...\n");
  else {
    erase_sweep();
    write_sweep();
    if(check_memory(true) == true)
      printf("Flash writes complete\n");
    else
      errx(1,"FAILED TO WRITE DATA CORRECTLY\n");
  }

  return 0;
}
