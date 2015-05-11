/*-
 * Copyright (c) 2010 Simon W. Moore
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010 Jonathan Woodruff
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
 Avalon2ClientServer
 ===================
 
 Provides Avalon (Altera's switched bus standard) slave and master interfaces
 to Bluespec Client and Server interfaces
 *****************************************************************************/


package Avalon2ClientServer64be;

import FIFO::*;
import FIFOF::*;
import FIFOLevel::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

// Type for avalon bus data
typedef Bit#(64) AvalonWordT;
typedef Bit#(8) AvalonByteEnableT;
typedef Maybe#(AvalonWordT) ReturnedDataT;

// Memory access type.  Note that MemNull used as part of arbiterlock release message.
typedef enum { MemRead, MemWrite, MemNull } MemAccessT deriving(Bits,Eq);

// Structure for memory requests
typedef struct {
   MemAccessT   rw;
   Bit#(word_address_width)  addr; // word address
   AvalonWordT  data;
   AvalonByteEnableT byteenable;
   Bool cached;
   } MemAccessPacketT#(numeric type word_address_width) deriving(Bits,Eq);

/*****************************************************************************
   Bluespec Server interface to Avalon master PIPELINED interface
   ==============================================================
   Simon Moore, October 2009
 *****************************************************************************/


// Avalon Master Interface - pipelined version
//  - partially working - really need "flush" signal
// notes:
//  - all methods are ready and enabled
//  - names are chosen to match what SOPC builder expects for variable names
//    in the Verilog code - don't change!
//  - initally a long latency (too much buffering?) but (hopfully) robust
//    design remove some latch stages in the future

(* always_ready, always_enabled *)
interface AvalonPipelinedMasterIfc#(numeric type word_address_width);
	(* prefix = "" *)
   method Action m0(AvalonWordT readdata, Bool readdatavalid, Bool waitrequest);
   method AvalonWordT writedata;
   method Bit#(TAdd#(3,word_address_width)) address;
   method Bool read;
   method Bool write;
   method Bool arbiterlock;
   method AvalonByteEnableT byteenable;
endinterface


interface Server2AvalonPipelinedMasterIfc#(numeric type word_address_width);
   interface AvalonPipelinedMasterIfc#(word_address_width) avm;
   interface Server#(MemAccessPacketT#(word_address_width),ReturnedDataT) server;
endinterface


module mkServer2AvalonPipelinedMaster(Server2AvalonPipelinedMasterIfc#(word_address_width))
   provisos(Max#(word_address_width,29,29),
	    Add#(word_address_width, 3, TAdd#(3, word_address_width)));
   // bypass wires for incoming Avalon master signals
   // N.B. avalon master address is a byte address, so need to add 2 bits
   Reg#(Bit#(word_address_width))  address_r       <- mkReg(0);
   Reg#(AvalonWordT)  writedata_r     <- mkReg(0);
   Reg#(Bool)         read_r          <- mkReg(False);
   Reg#(Bool)         write_r         <- mkReg(False);
   Reg#(Bool)         arbiterlock_r   <- mkReg(False);
   Reg#(AvalonByteEnableT) byteenable_r <- mkReg(?);
   PulseWire          signal_read     <- mkPulseWire;
   PulseWire          signal_write    <- mkPulseWire;
   Wire#(Bool)        avalonwait      <- mkBypassWire;
   Wire#(Bool)        avalonreadvalid <- mkBypassWire;
   Wire#(AvalonWordT) avalonreaddata  <- mkBypassWire;
   
   // buffer data returned
   // TODO: could this buffer be removed by not initiating the transaction
   // until the returndata get operation was active, then do the memory 
   // transaction and return the value to the get without buffering?
   //  - possibly not if the interface is fully pipelined because there
   //    can be several transactions ongoing (several addresses issued, etc.)
   //    before data comes back
   
   // FIFO of length 4 which is:
   // Unguarded enq since it it guarded by the bus transaction initiation
   // Guarded deq
   // Unguarded count so isLessThan will not block
   FIFOLevelIfc#(ReturnedDataT,4) datareturnbuf <- mkGFIFOLevel(True,False,True);
   FIFO#(MemAccessT) pending_acks <- mkSizedFIFO(4);
   FIFO#(MemAccessT) pending_write_acks <- mkSizedFIFO(4);
   
   let write_ack = write_r && !read_r && !avalonwait;
   
   rule buffer_data_read (avalonreadvalid && (pending_acks.first==MemRead));
      datareturnbuf.enq(tagged Valid avalonreaddata);
      $display("   %05t: Avalon2ClientServer returning data",$time);
      pending_acks.deq;
   endrule
   
   rule data_read_error (avalonreadvalid && (pending_acks.first!=MemRead));
      $display("ERROR: Server2AvalonPipelinedMaster - read returned when expeting a write or null ack");
   endrule
   
   rule buffer_data_write_during_readvalid (avalonreadvalid && write_ack);
      pending_write_acks.enq(MemWrite);
   endrule
   
   rule signal_data_write (!avalonreadvalid && write_ack && (pending_acks.first==MemWrite));
     // datareturnbuf.enq(tagged Invalid); // signal write has happened
      pending_acks.deq;
   endrule

   rule signal_mem_null (pending_acks.first==MemNull);
      //datareturnbuf.enq(tagged Invalid); // signal null has happened
      pending_acks.deq;
   endrule

   rule resolve_pending_write_acks (!avalonreadvalid && !write_ack && (pending_acks.first==MemWrite));
      pending_write_acks.deq; // N.B. only fires if this dequeue can happen
      //datareturnbuf.enq(tagged Invalid);
      pending_acks.deq;
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
   
   // Avalon master interface - just wiring
   interface AvalonPipelinedMasterIfc avm;
      method Action m0(readdata, readdatavalid, waitrequest);
	 avalonreaddata <= readdata;
	 avalonreadvalid <= readdatavalid;
	 avalonwait <= waitrequest;
      endmethod
      
      method writedata;   return writedata_r;    endmethod
      method address;     return unpack({pack(address_r),3'b000});   endmethod
      method read;        return read_r;         endmethod
      method write;       return write_r;        endmethod
      method arbiterlock; return arbiterlock_r;  endmethod
	  method byteenable;  return byteenable_r;   endmethod
   endinterface

   // server interface   
   interface Server server;
      interface response = toGet(datareturnbuf);
      
      interface Put request;
	 method Action put(packet) if (!avalonwait && datareturnbuf.isLessThan(2));
	    address_r     <= packet.addr;
	    writedata_r   <= packet.data;
	    arbiterlock_r <= False;
      byteenable_r  <= packet.byteenable;
	    pending_acks.enq(packet.rw);
	    case(packet.rw)
	       MemRead:  signal_read.send();
	       MemWrite: signal_write.send();
	    endcase
	 endmethod
      endinterface
   endinterface

endmodule

endpackage
