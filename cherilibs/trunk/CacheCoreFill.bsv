/*-
 * Copyright (c) 2015 Jonathan Woodruff
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
import FIFO::*;
import FIFOF::*;
import Vector::*;
import ConfigReg::*;
import CacheCoreTypes::*;
import Bag::*;
import Interconnect::*;

module mkCacheCoreFill#(Bit#(16) cacheId, 
                    WhichCache whichCache,
                    Bag#(inFlight, ReqId, Bank) nextBank,
                    FIFOF#(CheriMemResponse) memRsps)
                   (CacheCoreFill#(ways, keyBits, tagBits, inFlight))
    provisos (
      Bits#(CheriPhyAddr, paddr_size),
      Bits#(CacheCoreTypes::CacheAddress#(keyBits, tagBits), paddr_size),
      Add#(a__, TAdd#(TLog#(inFlight), 1), 8)
    );
        
  Reg#(Bank)                                                     inFlit <- mkConfigReg(0);
  FIFOF#(Bool)                                      uncachedPendingFifo <- mkUGFIFOF;  // The bool indicates a read response expected.
  Bag#(inFlight, ReqId, RequestRecord#(ways, keyBits, tagBits))readReqs <- mkSmallBag; // Hold data for outstanding memory requests
  Bag#(inFlight, ReqId, Bit#(0))                              memReqIds <- mkSmallBag; // A searchable list of local request ids that have outstanding memory request.
  
  method Action reportRequest(CacheCommitToken#(ways, keyBits, tagBits) cct);
    if (cct.insertReadRec) begin
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Inserting %x into ID table", $time, cacheId, cct.readId, fshow(cct.readRec)));
      // Insert info about the outstanding request keyed by external request id.
      readReqs.insert(cct.readId, cct.readRec);
    end
    if (cct.insertReqId) memReqIds.insert(cct.reqId, ?);
    if (cct.enqPending) begin
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enquing pending uncached request", $time, cacheId));
      uncachedPendingFifo.enq(cct.pendingResponse);
    end
  endmethod
  
  method ActionValue#(ControlToken#(ways, keyBits, tagBits)) getAnyMemoryResponse(ControlToken#(ways, keyBits, tagBits) ct);
    // Deal with any memory responses ====
    ReqId memRspId = getRespId(memRsps.first);
    
    CheriMemResponse memResp = memRsps.first;
    Bool last = getLastField(memResp);
    if (memRsps.notEmpty) begin
      if (memResp.operation matches tagged Write .wop) begin
        memRsps.deq;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received write memory response ", $time, cacheId, fshow(memResp)));
        if (uncachedPendingFifo.notEmpty && !uncachedPendingFifo.first) begin 
          uncachedPendingFifo.deq();
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, cacheId));
        end
      end else if (ct.ft.command != Writeback && !ct.ft.fresh) begin // Don't hijack a writeback command or a fresh request.
        case (memResp.operation) matches
          tagged Read .rr: begin
            memRsps.deq;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Hijacked memory response lookup, last:%x ", $time, cacheId, last, fshow(ct.ft.req)));
            ct.ft.command = MemResponse; // Hijack this request and turn it into a fill.
            ct.ft.addr = unpack(0);                                     
            // Construct reqId to recall key. 
            Maybe#(RequestRecord#(ways, keyBits, tagBits)) mReqRec = readReqs.isMember(memRspId);
            if (mReqRec matches tagged Valid .reqRec) begin
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Found %x in ID table", $time, cacheId, memRspId, fshow(reqRec)));
              ct.way     = reqRec.oldWay;
              ct.tagsRead   = reqRec.oldTags;
              // This not the bank of the response, but the bank of the original request.
              // In the !(ooo) case, the bank of the original request will simply be the existing bank in ct.
              CacheAddress#(keyBits, tagBits) tmpAddr = unpack(pack(ct.ft.req.addr));
              ct.ft.addr.bank = fromMaybe(tmpAddr.bank,nextBank.isMember(reqRec.inId));
              ct.ft.addr.tag = reqRec.oldTags[ct.way].tag;
              ct.ft.addr.key = reqRec.key;
              ct.cached   = reqRec.cached;
              ct.respForWrite= reqRec.write;
              ct.ft.req.masterID      = reqRec.inId.masterID;
              ct.ft.req.transactionID = reqRec.inId.transactionID;
              ct.noOfFlits   = reqRec.noOfFlits;
              //if (reqRec.oldDirty) ct.ft.command = MemResponseWriteback; // Also do a writeback
              if (!reqRec.cached) begin
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, cacheId));
                uncachedPendingFifo.deq();
              end
              if (last) begin
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing %x from ID table", $time, cacheId, memRspId, fshow(reqRec)));
                readReqs.remove(memRspId);
                memReqIds.remove(getReqId(ct.ft.req));
              end else begin
                RequestRecord#(ways, keyBits, tagBits) update = reqRec;
                update.oldTags[ct.way].valid[inFlit] = True;
                ct.cacheCommit.readId = memRspId;
                ct.cacheCommit.readRec = update;
                ct.cacheCommit.insertReadRec = True;
                //readReqs.insert(memRspId, update); // Update tag record!
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Updating %x in ID table", $time, cacheId, memRspId, fshow(update)));
              end
            end else $display("<time %0t, cache %0d, CacheCore> Panic!  received response for index that was not expected!", $time, cacheId);
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received memory response ", $time, cacheId, fshow(memResp)));
            ct.ft.rspError = memResp.error;
            // Store original request address before updating the bank.
            ct.ft.req.addr = unpack(pack(ct.ft.addr));
            // This is only accurate if the response is cached (assuming that external cached reads are bursts aligned on cache lines).
            ct.ft.addr.bank = truncate(pack(inFlit));
            // Shoehorn the response data and properties into the request that the lookup will see.
            ct.ft.req.operation = tagged Write {
                                uncached: !ct.cached,
                                conditional: False,
                                byteEnable: replicate(True),
                                data: rr.data,
                                last: last
                              };
            ct.ft.dataKey = DataKey{key:ct.ft.addr.key, bank: ct.ft.addr.bank, way: ct.way};
            ct.ft.last = last;
            if (last) begin
              inFlit <= 0;
              ct.ft.last = True;
            end else inFlit <= inFlit + 1;
          end
          tagged SC .scr: begin
            memRsps.deq;
            ct.ft.command = MemResponse;
            Data#(CheriDataWidth) retData = ?;
            retData.data = zeroExtend(pack(scr));
            // Shoehorn the store conditional response into the request that the lookup will see.
            ct.ft.req.operation = tagged Write {
                                uncached: True,
                                conditional: False,
                                byteEnable: replicate(True),
                                data: retData,
                                last: last
                              };
            ct.scResult = scr;
            ct.respondWithSC = True;

            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing %x from ID table", $time, cacheId, memRspId, fshow(scr)));
            readReqs.remove(memRspId);
            memReqIds.remove(getReqId(ct.ft.req));

            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> store conditional response lookup, last:%x ", $time, cacheId, last, fshow(ct.ft.req)));
          end
        endcase
      end
    end
    return ct;
  endmethod
  method Bool noMoreReadReqs() = readReqs.full();
  method Bool outstandingRequest(ReqId id);
    return isValid(memReqIds.isMember(id));
  endmethod
  method Bool uncachedPending() = uncachedPendingFifo.notEmpty();
endmodule
