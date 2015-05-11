/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Alex Horsman
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014 Alexandre Joannou
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
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

import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import MasterSlave::*;
import Vector::*;
import EHR::*;
import MEM::*;
import MemTypes::*;
import Assert::*;
import DefaultValue::*;
import Debug::*;
import FF::*;
import ConfigReg::*;
import Interconnect::*;
import CacheCore::*;
import BeriUGBypassFIFOF::*;
`ifdef MULTI
  import CoherenceController::*;
`endif

/* =================================================================
mkL2Cache
 =================================================================*/

interface L2CacheIfc;
  interface Slave#(CheriMemRequest, CheriMemResponse) cache;
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef MULTI
    method ActionValue#(Maybe#(InvalidateCache)) getInvalidate; 
  `endif
endinterface: L2CacheIfc

(*synthesize*)
module mkL2Cache(L2CacheIfc ifc);
  FIFOF#(CheriMemResponse) resp_fifo <- mkBeriUGBypassFIFOF;
  FF#(CheriMemRequest, 8)    memReqs <- mkUGFF();
  FF#(CheriMemResponse, 2)   memRsps <- mkUGFF();
  CacheCore#(4, 7)              core <- mkCacheCore(3, WriteAllocate, L2, 
                                         zeroExtend(memReqs.remaining()),
                                         ff2fifof(memReqs), ff2fifof(memRsps));
  `ifdef MULTI 
    CoherenceController#(7)        coherence <- mkCoherenceController;
    FIFOF#(CheriMemRequest)      commit_fifo <- mkBypassFIFOF;
    FIFOF#(CheriMemResponse) scResponse_fifo <- mkBeriUGBypassFIFOF;
  `endif
  
  rule getCachedResponse;
    Maybe#(CheriMemResponse) memResp <- core.get(resp_fifo.notFull);
    `ifndef MULTI
      if (memResp matches tagged Valid .mr) begin
        resp_fifo.enq(mr);
        debug2("l2cache", $display("<time %0t L2Cache> response ", $time, fshow(mr)));
      end
    `else
      if (memResp matches tagged Valid .mr) begin
        CheriMemResponse scr = scResponse_fifo.first;
        CheriMemResponse resp = mr;
        if (scResponse_fifo.notEmpty && scr.masterID == mr.masterID && scr.transactionID == mr.transactionID) begin
          resp = scResponse_fifo.first;
          scResponse_fifo.deq;
          debug2("l2cache", $display("<time %0t L2Cache> store conditional response ", $time));
        end
        debug2("l2cache", $display("<time %0t L2Cache> response ", $time, fshow(resp)));
        resp_fifo.enq(resp);
      end
    `endif
  endrule

  `ifdef MULTI
    rule getCoherenceResponse(commit_fifo.notEmpty && scResponse_fifo.notFull);
      Maybe#(Bool) coherenceResp <- coherence.get;
      Bool commit = True;
      CheriMemRequest cmr = commit_fifo.first;
      commit_fifo.deq;
  
      if (coherenceResp matches tagged Valid .cr) begin
        commit = cr;
        CheriMemResponse scResponse = CheriMemResponse{masterID: cmr.masterID,
                                                       transactionID: cmr.transactionID,
                                                       error: NoError,
                                                       operation: tagged SC cr
                                                      };
        scResponse_fifo.enq(scResponse);
        debug2("l2cache", $display("<time %0t L2Cache> store conditional fifo enq: %x ", $time, cr));
      end

      if (cmr.operation matches tagged Write .wop &&& wop.conditional) begin
        debug2("l2cache", $display("<time %0t L2Cache> nextWillCommit store conditional: %x ", $time, commit));
        core.nextWillCommit(commit);
      end
      else begin
        debug2("l2cache", $display("<time %0t L2Cache> nextWillCommit default true", $time));
        core.nextWillCommit(True);
      end
    endrule
  `endif
 
  interface Slave cache;
    interface CheckedPut request;
        method Bool canPut();
          return True; // Dangerous
        endmethod
        method Action put(CheriMemRequest cmr);
          debug2("l2cache", $display("<time %0t L2Cache> request ", $time, fshow(cmr)));

          `ifndef MULTI
            core.nextWillCommit(True);
          `else
            coherence.put(cmr);

            if (cmr.operation matches tagged Write .wop &&& wop.conditional) begin
              commit_fifo.enq(cmr);
              cmr.operation = tagged Write{
                                           uncached: wop.uncached,
                                           conditional: False,
                                           byteEnable: wop.byteEnable,
                                           data: wop.data,
                                           last: wop.last
                                          };
            end
            else begin
              core.nextWillCommit(True);
            end
          `endif

          core.put(cmr);
        endmethod
    endinterface
    interface response = toCheckedGet(resp_fifo);
  endinterface
  interface Master memory;
    interface request  = toCheckedGet(ff2fifof(memReqs));
    interface response = toCheckedPut(ff2fifof(memRsps));
  endinterface
  `ifdef MULTI
    interface getInvalidate = coherence.getInvalidate;  
  `endif

endmodule
