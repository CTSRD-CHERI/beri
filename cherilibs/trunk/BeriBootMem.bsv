/*-
 * Copyright (c) 2013 Jonathan Woodruff
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
 */

/*****************************************************************************
  BeriBootMem
  ==============================================================
  Jonathan Woodruff, October 2010, 2013
 *****************************************************************************/
package BeriBootMem;

import Vector::*;
import FIFO ::*;
import FIFOF ::*;
import SpecialFIFOs::*;
import BRAM::*;
import Peripheral::*;
import MemTypes::*;
import MasterSlave::*;
import ClientServer::*;
import Debug::*;

`ifdef VERIFY2

import Bram :: *;
`endif
    
typedef enum {Serving, Reading, Writing} MemState deriving (Bits, Eq);

// This is like a banked BRAM, except it uses one BRAM, and incurs a four cycle
// latency for each request.
(*synthesize*)
module mkBeriBootMemServer(BRAMServerBE#(Bit#(13), Bit#(64), 8));
  `ifndef VERIFY2
    BRAM_Configure cfg = defaultValue;
    cfg.memorySize = 65536/8; // full size
    cfg.loadFormat = tagged Hex "mem64.hex";
    BRAM2Port#(Bit#(13), Vector#(8, Bit#(8))) mem <- mkBRAM2Server(cfg);
  `else
    Bram#(Bit#(13), Vector#(8, Bit#(8))) mem <- mkBram();
  `endif
  
  FIFO#(BRAMRequestBE#(Bit#(13), Vector#(8, Bit#(8)), 8)) req <- mkLFIFO;
  FIFO#(Bit#(64)) resp <- mkBypassFIFO;
  Reg#(MemState) state <- mkReg(Serving);
  
  rule readRam(state == Serving);
	  `ifndef VERIFY2
    Vector#(8, Bit#(8)) readWord <- mem.portA.response.get();
    `else
    Vector#(8, Bit#(8)) readWord <- mem.readResp();
    `endif
    resp.enq(pack(readWord));
  endrule
  
  rule writeRam(state == Writing);
	  `ifndef VERIFY2
    Vector#(8, Bit#(8)) readWord <- mem.portA.response.get();
    `else
    Vector#(8, Bit#(8)) readWord <- mem.readResp();
    `endif

    Vector#(8, Bit#(8)) newWord;
    Vector#(8, Bit#(8)) writeWord = readWord;
    for (Integer i=0; i<8; i=i+1) begin
      Bit#(3) idx = fromInteger(i);
      newWord[i] = req.first.datain[idx];
      if (req.first.writeen[idx] == 1'b1) writeWord[i] = newWord[i];
    end

    `ifndef VERIFY2 
      mem.portB.request.put(BRAMRequest{
        write: True,
        responseOnWrite: False,
        address: req.first.address,
        datain: writeWord
      });
    `else
      mem.write(req.first.address, writeWord);
    `endif
    
    req.deq;
    state <= Serving;
  endrule
  
  interface Put request;
    method Action put(bramReqBE) if (state == Serving);
      if (bramReqBE.writeen != 0) begin
        req.enq(unpack(pack(bramReqBE)));
        state <= Writing;
      end
      `ifndef VERIFY2
        mem.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: bramReqBE.address,
                datain: ?
              });
      `else 
        mem.readReq(bramReqBE.address);
      `endif
    endmethod
  endinterface
  interface response = toGet(resp);
endmodule

(*synthesize*)
module mkBootMem(Peripheral#(0));
  FIFOF#(CheriMemRequest64)   req_fifo <- mkBypassFIFOF;
  FIFOF#(CheriMemResponse64) pend_fifo <- mkFIFOF;
  FIFOF#(CheriMemResponse64) resp_fifo <- mkBypassFIFOF;
  BRAMServerBE#(Bit#(13), Bit#(64), 8) bootMem <- mkBeriBootMemServer;
  
  rule handle_request;
    CheriMemRequest64 req <- toGet(req_fifo).get;
    debug2("bootMem", $display("<time %0t, bootMem> request ", $time, fshow(req)));
    CheriMemResponse64 resp = defaultValue;
    resp.masterID = req.masterID;
    resp.transactionID = req.transactionID;
    BRAMRequestBE#(Bit#(13), Bit#(64), 8) bramReq = BRAMRequestBE{
                  responseOnWrite: False,
                  address: {req.addr.lineNumber[12:0]},
                  datain: ?,
                  writeen: 8'b0
                };
    case (req.operation) matches
      tagged Read .rreq: begin
        resp.operation = tagged Read{data: ?, last: ?};
        bootMem.request.put(bramReq);
      end
      tagged Write .wreq: begin
        bramReq.datain = wreq.data.data;
        bramReq.writeen = pack(wreq.byteEnable);
        resp.operation = tagged Write;
        if (bramReq.writeen!=0) bootMem.request.put(bramReq);
      end
    endcase
    pend_fifo.enq(resp);
  endrule
  
  rule handle_read_response(pend_fifo.first.operation matches tagged Read .unused);
    CheriMemResponse64 resp <- toGet(pend_fifo).get;
    Data#(64) data = unpack(0);
    data.data <- bootMem.response.get();
    resp.operation = tagged Read{data: data, last: True};
    resp_fifo.enq(resp);
    debug2("bootMem", $display("<time %0t, bootMem> read response ", $time, fshow(resp)));
  endrule
  
  rule handle_write_response(pend_fifo.first.operation matches tagged Write .unused);
    CheriMemResponse64 resp <- toGet(pend_fifo).get;
    resp_fifo.enq(resp);
    debug2("bootMem", $display("<time %0t, bootMem> write response ", $time, fshow(resp)));
  endrule
  
  interface Slave slave;
    interface request  = toCheckedPut(req_fifo);
    interface response = toCheckedGet(resp_fifo);
  endinterface

  method Bit#(numIrqs) getIrqs();
    return 0;
  endmethod: getIrqs
endmodule

endpackage

