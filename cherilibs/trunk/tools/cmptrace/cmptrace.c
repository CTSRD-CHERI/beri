/*-
 * Copyright (c) 2014 Michael Roe
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
 * cmptrace.c - Compare a trace from the L3 model of the MIPS ISA with a
 * Bluesim trace of BERI1.
 *
 * Command line arguments:
 *
 * -a <address>  Address of the UART device driver. Instructions which are
 * in the 1024 bytes after this address will not be compared between traces.
 * This is one way of comparing traces that differ only in the
 * non-determinism introduced by the UART.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <getopt.h>

static unsigned long long putc_start = 0xffffffff804c33c0;

#define BUFF_SIZE 128

struct trace_info {
  unsigned long long trace_pc;
  unsigned long long trace_value;
  unsigned long long trace_addr;
  unsigned long long trace_memvalue;
  int trace_reg;
  int trace_memwrite;
  int trace_capwrite;
  int trace_count;
  int trace_core;
};

static unsigned long long new_pc1;
static int new_count1;
static int new_core1;

void read_l3_trace(FILE *f1, struct trace_info *info)
{
char *cp;
int done1;
int exception_skip;
char buff[BUFF_SIZE];
unsigned long long mask;
int reg;

    done1 = 0;
    info->trace_reg = 0;
    info->trace_value = 0;
    info->trace_addr = 0;
    info->trace_memvalue = 0;
    info->trace_memwrite = 0;
    info->trace_capwrite = 0;
    info->trace_pc = new_pc1;
    info->trace_count = new_count1;
    info->trace_core = new_core1;
    exception_skip = 0;
    do
    {
      fgets(buff, BUFF_SIZE, f1);
      if (strncmp(buff, "instr ", 6) == 0)
      {
        /* This line gives the program counter and opcode of the next
         * instruction, implying that we've now read everything that happened
         * in the previous instruction.
         */
        sscanf(buff + 6, "%d %d %llx", &new_core1, &new_count1, &new_pc1);

        /* If the previous instruction was in the UART device driver,
         * skip over it and carrying on reading the next instruction.
         * Otherwise, we've got a complete instruction and all the associated
         * state changes, so exit the loop.
         */
        if (0 /* (info->trace_pc >= putc_start) && (info->trace_pc < putc_start + 1024) */)
        {
          /* Forget the list of state changes that happened in the previous
           * instruction.
           */
          info->trace_reg = -1;
          info->trace_value = 0;
          info->trace_memvalue = 0;
          info->trace_addr = 0;
          info->trace_memwrite = 0;
          info->trace_capwrite = 0;
          info->trace_count = new_count1;
          info->trace_pc = new_pc1;
        }
        else if (exception_skip)
        {
          exception_skip = 0;
          info->trace_reg = -1;
          info->trace_value = 0;
          info->trace_memvalue = 0;
          info->trace_addr = 0;
          info->trace_memwrite = 0;
          info->trace_capwrite = 0;
          info->trace_count = new_count1;
          info->trace_pc = new_pc1;
        }
        else
        {
          done1 = 1;
        }
      }
#if 0
      else if (strncmp(buff, "======   Registers   ======", 27) == 0)
      {
        done1 = 1;
      }
#endif
      else if (strncmp(buff, "Reg ", 4) == 0)
      {
        /*
         * Need to distinguish 'Reg' lines that are register assignments from
         * 'Reg' lines in the register dump at the end.
         */
        cp = buff + 4;
        while (*cp == ' ')
          cp++;
        reg = strtol(cp, NULL, 0);
        cp = strstr(buff, "<-");
        if (cp)
        {
          info->trace_reg = reg;
          info->trace_value = strtoull(cp + 5, NULL, 16);
        }
      }
      else if (strncmp(buff, "Store", 5) == 0)
      {
        info->trace_memwrite = 1;
        if (strncmp(buff, "Store cap", 9) == 0)
          info->trace_capwrite = 1;
          /* XXX: ought to parse the capability here */
        info->trace_memvalue = strtoull(buff + 8, NULL, 16);
        cp = strstr(buff, "mask");
        if (cp)
        {
          mask = strtoull(cp + 7, NULL, 16);
          cp = strstr(cp, "vAddr");
          if (cp)
          {
            info->trace_addr = strtoull(cp + 8, NULL, 16);
            if (mask)
            {
              info->trace_memvalue &= mask;
              while ((mask & 0xff) == 0)
              {
                mask = mask >> 8;
                info->trace_memvalue = info->trace_memvalue >> 8;
              }
#if 0
             fprintf(stderr, "memvalue = %llx\n", info->trace_memvalue);
             fprintf(stderr, "memaddr = %llx\n", info->trace_addr);
#endif
            }
          }
        }
        else
          info->trace_memvalue = 0;
      }
      else if ((strncmp(buff, "MIPS exception", 14) == 0) ||
          (strncmp(buff, "Cap exception", 13) == 0))
      {
        /* The instruction didn't commit, so forget about it and its
         * state changes, and wait to see if the next instruction will be
         * more interesting.
         */
        info->trace_reg = -1;
        info->trace_value = 0;
        info->trace_memvalue = 0;
        info->trace_addr = 0;
        info->trace_memwrite = 0;
        info->trace_capwrite = 0;
        exception_skip = 1;
      }
    } while ((!feof(f1)) && (done1 == 0));

    /* printf("pc1 = %08lx reg1 = %d value1 = %llx\n", pc1, reg1, value1);  */

}

static int blue_time = 0;

void read_blue_trace(FILE *f2, struct trace_info *info, int multicore)
{
char buff[BUFF_SIZE];
int done2;
char *cp;
char *line;
int new_time2;

    done2 = 0;
    info->trace_reg = -1;
    info->trace_value = 0;
    info->trace_addr = 0;
    info->trace_memwrite = 0;
    info->trace_capwrite = 0;
    info->trace_memvalue = 0;

    do
    {
      fgets(buff, BUFF_SIZE, f2);
      if (multicore)
      {
        if (strncmp(buff, "Time:", 5) == 0)
        {
          new_time2 = strtol(buff+5, NULL, 16);
          if (new_time2 < blue_time)
          {
            printf("Warning: Internal clock went backwards\n");
          }
          blue_time = new_time2;
          cp = strstr(buff, "::");
          if (cp)
          {
            line = cp + 3;
          }
          else
            line = "";
        }
        else
          line = "";
      }
      else
      {
        line = buff;
      }

      if (strncmp(line, "Reg ", 4) == 0)
      {
        cp = line + 4;
        while (*cp == ' ')
          cp++;
        info->trace_reg = strtol(cp, NULL, 0);
        cp = strstr(line, "<-");
        if (cp)
        {
          info->trace_value = strtoull(cp + 3, NULL, 16);
          /* If this is a store conditional instruction, there will also
           * be a write to a memory address on the same line.
	   * BERI1 writes a debug line for store conditional even if
           * the store conditional failed, so check that the result of
           * store conditional was non-zero before concluding that this is
           * a memory write.
           */
          cp = strstr(line, "Address ");
          if (cp && (info->trace_value != 0))
          {
            info->trace_memwrite = 1;
            info->trace_addr = strtoull(cp + 8, NULL, 16);
            cp = strstr(cp + 8, "<-");
            if (cp)
              info->trace_memvalue = strtoull(cp + 3, NULL, 16);
            else
              info->trace_memvalue = 0;
          }
        }
        else
        {
          info->trace_value = 0;
        }
      }
      else if (strncmp(line, "Address ", 8) == 0)
      {
        info->trace_addr = strtoull(line + 8, NULL, 16);
        if (strstr(line, "CapLine") != NULL)
          info->trace_capwrite = 1;
          /* XXX: ought to parse capability here */
        cp = strstr(line, "<-");
        if (cp)
          info->trace_memvalue = strtoull(cp + 3, NULL, 16);
        else
          info->trace_memvalue = 0;
        info->trace_memwrite = 1;
      }
      else if (strncmp(line, "inst ", 5) == 0)
      {
        info->trace_count = strtol(line + 5, NULL, 0);

        cp = index(line, '-');
        if (cp)
        {
         sscanf(cp+1, "%llx", &(info->trace_pc));
         if (0 /* (pc2 >= putc_start) && (pc2 < putc_start + 1024) */)
         {
           /* If this instruction is in the UART device driver, ignore it
            * and its state changes, and wait to see if the next instruction
            * turns out to be more interesting.
            */
           info->trace_reg = -1;
           info->trace_value = 0;
           info->trace_addr = 0;
           info->trace_memvalue = 0;
           info->trace_memwrite = 0;
         }
         else
         {
           done2 = 1;
         }
        }
        else
        {
          /* couldn't parse the line */
          info->trace_count = -1;
          info->trace_pc = 0;
        }
      }
    } while ((!feof(f2)) && (done2 == 0));
}

int in_uart_driver(unsigned long long addr)
{
  if ((addr >= putc_start) && (addr < putc_start + 2000))
  {
    return 1;
  }  
  else
    return 0;
}

int main(int argc, char **argv)
{
char buff[BUFF_SIZE];
struct trace_info l3_info;
struct trace_info blue_info;
FILE *f1;
FILE *f2;
char *cp;
int c;
int multicore;

  multicore = 0;
  while ((c = getopt(argc, argv, "a:m")) != -1)
  {
    switch (c)
    {
      case 'a':
        putc_start = strtoull(optarg, NULL, 16);
        break;
      case 'm':
        multicore = 1;
        break;
    }
  }

  if (argc - optind < 2)
  {
    fprintf(stderr, "Usage: cmptrace [-a <address] <l3 trace file> <Bluespec trace file>\n");
    return -1;
  }

  f1 = fopen(argv[optind], "r");
  if (f1 == NULL)
  {
    fprintf(stderr, "Couldn't open %s\n", argv[optind]);
    return -1;
  }


  f2 = fopen(argv[optind + 1], "r");
  if (f2 == NULL)
  {
    fprintf(stderr, "Couldn't open %s\n", argv[optind + 1]);
    return -1;
  }

   /* hackly way to deal with th efact that the l3 trace puts the instruction
    * info before the stste changes
     */
  new_pc1 = -1;
  read_l3_trace(f1, &l3_info); 

  while (!((feof(f1) || feof(f2))))
  {

    do
    {
      read_l3_trace(f1, &l3_info);
    } while (in_uart_driver(l3_info.trace_pc));
/*
    fprintf(stderr, "pc1 = %llx\n", l3_info.trace_pc);
    fprintf(stderr, "addr1 = %llx\n", l3_info.trace_addr);
    fprintf(stderr, "value1 = %llx\n", l3_info.trace_value);
    fprintf(stderr, "reg1 = %d\n", l3_info.trace_reg);
*/
    do
    {
      read_blue_trace(f2, &blue_info, multicore);
    } while (in_uart_driver(blue_info.trace_pc));

    /* printf("pc2 = %08lx reg2 = %d value2 = %llx\n", pc2, reg2, value2); */

    if (blue_info.trace_count >= 0)
    {
      if (l3_info.trace_pc != blue_info.trace_pc)
      {
        printf("program counters differ: count1 = %d count2 = %d pc1 = %llx pc2 = %llx\n",
          l3_info.trace_count, blue_info.trace_count,
          l3_info.trace_pc, blue_info.trace_pc);
        return -1;
      }
      else
      {
        if (l3_info.trace_value != blue_info.trace_value)
        {
          printf("register values differ: count1 = %d count2 = %d value1 = %llx value2 = %llx\n", l3_info.trace_count, blue_info.trace_count, l3_info.trace_value, blue_info.trace_value);
        }

        if (l3_info.trace_memwrite != blue_info.trace_memwrite)
        {
          printf("memwrite differs: count1 = %d count2 = %d memwrite1 = %d memwrite2 = %d\n",
            l3_info.trace_count, blue_info.trace_count,
            l3_info.trace_memwrite, blue_info.trace_memwrite);

        }

        if (l3_info.trace_capwrite != blue_info.trace_capwrite)
        {
          printf("capwrite differs: count1 = %d count2 = %d\n",
            l3_info.trace_count, blue_info.trace_count);
        }

        if ((l3_info.trace_capwrite == 0) &&
          (l3_info.trace_memvalue != blue_info.trace_memvalue))
        {
          printf("memvalue differs: count1 = %d count2 = %d memvalue1 = %llx memvalue2 = %llx\n",
            l3_info.trace_count, blue_info.trace_count,
            l3_info.trace_memvalue, blue_info.trace_memvalue);
          /* printf("mask = %llx\n", mask); */
        }

#if 0
        /*
         * The L3 trace contains physical addresses and the BERI1 trace
         * contains virtual addresses, so we can't compare them directly.
         */
        if ((l3_info.trace_addr & 0xfff) != (blue_info.trace_addr & 0xfff))
        {
          printf("memory addresses differ: count1 = %d count2 = %d addr1 = %llx addr2 = %llx\n", l3_info.trace_count, blue_info.trace_count, l3_info.trace_addr, blue_info.trace_addr);
        }
#endif
      }
    }
  }

  if ((l3_info.trace_count == 0) || (blue_info.trace_count == 0))
  {
    fprintf(stderr, "No instructions were processed. Empty log file?\n");
    return -1;
  }

  printf("Finished comparing traces\n");
  printf("Count1 = %d Count2 = %d\n", l3_info.trace_count,
    blue_info.trace_count);

  return 0;
}
