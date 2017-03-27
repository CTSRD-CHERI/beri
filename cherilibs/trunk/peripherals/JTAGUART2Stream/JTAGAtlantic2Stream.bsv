/*-
 * Copyright (c) 2012 Simon W. Moore
 * Copyright (c) 2016 A. Theodore Markettos
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

 JTAGAtlantic2Stream
 ===========
 
 Provides an adapter between a JTAG UART and a pair of byte streams, one
 for input and the other for output.  We use the undocumented 'JTAG Atlantic'
 interface to JTAG UART component to avoid having to use the Avalon MM port
 Altera provides

 We provide an external parameter:
   jtag_uart_instance_id: the instance number to be supplied to nios2-terminal
 
 The JTAG Atlantic Verilog component also provides some parameters we define here
 and don't currently export:
   log2rx: log2 size of receive buffer - set to 6 (ie buffer=64)
   log2tx: log2 size of transmit buffer - set to 6 (ie buffer=64)
   instance_auto: assign instance id automatically - set to false

 To match the UART2Stream interface we have an additional Avalon master port,
 that we don't use.

 To transfer binary files using nios2-terminal, first cancel the interrupt
 keys vis:
   stty intr ''
   stty quit ''
   stty susp ''

 and invoke vis (quiet + ignore ctrl-d):
    nios2-terminal -q --no-quit-on-ctrl-d
 
 *****************************************************************************/


package JTAGAtlantic2Stream;

import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Connectable::*;
import ClientServer::*;
import AvalonStreaming::*;
import Avalon2ClientServer::*;
import AlteraJtagUart::*;

typedef Bit#(8) StreamT;
typedef enum {S_Start, S_JTAG_Status, S_Send_Data, S_Send_Data_Ack, S_Receive_Data, S_Receive_Data_Check} JTAGAtlantic2StreamState deriving (Bits,Eq);

interface JTAGAtlantic2Stream;
  interface AvalonStreamSinkPhysicalIfc#(StreamT)   asi; // Avalon stream in
  interface AvalonStreamSourcePhysicalIfc#(StreamT) aso; // Avalon stream out
  interface AvalonMasterIfc#(1)                     avm; // Avalon master (connect to JTAG UART)
endinterface


(* synthesize,
 reset_prefix = "csi_clockreset_reset_n",
 clock_prefix = "csi_clockreset_clk" *)
module mkJTAGAtlantic2Stream #(parameter Bit#(8) jtag_uart_instance_id) (JTAGAtlantic2Stream);
  
  AvalonStreamSinkIfc#(StreamT)   asi_adapter <- mkAvalonStreamSink2Get;
  AvalonStreamSourceIfc#(StreamT) aso_adapter <- mkPut2AvalonStreamSource;
  // set FIFO depth to be 1024 (2^10) bytes in each direction
  AlteraJtagUart		  uart        <- mkAlteraJtagUart(10,10,jtag_uart_instance_id, 0);

  mkConnection(uart.rx, aso_adapter.tx);
  mkConnection(asi_adapter.rx, uart.tx);
  
  interface asi = asi_adapter.physical;
  interface aso = aso_adapter.physical;
  
endmodule



endpackage
