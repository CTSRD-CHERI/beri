/*-
 * Copyright (c) 2011 Jonathan Woodruff
 * Copyright (c) 2014 Alexandre Joannou
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
  Bluespec interface to merge Memory requests into a single 256-bit Memory interface.
  ==============================================================
  Jonathan Woodruff, July 2011
 *****************************************************************************/
package Merge;

import Debug::*;
import MIPS::*;
import GetPut::*;
import MasterSlave::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import MemTypes::*;
import Interconnect::*;
   
typedef Bit#(4) InterfaceT;

interface MergeIfc#(numeric type numIfc);
  interface Master#(CheriMemRequest, CheriMemResponse) merged;
  interface Vector#(numIfc, Slave#(CheriMemRequest, CheriMemResponse)) slave;
endinterface

module mkMerge(MergeIfc#(numIfc));
  Vector#(numIfc,  FIFOF#(CheriMemRequest))  req_fifos   <- replicateM(mkUGFIFOF);
  FIFOF#(CheriMemRequest)                    nextReq     <- mkBypassFIFOF;
  Vector#(numIfc,  FIFOF#(CheriMemResponse)) rsp_fifos   <- replicateM(mkFIFOF);
  FIFOF#(InterfaceT)                         pendingReqs <- mkSizedFIFOF(16);
  `ifdef MULTI
    Reg#(Bool)                                 scLock      <- mkReg(False);
    Reg#(InterfaceT)                           scLockPort  <- mkReg(0);
    Reg#(Bit#(8))                              arbiter     <- mkReg(0);
  `endif

  rule mergeInputs;
    Bool found = False;
    `ifdef MULTI
    Bit#(8) j = arbiter;
    for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
      if (found == False && req_fifos[j].notEmpty) begin
        debug2("merge", $display("%t : Choosing request from %d in Memory Merge interface", $time, j));
        nextReq.enq(req_fifos[j].first);
        if ((req_fifos[j].first.operation matches tagged Read .rop ? True : False)||
            (req_fifos[j].first.operation matches tagged Write .wop &&& wop.conditional ? True : False)) begin
          pendingReqs.enq(truncate(j));
          if (req_fifos[j].first.operation matches tagged Write .wop &&& wop.conditional) begin 
            debug2("merge", $display("Merge - Expecting L2 Response for req ", fshow(req_fifos[j].first)));
          end
        end
        req_fifos[j].deq();
        found = True;
      end
      j = j + 1;
      if (j >= fromInteger(valueOf(numIfc))-1) begin
        j = 0;
      end
    end
    if (arbiter >= fromInteger(valueOf(numIfc))-1) begin
      arbiter <= 0;
    end
    else begin
      arbiter <= arbiter + 1;
    end
   `else
    for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
      if (found == False && req_fifos[i].notEmpty) begin
        debug2("merge", $display("%t : Choosing request from %d in Memory Merge interface", $time, i));
        nextReq.enq(req_fifos[i].first);
        `ifndef MULTI
          case (req_fifos[i].first.operation) matches
            tagged Read .r : pendingReqs.enq(fromInteger(i));
          endcase
        `else
        //if ((req_fifos[i].first.operation matches tagged Read .r ? True : False) ||
        //    (req_fifos[i].first.operation matches tagged Write .w &&& w.conditional ? True : False)) begin
          pendingReqs.enq(fromInteger(i));
          if (req_fifos[i].first.operation matches tagged Write .w &&& w.conditional == True) begin 
            debug2("merge", $display("Merge - Expecting L2 Response for pending request: ", fshow(req_fifos[i].first)));
          end
        //end
        `endif
        req_fifos[i].deq();
        found = True;
      end
    end
    `endif
  endrule
  
  Vector#(numIfc, Slave#(CheriMemRequest, CheriMemResponse)) slaves;
  for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
    slaves [i] = interface Slave;
      interface response = toCheckedGet(rsp_fifos[i]);
      interface request  = toCheckedPut(req_fifos[i]);
    endinterface;
  end
  
  interface slave = slaves;
  
  interface Master merged;
    interface CheckedGet request = toCheckedGet(nextReq);
    interface CheckedPut response;
      method Bool canPut = (rsp_fifos[pendingReqs.first].notFull && pendingReqs.notEmpty);
      method Action put(CheriMemResponse resp);
        rsp_fifos[pendingReqs.first].enq(resp);
        if (resp.operation matches tagged Read .rr) begin
          if (rr.last) pendingReqs.deq;
        end else pendingReqs.deq;
      endmethod
    endinterface
  endinterface
endmodule

module mkMergeFast(MergeIfc#(numIfc));
  FIFOF#(CheriMemRequest)      nextReq     <- mkBypassFIFOF;
  FIFOF#(CheriMemResponse)     rsp_fifo    <- mkBypassFIFOF;
  Vector#(numIfc, Wire#(Bool)) fired       <- replicateM(mkDWire(False));
  Vector#(numIfc, Bool)        block;
  
  block[0] = False;
  for (Integer i=1; i<valueOf(numIfc); i=i+1) begin
    block[i] = block[i-1] || fired[i-1];
  end
  
  rule debugRule;
    debug2("merge", $write("<time %0t Merge> ", $time));
    /*for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
      debug2("l2cache", $write(" block[%x]=%x ",i,block[i]));
    end*/
    debug2("merge", $write("rsp_fifo.notFull: %x\n", rsp_fifo.notFull));
  endrule
  
  Vector#(numIfc, Slave#(CheriMemRequest, CheriMemResponse)) slaves;
  for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
    slaves [i] = interface Slave;
      interface CheckedGet response;
        method Bool canGet = (rsp_fifo.notEmpty && rsp_fifo.first.masterID == fromInteger(i));
        method CheriMemResponse peek if (rsp_fifo.first.masterID == fromInteger(i));
          return rsp_fifo.first;
        endmethod
        method ActionValue#(CheriMemResponse) get if (rsp_fifo.first.masterID == fromInteger(i));
          CheriMemResponse resp <- toGet(rsp_fifo).get;
          debug2("merge", $display("<time %0t, Merge %x> giving Response: ", 
            $time, i, fshow(resp)));
          return resp;
        endmethod
      endinterface
      interface CheckedPut request;
        method Bool canPut = (!block[i] && nextReq.notFull);
        method Action put(CheriMemRequest req) if (!block[i]);
          nextReq.enq(req);
          debug2("merge", $display("<time %0t, Merge %x> passing request: ", $time, i, fshow(req)));
          fired[i] <= True;
        endmethod
      endinterface
    endinterface;
  end
  
  interface slave = slaves;
  
  interface Master merged;
    interface CheckedGet request  = toCheckedGet(nextReq);
    interface CheckedPut response = toCheckedPut(rsp_fifo);
  endinterface
endmodule

endpackage
