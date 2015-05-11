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

/******************************************************************************
 * Unit Test UART16550
 * ===================
 * Simon Moore, July 2013
 ******************************************************************************/

package UnitTestUart16550;

import FIFO::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import Avalon2ClientServer::*;
import StmtFSM::*;
import Uart16550simpler::*;


// TODO: move the following into Avalon2ClientServer?
// Provide a simple mechanism to connect an Avalon master to a slave
// at the physical level
module mkConnectionAvalonMaster2Slave(
   AvalonMasterIfc#(word_address_width) master,
   AvalonSlaveIfc#(word_address_width) slave,
   Empty unused_default_ifc);
  
//  provisos(Max#(word_address_width,30,30));

  Wire#(UInt#(TAdd#(2,word_address_width))) addr <- mkBypassWire;
  Wire#(AvalonWordT) writedata <- mkBypassWire;
  Wire#(AvalonWordT) readdata <- mkBypassWire;
  Wire#(Bool) read <- mkBypassWire;
  Wire#(Bool) write <- mkBypassWire;
  Wire#(Bool) waitrequest <- mkBypassWire;
  
  (* no_implicit_conditions *)
  rule do_read_m;
    read <= master.m0_read;
  endrule

  (* no_implicit_conditions *)
  rule do_write_m;
    write <= master.m0_write;
  endrule

  (* no_implicit_conditions *)
  rule do_addr_m;
    addr <= master.m0_address;
  endrule

  (* no_implicit_conditions *)
  rule do_rdata_m;
    writedata <= master.m0_writedata;
  endrule

  (* no_implicit_conditions *)
  rule do_inputs_m;
    master.m0(readdata, waitrequest);
  endrule
  
  (* no_implicit_conditions *)
  rule do_inputs_s;
    slave.s0(truncate(addr>>2), writedata, write, read);
  endrule

  (* no_implicit_conditions *)
  rule do_readdata_s;
    readdata <= slave.s0_readdata;
  endrule
  
  (* no_implicit_conditions *)
  rule do_waitrequest_s;
    waitrequest <= slave.s0_waitrequest;
  endrule
  
endmodule



typedef struct {
   MemAccessPacketT#(3) req;
   ReturnedDataT        correct;
   Bool                 read_response;
   } TestMemTransactionT deriving (Bits,Eq);


module mkUnitTestUart16550(Empty);

  // design under test
  Uart16550_Avalon_Ifc dut <- mkUart16550_Avalon;
  
  // Avalon master used to drive Avalon slace on dut
  Server2AvalonMasterIfc#(3) master <- mkServer2AvalonMaster;
  
  // Connect Avalon master to dut's slave
  mkConnectionAvalonMaster2Slave(master.avm, dut.avs);
  
  // FIFO to send tests
  FIFOF#(TestMemTransactionT) memtestbuf <- mkLFIFOF;
  FIFO#(ReturnedDataT)       memtestresp <- mkFIFO;
  
  // count fails
  Reg#(UInt#(32))      fail <- mkReg(0);
  PulseWire         fail_pw <- mkPulseWireOR;

  // state during simulation
  Reg#(Bool)       tx_empty <- mkReg(False);
  Reg#(Bool)       rx_ready <- mkReg(False);
  Reg#(UInt#(8))       chtx <- mkReg(65);
  Reg#(UInt#(8))       chrx <- mkReg(65);
  Reg#(bit)        last_stx <- mkReg(0);
  Reg#(bit)  prev_interrupt <- mkReg(0);
  
  // function to convert UART_ADDR_T enumerations to Avalon word addresses
  function UInt#(3) uart2addr(UART_ADDR_T a) = unpack(pack(a));

  function memtest(MemAccessT rw, UART_ADDR_T addr, AvalonWordT data, ReturnedDataT correct);
    action
      memtestbuf.enq(TestMemTransactionT{
	 req: 	  MemAccessPacketT{
	    rw:   rw,
	    addr: uart2addr(addr),
	    data: data},
	 correct: correct,
	 read_response: False});
    endaction
  endfunction
  
  function memreadrequest(UART_ADDR_T addr);
    action
      memtestbuf.enq(TestMemTransactionT{
	 req: 	  MemAccessPacketT{
	    rw:   MemRead,
	    addr: uart2addr(addr),
	    data: 0},
	 correct: tagged Valid 0, // not checked in this instance
	 read_response: True});
    endaction
  endfunction
  
  Stmt seq_mem_tests =
  (seq
     master.server.request.put(memtestbuf.first.req);
     action
       let c = memtestbuf.first.correct;
       let r = memtestbuf.first.req;
       Bool response_required = memtestbuf.first.read_response;
       memtestbuf.deq;
       UART_ADDR_T a = unpack(pack(r.addr));
       ReturnedDataT rtn <- master.server.response.get;
       if(response_required)
	 memtestresp.enq(rtn);
       else
       case(memtestbuf.first.req.rw)
	 MemRead:
	 begin
	   $write("%05t: read of ", $time);
	   $write(fshow(a));
	   if(!isValid(rtn))
	     begin
	       $display(" didn't return data - FAIL");
	       fail_pw.send();
	     end
	   else if(c!=rtn)
	     begin
	       $display(" returned 0x%08x rather than 0x%08x - FAIL",
		  fromMaybe(0,rtn), fromMaybe(0,c));
	       fail_pw.send();
	     end
	   else
	     $display(" returned 0x%02x = %3d - PASS", fromMaybe(0,rtn), fromMaybe(0,rtn));
	 end
	 MemWrite: 
	 begin
	   $write("%05t: writing 0x%02x = %3d to ", $time, r.data, r.data);
	   $write(fshow(a));
	   if(isValid(rtn))
	     begin
	       $display(" returned data in error - FAIL");
	       fail_pw.send();
	     end
	   else
	     $display(" completed - PASS");
	 end
	 default:
	 begin
	   $display("%05t: unknown or null memory transaction - FAIL", $time);
	   fail_pw.send();
	 end
       endcase
     endaction
   endseq);
  
  Integer baud = 115200;
  Integer clk_freq = 10000000; // 10MHz clock for testing
//  Integer uart_div = clk_freq / (16*baud); // UART clock divider
  Integer uart_div = 2;
  UInt#(8) last_character = 90;
  
  Stmt tst_dut =
  (seq
     // test that the scratch register can be written to and read from
     memtest(MemWrite, UART_ADDR_SCRATCH, 32'h12345678, tagged Invalid);
     memtest(MemRead,  UART_ADDR_SCRATCH, 0,            tagged Valid 32'h78);
     memtest(MemWrite, UART_ADDR_SCRATCH, 32'h00000012, tagged Invalid);
     memtest(MemRead,  UART_ADDR_SCRATCH, 32'hdeaddead, tagged Valid 32'h12);
     // uart initialisation
     memtest(MemWrite, UART_ADDR_LINE_CTRL,    32'h83, tagged Invalid); // access divisor registers
     memtest(MemWrite, unpack(1), (fromInteger(uart_div)>>8) & 32'h0ff, tagged Invalid);
     memtest(MemWrite, unpack(0), fromInteger(uart_div) & 32'h0ff, tagged Invalid);
     memtest(MemWrite, UART_ADDR_LINE_CTRL,    32'h03, tagged Invalid); // 8-bit data, 1-stop, no parity
     memtest(MemWrite, UART_ADDR_INT_ID_FIFO_CTRL, 32'h06, tagged Invalid); // interrupt every 1 byte, clear FIFO
     memtest(MemWrite, UART_ADDR_INT_ENABLE,   32'h00, tagged Invalid); // disable interrupts

     // loop to send and receive characters using polled mode
     while(chrx <= last_character)
       seq
	 memreadrequest(UART_ADDR_LINE_STATUS);
	 action
	   Bit#(8) d = truncate(pack(fromMaybe(~0,memtestresp.first)));
	   // $display("%05t: status=0x%02x", $time, d);
	   memtestresp.deq;
	   tx_empty <= d[5]==1;
	   rx_ready <= d[0]==1;
	 endaction
	 if(rx_ready)
	   seq
	     memtest(MemRead, UART_ADDR_DATA, 0, tagged Valid zeroExtend(chrx));
	     chrx <= chrx+1;
	   endseq
	 if(tx_empty && (chtx <= last_character))
	   seq
	     memtest(MemWrite, UART_ADDR_DATA, zeroExtend(chtx), tagged Invalid);
	     chtx <= chtx+1;
	   endseq
       endseq

     // test interrupt mode
     memtest(MemWrite, UART_ADDR_INT_ID_FIFO_CTRL, 32'h06, tagged Invalid); // interrupt every 1 byte, clear FIFO
     memtest(MemWrite, UART_ADDR_INT_ENABLE, 32'h01, tagged Invalid); // enable received data interrupt
     memtest(MemRead,  UART_ADDR_INT_ENABLE, 32'hdeaddead, tagged Valid 32'h01); // check IE reg

     chtx <= 70;
     while(chtx <= 80)
       seq
	 action
	   memtest(MemWrite, UART_ADDR_DATA, zeroExtend(chtx), tagged Invalid);
	   chtx <= chtx+1;
	 endaction
       endseq
   
     $display("%05t: wait for a while so that data will back up in RX FIFO", $time);
     delay(10000);

     chrx <= 70;
     while(chrx <= 80)
       seq
	 if(dut.irq==1)
	   seq
	     // read interrupt cause register
   	     memreadrequest(UART_ADDR_INT_ID_FIFO_CTRL);
	     action
	       Bit#(4) d = truncate(pack(fromMaybe(~0,memtestresp.first)));
	       if(d!=4'b0100)
		 begin
		   $display("%05t: ERROR: interrupt cause = 0x%1x but expecting 4'b0100", $time, d);
		   fail_pw.send();
		 end
	       memtestresp.deq;
	     endaction
	     action
	       memtest(MemRead, UART_ADDR_DATA, 0, tagged Valid zeroExtend(chrx));
	       chrx <= chrx+1;
	     endaction
	   endseq
       endseq

     await(!memtestbuf.notEmpty);
     $display("%0t5: The End", $time);
     if(fail==0)
       $display("PASSED");
     else
       $display("FAILED");
   endseq);
  
  let do_tst_dut <- mkAutoFSM(tst_dut);
  let do_seq_mem_tests <- mkFSM(seq_mem_tests);
  
  rule start_seq_mem_tests;
    do_seq_mem_tests.start;
  endrule
  
  rule monitor_interrupts;
    let i = dut.irq;
    prev_interrupt <= i;
    if((i==1) && (prev_interrupt==0))
      $display("%05t: >>>>>>>>>>>>>>> INTERRUPT <<<<<<<<<<<<<<<", $time);
    if((i==0) && (prev_interrupt==1))
      $display("%05t: --------------- interrupt lowered ---------------", $time);
  endrule    
  
  rule count_fails(fail_pw);
    $display("%05t: fail++", $time);
    fail <= fail+1;
  endrule
  
  rule loop_back_tx_rx;
    bit stx = dut.coe_rs232.modem_output_stx;
    bit srx = stx;
    bit cts = 0;
    bit dsr = 0;
    bit ri  = 0;
    bit dcd = 0;
    dut.coe_rs232.modem_input(srx, cts, dsr, ri, dcd);
    last_stx <= stx;
    //if(stx!=last_stx)
    //  $display("%05t: UnitTest: stx changed to %1d", $time, stx);
  endrule
  
endmodule


endpackage
