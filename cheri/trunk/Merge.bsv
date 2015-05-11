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

import MIPS::*;
import GetPut::*;
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import MemTypes::*;
   
typedef Bit#(4) InterfaceT;

interface MergeIfc#(numeric type numIfc);
  interface Client#(CheriMemRequest, CheriMemResponse) merged;
  interface Vector#(numIfc, Server#(CheriMemRequest, CheriMemResponse)) server;
endinterface

module mkMerge(MergeIfc#(numIfc));
  Vector#(numIfc,  FIFOF#(CheriMemRequest))    req_fifos     <- replicateM(mkUGFIFOF);
  FIFO#(CheriMemRequest)                       nextReq       <- mkBypassFIFO;
  Vector#(numIfc,  FIFOF#(CheriMemResponse))   rsp_fifos     <- replicateM(mkFIFOF);
  FIFO#(InterfaceT)                         pendingReqs   <- mkSizedFIFO(16);
  `ifdef MULTI
    Reg#(Bool)                              scLock        <- mkReg(False);
    Reg#(InterfaceT)                        scLockPort    <- mkReg(0);
    Reg#(Bit#(8))                                 arbiter       <- mkReg(0);
  `endif 

  rule mergeInputs;
    Bool found = False;
    `ifdef MULTI
    Bit#(8) j = arbiter;
    for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
      if (found == False && req_fifos[j].notEmpty) begin
        debug($display("%t : Choosing request from %d in Memory Merge interface", $time, j));
        nextReq.enq(req_fifos[j].first);
        if ((req_fifos[j].first.operation matches tagged Read .rop ? True : False)||
            (req_fifos[j].first.operation matches tagged Write .wop &&& wop.conditional ? True : False)) begin
          pendingReqs.enq(truncate(j));
          if (req_fifos[j].first.operation matches tagged Write .wop &&& wop.conditional) begin 
            debug($display("Merge - Expecting L2 Response for req ", fshow(req_fifos[j].first)));
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
        debug($display("%t : Choosing request from %d in Memory Merge interface", $time, i));
        nextReq.enq(req_fifos[i].first);
        `ifndef MULTI
          case (req_fifos[i].first.operation) matches
            tagged Read .r : pendingReqs.enq(fromInteger(i));
          endcase
        `else
        if ((req_fifos[i].first.operation matches tagged Read .r ? True : False) ||
            (req_fifos[i].first.operation matches tagged Write .w &&& w.conditional ? True : False)) begin
          pendingReqs.enq(fromInteger(i));
          if (req_fifos[i].first.operation matches tagged Write .w &&& w.conditional == True) begin 
            debug($display("Merge - Expecting L2 Response for pending request: ", fshow(req_fifos[i].first)));
          end
        end
        `endif
        req_fifos[i].deq();
        found = True;
      end
    end
    `endif
  endrule
  
  Vector#(numIfc, Server#(CheriMemRequest, CheriMemResponse)) servers;
  for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
    servers [i] = interface Server;
      interface response = toGet(rsp_fifos[i]);
      interface Put request;
        method Action put(CheriMemRequest req) if (req_fifos[i].notFull);
          debug($display("Merge - Request from L1 Cache Port:%0d", fromInteger(i)));
          req_fifos[i].enq(req);
        endmethod
      endinterface
    endinterface;
  end
  
  interface server = servers;
  
  interface Client merged;
    interface Get request;
      method ActionValue#(CheriMemRequest) get();
        debug($display("%t : Submitted request in Memory Merge interface", $time));
        CheriMemRequest rtnPacket = nextReq.first;
        nextReq.deq;
        return rtnPacket;
      endmethod
    endinterface
    interface Put response;
      method Action put(CheriMemResponse resp);
        debug($display("%t : Put response into interface %d Memory Merge", $time, pendingReqs.first));
        rsp_fifos[pendingReqs.first].enq(resp);
        pendingReqs.deq;
      endmethod
    endinterface
  endinterface
endmodule

module mkMergeFast(MergeIfc#(numIfc));
  FIFO#(CheriMemRequest)    nextReq       <- mkBypassFIFO;
  FIFO#(CheriMemResponse)      rsp_fifo      <- mkBypassFIFO;
  FIFO#(InterfaceT)                pendingReqs   <- mkSizedFIFO(16);
  Vector#(numIfc, Wire#(Bool))     fired         <- replicateM(mkDWire(False));
  Vector#(numIfc, Bool)            block;
  
  for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
    block[i] = (i==0) ? False:(fired[(i==0) ? 0:i-1]);
  end
  
  Vector#(numIfc, Server#(CheriMemRequest, CheriMemResponse)) servers;
  for (Integer i=0; i<valueOf(numIfc); i=i+1) begin
    servers [i] = interface Server;
      interface Get response;
        method ActionValue#(CheriMemResponse) get() 
                           if (pendingReqs.first == fromInteger(i));
          CheriMemResponse resp <- toGet(rsp_fifo).get;
          pendingReqs.deq;
          return resp;
        endmethod
      endinterface
      interface Put request;
        method Action put(CheriMemRequest req) if (!block[i]);
          nextReq.enq(req);
          `ifndef MULTI
            case (req.operation) matches
              tagged Read .r : pendingReqs.enq(fromInteger(i));
            endcase
          `else
            if ((req.operation matches tagged Read .r ? True : False) ||
                (req.operation matches tagged Write .w &&& w.conditional ? True : False)) begin
              pendingReqs.enq(fromInteger(i));
              if (req.operation matches tagged Write .w &&& w.conditional) begin
                debug($display("Merge Fast Store Conditional Request"));
              end
            end
          `endif
          fired[i] <= True;
        endmethod
      endinterface
    endinterface;
  end
  
  interface server = servers;
  
  interface Client merged;
    interface Get request;
      method ActionValue#(CheriMemRequest) get();
        debug($display("%t : Submitted request in Memory MergeFast interface", $time));
        CheriMemRequest rtnPacket = nextReq.first;
        nextReq.deq;
        return rtnPacket;
      endmethod
    endinterface
    interface Put response;
      method Action put(CheriMemResponse resp);
        debug($display("%t : Put response into interface %d Memory MergeFast", $time, pendingReqs.first));
        rsp_fifo.enq(resp);
      endmethod
    endinterface
  endinterface
endmodule

endpackage
