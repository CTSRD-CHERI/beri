/*
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
 *
 *****************************************************************************
 * Description
 * ===========
 * 
 * This package provides a simple unit test between Bluespec and C-code
 * peripherals provided by the PISM suite.  This package is intended for
 * simulation only (not for synthesis).
 * 
 * This is a user interactive test since it requires the user to view
 * the X-window graphical output and to provide keyboard input.
 * 
 * Had to install various libsdl libraries which the frame buffer uses.
 *****************************************************************************/


package PISM_unit_test;

// CHERI parameters - base addresses for peripherals;
`include "parameters.bsv"

// use to turn on debug trace
// `define DEBUG 1

// this following frame buffer base address seems to be missing from
//  parameters.bsv but was copied from cheri.h in deimos
`define CHERI_FB_BASE           64'h04000000


// standard finite statemachine package:
import StmtFSM::*;

// import PISM C functions
import "BDPI" function ActionValue#(Bit#(32))  c_getchar();
import "BDPI" function Bool                    pism_init(PismBus bus);
import "BDPI" function Bit#(32)                pism_interrupt_get(PismBus bus);
import "BDPI" function Bool                    pism_request_ready(PismBus bus, PismData req);
import "BDPI" function Action                  pism_request_put(PismBus bus, PismData req);
import "BDPI" function Bool                    pism_response_ready(PismBus bus);
import "BDPI" function ActionValue#(Bit#(512)) pism_response_get(PismBus bus);
import "BDPI" function Bool                    pism_addr_valid(PismBus bus, PismData req);

// type copied from Avalon2ClientServer256be.bsv
// TODO: this should really be abstracted, e.g. into a PISM_types.bsv module
typedef enum {
	 PISM_BUS_CHERI_0,
	 PISM_BUS_TRACE
   } PismBus deriving(Bits, Eq);

typedef struct {
   Bit#(64)	addr;		// 8 bytes
   Bit#(256)	data;		// 32 bytes
   Bit#(32)	writemask;	// 4 bytes
   Bit#(8)      write;          // 1 byte, 1==write, 0==read
   Bit#(152)	pad1;		// 19 bytes
   } PismData deriving (Bits, Eq, Bounded);
	
PismData pdef = PismData {
   addr: 64'h0,
   data: 256'h0,
   writemask: 32'hffffffff,
   write: 8'h0,
   pad1: 152'h0
   };

typedef enum {
   UART_0, UART_1,
   DBG_UART_0, DBG_UART_1,
   COUNT,
   LOOPBACK,
   NET,
   C_BUS,
   None
   } Perif deriving (Bits, Eq);

// TODO: this function was also derived from Avalon2ClientServer256be.bsv and should
// probably be provided in a library

// map periphical physical addresses (from parameters.bsv) to enumerated peripherals
function Perif address2Perif(Int#(32) addr);
  Perif p;
  case (addr)
		`AVN_JTAG_UART_BASE: p = UART_0;
		(`AVN_JTAG_UART_BASE + 1): p = UART_1;
		`DEBUG_JTAG_UART_BASE: p = DBG_UART_0;
		(`DEBUG_JTAG_UART_BASE + 1): p = DBG_UART_1;
		`LOOPBACK_UART_BASE, (`LOOPBACK_UART_BASE + 1): p = LOOPBACK;
		`CHERI_COUNT: p = COUNT;
		`ifdef CHERI_NET
		`CHERI_NET_TX, `CHERI_NET_RX: p = NET;
		`endif
		default: p = None;
  endcase
  return p;
endfunction		    
								
		 
module mkPISM_unit_test(Empty);
   
  Reg#(Bool) periphSetup <- mkReg(False); // flag indicating if peripherals have been initialised
  Reg#(Bit#(32)) last_interrupt <- mkReg(0);
  Reg#(Bit#(64)) x <- mkReg(0);
  Reg#(Bit#(64)) y <- mkReg(0);
  Reg#(Bit#(16)) col <- mkReg(0);
  
  // poll interrupts since this is used to time PISM screen refreshes (!)
  rule poll_interrupts;
    last_interrupt <= pism_interrupt_get(PISM_BUS_CHERI_0);
  endrule
  
  // create a finite statemachine (i.e. sequential code) to provide
  // a test sequence
  Stmt tester_fsm =
  (seq
     // initilise PISM
     periphSetup <= pism_init(PISM_BUS_CHERI_0);
     if(!periphSetup)
       seq
	 $display("%05t: FAILED: to initialise peripherals, exiting",$time);
	 $finish;
       endseq
     // loop around colours and coordinates drawing test images to the framestore
     for(col<=16'hffff; col>0; col<=col - 16'd1)
       for(y<=0; y<600; y<=y+1)
	 for(x<=0; x<800; x<=x+1)
	   action
	     `ifdef DEBUG
	       $display("%05t: writing pixel (%3d,%3d)=0x%04x",$time,x,y,col);
	     `endif
	     // calculate bounding box for a circle
	     UInt#(64) x0 = unpack(pack(x))-400;
	     UInt#(64) y0 = unpack(pack(y))-300;
	     let inside_circle = (x0*x0 + y0*y0) < (250*250);
	     // what colour shall we draw?
	     Bit#(256) draw = zeroExtend(inside_circle ? col : ~col);
   
	     // calcuate the 16-bit address offset of the pixel
	     Bit#(64) offset_16b = (x+800*y)*2;
	     // we need to write over a 256-bit bus, so calculate the 8-byte aligned address
	     Bit#(64) offset_256b = offset_16b & (~64'h1f);
	     // calculate shift offset for our 16-bit colour for the 256-bit bus
	     Bit#(64) offset_line_data = extend(offset_16b & 64'h1f)*8;
	     // calcuate the corresponding write mask offset
	     Bit#(32) offset_line_mask = truncate(offset_16b & 64'h1f);
	     // create data structure for bus request
	     PismData pdata = pdef;
	     pdata.addr = `CHERI_FB_BASE + offset_256b;
	     pdata.data = draw << offset_line_data;
	     pdata.writemask = 32'h00000003 << offset_line_mask;
	     pdata.write = 1;
	     // do bus request
	     pism_request_put(PISM_BUS_CHERI_0, pdata);
	 endaction
     $display("Finishing at time %t",$time);
   endseq);
  
  // instantiate and run the tester FSM until it terminates
  mkAutoFSM(tester_fsm);
  
endmodule
		

endpackage
