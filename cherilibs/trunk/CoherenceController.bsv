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
  method Bool canGet();
  //method Action put(CheriMemRequest req);
  method ActionValue#(SCRecord) get(CheriMemRequest req);
  method ActionValue#(Maybe#(InvalidateCache)) getInvalidate;
  method Action putInvalidateDone(Bool didWriteback);
endinterface: CoherenceController

typedef Bit#(tagBits) Tag#(numeric type tagBits);
typedef Bit#(keyBits) Key#(numeric type keyBits);
typedef enum {Init, Serving} CacheState deriving (Bits, Eq, FShow);

typedef Bit#(8) InvalidateCount;

typedef struct {
  InvalidateCount syncCount;
  Bool synced;
  Bool linked;
  CheriPhyAddr addr;
} LinkRecord deriving (Bits, Eq, Bounded, FShow);

`ifdef MULTI
  typedef struct {
    ReqId id;
    Bool  scResult;
  } SCRecord deriving (Bits, Eq, FShow);
`endif

module mkCoherenceController(CoherenceController#(keyBits));
  Reg#(CacheState)                                      cacheState <- mkConfigReg(Serving);
  Reg#(Key#(keyBits))                                        count <- mkConfigReg(0);
  // This FIFO is small so that all invalidates sit in queues in the caches where they are counted for syncs.
  Reg#(Maybe#(InvalidateCache))                     lastInvalidate <- mkReg(tagged Invalid);
  FF#(Maybe#(InvalidateCache), 2)                   invalidateFifo <- mkUGFF(); 
  Vector#(CORE_COUNT, Reg#(LinkRecord))              loadLinkedReg <- replicateM(mkRegU);

  Reg#(InvalidateCount)                        invIssued <- mkConfigReg(0);
  Reg#(InvalidateCount)                          invDone <- mkConfigReg(0);
  
  method Bool canGet() = (cacheState == Serving && invalidateFifo.notFull);
 
  method ActionValue#(SCRecord) get(CheriMemRequest req) if (cacheState == Serving && invalidateFifo.notFull);
    debug2("coherenceController", $display("<time %0t CoherenceController> get ", $time, fshow(req)));
    Bit#(TLog#(TMul#(CORE_COUNT, 2))) currentMasterID = truncate(pack(req.masterID));
    Bit#(TLog#(CORE_COUNT)) currentCoreID = truncateLSB(pack(currentMasterID));
    InvalidateCount numNewInvalidates = 0;
    `ifndef TIMEBASED
      // Prepare invalidates in case this is a write.
      Vector#(TMul#(CORE_COUNT, 2), Bool) sharersList = replicate(True);
      sharersList[currentMasterID] = False;  
      Integer iCacheNum = 0;
      for (iCacheNum=0; iCacheNum<valueof(TMul#(CORE_COUNT, 2)); iCacheNum=iCacheNum+2) begin
        sharersList[iCacheNum] = False;
      end
      debug2("coherenceController", $display("<time %0t CoherenceController> currentMasterID: %d", $time, currentMasterID)); 
      Bool doInvalidate = (case (req.operation) matches
                                tagged Write .wop &&& (pack(wop.byteEnable)!=0): return True;
                                tagged Read .rop &&& rop.linked: return True;
                                default: return False;
                          endcase);
      
      Maybe#(InvalidateCache) invRet = tagged Invalid;
      if (doInvalidate) begin
        // Align the address to the line so that all invalidates to the same line alias.
        CheriPhyAddr invAddr = req.addr;
        invAddr.byteOffset = 0;
        invAddr.lineNumber[1:0] = 0;
        InvalidateCache inv = InvalidateCache{sharers     : sharersList,
                                              addr        : invAddr};
        invRet = tagged Valid inv;
        if (invRet != lastInvalidate) begin
          numNewInvalidates = zeroExtend(pack(countOnes(pack(sharersList))));
          invIssued <= invIssued + numNewInvalidates;
          debug2("coherenceController", $display("<time %0t CoherenceController> getInvalidate, invIssued: %d", $time, invIssued + numNewInvalidates));
          invalidateFifo.enq(invRet);
          debug2("coherenceController", $display("<time %0t CoherenceController> invalidateFifo sharers:%b, addr:%x", $time, inv.sharers, inv.addr));
        end
      end
      lastInvalidate <= invRet;
    `endif

    SCRecord scResponse = SCRecord{
      id: ReqId{
        masterID:      req.masterID,
        transactionID: req.transactionID
      },
      scResult: False
    };
    Vector#(CORE_COUNT, LinkRecord) newLoadLinkedReg = readVReg(loadLinkedReg);
    // Update the "sync" flags of the link registers before checking for success so that any
    // invalidates that have come back since the last access are reflected when we check if they are synced.
    for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin
      if (newLoadLinkedReg[i].linked && !newLoadLinkedReg[i].synced) begin
        // Set synced == True if invDone is equal to or bigger than syncCount.
        newLoadLinkedReg[i].synced = (newLoadLinkedReg[i].syncCount==invDone || msb(newLoadLinkedReg[i].syncCount - invDone)==1'b1);
        debug2("coherenceController", $display("<time %0t CoherenceController> waiting for a sync, loadLinkedReg[%d].syncCount: %d, invDone: %d, writing", 
                                               $time, i, newLoadLinkedReg[i].syncCount, invDone, fshow(newLoadLinkedReg)));
      end
    end
    // Setup a new link register address if this is a load linked.
    if (req.operation matches tagged Read .rop &&& rop.linked) begin
      debug2("coherenceController", $display("<time %0t CoherenceController> load linked fullAddr:%x, llRegAddr:%x, syncCount:%d", $time, req.addr, req.addr.lineNumber, invIssued));
      newLoadLinkedReg[currentCoreID] = LinkRecord{
        syncCount: invIssued + numNewInvalidates, // We will check for when more than the current number of issued invalidates are complete.
        synced: (numNewInvalidates==0),
        linked: True,
        addr: req.addr
      };
    // Check against the linked register if this is a store conditional.
    end else if (req.operation matches tagged Write .wop) begin
      for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin  
        if (newLoadLinkedReg[i].linked) begin    
          CheriPhyAddr lladdr = newLoadLinkedReg[i].addr;
          debug2("coherenceController", $display("<time %0t CoherenceController> write operation, valid load linked reg, i=%0d, currentCoreID=%0d, addr=%x, llRegAddr=%x", $time, i, currentCoreID, req.addr.lineNumber, lladdr.lineNumber));
          if ((lladdr.lineNumber>>2) == (req.addr.lineNumber>>2)) begin  
            debug2("coherenceController", $display("<time %0t CoherenceController> load linked reg addr match %x", $time, req.addr.lineNumber));
            if (currentCoreID == fromInteger(i) /*&& newLoadLinkedReg[i].synced*/ && wop.conditional && !wop.uncached) begin
              scResponse.scResult = True; 
              debug2("coherenceController", $display("<time %0t CoherenceController> store conditional match %x", $time, req.addr.lineNumber));
            end 
            newLoadLinkedReg[i].linked = False; 
          end    
        end    
      end
    end
    
    writeVReg(loadLinkedReg, newLoadLinkedReg);
    return scResponse;
  endmethod

  `ifndef TIMEBASED
    method ActionValue#(Maybe#(InvalidateCache)) getInvalidate if (invalidateFifo.notEmpty);
      invalidateFifo.deq(); 
      return invalidateFifo.first; 
    endmethod  
    method Action putInvalidateDone(Bool didWriteback);
      invDone <= invDone + 1;
      debug2("coherenceController", $display("<time %0t CoherenceController> invalidate done, was dirty %x, invDone %d", $time, didWriteback, invDone+1));
    endmethod 
  `endif

endmodule
