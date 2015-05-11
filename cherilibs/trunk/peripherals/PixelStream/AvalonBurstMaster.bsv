/*-
 * Copyright (c) 2013 Simon W. Moore
 * Copyright (c) 2013 Matthew Naylor
 * Copyright (c) 2013 Philip Withnall
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
   Bluespec Server interface to Avalon master PIPELINED interface
   ==============================================================
   Simon Moore, October 2009
   Customised by by Matt N, December 2012
   Modified by Simon to avoid name conflicts
 *****************************************************************************/

// Avalon Master Interface.  Pipelined version, with burst reads.
// Write requests are NOT acknowleged via a response to client,
// i.e. responses are only issued for read requests.
// Instead, the allWritesComplete method can be used to ensure that
// there are no outstanding write requests.
// Also, N consecutive put requests are guaranteed not to block
// provided that canPut(N) returns True.

package AvalonBurstMaster;

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import FIFOLevel::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;
import ConfigReg::*;

// Type for avalon bus data
typedef UInt#(256) AvalonBurstWordT;
typedef 8 DDR2_Max_Burst_Length;
typedef UInt#(TAdd#(TLog#(DDR2_Max_Burst_Length), 1)) BurstLength;
typedef 2 RequestBufferSize; // was 32 which seemed to be huge!
typedef TMul#(TAdd#(RequestBufferSize,1), DDR2_Max_Burst_Length) ResponseBufferSize;
typedef TAdd#(TLog#(RequestBufferSize), 1) RequestBufferCountWidth;
typedef TAdd#(TLog#(ResponseBufferSize), 1) ResponseBufferCountWidth;

typedef union tagged {
  BurstLength MemRead; // Burst length must not be 0
  void MemWrite;
}  MemAccessT
  deriving(Bits,Eq);

// Structure for memory requests (no byte enables)
typedef struct {
   MemAccessT   rw;
   UInt#(word_address_width)  addr; // word address
   AvalonBurstWordT  data;
   } MemAccessPacketT#(numeric type word_address_width)
  deriving(Bits,Eq);


(* always_ready, always_enabled *)
interface AvalonPipelinedMasterIfc#(numeric type word_address_width);
  method Action m0(AvalonBurstWordT readdata, Bool readdatavalid, Bool waitrequest);
  method AvalonBurstWordT m0_writedata;
  method UInt#(TAdd#(5,word_address_width)) m0_address;
  method Bool m0_read;
  method Bool m0_write;
  method BurstLength m0_burstcount;
endinterface


interface Server2AvalonPipelinedMasterIfc#(numeric type word_address_width);
  interface AvalonPipelinedMasterIfc#(word_address_width) avm;
  interface Server#(MemAccessPacketT#(word_address_width),AvalonBurstWordT) server;
  method Bool canPut(Integer n);
  method Bool allWritesComplete;
endinterface

module mkServer2AvalonPipelinedMaster(Server2AvalonPipelinedMasterIfc#(word_address_width))
  provisos(Max#(word_address_width,30,30),
           Add#(word_address_width, 5, TAdd#(5, word_address_width)));
  // bypass wires for incoming Avalon master signals
  // N.B. avalon master address is a word address, so need to add 5 bits
  Reg#(UInt#(word_address_width))  address_r       <- mkReg(0);
  Reg#(AvalonBurstWordT)  writedata_r     <- mkReg(0);
  Reg#(Bool)         read_r          <- mkReg(False);
  Reg#(BurstLength)  burstcount_r    <- mkRegU;
  Reg#(Bool)         write_r         <- mkReg(False);
  PulseWire          signal_read     <- mkPulseWire;
  PulseWire          signal_write    <- mkPulseWire;
  Wire#(Bool)        avalonwait      <- mkBypassWire;
  Wire#(Bool)        avalonreadvalid <- mkBypassWire;
  Wire#(AvalonBurstWordT) avalonreaddata  <- mkBypassWire;
   
  // Request buffer (and a counter)
  FIFOF#(MemAccessPacketT#(word_address_width)) requestBuffer <-
    mkSizedFIFOF(valueOf(RequestBufferSize));
  BurstMasterCounter#(RequestBufferCountWidth) requestBufferCount <- mkBurstMasterCounter;
  
  // Response buffer (and register to record allocated space)
  FIFOF#(AvalonBurstWordT) responseBuffer <-
    mkGSizedFIFOF(True, False, valueOf(ResponseBufferSize));
  Reg#(UInt#(ResponseBufferCountWidth))  responseBufferSpace <- 
    mkReg(fromInteger(valueOf(ResponseBufferSize)));
  Wire#(BurstLength) responseBufferSpace_allocate <- mkDWire(0);
  Wire#(BurstLength) responseBufferSpace_freeup   <- mkDWire(0);

  // Keep track of writes and write-acknowlegements
  BurstMasterCounter#(RequestBufferCountWidth) outstandingWrites <- mkBurstMasterCounter;
  
  let write_ack = write_r && !read_r && !avalonwait;
   
  rule buffer_data_read (avalonreadvalid);
    responseBuffer.enq(avalonreaddata);
  endrule
   
  rule acceptWriteAck (write_ack);
    outstandingWrites.decr;
  endrule

  (* no_implicit_conditions *)
  rule do_read_reg;
    if(signal_read) read_r <= True;
    else if(!avalonwait) read_r <= False;
  endrule
   
  (* no_implicit_conditions *)
  rule do_write_reg;
    if(signal_write) write_r <= True;
    else if(!avalonwait) write_r <= False;
  endrule
  
  (* no_implicit_conditions *)
  rule update_responseBufferSpace;
    responseBufferSpace <= responseBufferSpace
                         - extend(responseBufferSpace_allocate)
                         + extend(responseBufferSpace_freeup);
  endrule
  
  // Do a request if avalon wait is false or both read reg and write reg are false
  rule performRequest (
      !(avalonwait && (read_r || write_r)) &&
      (responseBufferSpace > fromInteger(valueOf(DDR2_Max_Burst_Length)))
      );
    // Take request from the request buffer
    let packet = requestBuffer.first;
    requestBuffer.deq;
    requestBufferCount.decr;
    // Perform request
    address_r <= packet.addr;
    writedata_r <= packet.data;
    case (packet.rw) matches
      tagged MemRead .n:
        begin
          signal_read.send();
          burstcount_r <= n;
          // Reserve space in the response FIFO
          responseBufferSpace_allocate <= n;
        end
      tagged MemWrite:
        begin
          signal_write.send();
          burstcount_r <= 1;
          outstandingWrites.incr;  // Move to request.put?
        end
    endcase
  endrule
  
  // Avalon master interface - just wiring
  interface AvalonPipelinedMasterIfc avm;
    method Action m0(readdata, readdatavalid, waitrequest);
      avalonreaddata <= readdata;
      avalonreadvalid <= readdatavalid;
      avalonwait <= waitrequest;
    endmethod
    
    method m0_writedata  = writedata_r;
    method m0_address    = unpack({pack(address_r),5'b00});
    method m0_read       = read_r;
    method m0_write      = write_r;
    method m0_burstcount = burstcount_r;
  endinterface

  // server interface   
  interface Server server;
    interface Get response;
      method ActionValue#(AvalonBurstWordT) get();
        responseBufferSpace_freeup <= 1;
        responseBuffer.deq;
        return responseBuffer.first;
      endmethod
    endinterface
    
    interface Put request;
      method Action put(packet);
        requestBuffer.enq(packet);
        requestBufferCount.incr;
      endmethod
    endinterface
  endinterface

  method Bool canPut(Integer numPuts) =
    requestBufferCount.read < fromInteger(valueOf(RequestBufferSize)-numPuts);

  method Bool allWritesComplete = (outstandingWrites.read == 0);

endmodule

// A simple counter, used above.

interface BurstMasterCounter#(type n);
  method UInt#(n) read;
  method Action incr;
  method Action decr;
endinterface

module mkBurstMasterCounter(BurstMasterCounter#(n));
  ConfigReg#(UInt#(n)) value <- mkConfigReg(0);

  PulseWire incrementCalled <- mkPulseWire();
  PulseWire decrementCalled <- mkPulseWire();

  rule doIncrement(incrementCalled && !decrementCalled);
    value <= value + 1;
  endrule

  rule doDecrement(!incrementCalled && decrementCalled);
    value <= value - 1;
  endrule

  method UInt#(n) read;
    return value;
  endmethod

  method Action incr if (value < unpack(~0));
    incrementCalled.send();
  endmethod

  method Action decr if (value > 0);
    decrementCalled.send();
  endmethod
endmodule

endpackage
