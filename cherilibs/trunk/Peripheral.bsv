/*-
 * Copyright (c) 2013 Philip Withnall
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2014 Colin Rothwell
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
 ******************************************************************************
 *
 * Author: Robert Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Interface for memory mapped peripherals written in BlueSpec.
 * CR: There used to be an actual bus here. Now peripherals are written for the
 * AxiBus. There is a wrapper called mkBlueBusPeripheralToTLM to support this
 * interface now.
 *
 ******************************************************************************/

import ClientServer::*;
import Clocks::*;
import Connectable::*;
import Vector::*;
import GetPut::*;
import MasterSlave::*;
import MemTypes::*;
import DefaultValue :: *;

import Debug::*;
import Library::*;
import FIFO::*;
import FIFOF::*;

`ifdef MULTI
  import FIFOF::*;
  import MemTypes::*;
`endif

`include "parameters.bsv"

// Type for register access requests
typedef struct {
   Bit#(23) offset; // Byte offset of the access
   Bool      read; // Is the request a read or a write?
   Bit#(64)  data;
} PerifReq deriving (Bits, FShow);

// Type for read response. NB writes do not give a response.
typedef Bit#(64) PerifResp;

// numIrqs is the number of IRQ lines this peripheral exports (which may be 0)
interface Peripheral#(numeric type numIrqs);
  interface Slave#(CheriMemRequest64, CheriMemResponse64) slave;
  (* always_ready, always_enabled *)
  method Bit#(numIrqs) getIrqs();
endinterface

// A simple peripheral which implements a register which increments
// every time it is read. Serves as an example for blue bus and is
// also useful for testing cache instructions, and potentially useful
// for getting a unique ID in a multiprocessor context.
(*synthesize*)
module mkCountPerif(Peripheral#(0));
  FIFOF#(CheriMemRequest64)   req_fifo <- mkFIFOF1;
  FIFOF#(CheriMemResponse64) resp_fifo <- mkFIFOF1;
  Reg#(Bit#(16))               count <- mkReg(0);
  
  rule handle_request;
    CheriMemRequest64 req <- toGet(req_fifo).get;
    CheriMemResponse64 resp = defaultValue;
    resp.masterID = req.masterID;
    resp.transactionID = req.transactionID;
    if (req.operation matches tagged Read .unused) begin
      count <= count + 1;
      resp.data.data = zeroExtend(count);
      resp.operation = tagged Read{last: True};
    end else
      resp.operation = tagged Write;
    resp_fifo.enq(resp);
  endrule
  
  interface Slave slave;
    interface request  = toCheckedPut(req_fifo);
    interface response = toCheckedGet(resp_fifo);
  endinterface

  method Bit#(numIrqs) getIrqs();
    return 0;
  endmethod: getIrqs
endmodule

// A catch-all peripheral for unmapped space.
(*synthesize*)
module mkNullPerif(Peripheral#(0));
  FIFOF#(CheriMemRequest64)   req_fifo <- mkFIFOF1;
  FIFOF#(CheriMemResponse64) resp_fifo <- mkFIFOF1;
  Reg#(Bit#(16))               count <- mkReg(0);
  
  rule handle_request;
    CheriMemRequest64 req <- toGet(req_fifo).get;
    CheriMemResponse64 resp = defaultValue;
    resp.masterID = req.masterID;
    resp.transactionID = req.transactionID;
    resp.data = unpack(0);
    if (req.operation matches tagged Read .unused) begin
      resp.operation = tagged Read{last: True};
    end else
      resp.operation = tagged Write;
    resp.error = BusError;
    resp_fifo.enq(resp);
  endrule
  
  interface Slave slave;
    interface request  = toCheckedPut(req_fifo);
    interface response = toCheckedGet(resp_fifo);
  endinterface

  method Bit#(numIrqs) getIrqs();
    return 0;
  endmethod: getIrqs
endmodule
