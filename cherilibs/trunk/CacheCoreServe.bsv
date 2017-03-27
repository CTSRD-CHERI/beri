/*-
 * Copyright (c) 2015 Jonathan Woodruff
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
import FIFO::*;
import FIFOF::*;
import Vector::*;
import ConfigReg::*;
import CacheCoreTypes::*;
import Interconnect::*;
import MEM::*;
`ifdef STATCOUNTERS
import GetPut::*;
import StatCounters::*;
`endif

`ifdef CAP
  `define USECAP 1
`elsif CAP128
  `define USECAP 1
`elsif CAP64
  `define USECAP 1
`endif

function ActionValue#(Maybe#(Way#(ways))) findWay(Vector#(ways,TagLine#(tagBits)) tagVec,Tag#(tagBits) tag, Bank bank);
  actionvalue
  function Bool hit(TagLine#(tagBits) t) = (tag==t.tag && t.valid[bank]);
  //Maybe#(Way#(ways)) way = 
  //Maybe#(Way#(ways)) way = Invalid;
  /*for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
    if (tag==tagVec[i].tag && tagVec[i].valid[bank]) begin
      if (isValid(way)) $display("Panic! Duplicate ways match in cache!");
      way = Valid(fromInteger(i));
    end
    debug2("CacheCore", $display("i:%d, valid:%x, dirty: %x, pending:%x, tagIn:%x, tagCmp:%x, found: %x, way:%x", 
            i, tagVec[i].valid, tagVec[i].dirty, tagVec[i].pending, tag, tagVec[i].tag, isValid(way), fromMaybe(0,way)));
  end*/ 
  return unpack(pack(findIndex(hit, tagVec)));
  endactionvalue
endfunction

function ActionValue#(Maybe#(Way#(ways))) findPendingWay(Vector#(ways,TagLine#(tagBits)) tagVec);
  actionvalue
  function Bool pending(TagLine#(tagBits) t) = t.pendMem;
  //Maybe#(Way#(ways)) way = 
  /*for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
    if (tagVec[i].pendMem) way = Valid(fromInteger(i));
  end */
  return unpack(pack(findIndex(pending, tagVec)));
  endactionvalue
endfunction

module mkCacheCoreServe#(Bit#(16) cacheId, 
                        WriteMissBehaviour writeBehaviour,
                        ResponseBehaviour responseBehaviour,
                        WhichCache whichCache, 
                        Bit#(6) memReqFifoSpace,
                        CacheCoreWriteback#(ways, keyBits, tagBits) writebacks,
                        CacheCoreFill#(ways, keyBits, tagBits, inFlight) filler
                       )
                   (CacheCoreServe#(ways, keyBits, tagBits))
    provisos (
      Bits#(CheriPhyAddr, paddr_size),
      Bits#(CacheCoreTypes::CacheAddress#(keyBits, tagBits), paddr_size),
      Add#(smaller3, tagBits, 30)
    );
    
  Reg#(Way#(ways))       randomWay <- mkRegU;
  Reg#(CheriTransactionID)  nextId <- mkReg(0);
  `ifdef STATCOUNTERS
  Wire#(CacheCoreEvents)  cacheCoreEvents <- mkDWire(defaultValue);
  `endif

  TagLine#(tagBits) invTag = ?;
  invTag.valid = replicate(False);
  invTag.pendMem = False;
  
  rule countUp;
    randomWay <= randomWay + 1;
  endrule
    
  Bool writeThrough = writeBehaviour==WriteThrough;
  Bool roomForOneRequest = memReqFifoSpace >= 1;
  // If the cache is writethrough, we never need to writeback.
  Bool roomForWriteback        = (writeThrough) ? True:(memReqFifoSpace >= 4);
  Bool roomForReadAndWriteback = (writeThrough) ? roomForOneRequest:(memReqFifoSpace >= 5);
          
  method ActionValue#(ControlToken#(ways, keyBits, tagBits)) serveCacheRequest(ControlToken#(ways, keyBits, tagBits) ct);
    // Calculate miss and wayMiss
    Maybe#(Way#(ways)) mWay = tagged Invalid;
    if (ct.ft.command!=Nop) mWay <- findWay(ct.tagsRead,ct.ft.addr.tag,ct.ft.addr.bank);
    Bool miss = !isValid(mWay);
    ct.way = fromMaybe(randomWay,mWay);
    // Check if we have a way miss
    Bool wayMiss = False;
    if (valueOf(ways) > 1) begin
      if (!miss && ct.way != ct.ft.dataKey.way) wayMiss = True;
    end
    Bool doMemRequest = False;
    TagLine#(tagBits) tag = ct.tagsRead[ct.way];
    Vector#(ways,TagLine#(tagBits)) tagUpdate =  ct.tagsRead;
    ReqId reqId = getReqId(ct.ft.req);
    Bool doInvalidate = False;
    Bool writeback = False;
    Bool returnTag = False;
    Bool writeTags = False;
    Bool cachedWrite = False;
    Bool cachedResponse = False; 
    Bool expectResponse = False;
    Bool evict = False;
    Bool isPftch = {case (ct.ft.req.operation) matches
                    tagged CacheOp .cop &&& (cop.inst == CachePrefetch && cop.cache == whichCache): return True;
                    default: return False;
                   endcase};
    Bool linked = {case (ct.ft.req.operation) matches
                      tagged Read .rop:  return rop.linked;
                      default: return False;
                    endcase};
    Bool conditional = {case (ct.ft.req.operation) matches
                      tagged Write .wop: return wop.conditional;    
                      default: return False;
                    endcase};
    Bool prefetchMissLocal = (isPftch && miss);
    Bool isWrite = False;
    if (ct.ft.req.operation matches tagged Write .wop) isWrite = True;
    if (prefetchMissLocal) isWrite = True;
    Bool isRead = False;
    if (ct.ft.req.operation matches tagged Read .rop) isRead = True;
    // If this is a write-through cache, then a lower level will handle ordering
    // of load-linked and store conditional.
    Bool handleLinked = writeBehaviour!=WriteThrough;
    // If this cache doesn't handle load linked, then force a miss.
    Bool passConditional = (!handleLinked && (linked||conditional));
    
    // Check if there is a pending transaction for this index
    mWay <- findPendingWay(ct.tagsRead); // For this case, we just need to find the way that is expecting a fill, if there is one.
    Bool pendMem = isValid(mWay); // If this index has a pending memory transaction.
    // Setup default cache response
    ct.rt.resp.masterID = ct.ft.req.masterID;
    ct.rt.resp.transactionID = ct.ft.req.transactionID;
    ct.rt.resp.error = ct.ft.rspError;
    
    function ActionValue#(Bool) doWriteback = actionvalue
      Bool doingEviction = False;
      if (tag.valid[ct.ft.addr.bank] && tag.dirty && !writeThrough) begin
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Requesting eviction! Address: %x", $time, cacheId, CacheAddress{tag: tag.tag, key: ct.ft.addr.key, bank: ct.ft.addr.bank, offset: 0}));
        writebacks.put(AddrTagWay{
          way   : ct.way,
          tag   : tag,
          addr  : CacheAddress{tag: tag.tag, key: ct.ft.addr.key, bank: ct.ft.addr.bank, offset: 0},
          cached: False,
          reqId : reqId
        });
        doingEviction = True;
      end
      return doingEviction;
    endactionvalue;
    
    Bool needWriteback = False;
    Bool dontCommit = False;
    Bool dead = False;  // To allow us to kill this operation at any stage.
    ct.cacheCommit.memReq = ct.ft.req;
    if (ct.commit matches tagged Valid .cb &&& !cb) dontCommit = True;
    if (ct.ft.invalidate) dontCommit = False;
    if (ct.thisReqNext && dontCommit) begin
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Don't commit, NULL response! ", $time, cacheId));
      Bool giveReadResponse = False;
      if (ct.ft.req.operation matches tagged Read .rop)  giveReadResponse = True;
      if (ct.ft.req.operation matches tagged CacheOp .cop &&& cop.inst == CacheLoadTag) giveReadResponse = True;
      if (giveReadResponse) ct.rt.resp.operation = tagged Read {
                                data: ?,
                                last: ct.thisReqLast
                            };
      ct.rt.valid = True;
    // This case will skip an attempt at success for now under the following conditions:
    end else if (ct.noWaitingReqs
                  /*|| (pendMem && (ooo||!isRead))*/ // Allow reads of pending locations to succeed if cache is in-order.
                  || (!ct.thisReqNext&&!ct.cached)  // Execute uncached operations strictly in order.
                  || filler.uncachedPending // Don't do anything if an uncached operation is outstanding.
                  || writebacks.canGet // If there is an unfinished writeback request so that we don't overfill request fifo.
                  || (ct.nextSetMatch&&ct.ft.fresh) // Don't lookup out of order if there is another request on this key
                ) begin
      // If this request is uncached and not next, don't do a lookup because an uncached load must be at the head of the queue
      // when the response comes back or the response will be dropped on the floor because it is not stored in the cache.
      // If it is in the head of the queue when we first issue the request, it will certainly be there when it gets back.
      //
      // Cached requests can begin early (though we will still respond in order).
      dead = True;
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> failing early ", $time, cacheId));
    end else begin
      case (ct.ft.req.operation) matches
        tagged CacheOp .cop &&& (!prefetchMissLocal): begin
          wayMiss = False;
          if (cop.cache == whichCache) begin
            if (pendMem) dead = True; // If there is a pending request on this line, kill it for this go-round.
            else begin
              if (cop.indexed) miss = False;
              case (cop.inst) matches
                CacheInternalInvalidate &&& (!miss): begin
                  ct.ft.invalidate = True;
                  doInvalidate = True;
                end
                CacheInvalidate &&& (!miss): begin
                  doInvalidate = True;
                end
                CacheInvalidateWriteback &&& (!miss): begin
                  doInvalidate = True;
                  if (roomForWriteback) writeback <- doWriteback;
                  else dead = True;
                end
                CacheWriteback &&& (!miss): begin
                  if (roomForWriteback) writeback <- doWriteback;
                  else dead = True;
                end
                CacheLoadTag: begin
                  returnTag = True;
                end
              endcase
              ct.rt.valid = True;
            end
          end else begin
            doMemRequest = True;
            if (cop.inst == CacheLoadTag) begin
              expectResponse = True;
            end else begin
              ct.rt.valid = True;
            end
          end
        end
        tagged Read .rop &&& (!miss && ct.cached && !passConditional): begin
          cachedResponse=True;
        end
        tagged Write .wop &&& (!miss && ct.cached && !passConditional): begin
          cachedWrite = True;
          tagUpdate[ct.way] = TagLine{
            tag      : tag.tag,
            dirty    : (writeThrough) ? False:True,
            pendMem  : tagUpdate[ct.way].pendMem,
            valid    : tag.valid
          };
          writeTags = True;
          if (writeThrough) doMemRequest = True;
        end
        tagged Write .wop &&& (!ct.cached): begin
          //Write directly to memory.
          doMemRequest = True;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Uncached Write - Invalidating key=0x%0x", $time, cacheId, ct.ft.addr.key));
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Sending ", $time, cacheId, fshow(ct.cacheCommit.memReq)));
          if (!miss) doInvalidate = True;
        end
        tagged Write .wop &&& writeThrough: begin
          doMemRequest = True;
          if (conditional) begin
            if (!miss) doInvalidate = True;
            expectResponse = True;
          end
        end
        default: begin
          // If it's a cached operation, align the access.
          if (ct.cached) begin 
            ct.cacheCommit.memReq.addr = unpack(pack(CacheAddress{
                                      tag: ct.ft.addr.tag, 
                                      key: ct.ft.addr.key, 
                                      bank: 0,
                                      offset:0
                                    }));
            writeTags = True;
            needWriteback = True;
          end
          
          ct.cacheCommit.memReq.operation = tagged Read {
                                uncached: !ct.cached,
                                linked: (ct.cached) ? linked:False,
                                noOfFlits: (ct.cached) ? 3:0,
                                bytesPerFlit: (ct.cached) ? cheriBusBytes : (case (ct.ft.req.operation) matches
                                    tagged Read .rop : return rop.bytesPerFlit;
                                  endcase)
                            };
          debug2("CacheCore", $display("CacheCore - Fetch on write Miss / cached Miss ", fshow(ct.ft.req)));
          doMemRequest = True;
          expectResponse = True;
        end
      endcase 
      
      if (!ct.thisReqNext) begin // If this is not the next request, kill the external request under two conditions...
        if (!ct.cached) dead = True;
        // Kill the operation if it is not a read, which (probably) has no side effects.
        if (ct.ft.req.operation matches tagged Read .rop) begin
        end else dead = True;
      end
      Bool writeTagsEvenIfDead = False;
      if (doMemRequest && !dead) begin
        // Don't issue a memory request if:
        //   Our table of outstanding memory requests if full
        //   If we don't have room for one more request in the output FIFO
        //   If this line already has an outstanding memory request
        Bool doMemRequestShouldSucceed = (!filler.noMoreReadReqs && roomForOneRequest && !pendMem);
        if (!doMemRequestShouldSucceed) debug2("CacheCore", 
          $display("<time %0t, cache %0d, CacheCore> External memory request failing: filler.noMoreReadReqs:%x, roomForOneRequest:%x, pendMem:%x", 
          $time, cacheId, filler.noMoreReadReqs, roomForOneRequest, pendMem));
        // If the conditions for a fill are good and we need to, do an eviction.
        if (needWriteback && tag.dirty && doMemRequestShouldSucceed) begin
            if (roomForReadAndWriteback) begin
              evict = True;
              writeback <- doWriteback;
            end
          else dead = True;
        end
        if (doMemRequestShouldSucceed && !dead) begin // And if this is the next request in the queue.
          ReqId outReqId = ReqId{masterID: ct.ft.req.masterID, transactionID: nextId};
          ct.cacheCommit.memReq.masterID = outReqId.masterID;
          ct.cacheCommit.memReq.transactionID = outReqId.transactionID;
          nextId <= nextId + 1;
          ct.cacheCommit.doMemReq = True;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Issuing external memory request, memReqFifoSpace:%x", 
                                        $time, cacheId, memReqFifoSpace, fshow(ct.cacheCommit.memReq)));
          if (expectResponse && ct.cached) begin
            tagUpdate[ct.way] = TagLine{
              tag    : ct.ft.addr.tag,
              pendMem: True,
              valid  : replicate(False),
              dirty  : False
            };
            writeTags = True;  // This must happen!
            writeTagsEvenIfDead = True;
          end
          RequestRecord#(ways, keyBits, tagBits) reqRec = RequestRecord{
                                                              key: ct.ft.addr.key, 
                                                              inId: reqId, 
                                                              cached: ct.cached,
                                                              oldTags: tagUpdate,
                                                              oldWay: ct.way,
                                                              oldDirty: ct.tagsRead[ct.way].dirty&&any(id,ct.tagsRead[ct.way].valid),
                                                              write: isWrite,
                                                              noOfFlits: ct.noOfFlits
                                                            };
          
          if (!ct.cached) begin
            ct.cacheCommit.pendingResponse = expectResponse;
            ct.cacheCommit.enqPending = True;
          end
          if (expectResponse) begin
            // Insert info about the outstanding request keyed by external request id.
            ct.cacheCommit.readId = outReqId;
            ct.cacheCommit.readRec = reqRec;
            ct.cacheCommit.insertReadRec = True;
            // Insert local request id into a list so that we don't service a duplicate ID before its done.
            ct.cacheCommit.reqId = reqId;
            ct.cacheCommit.insertReqId = True;
          end
        end else begin // Kill the operation if we were meant to send a memory request but couldn't
          dead = True;
          // Don't write tags for fill if we didn't send a request.
          if (expectResponse) writeTags = False;
        end
      end
      
      // Report state of lookup
      if (ct.firstFresh) begin // Only report once, when the lookup is fresh
        cycReport($display("%s[$%s%s%s] %x",
        `ifdef MULTI
          case (cacheId)
            0,1: return "c0";
            2,3: return "c1";
            4,5: return "c2";
            6,7: return "c3";
            default: return "";
          endcase,
        `else
            "",
        `endif
        case (whichCache)
          ICache: return "IL1";
          DCache: return "DL1";
          L2:     return "L2";
          TCache: return "T";
        endcase,
        ct.ft.req.operation matches tagged Read .* ?"R":"W",(miss)?"M":"H", ct.ft.addr));
        `ifdef STATCOUNTERS
        cacheCoreEvents <= CacheCoreEvents {
            id: cacheId,
            whichCache: whichCache,
            incHitWrite:   (!miss && isWrite),
            incMissWrite:  ( miss && isWrite),
            incHitRead:    (!miss && isRead),
            incMissRead:   ( miss && isRead),
            incHitPftch:   (!miss && isPftch),
            incMissPftch:  ( miss && isPftch),
            incEvict:      ( evict),
            incPftchEvict: ( evict && isPftch)
        };
        `endif
      end
      
      if (wayMiss) begin
        ct.wayUpdateKey = ct.ft.addr.key;
        ct.wayUpdate = ct.way;
        ct.doWayUpdate = True;
        dead = True;
        if (valueOf(ways) > 1)
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Way miss, %x != %x, wayHist[%x]<=%x", 
                                        $time, cacheId, ct.way, ct.ft.dataKey.way, ct.wayUpdateKey[3:0], ct.way));
      end else if (cachedResponse) begin
        //Return cached data.
        ct.rt.resp.operation = tagged Read {
            data: ct.dataRead,
            last: ct.thisReqLast
        };
        ct.rt.valid = True;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> returning @0x%0x:0x%0x", $time, cacheId, ct.ft.addr, ct.dataRead));
      end else if (returnTag) begin
        Bit#(CheriDataWidth) tagLo = 0;
        tagLo[30] = (tag.valid[ct.ft.addr.bank])?1:0;
        tagLo[29:0] = zeroExtend(tag.tag);
        debug2("CacheCore", $display("CacheCore: CacheLoadTag resp=%x", tagLo));
        ct.rt.resp.operation = tagged Read {
          data: Data {
            `ifdef USECAP
              cap: ct.dataRead.cap,
            `endif
            data: pack(tagLo)
            },
          last: ct.thisReqLast
        };
        ct.rt.valid = True;
      end
      
      // From this point on, kill the request completely if it is not next or if there is an outstanding memory request on this line.
      if (!ct.thisReqNext || pendMem) dead = True;
      
      // Do any tag update that has been requested if this update is committing (or if we issued a memory request).
      if (!dead||writeTagsEvenIfDead) begin
        if (doInvalidate) begin
          tagUpdate[ct.way] = invTag;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Invalidating key=0x%0x", $time, cacheId, ct.ft.addr.key));
          writeTags = True;
        end
        if (writeTags) begin
          //tags.write(ct.ft.addr.key, tagUpdate);
          ct.cacheCommit.key.key = ct.ft.addr.key; // Is dataKey.key == ct.ft.addr.key?
          ct.cacheCommit.tags = tagUpdate;
          ct.cacheCommit.writeTags = True;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Wrote tags key=0x%0x", $time, cacheId, ct.ft.addr.key, fshow(tagUpdate)));
        end
      end
      
      // Only finish the write if this is the next operation in order, and if this is not a way miss.
      if (ct.ft.req.operation matches tagged Write .wop &&& !dead) begin
        ct.rt.resp.operation = tagged Write;
        if (cachedWrite) begin
          //Construct new line.
          function Byte choose(Byte o, Byte n, Bool sel) = (sel) ? n:o;
          // zipWith3 combines the three vectors with the function "choose", defined above, producing another vector.
          // In this case it is just selecting the old byte or new byte based on byteEnable.
          Vector#(CheriBusBytes,Byte) maskedWriteVec = zipWith3(choose, unpack(ct.dataRead.data), unpack(wop.data.data), wop.byteEnable);
          Data#(CheriDataWidth) maskedWrite = wop.data;
          maskedWrite.data = pack(maskedWriteVec);
          `ifdef USECAP
            // Fold in capability tags.
            CapTags capTags = ct.dataRead.cap;
            Integer i = 0;
            //$display("wop.byteEnable: %x, capTags: %x, wop.data.cap: %x", wop.byteEnable, capTags, wop.data.cap);
            for (i=0; i<valueOf(CapsPerFlit); i=i+1) begin
              Integer bot = i*valueOf(CapBytes);
              Integer top = bot + valueOf(CapBytes) - 1;
              Bit#(CapBytes) capBytes = pack(wop.byteEnable)[top:bot];
              if (capBytes != 0) capTags[i] = wop.data.cap[i];
            end
            //$display("capTags: %x", capTags);
            maskedWrite.cap = capTags;
          `endif
          //Write updated line to cache.
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> wrote cache bank %x, way %x with %x",$time, cacheId, DataKey{key:ct.ft.addr.key, way:ct.way, bank:ct.ft.addr.bank},ct.way, maskedWrite));
          //data.write(DataKey{key:ct.ft.addr.key, way:ct.way, bank:ct.ft.addr.bank}, maskedWrite);
          ct.cacheCommit.key = DataKey{key:ct.ft.addr.key, way:ct.way, bank:ct.ft.addr.bank};
          ct.cacheCommit.data = maskedWrite;
          ct.cacheCommit.writeData = True;
          ct.rt.valid = True;
        end
        if (miss && writeThrough) ct.rt.valid = True;
        // If this is a store conditional and we're not handling it,
        // the response is coming later.
        if (conditional && writeThrough) dead = True;
        if (wop.uncached) ct.rt.valid = True;
      end
    end

    // Make sure it's dead if it's not next, and if this line has an outstanding memory request.
    if (!ct.thisReqNext || pendMem) dead = True;
    if (dead) ct.rt.valid = False;
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Request Dead %x, noReqs %x, thisReqNext %x ", 
                                  $time, cacheId, dead, ct.noWaitingReqs, ct.thisReqNext, fshow(ct.rt.resp)));
    // Report the hit or miss of this lookup, only once per access.
    if (ct.rt.valid == True) begin
      if (ct.thisReqLast) begin
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Finishing request ", $time, cacheId, fshow(ct.ft.req)));
        ct.rt.deqNext = True;
        ct.rt.deqId = getRespId(ct.rt.resp);
        if (!ct.ft.invalidate) ct.rt.deqReqCommits = True;
        ct.rt.rspFlit = 0;
        ct.rt.rspId = tagged Invalid;
      end else begin
        ct.rt.rspFlit = ct.rt.rspFlit + 1;
        ct.rt.rspId = tagged Valid getRespId(ct.rt.resp);
      end
      if (responseBehaviour == OnlyReadResponses) begin
        case (ct.rt.resp.operation) matches
          tagged Read .rop: ct.rt.resp = ct.rt.resp;
          default: ct.rt.valid = False;
        endcase
      end
      if (ct.ft.invalidate) ct.rt.valid = False;
    end
    // Only enq this one if it is fresh and not done.
    if (ct.firstFresh) begin
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enquing fresh request to retry reqs fifo ", $time, cacheId, fshow(ct.ft.req)));
      ct.rt.enqRetryReq = True;
    end
    return ct;
  endmethod
  `ifdef STATCOUNTERS
  interface Get cacheEvents;
    method ActionValue#(CacheCoreEvents) get ();
      return cacheCoreEvents;
    endmethod
  endinterface
  `endif
endmodule
