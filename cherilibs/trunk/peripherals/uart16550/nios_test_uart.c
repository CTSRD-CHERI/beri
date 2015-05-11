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
 * C-code for NIOS processor to test the UART
 *****************************************************************************/

#include "system.h"
#include "sys/alt_stdio.h"
#include "io.h"

// UART TX (W) and RX (R) buffers
#define UART_DATA 0
// UART interrupt enable (RW)
#define UART_INT_ENABLE 1
// UART interrupt identification (R)
#define UART_INT_ID 2
// UART FIFO control (W)
#define UART_FIFO_CTRL 2
// UART Line Control Register (RW)
#define UART_LINE_CTRL 3
// UART Modem Control (W)
#define UART_MODEM_CTRL 4
// UART Line Status (R)
#define UART_LINE_STATUS 5
// UART Modem Status (R)
#define UART_MODEM_STATUS 6
// UART base address of peripheral in NIOS memory map
#define UART_SCRATCH 7

//#define UART_BASE OPENCORE_16550_UART_0_BASE
#define UART16550_0_BASE 0x21000
#define UART_BASE UART16550_0_BASE

int fifo_trigger_level = 0;

int
reg_mapper(int reg)
{
  //  return ((reg & 0xc)<<2) | (reg&0x3);
  return reg<<2;
}

void
uart_write_reg(int reg, int val)
{
  IOWR_8DIRECT(UART_BASE,reg_mapper(reg),val);
}

int
uart_read_reg(int reg)
{
  if((reg<0) || (reg>7)) {
    alt_printf("UART_read_reg - reg=%x is out of range\n",reg);
    return -1;
  } else
    return IORD_8DIRECT(UART_BASE,reg_mapper(reg));
}

void
uart_init(int baud)
{
  int d = ALT_CPU_FREQ / (16 * baud);
  alt_printf("Set divisor to 0x%x\n",d);
  uart_write_reg(UART_LINE_CTRL,0x83);  // access divisor registers
  uart_write_reg(1,d>>8);
  uart_write_reg(0,d & 0xff);
  uart_write_reg(UART_LINE_CTRL,0x03);  // 8-bit data, 1-stop bit, no parity
  uart_write_reg(UART_FIFO_CTRL,0x06);  // interrupt every 1 byte, clear FIFOs
  uart_write_reg(UART_INT_ENABLE,0x00);   // disable interrupts
}


int
uart_check_scratch(void)
{
  int j,k,error=0;
  for(j=13; j>=7; j--){
    uart_write_reg(UART_SCRATCH,j);
    k=uart_read_reg(UART_SCRATCH);
    if(k != j) {
      alt_printf("ERROR: unable to set scratch register to %x read back %x\n",j,k);
      error=1;
    }
  }
  return !error;
}


void
uart_tx_char(char c)
{
  int status, tx_empty;

  // send carrage-return (CR) for every line-feed
  if(c == '\n')
    uart_tx_char('\r');

  do {
    status = uart_read_reg(UART_LINE_STATUS);
    tx_empty = ((status>>5) & 0x1) == 1;
  } while(!tx_empty);
  // tx must be empty now so send
  uart_write_reg(UART_DATA, (int) c);
  //  alt_printf("Sent character %c\n",c);
}


void
uart_tx_string(char *s)
{
  for(; *s != 0; s++)
    uart_tx_char(*s);
}


int
uart_rx_ready(void)
{
  int status = uart_read_reg(UART_LINE_STATUS);
  int rx_ready = (status & 0x1) == 1;
  return rx_ready;
}


char
uart_rx_char(void)
{
  while(!uart_rx_ready()) {}
  return (char) uart_read_reg(UART_DATA);
}


int
uart_rx_string_check(char *s)
{
  for(; *s != 0; s++) {
    char c = uart_rx_char();
    if(c != *s) {
      if((c<' ') || (*s<' '))
	alt_printf("uart_rx_string_check: received 0x%x but expected 0x%x\n", c, *s);
      else	
	alt_printf("uart_rx_string_check: received %c but expected %c\n", c, *s);
      return (1 == 0);
    }
  }
  return (0==0);
}


void
uart_fifo_flush(void)
{
  int j;
  uart_write_reg(UART_FIFO_CTRL, 0x07 | fifo_trigger_level);  // FIFO enable and reset TX and RX FIFOs
  uart_write_reg(UART_FIFO_CTRL, 0x01 | fifo_trigger_level);  // FIFO enable
  for(j=1000; (j>0); j--)
    if(uart_rx_ready())
      uart_rx_char();
}


int
uart_interrupt_status(void)
{
  return uart_read_reg(UART_INT_ID);
}


inline int
read_pio_interrupt(void)
{
  return IORD_8DIRECT(PIO_UART_INT_BASE,0) & 0x01;
}


void
echo_test(void)
{
  int pause=0;
  alt_printf("Starting echo test - use RS232 terminal to test this\n");
  uart_tx_string("Type characters for echo test:\n");
  while(1) {
    char rx = uart_rx_char();
    //	alt_printf("Received %c = 0x%x\n", rx, rx);
    pause = ((rx=='\023') || pause) && !(rx=='\021');
    if(((rx>='A') && (rx<='Z')) || ((rx>='a') && (rx<='z')))
      //	  uart_tx_char(rx ^ ' ');	// echo with case swap
      uart_tx_char(rx);	// echo
    else if(rx=='\n')
      uart_tx_char('\n');
    else
      uart_tx_char(rx);
  }
}


// simple tx interrupt test when not in loop-back mode
int
simple_tx_interrupt_test(void)
{
  int j;
  uart_fifo_flush();
  uart_write_reg(UART_INT_ENABLE,0x02);   // enable tx interrupts
  if(read_pio_interrupt()==0) {
    alt_printf("Error: interrupt low when tx buffer is empty - FAIL\n");
    return (1==0);
  }  
  for(j=0; j<80; j++)
    uart_tx_char('0'+((char) (j % 10)));

  for(j=0; (j<1000000) && (read_pio_interrupt()==0); j++) { }

  if(read_pio_interrupt()==0)
    alt_printf("simple tx interrupt test - timeout waiting for interrupt to go high\n");
  else
    alt_printf("simple tx interrupt test - interrupt went high after 0x%x poll loops\n",j);

  uart_write_reg(UART_INT_ENABLE,0x00);   // disable tx interrupts
  uart_tx_char('\n');
  return (1==1);
}


// simple rx interrupt test when in loop-back mode
int
simple_rx_interrupt_test(int trigger_code)
{
  int j;
  int trigger_level;
  switch(trigger_code) {
  case 1:  trigger_level= 4; break;
  case 2:  trigger_level= 8; break;
  case 3:  trigger_level=14; break;
  default: trigger_level= 1; break;
  }
  fifo_trigger_level = trigger_code << 6; // trigger level set
  uart_fifo_flush(); // N.B. also writes trigger level into the config reg
  uart_write_reg(UART_INT_ENABLE,0x01);   // enable rx interrupts
  if(read_pio_interrupt()==1) {
    alt_printf("Error: interrupt high when buffer is empty - FAIL\n");
    return (1==0);
  }  
  for(j=0; j<trigger_level; j++) {
    if(read_pio_interrupt()==1) {
      alt_printf("Error: interrupt high when buffer has not reached trigger level after sending 0x%x characters - FAIL\n",j);
      return (1==0);
    }  
    uart_tx_char('a'+((char) j));
  }
  for(j=1000000; (j>0) && (read_pio_interrupt()==0); j--) {}
  if(read_pio_interrupt()==0) {
    alt_printf("Error: interrupt never went high - FAIL\n");
    return (1==0);
  }
  j = uart_interrupt_status();
  if((j & 0x0f) != 4)
    alt_printf("Interrupt high and but interrupt code = 0x%x but expecting 0xc4\n", j);

  if(!uart_rx_ready()) {
    alt_printf("Error: interrupt gone off but no character is ready - FAIL\n");
    return (1==0);
  }
  for(j=0; j<trigger_level; j++) {
    char c = uart_rx_char();
    char t = 'a' + ((char) j);
    if(c!=t) {
      alt_printf("Error: read back the wrong character during interrupt test (rx=%x, expected=%c) - FAIL\n",c,t);
      return (1==0);
    }
    if(read_pio_interrupt()==1) {
      alt_printf("Error: interrupt high even though RX buffer should be below trigger level - FAIL\n");
      return (1==0);
    }
    j = uart_interrupt_status();
    if((j & 0x0f) != 1)
      alt_printf("Interrupt low and code = 0x%x but expecting 0xc1\n", j);
  }
  alt_printf("Simple interrupt test passed\n");
  return (1==1);
}


void
loop_back_test(void)
{
  int j;
  alt_printf("Starting loop-back test\n");
  uart_write_reg(UART_MODEM_CTRL, 0x13); // set DRT and RTS high, loop-back on
  uart_fifo_flush();

  if(uart_rx_ready()) {
    alt_printf("Failed to empty rx fifo - exiting\n");
    return;
  }
  { // simple loop-back test
    char *ts = "01234567";
    uart_tx_string(ts);
    if(uart_rx_string_check(ts))
      alt_printf("Simple loop-back test passed\n");
    else {
      alt_printf("Simple loop-back test FAILED\n");
      uart_fifo_flush();
    }
  }
  for(j=0; j<4; j++) {
    alt_printf("Simple interrupt test with level code = 0x%x\n",j);
    simple_rx_interrupt_test(j);
  }
  /*  for(j=1; j<128; j++) {
    for(k=0; k<j; k++)
      uart_tx_char("A" + (k%26));
    for(k=0; (k<j); k++) {
      char c = uart_rx_char("A" + (k%26));
  */
  alt_printf("End of loop-back test\n");
}


int main()
{ 

  if(uart_check_scratch()) {
    alt_putstr("Initialise UART\n");
    uart_init(115200);
    uart_write_reg(UART_MODEM_CTRL, 0x0); // set DRT and RTS low
    simple_tx_interrupt_test();
    loop_back_test(); 
    uart_write_reg(UART_MODEM_CTRL, 0x3); // set DRT and RTS high
    echo_test();
  } else
    alt_printf("Errors while testing the scratch register\n");

  alt_printf("The End\n");
  alt_putchar((char) 4);
  /* Event loop never exits. */
  while (1);

  return 0;
}
