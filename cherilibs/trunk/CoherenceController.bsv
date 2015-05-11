/*-
 * Copyright (c) 2014 Alan Mujumdar
 * Copyright (c) 2014 Jonathan Woodruff
 * Copyright (c) 2015 Alexandre Joannou
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
 
import Debug::*;
import MemTypes::*;
import DefaultValue::*;
import Assert::*;
import List::*;
import FIFO::*;
import FF::*;
import SpecialFIFOs::*;
import FIFOF::*;
import GetPut::*;
import MasterSlave::*;
import Interconnect::*;
import Vector::*;
import ConfigReg::*;
import MEM::*;
import Bag::*;
import ClientServer::*;
 
interface CoherenceController#(numeric type keyBits);
  method Action put(CheriMemRequest req);
  method ActionValue#(Maybe#(Bool)) get;
  method ActionValue#(Maybe#(InvalidateCache)) getInvalidate; 
endinterface: CoherenceController

typedef Bit#(tagBits) Tag#(numeric type tagBits);
typedef Bit#(keyBits) Key#(numeric type keyBits);
typedef enum {Init, Serving} CacheState deriving (Bits, Eq, FShow);

typedef struct {
  Bool valid;
  Vector#(CORE_COUNT, Bool) linked;
  Vector#(TMul#(CORE_COUNT, 2), Bool) sharers;
} CoherenceLine deriving (Bits, Eq, Bounded);

module mkCoherenceController(CoherenceController#(keyBits));
  Reg#(CacheState)                                      cacheState <- mkConfigReg(Init);
  Reg#(Key#(keyBits))                                        count <- mkConfigReg(0); 
  FIFOF#(Maybe#(InvalidateCache))                    invalidateFifo <- mkSizedBypassFIFOF(10);
  FIFO#(Maybe#(Bool))                                 responseFifo <- mkBypassFIFO;
  Vector#(CORE_COUNT, Reg#(Maybe#(CheriPhyAddr)))    loadLinkedReg <- replicateM(mkReg(tagged Invalid));
  //MEM#(Key#(keyBits), CoherenceLine)           tags <- mkMEM();

  CoherenceLine initCoherenceLine = CoherenceLine{
                                                  valid: False,
                                                  linked: replicate(False),
                                                  sharers: ?
                                                 };

  rule initialize(cacheState == Init);
    //tags.write(pack(count), initCoherenceLine);
    count <= count + 1;
    if (count == 0-1) cacheState <= Serving;
  endrule

  method Action put(CheriMemRequest req) if (cacheState == Serving);
    debug2("coherenceController", $display("<time %0t CoherenceController> put ", $time, fshow(req)));
    Bit#(TLog#(TMul#(CORE_COUNT, 2))) currentMasterID = truncate(pack(req.masterID));
    Bit#(TLog#(CORE_COUNT)) currentCoreID = truncateLSB(pack(currentMasterID));

    Bool scResult = False;
    Maybe#(Bool) response = tagged Invalid;

    if (req.operation matches tagged Read .rop &&& rop.linked) begin
      debug2("coherenceController", $display("<time %0t CoherenceController> load linked %x", $time, req.addr));
      loadLinkedReg[currentCoreID] <= tagged Valid req.addr; 
    end 
    else if (req.operation matches tagged Write .wop) begin
      for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin  
        if (isValid(loadLinkedReg[i])) begin    
        debug2("coherenceController", $display("<time %0t CoherenceController> valid load linked reg", $time));
          CheriPhyAddr lladdr = fromMaybe(?, loadLinkedReg[i]);
          if ((lladdr.lineNumber>>2) == (req.addr.lineNumber>>2)) begin  
          debug2("coherenceController", $display("<time %0t CoherenceController> load linked reg addr match %x", $time, req.addr.lineNumber));
            if (currentCoreID == fromInteger(i) && wop.conditional && !wop.uncached) begin
              scResult = True; 
              debug2("coherenceController", $display("<time %0t CoherenceController> store conditional match %x", $time, req.addr.lineNumber));
            end 
            loadLinkedReg[i] <= tagged Invalid; 
          end    
        end    
      end   
      if (wop.conditional) begin 
        response = tagged Valid scResult;
        responseFifo.enq(response); 
        debug2("coherenceController", $display("<time %0t CoherenceController> store conditional(%b) addr: %x", $time, scResult, req.addr.lineNumber));
      end
    end    

    Vector#(TMul#(CORE_COUNT, 2), Bool) sharersList = replicate(True);
///*
    sharersList[currentMasterID] = False; 
    sharersList[0] = False; 
    if (valueof(CORE_COUNT) > 1) begin
      sharersList[2] = False;
    end
//*/
    debug2("coherenceController", $display("<time %0t CoherenceController> currentMasterID: %d", $time, currentMasterID)); 
    if (req.operation matches tagged Write .wop) begin
      InvalidateCache inv = InvalidateCache{sharers     : sharersList,
                                            addr        : req.addr};
      Maybe#(InvalidateCache) invRet = tagged Valid inv;
      invalidateFifo.enq(invRet);
      debug2("coherenceController", $display("<time %0t CoherenceController> invalidateFifo sharers:%b, addr:%x", $time, inv.sharers, inv.addr));
    end  

    //responseFifo.enq(response); 
  endmethod
  
  method ActionValue#(Maybe#(Bool)) get if (cacheState == Serving);
    debug2("coherenceController", $display("<time %0t CoherenceController> get", $time));
    responseFifo.deq;
    return responseFifo.first;
  endmethod

  method ActionValue#(Maybe#(InvalidateCache)) getInvalidate if(cacheState == Serving); 
    debug2("coherenceController", $display("<time %0t CoherenceController> getInvalidate", $time));
    invalidateFifo.deq(); 
    return invalidateFifo.first; 
  endmethod  

endmodule
