/*-
 * Copyright (c) 2012 SRI International
 * Copyright (c) 2012 Jonathan Woodruff
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
 Loopback UART
 =============

 Provides a loop-backed UART-like device intended to test
 character input interrupt handlers.  Characters are enqueued
 with a delay in clock cycles before they are released into
 the input queue ready to be read.
 
 Address map (byte address offsets)
 0: reads character from buffer, or -1 if buffer empty
    writes (delay,char) into buffer where delay is 24-bits, char is 8-bits
 4: reads interrupt enable flag (bit 0) and number of items level in
      output buffer (bits 16 to 31)
    writes interrupt enable flag (bit 0) and resets buffers if bit 1 is set
 
 The following modules are present:
 * mkLoopbackUART_internal
   - internal module containing the main implementation
 
 * mkLoopbackUART_Abstract
   - abstract Server interface around mkLoopbackUART_internal
 
 * mkUnitTest_LoopbackUART_Abstract
   - Bluespec unit test for mkUnitTest_LoopbackUART_Abstract
 
 * mkLoopbackUART_Avalon
   - Avalon Memory Mapped interface for mkLoopbackUART_internal

 History:
 * Initial version written by Simon Moore, 7th July 2011
 * 8 July revisions:
   - turned outQ buffer into a BRAM to improve implementation efficiency
     - this reports warnings about scheduling conflicts inside the BRAMCore
       library but the implementation passes tests
     ---then removed this since the SizedFIFO actually produces a
        simpler implementation
   - added buffer space left via status register
   - added buffer space test to unit test
   - made unit test be clearer about what is information, errors, etc.
   - made unit test count errors and do a final report
 
 *****************************************************************************/


package LoopbackUART;

import FIFO::*;
import FIFOF::*;
import BRAMFIFO::*;
import GetPut::*;
import ClientServer::*;
import Avalon2ClientServer::*;
import StmtFSM::*;

`define output_buf_size 1024
`define word_address_width 1


typedef struct {
   UInt#(24) delay;
   UInt#(8) char;
   } CharsToSendT deriving (Bits, Eq);


// the internal module which provides the implementation but not the interface
module mkLoopbackUART_internal(
   Client#(MemAccessPacketT#(`word_address_width),ReturnedDataT) client,
   PulseWire interrupt,
   Empty unused_ifc);

   FIFO#(CharsToSendT) outQ <- mkSizedFIFO(`output_buf_size);
   Reg#(UInt#(16)) outQlevel <- mkReg(`output_buf_size);
   PulseWire outQlevel_inc <- mkPulseWire;
   PulseWire outQlevel_dec <- mkPulseWire;
   FIFOF#(UInt#(8)) inputQ <- mkUGSizedFIFOF(`output_buf_size);
   FIFO#(UInt#(8)) char_being_delayed <- mkLFIFO;
   
   Wire#(Maybe#(MemAccessPacketT#(`word_address_width))) req <- mkDWire(tagged Invalid);
   
   Wire#(MemAccessT) memrw <- mkDWire(MemNull);
   Wire#(UInt#(`word_address_width)) memaddr <- mkDWire(0);
   Reg#(UInt#(24)) timer <- mkReg(0);
   PulseWire cleartimer <- mkPulseWireOR;
   Reg#(Bool) enable_interrupt <- mkReg(False);
   
   // forward interrupt status
   rule handle_interrupt_send(inputQ.notEmpty && enable_interrupt);
      interrupt.send;
   endrule
   
   // look at (but don't dequeue) memory request and broadcast the result
   rule peek_mem_req;
      let req = peekGet(client.request);
      memrw <= req.rw;
      memaddr <= req.addr;
   endrule

   // handle writes to buffer
   (* preempts="write_to_outQ,write_to_outQ_full" *)
   rule write_to_outQ((memrw==MemWrite) && (memaddr==0));
      let req <- client.request.get();
      // enqueue data assuming software used the ChartToSendT bit format
	  $display("%05t: DEBUG  - write_to_outQ ", $time);
      outQ.enq(unpack(pack(req.data)));
      outQlevel_dec.send;
      //client.response.put(tagged Invalid);
   endrule
   rule write_to_outQ_full((memrw==MemWrite) && (memaddr==0));
      let req <- client.request.get();
      // drop request on the floor since the buffer is full
      $display("%05t: DEBUG  - internal ERROR: LoopbackUART - inputQ is full, dropping request",$time);
      //client.response.put(tagged Invalid);
   endrule
   
   // handle reads from buffer
   rule read_inputQ((memrw==MemRead) && (memaddr==0));
      let req <- client.request.get();
      Int#(32) c;
	  if(inputQ.notEmpty) begin
	     c = unpack({24'b0,pack(inputQ.first)});
	     inputQ.deq;
	     // record that the buffer level has increased only after
	     // a character has left the final buffer (inputQ)
         outQlevel_inc.send();
      end else
         c = -1;
      client.response.put(tagged Valid unpack(pack(c)));
   endrule
   
   // handle writes to the status/control register
   (* preempts="write_to_control,(handle_outQlevel_inc, handle_outQlevel_dec)" *)
   rule write_to_control((memrw==MemWrite) && (memaddr==1));
      let req <- client.request.get();
      let b = pack(req.data);
      enable_interrupt <= b[0]==1;
      if(b[1]==1) begin
	     $display("%05t: DEBUG  - doing reset",$time);
	     // reset FIFOs
	     outQ.clear;
	     outQlevel <= `output_buf_size;
	     inputQ.clear;
	     char_being_delayed.clear;
	     cleartimer.send();
      end
	  $display("%05t: DEBUG  - enqueing invalid response in write_to_control ", $time);
      //client.response.put(tagged Invalid);
   endrule

   // handle inc/dec of buffer level
   rule handle_outQlevel_inc(outQlevel_inc && !outQlevel_dec);
      outQlevel <= outQlevel+1;
   endrule
   rule handle_outQlevel_dec(!outQlevel_inc && outQlevel_dec);
      outQlevel <= outQlevel-1;
   endrule

   // handle reads of status/control register
   rule read_from_control((memrw==MemRead) && (memaddr==1));
      let req <- client.request.get();
      $display("%05t: DEBUG  - returning status read",$time);
      // return interrupt enable flag
      let status_bits = {pack(outQlevel), 15'b0, pack(enable_interrupt)};
	  Maybe#(UInt#(32)) rtn = tagged Valid unpack(status_bits);
      client.response.put(rtn);
	  `ifdef DEBUG			
		$display("Sending %x from loopback uart at time %t. Response was %s", status_bits, $time(), rtn matches tagged Valid .val ? "Valid":"Invalid");
	`endif
   endrule
   
   // count down timer for next character to be inserted into inputQ
   rule count_down_timer(timer!=0);
      if(cleartimer)
	 timer <= 0;
      else
	 timer <= timer-1;
   endrule

   // get next character that needs to be timed
   rule next_char_being_processed(timer==0);
      $display("%05t: DEBUG  - timer=0 and deq outQ",$time);
      let b = outQ.first;
      outQ.deq;
      char_being_delayed.enq(b.char);
      timer <= b.delay;
   endrule
   
   // forward delayed character to inputQ
   rule char_ready_to_send((timer==0) && inputQ.notFull);
      $display("%05t: DEBUG  - timer=0 and enq inputQ",$time);
      inputQ.enq(char_being_delayed.first);
      char_being_delayed.deq;
   endrule
   
endmodule



/*****************************************************************************
 Abstract version of the LoopbackUART
 ====================================
 
 Provides a simple abstract interface for simulation purposes with a
 Server interface to send memory requests and receive responses.
 *****************************************************************************/

interface LoopbackUART_Abstract_Ifc;
   interface Server#(MemAccessPacketT#(`word_address_width),ReturnedDataT) server;
   method Bool interrupt;
endinterface

// helper interface and module
interface BufferServer2ClientIfc#(type requestT, type responseT);
   interface Server#(requestT, responseT) server;
   interface Client#(requestT, responseT) client;
endinterface

module mkBufferServer2Client(BufferServer2ClientIfc#(requestT, responseT))
   provisos(Bits#(responseT, responseTwidth), Bits#(requestT, requestTwidth));
   FIFO#(requestT) req <- mkLFIFO;
   FIFO#(responseT) res <- mkLFIFO;
   interface Server server;
      interface request = toPut(req);
      interface response = toGet(res);
   endinterface
   interface Client client;
      interface request = toGet(req);
      interface response = toPut(res);
   endinterface
endmodule


module mkLoopbackUART_Abstract(LoopbackUART_Abstract_Ifc);
   PulseWire ipw <- mkPulseWire;
   BufferServer2ClientIfc#(MemAccessPacketT#(`word_address_width),ReturnedDataT)
      bufs2c <- mkBufferServer2Client;
   Empty loopback_uart <- mkLoopbackUART_internal(bufs2c.client,ipw);
   method Bool interrupt;
      return ipw;
   endmethod
   interface Server server = bufs2c.server;
endmodule


module mkUnitTest_LoopbackUART_Abstract(Empty);

   LoopbackUART_Abstract_Ifc dut <- mkLoopbackUART_Abstract;
   Reg#(UInt#(32)) jr <- mkReg(0);
   Reg#(UInt#(32)) numerr <- mkReg(0);
   
   Stmt test_seq =
   (seq
       $display("%05t: INFO   - starting LoopbackUART unit test",$time);
       action
	  let msg=33;
	  $display("%5t: INFO   - Writing message (ready to be cleared) = 0x%08x",$time,msg);
	  dut.server.request.put(MemAccessPacketT{
	     rw: MemWrite, addr: 0, data: msg});
       endaction
       action
	  // accept null responses on writes
	  let rtn <- dut.server.response.get();
	  if(dut.interrupt)
	     begin
		$display("%05t: ERROR  - interrupt when not enabled",$time);
		numerr <= numerr+1;
	     end
       endaction
       action
	  $display("%5t: INFO   - enabling interrupt",$time);
	  dut.server.request.put(MemAccessPacketT{
	     rw: MemWrite, addr: 1, data: 1});
       endaction
       action	  // accept null responses on writes
	  let rtn <- dut.server.response.get();
       endaction
       action
	  if(dut.interrupt)
	     $display("%05t: PASSED - interrupt correctly received",$time);
	  else
	     $display("%05t: ERROR  - interrupt missing",$time);
       endaction
       action
	  $display("%5t: INFO   - requesting status",$time);
	  dut.server.request.put(MemAccessPacketT{
	     rw: MemRead, addr: 1, data: 0});
       endaction
       action
	  let rtn <- dut.server.response.get();
	  let bufspace = fromMaybe(unpack(pack(-1)),rtn)>>16;
	  if(bufspace == (`output_buf_size-1))
	     $display("%05t: PASSED - buf space correctly reported",$time);
	  else
	     begin
		$display("%05t: ERROR  - bufspace=%1d but expecting %1d",
			 $time, bufspace, `output_buf_size);
		numerr <= numerr+1;
	     end
       endaction
       action
	  $display("%5t: INFO   - Reset loop-back UART",$time);
	  dut.server.request.put(MemAccessPacketT{
	     rw: MemWrite, addr: 1, data: 3});
       endaction
       action
	  // accept null responses on writes
	  let rtn <- dut.server.response.get();
	  if(dut.interrupt)
	     begin
		$display("%05t: ERROR  - interrupt after reset",$time);
		numerr <= numerr+1;
	     end
       endaction
       action
	  dut.server.request.put(MemAccessPacketT{
	     rw: MemRead, addr: 1, data: 0});
       endaction
       action
	  let rtn <- dut.server.response.get();
	  let bufspace = fromMaybe(unpack(pack(-1)),rtn)>>16;
	  if(bufspace == `output_buf_size)
	     $display("%05t: PASSED - buf space correctly reported",$time);
	  else
	     begin
		$display("%05t: ERROR  - bufspace=%1d but expecting %1d",
			 bufspace, `output_buf_size);
		numerr <= numerr+1;
	     end
       endaction
       $display("%05t: INFO   - Writing test stimulus",$time);
       for(jr<=0; jr<=10; jr<=jr+1)
	  par
	     action
		UInt#(32) msg = ((100-jr*10)<<8) | jr;
		$display("%5t: INFO   - Writing message = 0x%08x",$time,msg);
		dut.server.request.put(MemAccessPacketT{
		   rw: MemWrite, addr: 0, data: msg});
	     endaction
	     action  // accept null responses on writes
		let rtn <- dut.server.response.get();
	     endaction
	  endpar
       $display("%05t: INFO   - Receiving",$time);
       jr<=0;
       while(jr<10)
	  seq
	     if(dut.interrupt)
		seq
		   dut.server.request.put(MemAccessPacketT{
		      rw: MemRead,
		      addr: 0,
		      data: 0});
		   action
		      // should have a char to read so inc. loop counter
    		      jr <= jr+1;
		      let c <- dut.server.response.get();
		      if(isValid(c))
			 begin
			    Int#(32) i = unpack(pack(fromMaybe(?,c)));
			    $display("%05t: INFO   - received char code = %2d",$time,i);
			 end
		      else
			 begin
			    $display("%05t: ERROR  - received an Invalid");
			    numerr <= numerr+1;
			 end
		   endaction
		endseq
	  endseq
       if(numerr==0)
	  $display("%05t: The End- ALL PASSED",$time);
       else
	  $display("%05t: The End- FAILED with %d errors",$time,numerr);
    endseq);
   
   let test_seq_FSM <- mkAutoFSM(test_seq);
endmodule



/*****************************************************************************
 Avalon Memory-Mapped version of the LoopbackUART
 ================================================
 
 Provides an avalon memory-mapped LoopbackUART device with interrupt.
 *****************************************************************************/

(* always_ready, always_enabled *)
interface LoopbackUART_Avalon_Ifc;
   // avalon memory-mapped slave interface using Altera's default name (avs)
   interface AvalonSlaveIfc#(`word_address_width) avs;
   // avalon interrupt using Altera's default name (ins)
   method Bool ins;
endinterface

(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkLoopbackUART_Avalon(LoopbackUART_Avalon_Ifc);
   // instantiate the avalon memory-mapped slave interface
   AvalonSlave2ClientIfc#(`word_address_width) mmslave <- mkAvalonSlave2Client;
   // provide a wire to transport the interrup
   PulseWire ipw <- mkPulseWire;
   // instantiate the main implementation
   Empty imp <- mkLoopbackUART_internal(mmslave.client,ipw);
   // connect up the avalon memory-mapped slave interface
   interface avs = mmslave.avs;
   // provide the interrupt - note that Qsys expects it to be inverted
   method Bool ins;
      return !ipw;
   endmethod
endmodule


endpackage: LoopbackUART
