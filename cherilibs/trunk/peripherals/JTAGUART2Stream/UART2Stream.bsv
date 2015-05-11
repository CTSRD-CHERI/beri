/*-
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
 *
 *****************************************************************************

 UART2Stream
 ===========
 
 Provides an adapter between a JTAG UART and a pair of byte streams, one
 for input and the other for output.
 
 Altera's JTAG UART has the following options:
 - read and write buffer length
     - the following settings were tried but made no impact to performace
       but note that 1024 byte length causes the FIFOs to fit nicely into M9K
       BRAMs which may be an advantage
     - both set to 64 bytes   - 130kB/s to 140kB/s transfer rate
     - both set to 1024 bytes - 130kB/s to 140kB/s transfer rate
 - irqs are ignored so irq options are irrelevant
 - "prepared interactive windows"
     - the setting doesn't appear to matter (possibly for simulation only?)
 
 To transfer binary files using nios2-terminal, first cancel the interrupt
 keys vis:
   stty intr ''
   stty quit ''
   stty susp ''

 and invoke vis (quiet + ignore ctrl-d):
    nios2-terminal -q --no-quit-on-ctrl-d
 
 *****************************************************************************/


package UART2Stream;

import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Connectable::*;
import ClientServer::*;
import AvalonStreaming::*;
import Avalon2ClientServer::*;


typedef UInt#(8) StreamT;
typedef enum {S_Start, S_JTAG_Status, S_Send_Data, S_Send_Data_Ack, S_Receive_Data, S_Receive_Data_Check} UART2StreamState deriving (Bits,Eq);

interface UART2Stream;
  interface AvalonStreamSinkPhysicalIfc#(StreamT)   asi; // Avalon stream in
  interface AvalonStreamSourcePhysicalIfc#(StreamT) aso; // Avalon stream out
  interface AvalonMasterIfc#(1)                     avm; // Avalon master (connect to JTAG UART)
endinterface


(* synthesize,
 reset_prefix = "csi_clockreset_reset_n",
 clock_prefix = "csi_clockreset_clk" *)
module mkUART2Stream(UART2Stream);
  
  AvalonStreamSinkIfc#(StreamT)   asi_adapter <- mkAvalonStreamSink2Get;
  AvalonStreamSourceIfc#(StreamT) aso_adapter <- mkPut2AvalonStreamSource;
  Server2AvalonMasterIfc#(1)      avm_adapter <- mkServer2AvalonMaster;

  Reg#(UInt#(16))                 write_space <- mkReg(0);
  FIFOF#(UInt#(8))                aso_buf     <- mkFIFOF;
  FIFOF#(UInt#(8))                asi_buf     <- mkFIFOF;
  Reg#(UART2StreamState)          state       <- mkReg(S_Start);

  mkConnection(toGet(aso_buf), aso_adapter.tx);
  mkConnection(asi_adapter.rx, toPut(asi_buf));
  
  rule start (state==S_Start);
     // first read the JTAG status
    avm_adapter.server.request.put(MemAccessPacketT{rw: MemRead, addr: 1, data: 0});
    state <= S_JTAG_Status;
  endrule

  rule jtag_status (state==S_JTAG_Status);
    let maybe_d <- avm_adapter.server.response.get();
    Bit#(32) d = pack(fromMaybe(0, maybe_d));
    UInt#(16) space = unpack(d[31:16]);  // space given by upper 16-bits of the status register
    write_space <= space;
    state <= (space>1) && (asi_buf.notEmpty) ? S_Send_Data : S_Receive_Data;
  endrule
  
  rule send_data (state==S_Send_Data);
     // now send data if data available and the JTAG buffer isn't full
    AvalonWordT d = unpack(zeroExtend(pack(asi_buf.first)));
    asi_buf.deq;
    avm_adapter.server.request.put(MemAccessPacketT{rw: MemWrite, addr: 0, data: d});
    state <= S_Send_Data_Ack;
  endrule
  
  rule send_data_ack (state==S_Send_Data_Ack);
    let bit_bucket <- avm_adapter.server.response.get();
    state <= S_Receive_Data;
  endrule
  
  rule receive_data (state==S_Receive_Data);
    if(aso_buf.notFull)
      begin
	avm_adapter.server.request.put(MemAccessPacketT{rw: MemRead, addr: 0, data: 0});
	state <= S_Receive_Data_Check;
      end
    else
      state <= S_Start;
  endrule

  rule receive_data_check (state==S_Receive_Data_Check);
    let maybe_data <- avm_adapter.server.response.get();
    Bit#(32) b = pack(fromMaybe(0, maybe_data));
    Bool valid = unpack(b[15]);
    if(valid)
      aso_buf.enq(unpack(b[7:0]));
    state <= S_Start;
  endrule
  
  interface asi = asi_adapter.physical;
  interface aso = aso_adapter.physical;
  interface avm = avm_adapter.avm;
  
endmodule



endpackage
