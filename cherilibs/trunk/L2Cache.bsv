/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Alex Horsman
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014, 2015 Alexandre Joannou
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
  import Bag::*;
`endif
`ifdef STATCOUNTERS
  import StatCounters::*;
`endif

/* =================================================================
mkL2Cache
 =================================================================*/

interface L2CacheIfc;
  interface Slave#(CheriMemRequest, CheriMemResponse) cache;
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef MULTI
    `ifndef TIMEBASED
      method ActionValue#(Maybe#(InvalidateCache)) getInvalidate;
      method Action putInvalidateDone(Bool didWriteback);
    `endif
  `endif
  `ifdef STATCOUNTERS
  interface Get#(ModuleEvents) cacheEvents;
  `endif
endinterface: L2CacheIfc


(*synthesize*)
module mkL2Cache(L2CacheIfc ifc);
  FF#(CheriMemRequest, 8)          memReqs <- mkUGFFDebug("L2Cache_memReqs");
  // The delay fifo can be used to insert latency between the L2 and main
  // memory. This delay can be controled with an argument during the build.
  // The argument represents the number of latency cycles added. Default (0)
  FF#(CheriMemResponse, 2)         memRsps <- mkUGFFDebug("L2Cache_memRsps");//mkUGFFDelay(0);
  CacheCore#(4, TAdd#(Indices, 2), 4) core <- mkCacheCore(8, WriteAllocate, RespondAll, InOrder, L2, 
                                         zeroExtend(memReqs.remaining()),
                                         ff2fifof(memReqs), ff2fifof(memRsps));
  `ifdef MULTI
    // Specify the number of ways and cache lines 
    CoherenceController#(7)        coherence <- mkCoherenceController;
    Bag#(4, ReqId, Bool)          scResponse <- mkSmallBag;
  `endif
  
  rule packCommits;
    core.nextWillCommit(True);
  endrule
  
  Bool respReady = core.response.canGet;

  function CheriMemResponse memResponsePeek();
    CheriMemResponse resp = core.response.peek();
    `ifdef MULTI
      if (getLastField(resp)) begin
        if (scResponse.isMember(getRespId(resp)) matches tagged Valid .scResult) begin
          resp.error = NoError;
          resp.operation = tagged SC scResult;
        end
      end
    `endif
    return resp;
  endfunction
 
  interface Slave cache;
    interface CheckedPut request;
      method Bool canPut();
        `ifdef MULTI
          return core.canPut() && coherence.canGet();
        `else
          return core.canPut();
        `endif
      endmethod
      method Action put(CheriMemRequest cmr);
        debug2("l2cache", $display("<time %0t L2Cache> request ", $time, fshow(cmr)));
        `ifdef MULTI
          SCRecord coherenceResp <- coherence.get(cmr);
          if (cmr.operation matches tagged Write .wop &&& wop.conditional) begin
            debug2("l2cache", $display("<time %0t L2Cache> SC result: ", $time, fshow(coherenceResp)));
            scResponse.insert(coherenceResp.id, coherenceResp.scResult);
            cmr.operation = tagged Write{
                                         uncached: wop.uncached,
                                         conditional: False,
                                         byteEnable: (coherenceResp.scResult) ? wop.byteEnable:unpack(0),
                                         bitEnable: -1,
                                         data: wop.data,
                                         last: wop.last
                                        };
          end
        `endif
        core.put(cmr);
      endmethod
    endinterface
    interface CheckedGet response;
      method canGet = respReady;
      method CheriMemResponse peek if (respReady);
        return memResponsePeek();
      endmethod
      method ActionValue#(CheriMemResponse) get if (respReady);
        CheriMemResponse unused <- core.response.get(); // Just to enforce the "actions" of taking a request.
        CheriMemResponse resp = memResponsePeek(); // Actually get the return values from here.
        `ifdef MULTI
          if (getLastField(resp)) begin
            if (scResponse.isMember(getRespId(resp)) matches tagged Valid .scResult) begin
              scResponse.remove(getRespId(resp)); // Update state, removing sc record from table.
              debug2("l2cache", $display("<time %0t L2Cache> found SC Result for this ID: ", $time, fshow(scResult)));
            end
          end
        `endif
        debug2("l2cache", $display("<time %0t L2Cache> response ", $time, fshow(resp)));
        return resp;
      endmethod
  endinterface
  endinterface
  interface Master memory;
    interface CheckedGet request;//  = toCheckedGet(ff2fifof(memReqs));
      method canGet = memReqs.notEmpty;
      method CheriMemRequest peek if (memReqs.notEmpty);
        return memReqs.first;
      endmethod
      method ActionValue#(CheriMemRequest) get if (memReqs.notEmpty);
        memReqs.deq; 
        debug2("l2cache", $display("<time %0t L2Cache> delivered memory request ", $time, fshow(memReqs.first)));
        return memReqs.first;
      endmethod
    endinterface
    interface CheckedPut response;// = toCheckedPut(ff2fifof(memRsps));
      method canPut = memRsps.notFull;
      method Action put(CheriMemResponse d) if (memRsps.notFull);
        debug2("l2cache", $display("<time %0t L2Cache> received memory response ", $time, fshow(d)));
        memRsps.enq(d);
      endmethod
    endinterface
  endinterface
  `ifdef MULTI
    `ifndef TIMEBASED
      interface getInvalidate     = coherence.getInvalidate;
      interface putInvalidateDone = coherence.putInvalidateDone;
    `endif
  `endif
  `ifdef STATCOUNTERS
  interface Get cacheEvents;
    method ActionValue#(ModuleEvents) get () = core.cacheEvents.get();
  endinterface
  `endif

endmodule
