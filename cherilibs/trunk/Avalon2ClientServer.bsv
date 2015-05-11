/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert N. M. Watson
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
 Avalon2ClientServer
 ===================
 
 Provides Avalon (Altera's switched bus standard) slave and master interfaces
 to Bluespec Client and Server interfaces
 
 Altered 31 May 2011 - removed arbiter locks since Qsys doesn't support them
 
 Added byte enables in Jan 2012
 
 TODO: added a master with byte enable but need to add a slave
 *****************************************************************************/


package Avalon2ClientServer;

import FIFO::*;
import FIFOF::*;
import FIFOLevel::*;
import GetPut::*;
import ClientServer::*;
import Connectable::*;

// Type for avalon bus data
typedef UInt#(32) AvalonWordT;
typedef Maybe#(AvalonWordT) ReturnedDataT;

// Memory access type.  Note that MemNull used as part of arbiterlock release message.
typedef enum { MemRead, MemWrite, MemNull } MemAccessT deriving(Bits,Eq);

// Byte enable type - 4 bytes per 32-bit word
typedef Bit#(4) AvalonByteEnableT;


// Structure for memory requests (no byte enables)
typedef struct {
   MemAccessT   rw;
   UInt#(word_address_width)  addr; // word address
   AvalonWordT  data;
   } MemAccessPacketT#(numeric type word_address_width) deriving(Bits,Eq);

// Structure for memory requests (with byte enables)
typedef struct {
   MemAccessT   rw;
   UInt#(word_address_width)  addr; // word address
   AvalonWordT  data;
   AvalonByteEnableT byteenable;
   } MemAccessPacketBET#(numeric type word_address_width) deriving(Bits,Eq);



/*****************************************************************************
   Avalon slave interface to Bluepsec Client interface
   ===================================================
   Simon Moore, September 2009
 *****************************************************************************/


// Avalon Slave Interface
// notes:
//  - all methods are ready and enabled
//  - names are chosen to match what SOPC builder expects for variable names
//    in the Verilog code - don't change!
(* always_ready, always_enabled *)
interface AvalonSlaveIfc#(numeric type word_address_width);
   method Action s0(UInt#(word_address_width) address, AvalonWordT writedata,
		    Bool write, Bool read); //, Bool arbiterlock); //, Bool resetrequest);
   method AvalonWordT s0_readdata;
   method Bool s0_waitrequest;
endinterface

interface AvalonSlave2ClientIfc#(numeric type word_address_width);
   interface AvalonSlaveIfc#(word_address_width) avs;
   interface Client#(MemAccessPacketT#(word_address_width),ReturnedDataT) client;
//(* always_read, always_enabled *)  method Bool reset_from_bus;
endinterface

(* always_ready, always_enabled *)
interface AvalonSlaveBEIfc#(numeric type word_address_width);
   method Action s0(UInt#(word_address_width) address, AvalonWordT writedata,
		    Bool write, Bool read, AvalonByteEnableT byteenable); //, Bool arbiterlock); //, Bool resetrequest);
   method AvalonWordT s0_readdata;
   method Bool s0_waitrequest;
endinterface

interface AvalonSlave2ClientBEIfc#(numeric type word_address_width);
   interface AvalonSlaveBEIfc#(word_address_width) avs;
   interface Client#(MemAccessPacketBET#(word_address_width),ReturnedDataT) client;
//(* always_read, always_enabled *)  method Bool reset_from_bus;
endinterface

module mkAvalonSlave2ClientBE(AvalonSlave2ClientBEIfc#(word_address_width))
   provisos(Max#(word_address_width,30,30));

   // bypass wires for incoming Avalon slave signals
   Wire#(UInt#(word_address_width)) address_w   <- mkBypassWire;
   Wire#(AvalonWordT)       writedata_w          <- mkBypassWire;
   Wire#(Bool)              read_w               <- mkBypassWire;
   Wire#(Bool)              write_w              <- mkBypassWire;
   Wire#(AvalonByteEnableT) byteenable_w         <- mkBypassWire;
   
   // bypass wire for Avalon wait signal + pulsewires to clear
   Wire#(Bool)        avalonwait           <- mkBypassWire;
   PulseWire          avalonwait_end_read  <- mkPulseWire;
   PulseWire          avalonwait_end_write <- mkPulseWire;

   // DWire for read data returned to Avalon slave bus
   Wire#(AvalonWordT) datareturned <- mkDWire(32'hdeaddead);

   // reg indicating that the Avalon request is being processed and further
   // requests should be ignored until the avalonwait signal has been released
   // (gone low)
   Reg#(Bool) ignore_further_requests <- mkReg(False);

   // FIFO holding requests received from Avalon slave bus sent out via
   // the client request interface
   FIFOF#(MemAccessPacketBET#(word_address_width)) outbuf <- mkFIFOF;
   
   // provide the avalonwait signal
   // note: this must appear within the same clock cycle that a read or write
   //       is initiated
   (* no_implicit_conditions *)
   rule wire_up_avalonwait;
      avalonwait <= (read_w && !avalonwait_end_read) || (write_w && !avalonwait_end_write);
   endrule

   // if this is a new Avalon slave bus request then enqueue
   // note: if outbuf FIFO is full, Avalon slave forced to wait
   rule hanlde_bus_requests ((read_w || write_w) && !ignore_further_requests);
      outbuf.enq(MemAccessPacketBET{
        rw: read_w ? MemRead : MemWrite,
        addr: address_w,
        data: writedata_w,
        byteenable: byteenable_w}); // N.B. "data" is undefined for reads
      ignore_further_requests <= read_w;
      // release avalonwait for writes since the request has been enqueued
      if(write_w) avalonwait_end_write.send;
   endrule
   
   // once avalonwait has gone low, get ready to respond to next request
   // from the Avalon bus
   rule cancel_ingore_further_requests(!avalonwait && ignore_further_requests);
      ignore_further_requests <= False;
   endrule
   
   // Avalon slave interface - just wiring
   interface AvalonSlaveBEIfc avs;
      method Action s0(address, writedata, write, read, byteenable); // , arbiterlock); //, resetrequest);
        address_w     <= address;
        writedata_w   <= writedata;
        write_w       <= write;
        read_w        <= read;
        byteenable_w  <= byteenable;
      endmethod
      
      method s0_readdata;
        return datareturned;
      endmethod
      
      method s0_waitrequest;
        return avalonwait;
      endmethod
      
   endinterface

   // client interface   
   interface Client client;
      interface request = toGet(outbuf);
      
      interface Put response;
        method Action put(d);
          // note: respond to data read
          // currently if d is Invalid then ignored but it could be used
          // to do a avalonwait_end_write.send if it was required the
          // clients waited on writes until the writes had completed
          if(isValid(d))
	          begin
	            // note duality of DWire for data and PulseWire for
	            //  associated signal
	            datareturned <= fromMaybe(32'hdeaddead,d);
	            avalonwait_end_read.send;
	          end
	       endmethod
      endinterface
   endinterface

endmodule

module mkAvalonSlave2Client(AvalonSlave2ClientIfc#(word_address_width))
   provisos(Max#(word_address_width,30,30));

   // bypass wires for incoming Avalon slave signals
   Wire#(UInt#(word_address_width)) address_w   <- mkBypassWire;
   Wire#(AvalonWordT) writedata_w          <- mkBypassWire;
   Wire#(Bool)        read_w               <- mkBypassWire;
   Wire#(Bool)        write_w              <- mkBypassWire;
   
   // bypass wire for Avalon wait signal + pulsewires to clear
   Wire#(Bool)        avalonwait           <- mkBypassWire;
   PulseWire          avalonwait_end_read  <- mkPulseWire;
   PulseWire          avalonwait_end_write <- mkPulseWire;

   // DWire for read data returned to Avalon slave bus
   Wire#(AvalonWordT) datareturned <- mkDWire(32'hdeaddead);

   // reg indicating that the Avalon request is being processed and further
   // requests should be ignored until the avalonwait signal has been released
   // (gone low)
   Reg#(Bool) ignore_further_requests <- mkReg(False);

   // FIFO holding requests received from Avalon slave bus sent out via
   // the client request interface
   FIFOF#(MemAccessPacketT#(word_address_width)) outbuf <- mkFIFOF;
   
   // provide the avalonwait signal
   // note: this must appear within the same clock cycle that a read or write
   //       is initiated
   (* no_implicit_conditions *)
   rule wire_up_avalonwait;
      avalonwait <= (read_w && !avalonwait_end_read) || (write_w && !avalonwait_end_write);
   endrule

   // if this is a new Avalon slave bus request then enqueue
   // note: if outbuf FIFO is full, Avalon slave forced to wait
   rule hanlde_bus_requests ((read_w || write_w) && !ignore_further_requests);
      outbuf.enq(MemAccessPacketT{
	 rw: read_w ? MemRead : MemWrite,
	 addr: address_w,
	 data: writedata_w}); // N.B. "data" is undefined for reads
      ignore_further_requests <= read_w;
      // release avalonwait for writes since the request has been enqueued
      if(write_w) avalonwait_end_write.send;
   endrule
   
   // once avalonwait has gone low, get ready to respond to next request
   // from the Avalon bus
   rule cancel_ingore_further_requests(!avalonwait && ignore_further_requests);
      ignore_further_requests <= False;
   endrule
   
   // Avalon slave interface - just wiring
   interface AvalonSlaveIfc avs;
      method Action s0(address, writedata, write, read); // , arbiterlock); //, resetrequest);
	 address_w     <= address;
	 writedata_w   <= writedata;
	 write_w       <= write;
	 read_w        <= read;
      endmethod
      
      method s0_readdata;
	 return datareturned;
      endmethod
      
      method s0_waitrequest;
	 return avalonwait;
      endmethod
      
   endinterface

   // client interface   
   interface Client client;
      interface request = toGet(outbuf);
      
      interface Put response;
	 method Action put(d);
	    // note: respond to data read
	    // currently if d is Invalid then ignored but it could be used
	    // to do a avalonwait_end_write.send if it was required the
	    // clients waited on writes until the writes had completed
	    if(isValid(d))
	       begin
		  // note duality of DWire for data and PulseWire for
		  //  associated signal
		  datareturned <= fromMaybe(32'hdeaddead,d);
		  avalonwait_end_read.send;
	       end
	 endmethod
      endinterface
   endinterface

endmodule



/*****************************************************************************
 Bluespec Server interface to Avalon master interface
 ====================================================
 Simon Moore, October 2009
 
 Updated 2012 to include byte enables

 *****************************************************************************/


// Avalon Master Interface
// notes:
//  - the "Server" side must be ready to receive data if data is not to be lost
//  - all methods are ready and enabled
//  - names are chosen to match what SOPC builder expects for variable names
//    in the Verilog code - don't change!
//  - initally a long latency (too much buffering?) but (hopfully) robust
//    design remove some latch stages in the future

// version of the interface with no byte enables
(* always_ready, always_enabled *)
interface AvalonMasterIfc#(numeric type word_address_width);
   method Action m0(AvalonWordT readdata, Bool waitrequest);
   method AvalonWordT m0_writedata;
   method UInt#(TAdd#(2,word_address_width)) m0_address;
   method Bool m0_read;
   method Bool m0_write;
endinterface


// server form with no byte enables
interface Server2AvalonMasterIfc#(numeric type word_address_width);
   interface AvalonMasterIfc#(word_address_width) avm;
   interface Server#(MemAccessPacketT#(word_address_width),ReturnedDataT) server;
endinterface


// version of the interface with byte enables
(* always_ready, always_enabled *)
interface AvalonMasterBEIfc#(numeric type word_address_width);
   method Action m0(AvalonWordT readdata, Bool waitrequest);
   method AvalonWordT m0_writedata;
   method UInt#(TAdd#(2,word_address_width)) m0_address;
   method Bool m0_read;
   method Bool m0_write;
   method AvalonByteEnableT m0_byteenable;
endinterface


interface Server2AvalonMasterBEIfc#(numeric type word_address_width);
   interface AvalonMasterBEIfc#(word_address_width) avm;
   interface Server#(MemAccessPacketBET#(word_address_width),ReturnedDataT) server;
endinterface


module mkServer2AvalonMasterBE(Server2AvalonMasterBEIfc#(word_address_width))
  provisos(Max#(word_address_width,30,30),
	   Add#(word_address_width, 2, TAdd#(2, word_address_width)));
  // bypass wires for incoming Avalon master signals
  // N.B. avalon master address is a byte address, so need to add 2 bits
  Reg#(UInt#(word_address_width))  address_r       <- mkReg(0);
  Reg#(AvalonWordT)  writedata_r     <- mkReg(0);
  Reg#(Bool)         read_r          <- mkReg(False);
  Reg#(Bool)         write_r         <- mkReg(False);
  Reg#(AvalonByteEnableT) byteenable_r    <- mkReg(0);
  PulseWire          signal_read     <- mkPulseWire;
  PulseWire          signal_write    <- mkPulseWire;
  Wire#(Bool)        avalonwait      <- mkBypassWire;
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
   FIFO#(MemAccessT) pending_acks <- mkFIFO;
   
   let write_ack = write_r && !read_r && !avalonwait;
   let read_ack  = !write_r && read_r && !avalonwait;
   
   rule buffer_data_read (read_ack && (pending_acks.first==MemRead));
      datareturnbuf.enq(tagged Valid avalonreaddata);
      //$display("   %05t: Avalon2ClientServer returning data",$time);
      pending_acks.deq;
   endrule
   
   rule signal_data_write (write_ack && (pending_acks.first==MemWrite));
      datareturnbuf.enq(tagged Invalid); // signal write has happened
      pending_acks.deq;
   endrule

   rule signal_mem_null (pending_acks.first==MemNull);
      datareturnbuf.enq(tagged Invalid); // signal null has happened
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
   interface AvalonMasterBEIfc avm;
      method Action m0(readdata, waitrequest);
	 avalonreaddata <= readdata;
	 avalonwait <= waitrequest;
      endmethod
      
      method m0_writedata;   return writedata_r;                     endmethod
      method m0_address;     return unpack({pack(address_r),2'b00}); endmethod
      method m0_read;        return read_r;                          endmethod
      method m0_write;       return write_r;                         endmethod
      method m0_byteenable;  return byteenable_r;                    endmethod
   endinterface

   // server interface   
   interface Server server;
      interface response = toGet(datareturnbuf);
      
   interface Put request;
       // SWM: added (read_r || write_r) since we might start with avalonwait high
	 method Action put(packet) if (!(avalonwait && (read_r || write_r)) && datareturnbuf.isLessThan(2));
	    address_r     <= packet.addr;
	    writedata_r   <= packet.data;
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



// provide a master without byte enables, i.e. 32-bit are always accessed
module mkServer2AvalonMaster(Server2AvalonMasterIfc#(word_address_width))
  provisos(Max#(word_address_width,30,30),
	   Add#(word_address_width, 2, TAdd#(2, word_address_width)));
  
  Server2AvalonMasterBEIfc#(word_address_width) full_master <- mkServer2AvalonMasterBE;
  
  // Avalon master interface - just wiring
  interface AvalonMasterIfc avm;
    method Action m0(readdata, waitrequest);
      full_master.avm.m0(readdata, waitrequest);
    endmethod
      
    method m0_writedata; return full_master.avm.m0_writedata; endmethod
    method m0_address;   return full_master.avm.m0_address;   endmethod
    method m0_read;      return full_master.avm.m0_read;      endmethod
    method m0_write;     return full_master.avm.m0_write;     endmethod
  endinterface
  
  interface Server server;
    interface response = full_master.server.response;
    interface Put request;
      method Action put(packet);
	full_master.server.request.put(
	   MemAccessPacketBET{
	      rw:         packet.rw,
	      addr:       packet.addr,
	      data:       packet.data,
	      byteenable: 4'b1111});
      endmethod
    endinterface
  endinterface

endmodule


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
   method Action m0(AvalonWordT readdata, Bool readdatavalid, Bool waitrequest);
   method AvalonWordT m0_writedata;
   method UInt#(TAdd#(2,word_address_width)) m0_address;
   method Bool m0_read;
   method Bool m0_write;
endinterface


interface Server2AvalonPipelinedMasterIfc#(numeric type word_address_width);
   interface AvalonPipelinedMasterIfc#(word_address_width) avm;
   interface Server#(MemAccessPacketT#(word_address_width),ReturnedDataT) server;
endinterface


module mkServer2AvalonPipelinedMaster(Server2AvalonPipelinedMasterIfc#(word_address_width))
   provisos(Max#(word_address_width,30,30),
	    Add#(word_address_width, 2, TAdd#(2, word_address_width)));
   // bypass wires for incoming Avalon master signals
   // N.B. avalon master address is a byte address, so need to add 2 bits
   Reg#(UInt#(word_address_width))  address_r       <- mkReg(0);
   Reg#(AvalonWordT)  writedata_r     <- mkReg(0);
   Reg#(Bool)         read_r          <- mkReg(False);
   Reg#(Bool)         write_r         <- mkReg(False);
//   Reg#(Bool)         arbiterlock_r   <- mkReg(False);
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
   
   // FIFO of length 16 which is:
   // Unguarded enq since it it guarded by the bus transaction initiation
   // Guarded deq
   // Unguarded count so isLessThan will not block
   FIFOLevelIfc#(ReturnedDataT,16) datareturnbuf <- mkGFIFOLevel(True,False,True);
   FIFO#(MemAccessT) pending_acks <- mkSizedFIFO(16);
   FIFO#(MemAccessT) pending_write_acks <- mkSizedFIFO(16);
   
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
      datareturnbuf.enq(tagged Invalid); // signal write has happened
      pending_acks.deq;
   endrule

   rule signal_mem_null (pending_acks.first==MemNull);
      datareturnbuf.enq(tagged Invalid); // signal null has happened
      pending_acks.deq;
   endrule

   rule resolve_pending_write_acks (!avalonreadvalid && !write_ack && (pending_acks.first==MemWrite));
      pending_write_acks.deq; // N.B. only fires if this dequeue can happen
      datareturnbuf.enq(tagged Invalid);
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
      
      method m0_writedata;   return writedata_r;    endmethod
      method m0_address;     return unpack({pack(address_r),2'b00});   endmethod
      method m0_read;        return read_r;         endmethod
      method m0_write;       return write_r;        endmethod
//      method m0_arbiterlock; return arbiterlock_r;  endmethod
   endinterface

   // server interface   
   interface Server server;
      interface response = toGet(datareturnbuf);
      
      interface Put request;
	 method Action put(packet) if (!(avalonwait && (read_r || write_r)) && datareturnbuf.isLessThan(2));
	    address_r     <= packet.addr;
	    writedata_r   <= packet.data;
	    pending_acks.enq(packet.rw);
	    case(packet.rw)
	       MemRead:  signal_read.send();
	       MemWrite: signal_write.send();
	    endcase
	 endmethod
      endinterface
   endinterface

endmodule



/*****************************************************************************
 Avalon Bridge
 N.B. as usual the names on interfaces are chosen to match what SOPC
 builder expects, so don't change!
 ****************************************************************************/

interface AvalonBridgeIfc#(numeric type word_address_width);
   interface AvalonSlaveIfc#(word_address_width) avs;
   interface AvalonMasterIfc#(word_address_width) avm;
endinterface
   

module mkAvalonBridge(AvalonBridgeIfc#(word_address_width))
   provisos(Max#(word_address_width,30,30),
	    Add#(word_address_width, 2, TAdd#(2, word_address_width)));

   AvalonSlave2ClientIfc#(word_address_width) client <- mkAvalonSlave2Client;
   Server2AvalonMasterIfc#(word_address_width) server <- mkServer2AvalonMaster;
   
   mkConnection(client.client,server.server);
   
   interface avs = client.avs;
   interface avm = server.avm;
endmodule		      


endpackage
