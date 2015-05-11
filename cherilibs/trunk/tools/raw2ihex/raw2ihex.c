/*-
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

/*
 * Convert from raw bytes into Intel hex format
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>

#define BUFF_SIZE 1024

#define IHEX_DATA_RECORD 0

static record_bytes = 4;

char out_buff[BUFF_SIZE];

void write_record(char *data, int bytes, int addr)
{
char *in_ptr;
char *out_ptr;
int i;
int checksum;
int out_len;

  out_ptr = out_buff;
  *out_ptr = ':';
  out_ptr++;
  checksum = 0;

  sprintf(out_ptr, "%02x", bytes);
  out_ptr += 2;
  checksum += bytes;

  sprintf(out_ptr, "%04x", addr & 0xffff);
  out_ptr += 4;
  checksum += (addr & 0xff) + ((addr >> 8) & 0xff);

  sprintf(out_ptr, "%02x", IHEX_DATA_RECORD);
  out_ptr += 2;
  checksum += IHEX_DATA_RECORD;

  in_ptr = data + bytes - 1;
  for (i=0; i<bytes; i++)
  {
    sprintf(out_ptr, "%02x", (unsigned char) *in_ptr);
    out_ptr += 2;
    checksum += (unsigned char) *in_ptr;
    in_ptr--;
  }
  checksum = (checksum & 0xff) ^ 0xff;
  checksum = (checksum +1 ) & 0xff;
  sprintf(out_ptr, "%02x", checksum);
  out_ptr += 2;

  *out_ptr = '\0';

  out_len = strlen(out_buff);
  for (i=0; i<out_len; i++)
    out_buff[i] = toupper(out_buff[i]);

  printf("%s\n", out_buff);
}

void print_usage(char *progname)
{
  fprintf(stderr, "Usage: %s [-w <bit width>] <filename>\n", progname);
}

int main(int argc, char **argv)
{
int opt;
FILE *f1;
int len;
char buff[BUFF_SIZE];
char *cp;
int addr;
int i;

  while ((opt = getopt(argc, argv, "w:")) != -1)
  {
    switch (opt)
    {
      case 'w':
        break;
      default:
        break;
    }
  }

  if (optind >= argc)
  {
    print_usage(argv[0]);
    return -1;
  }

  f1 = fopen(argv[optind], "r");
  if (f1 == NULL)
  {
    fprintf(stderr, "Couldn't open %s\n", argv[optind]);
    return -1;
  }

  addr = 0;
  while ((len = fread(buff, 1, BUFF_SIZE, f1)) > 0)
  {
    cp = buff;
    while (len >= record_bytes)
    {
      write_record(cp, record_bytes, addr);
      len -= record_bytes;
      cp += record_bytes;
      addr++;
    }
    if (len > 0)
    {
      write_record(cp, len, 0);
    }
  }

  printf(":00000001FF\n");
  return (0);
}
