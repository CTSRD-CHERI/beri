/*-
 * Copyright (c) 2011 Simon W. Moore
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
 Test code to drive the LoopbackUART from a NIOS2 processor
 *****************************************************************************/

#include <stdio.h>
#include <io.h>
#include <system.h>
#include "alt_types.h"
#include "sys/alt_irq.h"
#include "sys/alt_timestamp.h"


void simple_loopback_test()
{
  int base=MKLOOPBACKUART_AVALON_0_BASE;
  char c;
  int t,p,rtn,j;
  int rtnbuf[100];
  int pbuf[100];
  IOWR_32DIRECT(base,1*4,0); // disable interrupts
  puts("Performing simple loop-back test without interrupts");
  do {
    rtn = IORD_32DIRECT(base,0);
  } while(rtn!=-1);
  //IOWR_32DIRECT(base,1*4,0);  // reset FIFOs
  for(t=0; t<26; t++)
    IOWR_32DIRECT(base,0,(((26-t)*1000)<<8) | (t+((int) 'a')));
  for(j=0,c='a'; c<='z'; c++) {
    //IOWR_32DIRECT(base,0,(100<<8) | ((int) c));
    for(p=0,rtn=-1; (p<1000000) && (rtn==-1); p++)
      rtn = IORD_32DIRECT(base,0);
    pbuf[j]=p;
    rtnbuf[j]=rtn;
    j++;
  }
  for(j=0; j<26; j++) {
    rtn=rtnbuf[j];
    if(rtn==-1)
      printf("Timed out waiting for %c to be returned\n",((char) j) + 'a');
    else
      printf("Sent %c and received %c after period %1d\n",((char) j) + 'a',(char) rtn,	pbuf[j]);
  }
}


#define ir_handler_bufsize 1000
volatile int ir_handler_buf[ir_handler_bufsize];
volatile int ir_handler_head=0;
volatile int loopback_context; // currently not used

static void handle_loopback_irq (void* base)
{
  alt_irq_context cpu_sr = alt_irq_disable_all();
  // read from buffer (should clear IRQ if no other chars waiting)
  int b=MKLOOPBACKUART_AVALON_0_BASE;
  int c = IORD_32DIRECT(b,0);
  if(ir_handler_head<ir_handler_bufsize)
    ir_handler_buf[ir_handler_head++] = c;
  alt_irq_enable_all(cpu_sr);
}


// initialise interrupt handler
void init_loopback_irq()
{
  int base=MKLOOPBACKUART_AVALON_0_BASE;
  // Recast the edge_capture pointer to match the alt_irq_register() function prototype.
  void* context_ptr = (void*) &loopback_context;

  alt_ic_isr_register(MKLOOPBACKUART_AVALON_0_IRQ_INTERRUPT_CONTROLLER_ID,
		      MKLOOPBACKUART_AVALON_0_IRQ,
		      handle_loopback_irq,
		      context_ptr, 0x0);

  alt_ic_irq_enable(0, MKLOOPBACKUART_AVALON_0_IRQ);
  IOWR_32DIRECT(base,1*4,1); // enable interrupts
}


void test_interrupts()
{
  int base=MKLOOPBACKUART_AVALON_0_BASE;
  int t;
  alt_timestamp_type buftime[100];

  init_loopback_irq();
  puts("Interrupts enabled, now to send some characters");
  for(t=0; t<26; t++)
      IOWR_32DIRECT(base,0,(((26-t)*10000)<<8) | (t+((int) 'a')));

  printf("Read back items:\n");
  if(alt_timestamp_start()<0)
    puts("Error - no timestamp available - exiting interrupt test");
  else {
    for(t=0; t<26; t++) {
      do {} while (t==ir_handler_head);
      buftime[t] = alt_timestamp();
    }
    for(t=0; t<26; t++)
      printf("%2d: time=%7lu  interval=%7lu  expected=%7d  %3d = %c\n",
	     t,
	     buftime[t],
	     buftime[t]-((t==0) ? 0 : buftime[t-1]),
	     (26-t)*10000,
	     ir_handler_buf[t],(char) ir_handler_buf[t]);
  }
}


int main()
{
  puts("The Start");
  simple_loopback_test();
  test_interrupts();
  puts("The End");
  return 0;
}
