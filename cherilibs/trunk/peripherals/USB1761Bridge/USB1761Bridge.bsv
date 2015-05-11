/*-
 * Copyright (c) 2014 Jonathan Woodruff
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

 Philips USB interface logic
 ===========
 
 This module should run at 100MHz and translates an Avalon memory mapped interface
 to the asynchronous interface of the Philips ISP1761 chip on the Terasic DE4.
 
 *****************************************************************************/


package USB1761Bridge;

import GetPut::*;
import ClientServer::*;
import Avalon2ClientServer::*;
import ConfigReg::*;


// conduit interfaces to export
(* always_ready, always_enabled *)
interface USBSignalConduit;
  method Bool     cs_n;
  method Bool     wr_n;
  method Bool     rd_n;
  method ActionValue#(Bit#(32)) dout(Bit#(32) din);
  method Bit#(17) a;
  method ActionValue#(Bool)     dc_irq(Bool in);
  method ActionValue#(Bool)     hc_irq(Bool in);
  // These should all be left floating
  //method Action   dc_dreq(Bool in);
  //method Action   hc_dreq(Bool in);
  //method Bool     dc_dack;
  //method Bool     hc_dack;
endinterface

typedef struct {
  Bool     cs_n; 
  Bool     wr_n;
  Bool     rd_n;
  Bit#(32) dout;
  Bit#(16) a;
} USBOutState deriving (Bits, Eq, FShow);

// top-level interface
(* always_ready, always_enabled *)
interface USB1761Bridge;
  interface AvalonSlaveIfc#(16) avs;
  interface USBSignalConduit      coe;
endinterface

typedef enum {Read0, Read1, Read2, Read3, Read4,
              Write0, Write1, Write2, Write3, Write4, 
              Idle} USBState deriving (Bits, Eq);
(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkUSB1761Bridge(USB1761Bridge);
  USBOutState initOut = USBOutState{
    cs_n: True,
    wr_n: True,
    rd_n: True,
    dout: 0,
    a:    0
  };
  Reg#(USBOutState)   out <- mkConfigReg(initOut);
  Wire#(Bit#(32)) dinWire <- mkWire;
  Reg#(USBState)    state <- mkReg(Idle);
  Reg#(Bit#(5))     count <- mkReg(0);
  
  AvalonSlave2ClientIfc#(16)
                avalon_slave <- mkAvalonSlave2Client;
  
  rule countDown(state==Idle && count!=0);
    count <= count-1;
  endrule

  // handle the AvalonMM slave interface to allow status to be read
  rule start(state==Idle && count==0);
    let req <- avalon_slave.client.request.get();
    USBOutState nout = out;
    nout.a = pack(req.addr);
    nout.dout = pack(req.data);    
    nout.cs_n = False;
    if (req.rw == MemRead) nout.rd_n = False;
    out <= nout;
    state <= (case(req.rw)
                MemRead:  return Read0;
                MemWrite: return Write0;
                default:  return Idle;
             endcase);
  endrule
  
  // ----------------- Write State Machine ------------------
  
  rule write0(state==Write0);
    out.wr_n <= False;
    state <= Write1;
  endrule
  
  rule write1(state==Write1);
    state <= Write2;
  endrule
  
  rule write2(state==Write2);
    out.wr_n <= True;
    state <= Write3;
  endrule
  
  rule write3(state==Write3);
    out.cs_n <= True;
    state <= Write4;
  endrule
  
  rule write4(state==Write4);
    ReturnedDataT rtn = tagged Invalid;
    avalon_slave.client.response.put(rtn);
    if (out.a == (16'h33C>>2)) count <= 8;
    out <= initOut;
    state <= Idle;
  endrule
  
  // ----------------- Read State Machine ------------------
  
  rule read0(state==Read0);
    state <= Read1;
  endrule
  
  rule read1(state==Read1);
    state <= Read2;
  endrule
  
  rule read2(state==Read2);
    ReturnedDataT rtn = tagged Valid unpack(dinWire);
    avalon_slave.client.response.put(rtn);
    out.rd_n <= True;
    state <= Read3;
  endrule
  
  rule read3(state==Read3);
    out <= initOut;
    state <= Idle;
  endrule
  
  // ----------------- Interfaces ---------------
  
  interface avs = avalon_slave.avs;
  interface USBSignalConduit coe;
    method Bool     cs_n; return out.cs_n; endmethod
    method Bool     wr_n; return out.wr_n; endmethod
    method Bool     rd_n; return out.rd_n; endmethod
    method ActionValue#(Bit#(32)) dout(Bit#(32) din);
      dinWire <= din;
      return out.dout;
    endmethod
    method Bit#(17) a; return {out.a,1'b0}; endmethod
    // Feed IRQs through to avalon.  These will need to be associated with
    // the slave manually in qsys.
    method ActionValue#(Bool) dc_irq(Bool in); return in; endmethod
    method ActionValue#(Bool) hc_irq(Bool in); return in; endmethod
    //method Action   dc_dreq(Bool in); endmethod
    //method Action   hc_dreq(Bool in); endmethod
    //method Bool     dc_dack; return True; endmethod
    //method Bool     hc_dack; return True; endmethod
  endinterface    
endmodule






 // ------------------ Unit Test ----------------

typedef enum {Start, Write, Read, Done} TestState deriving (Bits, Eq);

module mkUnitTestUSB1761Bridge();
  USB1761Bridge bridge <- mkUSB1761Bridge();
  Reg#(TestState) state <- mkReg(Start);
  
  rule startState(state==Start);
    bridge.avs.s0(16'h0000, 32'h00000000, False, False);
    state <= Write;
  endrule
  
  rule writeState(state==Write);
    bridge.avs.s0(16'h0001, 32'hCAFECAFE, True, False);
  endrule
  
  rule writeStateDone(state==Write);
    if (!bridge.avs.s0_waitrequest) state <= Read;
  endrule
  
  rule readState(state==Read);
    bridge.avs.s0(16'h0001, 32'h00000000, False, True);
  endrule
  
  rule readStateDone(state==Read);
    if (!bridge.avs.s0_waitrequest) begin
      $display("returned data: %x", bridge.avs.s0_readdata);
      state <= Done;
    end
  endrule
  
  rule doneState(state==Done);
    bridge.avs.s0(16'h0000, 32'h00000000, False, False);
  endrule
  
  rule report;
    $display("cs_n:%x wr_n:%x rd_n:%x dout:%x a:%x, dc_irq:%x, hc_irq:%x",
              bridge.coe.cs_n,
              bridge.coe.wr_n,
              bridge.coe.rd_n,
              bridge.coe.dout(32'hBEEFBEEF),
              bridge.coe.a,
              bridge.coe.dc_irq(True),
              bridge.coe.hc_irq(False)
            );
  endrule
  // How do you talk to an Avalon slave in simulation?
endmodule

endpackage
