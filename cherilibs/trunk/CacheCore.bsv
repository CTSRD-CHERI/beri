/*-
 * Copyright (c) 2014 Jonathan Woodruff
 * Copyright (c) 2015 Alexandre Joannou
 * Copyright (c) 2016 Alan Mujumdar
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
 
interface CacheCore#(numeric type ways,
                     numeric type keyBits,
                     numeric type inFlight);
  method Bool canPut();
  method Action put(CheriMemRequest req);
  method CheckedGet#(CheriMemResponse) response();
  method Action nextWillCommit(Bool nextCommitting);
  method Action invalidate(CheriPhyAddr addr);
  method ActionValue#(Bool) invalidateDone();
  //interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef STATCOUNTERS
  interface Get#(ModuleEvents) cacheEvents;
  `endif
endinterface: CacheCore

typedef Bit#(tagBits) Tag#(numeric type tagBits);
typedef Bit#(keyBits) Key#(numeric type keyBits);
typedef 2 BankBits;
typedef Bit#(BankBits)     Bank;
typedef CheriPhyByteOffset Offset; 
typedef struct {
  Tag#(tagBits)    tag;
  Key#(keyBits)    key;
  Bank            bank;
  Offset        offset;
} CacheAddress#(numeric type keyBits, numeric type tagBits) deriving (Bits, Eq, Bounded, FShow);
typedef Bit#(TLog#(ways)) Way#(numeric type ways);

typedef struct {
  Key#(keyBits) key;
  Bank          bank;
} DataKey#(numeric type ways, numeric type keyBits) deriving (Bits, Eq, Bounded, FShow);

typedef struct {
  CheriTransactionID id;
  Bool           commit;
} CacheCommit deriving (Bits, Eq, Bounded, FShow);

typedef struct {
  Tag#(tagBits)                     tag;
  Bool                          pendMem;
  Bool                            dirty;
  Vector#(TExp#(BankBits), Bool)  valid;
} TagLine#(numeric type tagBits) deriving (Bits, Eq, Bounded, FShow);

typedef enum {Init, Serving} CacheState deriving (Bits, Eq, FShow);
typedef enum {Serve, Writeback, MemResponse} LookupCommand deriving (Bits, Eq, FShow);

typedef enum {WriteThrough, WriteAllocate}   WriteMissBehaviour deriving (Bits, Eq, FShow);
typedef enum {OnlyReadResponses, RespondAll} ResponseBehaviour deriving (Bits, Eq, FShow);
typedef enum {InOrder, OutOfOrder} OrderBehaviour deriving (Bits, Eq, FShow);

typedef struct {
  CacheAddress#(keyBits, tagBits) addr;
  TagLine#(tagBits)                tag;
  Way#(ways)                       way;
  Bool                          cached;
  ReqId                          reqId;
} AddrTagWay#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, FShow);

typedef struct {
  Tag#(tagBits)                    tag;
  Key#(keyBits)                    key;
  Way#(ways)                       way;
  Bool                           valid;
} InvalidateToken#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, FShow);

typedef struct {
  LookupCommand                               command;
  CheriMemRequest                                 req; // Original request that triggered the lookup.
  CacheAddress#(keyBits, tagBits)                addr; // Byte address of the frame that was fetched.
  BytesPerFlit                              readWidth; // Latch read width for speed, in case it is a read.
  DataKey#(ways, keyBits)                     dataKey; // Datakey used in the fetch (which duplicates some of addr and adds the way).
  Way#(ways)                                      way;
  Bool                                           last;
  Bool                                          fresh;
  InvalidateToken#(ways, keyBits, tagBits) invalidate; // Token containing any invalidate request
  Error                                      rspError;
} ControlToken#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, FShow);

typedef struct {
  CheriMemResponse     resp;
  CheriMemRequest       req; // Request to potentially enq into retryReqs.
  Bank              rspFlit;
  Maybe#(ReqId)       rspId;
  Bool              deqNext;
  ReqId               deqId;
  Bool        deqReqCommits;
  Bool          enqRetryReq;
  Bool         deqRetryReqs;
} ResponseToken deriving (Bits, FShow);

function ReqId getReqId(CheriMemRequest req);
  //Bool reqWrite = False;
  //if (req.operation matches tagged Write .wop) reqWrite = True;
  return ReqId{masterID: req.masterID, transactionID: req.transactionID};
endfunction

function ReqId getRespId(CheriMemResponse resp);
  //Bool respWrite = False;
  //if (resp.operation matches tagged Write .wop) respWrite = True;
  return ReqId{masterID: resp.masterID, transactionID: resp.transactionID};
endfunction

typedef struct {
  Key#(keyBits)                       key;
  ReqId                              inId;
  Bool                             cached;
  Vector#(ways,TagLine#(tagBits)) oldTags;
  Way#(ways)                       oldWay;
  Bool                           oldDirty;
  Bool                              write;
  Bank                          noOfFlits;
} RequestRecord#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, Eq, FShow);

typedef struct {
  Bank first;
  Bank last;
} BankBurst deriving (Bits, Eq, FShow);

typedef struct {
  ReqId inId;
  Bool isSC;
  Bool scResult;
} ReqIdWithSC deriving (Bits, Eq, FShow);

typedef struct {
  Bool                            doWrite;
  Key#(keyBits)                       key;
  Vector#(ways,TagLine#(tagBits)) newTags;
} TagUpdate#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, Eq, FShow);

typedef Vector#(TDiv#(CheriDataWidth,8), Bool) ByteEnable;

/*
 * The CacheCore module is a generic cache engine that is parameterisable
 * by number of sets, number of ways, number of outstanding request,
 * and selectable write-allocate or write-through behaviours.
 * In addition, if the cache core is used as a level1 cache (ICache or DCache)
 * it will return the 64-bit word requested in the bottom of the data field.
 */

module mkCacheCore#(Bit#(16) cacheId, 
                    WriteMissBehaviour writeBehaviour, 
                    ResponseBehaviour responseBehaviour,
                    OrderBehaviour orderBehaviour,
                    WhichCache whichCache,
                    // Must be > 5 or we can't issue reads with evictions!
                    // This means that a write-allocate cache must have >=5 capacity in the output fifo.
                    Bit#(10) memReqFifoSpace,
                    FIFOF#(CheriMemRequest) memReqs,
                    FIFOF#(CheriMemResponse) memRsps)
                   (CacheCore#(ways, keyBits, inFlight))
  provisos (
      Bits#(CheriPhyAddr, paddr_size),
      `ifdef MEM128 // The line size is different for each bus width.
        Log#(64, offset_size),
      `elsif MEM64
        Log#(32, offset_size),
      `else
        Log#(128, offset_size),
      `endif
      Add#(TAdd#(offset_size, keyBits), tagBits, paddr_size),
      Add#(smaller1, TLog#(ways), keyBits),
      Add#(smaller2, TLog#(ways), tagBits),
      Add#(smaller3, tagBits, 30),
      Add#(0, TLog#(TMin#(TExp#(keyBits), 16)), wayPredIndexSize),
      Add#(smaller4, wayPredIndexSize, keyBits),
      Add#(smaller5, 4, keyBits),
      Add#(a__, TAdd#(TLog#(inFlight), 1), 8),
      Bits#(CacheAddress#(keyBits, tagBits), 40)
    );
  Bool oneInFlight = valueOf(inFlight) == 1;
  Wire#(Maybe#(CheriMemRequest))                                 newReq <- mkDWire(tagged Invalid);
  FF#(CheriMemRequest, inFlight)                              retryReqs <- mkUGFFDebug("CacheCoreRealAssociative_retryReqs");
  FF#(ReqId,inFlight)                                              next <- (oneInFlight) ? mkUGLFF() : mkUGFFDebug("CacheCoreRealAssociative_next");
  Bag#(inFlight, ReqId, Key#(keyBits))                          nextSet <- mkSmallBag;
  Bag#(inFlight, ReqId, Bank)                               nextBankBag <- mkSmallBag;
  Reg#(Bool)                                                  nextEmpty <- mkConfigRegU;
  ResponseToken defaultResponseToken = ResponseToken{
    resp: ?,
    req: defaultValue,
    rspFlit: 0,
    rspId: tagged Invalid,
    enqRetryReq: False,
    deqNext: False,
    deqId: ?,
    deqReqCommits: False,
    deqRetryReqs: False
  };
  Wire#(ResponseToken)                                            resps <- mkDWire(defaultResponseToken);
  Wire#(Bool)                                                respsReady <- mkDWire(False);
  Wire#(Bool)                                                   gotResp <- mkDWire(False);
  Wire#(Bool)                                                missedResp <- mkDWire(False);
  Wire#(Bool)                                                    putReq <- mkDWire(False);
  FF#(ReqIdWithSC,TMul#(inFlight,2))                         writeResps <- mkUGFFDebug("CacheCoreRealAssociative_writeResps");
  ControlToken#(ways, keyBits, tagBits) null_ct = ?;
  null_ct.command = MemResponse;
  null_ct.req.operation = tagged CacheOp CacheOperation{inst: CacheNop, cache: whichCache, indexed: True};
  null_ct.req.masterID = -1; // Not matching any real master.
  null_ct.fresh = False;
  null_ct.invalidate.valid = False;
  ControlToken#(ways, keyBits, tagBits) initCt = null_ct;
  initCt.req = defaultValue;
  initCt.last = True;
  Reg#(ControlToken#(ways, keyBits, tagBits))                       cts <- mkConfigReg(initCt);
  Reg#(CacheState)                                           cacheState <- mkConfigReg(Init);
  MEM2#(Key#(keyBits), Vector#(ways,TagLine#(tagBits)))            tags <- mkMEMNoFlow2();
  Vector#(ways,MEM#(DataKey#(ways, keyBits), Data#(CheriDataWidth))) data <- replicateM(mkMEMNoFlow());
  Reg#(Key#(keyBits))                                             count <- mkConfigReg(0);
  Reg#(Key#(keyBits))                                         initCount <- mkReg(0);
  Reg#(CheriTransactionID)                                       nextId <- mkConfigReg(0);
  Reg#(Bank)                                                     inFlit <- mkConfigReg(0);
  Reg#(Bank)                                                    lkpFlit <- mkConfigReg(0);
  Reg#(ReqId)                                                     lkpId <- mkConfigRegU;
  Reg#(Bank)                                                 rspFlitReg <- mkConfigReg(0);
  Reg#(Maybe#(ReqId))                                          rspIdReg <- mkConfigReg(tagged Invalid); // When this one is valid we are in the middle of a response.
  FF#(Bool, 16)                                             req_commits <- mkUGFFBypass; // Plenty big!
  Reg#(Bool)                                            waitingOnMemory <- mkConfigReg(False);
  
  FIFOF#(AddrTagWay#(ways, keyBits, tagBits))                writebacks <- mkUGFIFOF1;
  Reg#(Bank)                                         writebackWriteBank <- mkConfigReg(0);
  // Only used if "supportDirtyBytes" is set, currently in the DCache when it is in Writeback mode.
  `ifdef WRITEBACK_DCACHE
    Vector#(ways,MEM#(DataKey#(ways, keyBits), ByteEnable))    dirtyBytes <- replicateM(mkMEMNoFlow());
  `endif
  // These will only be used if "supportInvalidates" is set, as selected below.
  FIFOF#(AddrTagWay#(ways, keyBits, tagBits))      invalidateWritebacks <- mkUGFIFOF1;
  FF#(CheriPhyAddr,4)                                       invalidates <- mkUGFFDebug("CacheCore_invalidates");
  FF#(InvalidateToken#(ways, keyBits, tagBits),8)    delayedInvalidates <- mkUGFFDebug("CacheCore_delayedInvalidates");
  FF#(Bool,32)                                          invalidatesDone <- mkUGFFDebug("CacheCore_invalidatesDone");
  FF#(void,2)                                          writethroughNext <- mkUGFFDebug("CacheCore_writethroughNext");
  
  FIFOF#(Bool)                                          uncachedPending <- mkUGFIFOF;  // The bool indicates a read response expected.
  Bag#(inFlight, ReqId, RequestRecord#(ways, keyBits, tagBits))readReqs <- mkSmallBag; // Hold data for outstanding memory requests
  Reg#(RequestRecord#(ways, keyBits, tagBits))               readReqReg <- mkRegU;      // Hold data for outstanding memory request if we have only one outstanding request.
  Bag#(inFlight, ReqId, Bit#(0))                              memReqIds <- mkSmallBag; // A searchable list of local request ids that have outstanding memory request.
  `ifdef STATCOUNTERS
    Wire#(CacheCoreEvents)  cacheCoreEventsWire <- mkDWire(defaultValue);
    Reg#(ReqId) lastRespId <- mkReg(unpack(~0));
  `endif
  
  Bool writeThrough = writeBehaviour==WriteThrough;
  Bool supportInvalidates = (writeBehaviour==WriteAllocate && whichCache==DCache);
  `ifdef MULTI
  `ifndef TIMEBASED
    supportInvalidates = True;
  `endif
  `endif
  Bool supportDirtyBytes = (writeBehaviour==WriteAllocate && whichCache==DCache);
  
  Bool ooo = orderBehaviour==OutOfOrder;
  `ifdef MULTI
    Bool performWritethrough = (writeThrough || writethroughNext.notEmpty);
  `else
    Bool performWritethrough = writeThrough;
  `endif
  
  Bool roomForOneRequest = memReqFifoSpace >= 1;
  // If the cache is writethrough, we never need to writeback.
  Bool roomForWriteback        = (writeThrough) ? True:(memReqFifoSpace >= 4);
  Bool roomForReadAndWriteback = (writeThrough) ? roomForOneRequest:(memReqFifoSpace >= 5);
  
  CheriMemRequest waitingReq = (oneInFlight) ? cts.req:retryReqs.first;
  
  // Invalid tag constant to use for invalidating tags.
  TagLine#(tagBits) invTag = ?;
  invTag.valid = replicate(False);
  invTag.pendMem = False;
  invTag.dirty = False;
  Vector#(ways,TagLine#(tagBits)) invTagVec = replicate(invTag);

  rule initialize(cacheState == Init);
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Initializing tag %0d", $time, cacheId, initCount));
    tags.write(pack(initCount), invTagVec);
    if (initCount == 0-1) begin
      cacheState <= Serving;
      initCount <= 0;
    end
    else begin
      initCount <= initCount + 1;
    end
    // Invalidate tags for any pending request.
    // This only works with one outstanding request! which is what we usually have for the DCache...
    readReqReg.oldTags <= invTagVec;
  endrule
  
  rule writeNextEmpty;
    nextEmpty <= (ooo) ? nextSet.empty:!next.notEmpty;
    waitingOnMemory <= (!memReqIds.empty) && isValid(memReqIds.isMember(next.first)) && next.notEmpty;
  endrule
  
  function ActionValue#(Maybe#(Way#(ways))) findWay(Vector#(ways,TagLine#(tagBits)) tagVec,Tag#(tagBits) tag, Bank bank);
    actionvalue
    function Bool validBank(TagLine#(tagBits) t) = (tag==t.tag && t.valid[bank]);//(t.valid[bank]||t.pendMem));
    return unpack(pack(findIndex(validBank, tagVec)));
    endactionvalue
  endfunction
  
  function ActionValue#(Maybe#(Way#(ways))) needsInvalidate(Vector#(ways,TagLine#(tagBits)) tagVec,Tag#(tagBits) tag);
    actionvalue
    function Bool validBank(TagLine#(tagBits) t) = (tag==t.tag && (pack(t.valid)!=0||t.pendMem));
    return unpack(pack(findIndex(validBank, tagVec)));
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
  
  (* no_implicit_conditions *)
  rule startLookup(cacheState != Init);
    // ===========================================================================================
    // Second half of rule that begins new lookup 
    // ===========================================================================================
    Bool valid = False;
    ControlToken#(ways, keyBits, tagBits) newCt = null_ct;
    newCt.req = unpack(truncate(pack(newReq)));
    newCt.addr = unpack(pack(newCt.req.addr));
    newCt.rspError = NoError;
    newCt.way = truncate(count);
    Bool last = True;
    
    Bank nLkpFlit = lkpFlit;
    Bool multiFlitReq = False;
    
    // If we have a valid new request, always run it immediatly.
    if (newReq matches tagged Valid .nr) begin
      newCt.fresh = True;
      nLkpFlit = 0;
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Selecting a fresh request ", $time, cacheId, fshow(newReq)));
      valid = True;
    end else begin
      // All the "non-fresh" cases which are less timing critical.
      CheriMemRequest lookupReq = defaultValue;
      if (memRsps.notEmpty || waitingOnMemory) begin
        newCt = cts;
        newCt.fresh = False;
        lookupReq = cts.req;
        newCt.command = MemResponse;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Trying a memory response ", $time, cacheId));
        // Make sure we don't forget any ongoing requests...
      end else if (!cts.last) begin
        // Continue lookup in register if the previous one was not the last.
        newCt = cts;
        //newCt.fresh = False;
        lookupReq = cts.req;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Selecting a continuing request ", $time, cacheId, fshow(lookupReq)));
        valid = True;
      end else if (oneInFlight && (!nextEmpty||cts.fresh)) begin
        // Continue lookup in register if we are a "oneInFlight" cache and therefore don't need retryReqs.
        newCt = cts;
        newCt.fresh = False;
        lookupReq = cts.req;
        valid = True;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Selecting to Recycle request in cts ", $time, cacheId, fshow(lookupReq), fshow(cts)));
      end else if (!oneInFlight && retryReqs.notEmpty) begin
        newCt.fresh = False;
        lookupReq = retryReqs.first();
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Selecting a recycled request ", $time, cacheId, fshow(lookupReq)));
        valid = True;
      end else begin
        // Just do a MemResponse by default.
        newCt = cts;
        newCt.fresh = False;
        lookupReq = cts.req;
        newCt.command = MemResponse;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Trying a memory response ", $time, cacheId));
      end
      // Reset the lookup flit counter if this request is for another ID.
      newCt.addr = unpack(pack(lookupReq.addr));
      newCt.req = lookupReq;
      if (getReqId(lookupReq)!=lkpId) nLkpFlit = 0;
      if (lookupReq.operation matches tagged Read .rop &&& rop.noOfFlits > 0) begin
        newCt.addr.bank = newCt.addr.bank + nLkpFlit;
        multiFlitReq = True;
      end
    end
    
    // Only issue a writeback there are no outstanding requests, just to be safe.
    if (writebacks.notEmpty /* && !newCt.fresh*/) begin // Take a writeback request with the highest priority.
      // Make sure it is obvious to an optimiser that a writethrough cache will not ever do this.
      if (!writeThrough) begin
        newCt.command = Writeback;
        AddrTagWay#(ways, keyBits, tagBits) evict = writebacks.first;
        newCt.way = evict.way;
        evict.addr.bank = writebackWriteBank;
        newCt.addr = unpack(pack(evict.addr));
        newCt.fresh = False;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Started Eviction, evict write bank: %x ", $time, cacheId, writebackWriteBank, fshow(evict)));
        last = (writebackWriteBank == 3); // Signal the last eviction frame to the lookup stage.
        Bank nextFetch = writebackWriteBank + 1;
        if (writebackWriteBank == 3) begin
          writebacks.deq();
          writebackWriteBank <= 0;
        end else writebackWriteBank <= nextFetch;
      end else writebacks.deq();
    end else if (supportInvalidates && invalidateWritebacks.notEmpty && !newCt.fresh) begin // Take a writeback request with the highest priority.
      // Make sure it is obvious to an optimiser that a writethrough cache will not ever do this.
      if (!writeThrough) begin
        newCt.command = Writeback;
        AddrTagWay#(ways, keyBits, tagBits) evict = invalidateWritebacks.first;
        newCt.way = evict.way;
        evict.addr.bank = writebackWriteBank;
        newCt.addr = unpack(pack(evict.addr));
        newCt.fresh = False;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Started Invalidate Eviction, evict write bank: %x ", $time, cacheId, writebackWriteBank, fshow(evict)));
        last = (writebackWriteBank == 3); // Signal the last eviction frame to the lookup stage.
        Bank nextFetch = writebackWriteBank + 1;
        if (writebackWriteBank == 3) begin
          invalidateWritebacks.deq();
          writebackWriteBank <= 0;
        end else writebackWriteBank <= nextFetch;
      end else invalidateWritebacks.deq();
    end else if (valid) begin
      newCt.command = Serve;
      if (newCt.req.operation matches tagged CacheOp .cop) begin
        if (cop.indexed) newCt.way = truncate(newCt.addr.tag);
        if (cop.inst == CacheNop) begin // Special state identical to MemResponse except that it gives a null response to the pipeline.
          newCt.command = MemResponse;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Trying a memory response ", $time, cacheId));
        end
      end
      if (multiFlitReq) begin
        if (nLkpFlit == 3) last = True;
        else last = False;
        nLkpFlit = nLkpFlit + 1;
      end else nLkpFlit = 0;
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Started memory request, lkpFlit:%x(%x), lkpId:%x(%x) last:%x started lookup ", 
                                    $time, cacheId, lkpFlit, nLkpFlit, lkpId, getReqId(newCt.req), last, fshow(newCt.addr), fshow(newCt.req)));
    end
    lkpFlit <= nLkpFlit;
    lkpId <= getReqId(newCt.req);
    // Always start the fetch so that memory responses can be consumed!
    newCt.dataKey = DataKey{key:newCt.addr.key, bank: newCt.addr.bank};
    newCt.last = last;
    newCt.readWidth = BYTE_128;
    if (newCt.req.operation matches tagged Read .rop) newCt.readWidth = rop.bytesPerFlit;
    
    // Only service an invalidate if there are no pending writebacks.
    // Service any invalidate if there is one...
    if (supportInvalidates) begin
      if (delayedInvalidates.notEmpty) begin
        newCt.invalidate = delayedInvalidates.first;
        delayedInvalidates.deq;
        CacheAddress#(keyBits, tagBits) invAddr = unpack(0);
        invAddr.key = newCt.invalidate.key;
        invAddr.tag = newCt.invalidate.tag;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed delayed invalidate, addr: %x", $time, cacheId, invAddr));
        tags.readB.put(newCt.invalidate.key);
      end else if (invalidates.notEmpty) begin
        CacheAddress#(keyBits, tagBits) invAddr = unpack(pack(invalidates.first));
        invalidates.deq;
        newCt.invalidate.tag = invAddr.tag;
        newCt.invalidate.key = invAddr.key;
        newCt.invalidate.valid = True;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed an invalidate, addr: %x", $time, cacheId, invAddr));
        tags.readB.put(invAddr.key);
      end else newCt.invalidate.valid = False;
    end
    
    // Start tag lookup
    tags.read.put(newCt.dataKey.key);
    // Start data lookup
    Integer i;
    for (i=0; i<valueOf(ways); i=i+1) data[i].read.put(newCt.dataKey);
    `ifdef WRITEBACK_DCACHE
      if (supportDirtyBytes) begin
        for (i=0; i<valueOf(ways); i=i+1) dirtyBytes[i].read.put(newCt.dataKey);
      end
    `endif
    cts <= newCt;
  endrule
  
  (* no_implicit_conditions *)
  rule finishLookup(cacheState != Init);
    // ===========================================================================================
    // First half of rule that looks at the present lookup and potentially writes 
    // ===========================================================================================
    Maybe#(Bool) commit = (req_commits.notEmpty) ? (tagged Valid req_commits.first()):(tagged Invalid);
    // If we are in the serving state and our unguarded fifos are not full.
    ControlToken#(ways, keyBits, tagBits)     ct  =  cts;
    CacheAddress#(keyBits, tagBits)         addr  =  ct.addr;
    Vector#(ways,TagLine#(tagBits))     tagsRead <- tags.read.get();
    Maybe#(Way#(ways)) mWay <- findWay(tagsRead,addr.tag,addr.bank);
    Bool miss = !isValid(mWay);
    Way#(ways) way = truncate(pack(mWay));
    if (writeBehaviour==WriteAllocate) way = fromMaybe(ct.way,mWay);
    //if (ct.command!=Writeback) way <- findWay(tagsRead,addr.tag,addr.bank);
    
    // Independantly of the tag match, get the data from all the ways and shift it down.
    // This moves the shift from later to now where it can be in parallel with the match and select.
    function ActionValue#(Data#(CheriDataWidth)) getData(MEM#(DataKey#(ways, keyBits), Data#(CheriDataWidth)) bram) = bram.read.get();
    Vector#(ways, Data#(CheriDataWidth)) datasRead <- mapM(getData,data);
    Offset dataShift = 0;
    `ifdef USECAP
      Bit#(TLog#(CapsPerFlit)) capShift = 0;
    `endif
    if (whichCache==DCache || whichCache==ICache) begin
      dataShift = {truncateLSB(addr.offset),3'b0};
      `ifdef USECAP
        capShift = truncateLSB(dataShift);
      `endif
    end
    function Data#(CheriDataWidth) shiftData(Data#(CheriDataWidth) data) = 
              Data{
                data: (data.data)>>{dataShift,3'b0}
                `ifdef USECAP
                  , cap: unpack(pack(data.cap)>>capShift)
                `endif
              };
    // Put the 64-bit word of interest in the bottom.
    Vector#(ways, Data#(CheriDataWidth)) shiftedDatasRead = map(shiftData,datasRead);
    Data#(CheriDataWidth) shiftedDataRead = shiftedDatasRead[way];
    
    // Select the data that matched the way.
    Data#(CheriDataWidth) dataRead = datasRead[way];
    ByteEnable dirties = unpack(-1);
    `ifdef WRITEBACK_DCACHE
      if (supportDirtyBytes) begin
        dirties <- dirtyBytes[way].read.get();
      end
    `endif
    // After data is selected with the matched way, handle the other "way" cases that don't need matching data.
    // This fast-tracks data selection, but lets things like invalidates, which need another source for way, still work.
    if (cts.req.operation matches tagged CacheOp .cop &&& cop.indexed) way = cts.way;
    else if (ct.command==Serve && miss) way = cts.way;
    
    TagLine#(tagBits) tag = tagsRead[way];
    TagUpdate#(ways, keyBits, tagBits) tagsUpdate = TagUpdate{
      doWrite: False,
      key: addr.key,
      newTags: tagsRead
    };
    TagLine#(tagBits) tagUpdate = tagsRead[way];
    
    Bool respForWrite = False;
    Bool firstFresh = cts.fresh && pack(cts.req.addr)==pack(cts.addr); // This is the first of a set of fresh requests.
    // Check if there is a pending transaction for this index.
    mWay <- findPendingWay(tagsRead); // For this case, we just need to find the way that is expecting a fill, if there is one.
    Bool pendMem = isValid(mWay); // If this index has a pending memory transaction.
    Bool cached = True; // Just a default value.
    Bank noOfFlits = 0;
    if (ct.req.operation matches tagged Read .rop) noOfFlits = truncate(pack(rop.noOfFlits));
    Bool scResult = False;
    Bool respondWithSC = False;
    
    Bool invalidateDone = False;
    Bool failedInvalidate = False;
    Vector#(ways,TagLine#(tagBits)) invTags = ?;
    Maybe#(Way#(ways)) invPendWay = tagged Invalid;
    if (supportInvalidates) begin
      // Do tag match for invalidates ("shadow" tags, i.e. 2nd read port of tags).
      invTags <- tags.readB.get();
      if (ct.invalidate.valid) begin
        Maybe#(Way#(ways)) invWay <- needsInvalidate(invTags,ct.invalidate.tag);
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Invalidate lookup. ", $time, cacheId, fshow(ct.invalidate), fshow(invTags)));
        if (invWay matches tagged Valid .aWay) begin
          ct.invalidate.way = aWay;
          Maybe#(Way#(ways)) pending <- findPendingWay(invTags);
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Invalidate hit. key: %x, aWay: %x, invTags[aWay].pendMem: %x, isValid(pending)", $time, cacheId, ct.invalidate.key, aWay, invTags[aWay].pendMem, isValid(pending)));
          if (isValid(pending)) begin
            invPendWay = tagged Valid aWay;
            if (readReqReg.write && writethroughNext.notFull) writethroughNext.enq(?);
            if (!oneInFlight) $display("Panic!  Pending invalidation not supported yet with more than one in flight in CacheCore.");
          end
        end else invalidateDone = True; // Invalidate is done if it is not a hit!
      end
    end
    
    CheriMemRequest req = ct.req;
    Bool dead = False;  // To allow us to kill this operation at any stage.

    Bool cachedResponse = False;
    Bool cachedWrite = False;
    Bool returnTag = False;
    Bool writeback = False;
    Bool doInvalidate = False;
    Bool writeTags = False;
    Bool writeTagsEvenIfDead = False;
    Bool expectResponse = False;
    Bool evict = False;
    Bool isPftch = {case (req.operation) matches
                    tagged CacheOp .cop &&& (cop.inst == CachePrefetch && cop.cache == whichCache): return True;
                    default: return False;
                   endcase};
    Bool deqRetryReqs = False;
    Bool deqNext = False;
    ReqId deqId = getReqId(req);
    Bool deqReqCommits = False;
    Bool linked = {case (req.operation) matches
                      tagged Read .rop:  return rop.linked;
                      default: return False;
                    endcase};
    Bool conditional = {case (req.operation) matches
                      tagged Write .wop: return wop.conditional;    
                      default: return False;
                    endcase};
    cached = {case (req.operation) matches
                      tagged Read .rop:  return !rop.uncached;
                      tagged Write .wop: return !wop.uncached;
                      tagged CacheOp .cop &&& (cop.inst == CachePrefetch && cop.cache == whichCache): True;
                      default: return False;
                    endcase};
    Bool prefetchMissLocal = (isPftch && miss);

    // If this is not the last-level cache, then a lower level will handle ordering
    // of load-linked and store conditional.
    Bool handleLinked = whichCache==L2;
    
    // If this cache doesn't handle load linked, then force a miss.
    Bool passConditional = (!handleLinked && (linked||conditional));

    ReqId reqId     = getReqId(req);
    ReqId nextReqId = next.first;
    Bool ongoingResponse = isValid(rspIdReg);
    ReqId rspId = fromMaybe(reqId,rspIdReg);
    Bank rspFlit = (rspId==reqId)?rspFlitReg:0;
    Bool isWrite = False;
    if (req.operation matches tagged Write .wop) isWrite = True;
    if (prefetchMissLocal) isWrite = True;
    Bool isRead = False;
    if (req.operation matches tagged Read .rop) isRead = True;
    // Derive the bank range for the pending request
    CacheAddress#(keyBits, tagBits) reqAddr = unpack(pack(cts.req.addr)); // Address of original request.
    BankBurst nextBank = BankBurst{first: reqAddr.bank, last: reqAddr.bank};
    if (noOfFlits != 0) nextBank = BankBurst{first: 0, last: 3};
    Bool noReqs = (ooo) ? nextSet.empty:!next.notEmpty;
    Bool thisReqNext = (!noReqs
                        && addr.bank == nextBank.first + rspFlit
                        && isValid(commit)); // If this is the next flit expected
    if (ooo) begin
      // Only allow the response sequence to continue if it is for the same ID we have been responding to.
      thisReqNext = thisReqNext && (!ongoingResponse||rspId==reqId);
      // Also only respond if this request is still outstanding.
      thisReqNext = thisReqNext && isValid(nextSet.isMember(reqId));
    end else thisReqNext = thisReqNext && reqId==nextReqId;
    
    // If this is the last flit of transaction
    Bool thisReqLast = (!noReqs &&  (nextBank.last == nextBank.first + rspFlit));
    if (!noReqs) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> thisReqNext:%x, reqId:%x, nextReqId:%x, thisReqLast:%x, thisBank: %x, nextBank.last:%x, nextBank.first:%x, rspFlit:%x, rspId:%x, nextSet.isMember(reqId):%x, isValid(commit):%x, pendMem:%x, miss:%x",
                                       $time, cacheId, thisReqNext, reqId, nextReqId, thisReqLast, addr.bank, nextBank.last, nextBank.first, rspFlit, rspId, isValid(nextSet.isMember(reqId)), isValid(commit), pendMem, miss));
    // Setup any memory responses ====
    CheriMemResponse memResp = memRsps.first;
    Data#(CheriDataWidth) shiftedMemRespData = shiftData(memResp.data);
    
    Bool respValid = False;
    CheriMemResponse cacheResp = defaultValue;
    cacheResp.masterID = req.masterID;
    cacheResp.transactionID = req.transactionID;
    cacheResp.error = ct.rspError;
    // Pull assignment of cacheResp.data out of all other conditionals for speed.
    cacheResp.data = shiftedDataRead;
    if (ct.command == MemResponse) cacheResp.data = shiftedMemRespData;
    
    // These hold and control enqing the request to the retry fifo.
    CheriMemRequest memReq = req; // Request to forward to memory.
    Bool enqRetryReq = False;
    
    if (!noReqs) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Commit:%x, Serving request ", $time, cacheId, commit, fshow(ct), fshow(dataRead), fshow(tagsRead)));

    `ifdef STATCOUNTERS
      CacheCoreEvents cacheCoreEvents = defaultValue;
    `endif
    
    RequestRecord#(ways, keyBits, tagBits) newReadReqReg = readReqReg;
    
    case (ct.command)
      /*Nop: begin
        if (memRsps.notEmpty) begin
          if (memResp.operation matches tagged Write .wop) begin
            memRsps.deq;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received write memory response ", $time, cacheId, fshow(memResp)));
            if (uncachedPending.notEmpty && !uncachedPending.first) begin 
              uncachedPending.deq();
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, cacheId));
            end
          end
        end
        dead = True;
      end*/
      Writeback: begin
        if (memRsps.notEmpty) begin
          if (memResp.operation matches tagged Write .wop) begin
            memRsps.deq;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received write memory response ", $time, cacheId, fshow(memResp)));
            if (uncachedPending.notEmpty && !uncachedPending.first) begin 
              uncachedPending.deq();
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, cacheId));
            end
          end
        end
        Bool lineDirty = True;
        if (supportDirtyBytes) begin
          lineDirty = pack(dirties) != 0;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Checking dirties for writeback, bank %x, way %d, %x, lineDirty: %d", $time, cacheId, ct.dataKey, way, dirties, lineDirty));
        end
        // Make it obvious to the optimiser that this logic isn't required for a writethrough cache.
        if (!writeThrough && lineDirty) begin
          req.operation = tagged Write {
                      uncached: False,//True,
                      conditional: False,
                      byteEnable: dirties,
                      bitEnable: -1,
                      data: dataRead,
                      last: True
                  };
          req.addr = unpack(pack(ct.addr));
          req.masterID = truncate(cacheId);
          req.transactionID = nextId;
          nextId <= nextId+1;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Issuing external writeback memory request memReqs.notFull:%x, memReqFifoSpace:%x ", 
                                         $time, cacheId, memReqs.notFull, memReqFifoSpace, fshow(req)));
          memReqs.enq(req);
          `ifdef WRITEBACK_DCACHE
            if (supportDirtyBytes) begin
              dirtyBytes[cts.way].write(ct.dataKey, unpack(0)); // Line is now clean.
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> updated dirties bank %x, way %x with %x",$time, cacheId, 
                                            ct.dataKey, cts.way, 0));
            end
          `endif
          `ifdef STATCOUNTERS
            if (ct.addr.bank==0) cacheCoreEvents.incEvict = True; // trace a writeback once per line.
          `endif
        end
      end
      MemResponse: begin
        ct.req.operation = tagged Read {uncached: ?, linked: ?, noOfFlits: ?, bytesPerFlit: ?};
        ReqId memRspId = getRespId(memRsps.first);
        Bool last = getLastField(memResp);
        if (memRsps.notEmpty) begin
          if (memResp.operation matches tagged Write .wop) begin
            memRsps.deq;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received write memory response ", $time, cacheId, fshow(memResp)));
            if (uncachedPending.notEmpty && !uncachedPending.first) begin 
              uncachedPending.deq();
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, cacheId));
            end
          end else begin
            memRsps.deq;
            // Simplify the decision for operation type to speed up logic.
            Maybe#(RequestRecord#(ways, keyBits, tagBits)) mReqRec = (oneInFlight) ? tagged Valid readReqReg:readReqs.isMember(memRspId);
            RequestRecord#(ways, keyBits, tagBits) reqRec = fromMaybe(?,mReqRec); // Just grab the bits.
            way                = reqRec.oldWay;
            tagsUpdate.newTags = reqRec.oldTags;
            tag = reqRec.oldTags[way];
            CacheAddress#(keyBits, tagBits) tmpAddr = unpack(pack(ct.req.addr));
            // This not the bank of the response, but the bank of the original request.
            // In the !(ooo) case, the bank of the original request will simply be the existing bank in ct.
            ct.addr.bank = fromMaybe(tmpAddr.bank,nextBankBag.isMember(reqRec.inId));
            ct.addr.tag = reqRec.oldTags[way].tag;
            ct.addr.key = reqRec.key;
            cached      = reqRec.cached;
            ct.req.masterID      = reqRec.inId.masterID;
            ct.req.transactionID = reqRec.inId.transactionID;
            ct.rspError = memResp.error;
            // Store original request address before updating the bank.
            ct.req.addr = unpack(pack(ct.addr));
            // This is only accurate if the response is cached (assuming that external cached reads are bursts aligned on cache lines).
            ct.addr.bank = truncate(pack(inFlit));
            addr = ct.addr; // addr = address of incoming data
            ct.dataKey = DataKey{key:ct.addr.key, bank: ct.addr.bank};
            ct.req.operation = tagged Write {
                                    uncached: !cached,
                                    conditional: False,
                                    byteEnable: replicate(True),
                                    bitEnable: -1,
                                    data: memResp.data,
                                    last: last
                                  };
            case (memResp.operation) matches
              tagged Read .rr: begin
                respForWrite = reqRec.write;
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Memory response lookup, last:%x ", $time, cacheId, last, fshow(ct.req)));                                    
                // Construct reqId to recall key.
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Found %x in ID table", $time, cacheId, memRspId, fshow(reqRec)));
                noOfFlits   = reqRec.noOfFlits;
                if (mReqRec matches tagged Valid .reqRecValid) begin
                  if (!reqRecValid.cached) begin
                    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, cacheId));
                    uncachedPending.deq();
                  end
                  if (last) begin
                    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing %x from ID table", $time, cacheId, memRspId, fshow(reqRec)));
                    if (!oneInFlight) readReqs.remove(memRspId);
                    memReqIds.remove(getReqId(ct.req));
                  end
                end else $display("<time %0t, cache %0d, CacheCore> Panic!  received response for index that was not expected!", $time, cacheId);
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received memory response ", $time, cacheId, fshow(memResp)));
                
                ct.last = last;
                if (last) begin
                  inFlit <= 0;
                  ct.last = True;
                end else inFlit <= inFlit + 1;
              end
              tagged SC .scr: begin
                scResult = scr;
                respondWithSC = True;
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing %x from ID table", $time, cacheId, memRspId, fshow(scr)));
                if (!oneInFlight) readReqs.remove(memRspId);
                memReqIds.remove(getReqId(ct.req));
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> store conditional response lookup, scResult:%x, last:%x ", $time, cacheId, scResult, last, fshow(ct.req)));
              end
            endcase
          end
        end
        
        req = ct.req;
        deqId = getReqId(req);
        deqReqCommits = False;
        linked = {case (req.operation) matches
                          tagged Read .rop:  return rop.linked;
                          default: return False;
                        endcase};
        conditional = {case (req.operation) matches
                          tagged Write .wop: return wop.conditional;    
                          default: return False;
                        endcase};
        cached = {case (req.operation) matches
                          tagged Write .wop: return !wop.uncached;
                          default: return False;
                        endcase};

        reqId     = getReqId(req);
        ongoingResponse = isValid(rspIdReg);
        rspId = fromMaybe(reqId,rspIdReg);
        rspFlit = (rspId==reqId)?rspFlitReg:0;
        if (noOfFlits != 0) nextBank = BankBurst{first: 0, last: 3};
        thisReqNext = (!noReqs
                       && addr.bank == nextBank.first + rspFlit
                       && isValid(commit)); // If this is the next flit expected
        if (ooo) begin
          // Only allow the response sequence to continue if it is for the same ID we have been responding to.
          thisReqNext = thisReqNext && (!ongoingResponse||rspId==reqId);
          // Also only respond if this request is still outstanding.
          thisReqNext = thisReqNext && isValid(nextSet.isMember(reqId));
        end else thisReqNext = thisReqNext && reqId==nextReqId;
        
        // If this is the last flit of transaction
        thisReqLast = (!noReqs &&  (nextBank.last == nextBank.first + rspFlit));
        Bool cacheNop = False;
        if (!noReqs) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> thisReqNext:%x, reqId:%x, nextReqId:%x, thisReqLast:%x, thisBank: %x, nextBank.last:%x, nextBank.first:%x, rspFlit:%x, rspId:%x, nextSet.isMember(reqId):%x, isValid(commit):%x, pendMem:%x",
                                          $time, cacheId, thisReqNext, reqId, nextReqId, thisReqLast, addr.bank, nextBank.last, nextBank.first, rspFlit, rspId, isValid(nextSet.isMember(reqId)), isValid(commit), pendMem));
      
        // Setup response ID fields in case we return the response.
        cacheResp.masterID = rspId.masterID;
        cacheResp.transactionID = rspId.transactionID;
        
        case (ct.req.operation) matches
          tagged Write .wop: begin
            if (!cached) begin
              thisReqNext = True;
              thisReqLast = True;
            end else if (memResp.error!=NoError || respondWithSC) begin // We don't know the bank in this case!
              thisReqNext = (reqId == nextReqId)||(ooo && isValid(nextSet.isMember(reqId)));
              // Should check if commit is valid, but we can't structurally handle the case where it is not. 
              // Ignore the flit/bank number in this case, and this should be guaranteed to match for uncached responses.
              thisReqLast = True; // Assuming no bursts for read errors.
            end
            if (cached && !respondWithSC) begin
              // Do fill
              data[way].write(ct.dataKey, wop.data);  
              `ifdef WRITEBACK_DCACHE
                if (supportDirtyBytes) begin
                  dirtyBytes[way].write(ct.dataKey, unpack(0));  
                  debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> updated dirties bank %x, way %x with %x",$time, cacheId, 
                                            ct.dataKey, way, 0));
                end
              `endif
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> filled cache bank %x, way %x with %x", 
                                          $time, cacheId, ct.dataKey, way, wop.data));
              // If pendMem is already clear, this line has been invalidated previously, so don't do a tag update.
              if (tag.pendMem) begin
                tag.valid[addr.bank] = True;
                // If there was an error, declare the whole line valid to prevent deadlock due to repeated refetching.
                if (memResp.error!=NoError) tag.valid = unpack(-1);
                if (ct.last) tag.pendMem = False;
                tagsUpdate.newTags[way] = tag;
                //tags.write(ct.dataKey.key, tagsUpdate.newTags);
                tagsUpdate.doWrite = True;
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Wrote tags key=0x%0x, way=%d ", $time, cacheId, addr.key, way, fshow(tag), fshow(tagsRead)));
              end
              RequestRecord#(ways, keyBits, tagBits) reqRec = RequestRecord{
                                                                    key: ct.dataKey.key, 
                                                                    inId: reqId, 
                                                                    cached: cached,
                                                                    oldTags: tagsUpdate.newTags,
                                                                    oldWay: way,
                                                                    oldDirty: tag.dirty&&any(id,tag.valid),
                                                                    write: respForWrite,
                                                                    noOfFlits: noOfFlits
                                                                 };
              // Only update if it is still in the set.
              if (!ct.last) begin
                if (oneInFlight) newReadReqReg = reqRec;
                else readReqs.insert(memRspId, reqRec); // Update tag record!
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Updating %x in ID table", $time, cacheId, memRspId, fshow(reqRec)));
              end
            end else if (respondWithSC) begin
              cacheResp.operation = tagged SC scResult;
              //respValid = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> cached and store conditional ", $time, cacheId, fshow(cacheResp)));
              dead = True;
              // If pendMem is already clear, this line has been invalidated previously, so don't do a tag update.
              if (tag.pendMem) begin
                // Clear the "pendMem" flag in the tags for this line.
                tag.pendMem = False;
                tagsUpdate.newTags[way] = tag;
                //tags.write(ct.dataKey.key, tagsUpdate.newTags);
                tagsUpdate.doWrite = True;
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Wrote tags key=0x%0x, way=%d ", $time, cacheId, addr.key, way, fshow(tag), fshow(tagsRead)));
              end
            end
            // doWrite set above.
            tagsUpdate.key = ct.dataKey.key;
          end
          default: thisReqNext = False; // Don't send a response if we've had no memory response!
        endcase
        
        // These few lines send a basic response to a CacheNop request if we have one.
        // Feeding CacheNop's through this path allows us to consume memory responses
        // while responding to Nops.
        
        // Look at original request, not the possibly overwritten version.
        if (cts.req.operation matches tagged CacheOp .cop &&& cop.inst == CacheNop) begin
          if (getReqId(cts.req)==nextReqId && !noReqs) cacheNop = True;
        end
        if (cacheNop) begin
          thisReqNext = True;
          thisReqLast = True;
          respForWrite = False;
          cacheResp.operation = tagged Write;
          cacheResp.masterID = cts.req.masterID;
          cacheResp.transactionID = cts.req.transactionID;
        end
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> thisReqNext:%x, pendMem:%x, respForWrite:%x, reqId:%x, nextReqId:%x, thisReqLast:%x",
                                    $time, cacheId, thisReqNext, pendMem, respForWrite, reqId, nextReqId, thisReqLast));
        // Send a response if this memory response was for the request that is next, 
        // and if this request was not a write request.
        if (thisReqNext && !respForWrite) begin
          if (!respondWithSC && !cacheNop) begin
            cacheResp.operation = tagged Read {
                last: thisReqLast
            };
          end
          
          respValid = True;
          if (cacheResp.operation matches tagged Write .wop &&& responseBehaviour==OnlyReadResponses) respValid = False;
          if (thisReqLast) begin
            if (!cts.fresh && !oneInFlight) begin
              deqRetryReqs = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> dequing retry reqs ", $time, cacheId, fshow(retryReqs.first)));
            end
            deqNext = True;
            deqReqCommits = True;
            rspFlit = 0;
            ongoingResponse = False;
          end else begin
            rspFlit = rspFlit + 1;
            rspId = getRespId(cacheResp);
            ongoingResponse = True;
          end
        end
      end
      Serve: begin
        if (memRsps.notEmpty) begin
          if (memResp.operation matches tagged Write .wop) begin
            memRsps.deq;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received write memory response ", $time, cacheId, fshow(memResp)));
            if (uncachedPending.notEmpty && !uncachedPending.first) begin 
              uncachedPending.deq();
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, cacheId));
            end
          end
        end
        Bool doMemRequest = False;
        function ActionValue#(Bool) doWriteback = actionvalue
          Bool doingEviction = False;
          if (tag.valid[addr.bank] && tag.dirty && !writeThrough) begin
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Requesting eviction! Address: %x", $time, cacheId, CacheAddress{tag: tag.tag, key: addr.key, bank: addr.bank, offset: 0}));
            writebacks.enq(AddrTagWay{
              way   : way,
              tag   : tag,
              addr  : CacheAddress{tag: tag.tag, key: addr.key, bank: addr.bank, offset: 0},
              cached: True,
              reqId : reqId
            });
            doingEviction = True;
          end
          return doingEviction;
        endactionvalue;
        
        Bool needWriteback = False;
        Bool dontCommit = False;
        // If the instruction did not commit, don't perform the cache instruction.
        if (commit matches tagged Valid .cb &&& !cb) dontCommit = True;
        // Unliess it is a CacheWriteback, since it might be injected as a cache flush for coherency, and it doesn't modify state anyway. 
        if (req.operation matches tagged CacheOp .cop &&& cop.inst matches tagged CacheWriteback) dontCommit = False;
        if (req.operation matches tagged CacheOp .cop &&& cop.inst matches tagged CacheSync)      dontCommit = False;
        if (thisReqNext && dontCommit) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Don't commit, NULL response! ", $time, cacheId));
          Bool giveReadResponse = False;
          if (req.operation matches tagged Read .rop)  giveReadResponse = True;
          
          if (giveReadResponse) cacheResp.operation = tagged Read {
                                    last: thisReqLast
                                };
          else if (req.operation matches tagged Write .wop &&& wop.conditional)
                                cacheResp.operation = tagged SC False;
          
          respValid = True;
        // This case will skip an attempt at success for now under the following conditions:
        end else if (noReqs
                      || (pendMem && miss)//(ooo||!isRead)) // Allow reads of pending locations to succeed if cache is in-order.
                      || (!thisReqNext&&!cached)  // Execute uncached operations strictly in order.
                      || uncachedPending.notEmpty // Don't do anything if an uncached operation is outstanding.
                      || writebacks.notEmpty // If there is an unfinished writeback request so that we don't overfill request fifo.
                      || invalidateWritebacks.notEmpty
                      || (nextSet.dataMatch(addr.key)&&ct.fresh) // Don't lookup out of order if there is another request on this key
                    ) begin
          // If this request is uncached and not next, don't do a lookup because an uncached load must be at the head of the queue
          // when the response comes back or the response will be dropped on the floor because it is not stored in the cache.
          // If it is in the head of the queue when we first issue the request, it will certainly be there when it gets back.
          //
          // Cached requests can begin early (though we will still respond in order).
          dead = True;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> failing early - noReqs(%x), (pendMem(%x) && miss(%x)), (!thisReqNext(%x) && !cached(%x)), uncachedPending.notEmpty(%x), writebacks.notEmpty(%x), (nextSet.dataMatch(addr.key)(%x) && ct.fresh(%x))", 
                                       $time, cacheId, noReqs, pendMem, miss, thisReqNext, cached, uncachedPending.notEmpty, writebacks.notEmpty, nextSet.dataMatch(addr.key), ct.fresh));
        end else begin
          case (req.operation) matches
            tagged CacheOp .cop &&& (!prefetchMissLocal): begin
              if (cop.cache == whichCache) begin
                if (pendMem) dead = True; // If there is a pending request on this line, kill it for this go-round.
                else begin
                  respValid = True;
                  if (cop.indexed) miss = False;
                  case (cop.inst) matches
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
                    // TIME-BASED COHERENCE, manage barrier instructions
                    CacheSync: begin
                      `ifdef TIMEBASED
                        // When we get a SYNC for the self-invalidate case, we just toast the whole cache.
                        // We had better not have any dirty lines in this case!
                        cacheState <= Init;
                        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Cache SYNC received, reinitialising cache", $time, cacheId));
                      `endif
                    end
                  endcase
                end
              end else begin
                doMemRequest = True;
                respValid = True;
              end
            end
            tagged Read .rop &&& (!miss && cached && passConditional && !writeThrough && tag.dirty): begin
              doInvalidate = True;
              if (roomForWriteback) writeback <- doWriteback;
              else dead = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Load Linked - Dirty line, requires writeback", $time, cacheId, addr.key));
            end
            tagged Read .rop &&& (!miss && cached && !passConditional): begin
              cachedResponse=True;
            end
            tagged Write .wop &&& passConditional: begin
              // If the tag we are going to use is dirty, evict. 
              // (not really sure why we need a tag slot, but that's how the mechanism works in the general case, so we'll go with it.)
              if (tag.dirty) begin 
                doMemRequest = False;
                dead = True;
                if (roomForWriteback) begin
                  writeback <- doWriteback;
                  doInvalidate = True;
                  writeTagsEvenIfDead = True;
                end
              end else begin
                doMemRequest = True;
                // Setup flags for outstanding request.
                // It should not be necessary to always invalidate the line, but we must let
                // later operations know that there is an pending memory request on this line.
                tagUpdate = invTag;
                tagUpdate.pendMem = True;
                writeTags = True;
                writeTagsEvenIfDead = True;
                ct.way = way;
                tagsUpdate.newTags[way] = tagUpdate;
                // done with tag update.
                expectResponse = True;
              end
            end
            tagged Write .wop &&& (!miss && cached && !passConditional): begin
              cachedWrite = True;
              tagUpdate = TagLine{
                tag      : tag.tag,
                dirty    : (performWritethrough) ? False:True,
                pendMem  : tagUpdate.pendMem,
                valid    : tag.valid
              };
              if (!writeThrough && tag.dirty != True) writeTags = True;
              if (performWritethrough) doMemRequest = True;
            end
            tagged Write .wop &&& (!cached): begin
              //Write directly to memory.
              doMemRequest = True;
              if (!miss) begin
                dead = True;
                writeTagsEvenIfDead = True;
                if (tag.dirty) begin
                  if (roomForWriteback) begin
                    writeback <- doWriteback;
                    doInvalidate = True;
                  end
                end else doInvalidate = True;
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Uncached Write Hit - tag.dirty: %x, roomForWriteback: %x", $time, cacheId, tag.dirty, roomForWriteback));
              end else debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Sending ", $time, cacheId, fshow(memReq)));
            end
            tagged Write .wop &&& (performWritethrough): begin
              doMemRequest = True;
              if (!miss) doInvalidate = True;
            end
            default: begin  // It's a miss!
              // If it's a cached operation, align the access.
              if (cached) begin 
                memReq.addr = unpack(pack(CacheAddress{
                                          tag: addr.tag, 
                                          key: addr.key, 
                                          bank: 0,
                                          offset:0
                                       }));
                // If the conditions for a fill are good and we need to, do an eviction.
                if (tag.dirty) begin
                  debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> CacheCore - attempting Writeback roomForReadAndWriteback: %x ", $time, cacheId, roomForReadAndWriteback));
                  if (roomForReadAndWriteback) writeback <- doWriteback;
                  else dead = True;
                end
              end
              
              memReq.operation = tagged Read {
                                    uncached: !cached,
                                    linked: (cached) ? linked:False,
                                    noOfFlits: (cached) ? 3:0,
                                    bytesPerFlit: (cached) ? cheriBusBytes : (case (req.operation) matches
                                        tagged Read .rop : return rop.bytesPerFlit;
                                      endcase)
                                };
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> CacheCore - Fetch on write Miss / cached Miss ", $time, cacheId, fshow(req)));
              doMemRequest = True;
              expectResponse = True;
            end
          endcase 
          
          if (!thisReqNext) begin // If this is not the next request, kill the external request under two conditions...
            if (!cached) dead = True;
            // Kill the operation if it is not a read, which (probably) has no side effects.
            if (memReq.operation matches tagged Read .rop) begin
            end else dead = True;
          end
          if (doMemRequest && !dead) begin
            // Don't issue a memory request if:
            //   Our table of outstanding memory requests if full
            //   If we don't have room for one more request in the output FIFO
            //   If this line already has an outstanding memory request
            Bool doMemRequestShouldSucceed = (!memReqIds.full && roomForOneRequest && !pendMem);
            if (!doMemRequestShouldSucceed) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> External memory request failing: memReqIds.full:%x, roomForOneRequest:%x, pendMem:%x", $time, cacheId, memReqIds.full, roomForOneRequest, pendMem));
            if (doMemRequestShouldSucceed && !dead) begin // And if this is the next request in the queue.
              ReqId outReqId = ReqId{masterID: req.masterID, transactionID: nextId};
              memReq.masterID = outReqId.masterID;
              memReq.transactionID = outReqId.transactionID;
              nextId <= nextId + 1;
              memReqs.enq(memReq);
              if (!cached) begin
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enquing pending uncached request", $time, cacheId));
                uncachedPending.enq(expectResponse);
              end
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Issuing external memory request, memReqs.notFull:%x, memReqFifoSpace:%x ", 
                                            $time, cacheId, memReqs.notFull, memReqFifoSpace, fshow(memReq)));
              if (expectResponse) begin
                if (cached) begin
                  tagUpdate = TagLine{
                    tag     : addr.tag,
                    pendMem : True,
                    valid   : replicate(False),
                    dirty   : False
                  };
                  writeTags = True;  // This must happen!
                  writeTagsEvenIfDead = True;
                  ct.way = way;
                  tagsUpdate.newTags[way] = tagUpdate;
                end
                
                RequestRecord#(ways, keyBits, tagBits) reqRec = RequestRecord{
                                                                  key: addr.key, 
                                                                  inId: reqId, 
                                                                  cached: cached,
                                                                  oldTags: tagsUpdate.newTags,
                                                                  oldWay: way,
                                                                  oldDirty: tag.dirty&&any(id,tag.valid),
                                                                  write: isWrite,
                                                                  noOfFlits: noOfFlits
                                                               };
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Inserting %x into ID table", $time, cacheId, outReqId, fshow(reqRec)));
                // Insert info about the outstanding request keyed by external request id.
                if (oneInFlight) newReadReqReg = reqRec;
                else readReqs.insert(outReqId, reqRec);
                // Insert local request id into a list so that we don't service a duplicate ID before its done.
                memReqIds.insert(reqId, ?);
              end
            end else begin // Kill the operation if we were meant to send a memory request but couldn't
              dead = True;
              // Don't write tags for fill if we didn't send a request.
              if (expectResponse) writeTags = False;
            end
          end

          // Report state of lookup
          if (firstFresh) begin // Only report once, when the lookup is fresh
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
            req.operation matches tagged Read .* ?"R":"W",(miss)?"M":"H", addr));
          end
          `ifdef STATCOUNTERS
            cacheCoreEvents = CacheCoreEvents {
              id: cacheId,
              whichCache: whichCache,
              incHitWrite:   (firstFresh && !miss && isWrite),
              incMissWrite:  (firstFresh &&  miss && isWrite),
              incHitRead:    (firstFresh && !miss && isRead),
              incMissRead:   (firstFresh &&  miss && isRead),
              incHitPftch:   (firstFresh && !miss && isPftch),
              incMissPftch:  (firstFresh &&  miss && isPftch),
              incEvict:      (False),
              incPftchEvict: (evict && isPftch)
              `ifdef USECAP
                ,
                incSetTagWrite: ?,
                incSetTagRead:  ?
              `endif
            };
          `endif
          
          if (cachedResponse) begin
            //Return cached data.
            cacheResp.operation = tagged Read {
                last: thisReqLast
            };
            
            respValid = True;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> returning @0x%0x:0x%0x", $time, cacheId, addr, dataRead));
          end
          
          // From this point on, kill the request completely if it is not next or if there is an outstanding memory request on this line.
          if (!thisReqNext || (pendMem&&!isRead)) dead = True;
          
          // Do any tag update that has been requested if this update is committing (or if we issued a memory request).
          if (!dead||writeTagsEvenIfDead) begin
            if (doInvalidate) begin
              tagsUpdate.newTags[way] = invTag;
              //tags.write(addr.key, tagsUpdate);
              tagsUpdate.doWrite = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Invalidating key=0x%0x, way=%d", $time, cacheId, addr.key, way));
            end else if (writeTags) begin
              tagsUpdate.newTags[way] = tagUpdate;
              //tags.write(addr.key, tagsUpdate);
              tagsUpdate.doWrite = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Wrote tags key=0x%0x, way=%d ", $time, cacheId, addr.key, way, fshow(tagUpdate), fshow(tagsUpdate)));
            end
          end
          
          // Only finish the write if this is the next operation in order.
          if (req.operation matches tagged Write .wop &&& !dead) begin
            cacheResp.operation = tagged Write;
            if (cachedWrite) begin
              //Construct new line.
              function Byte choose(Byte o, Byte n, Bool sel) = (sel) ? ((n&wop.bitEnable)|(o&~wop.bitEnable)):o;
              // zipWith3 combines the three vectors with the function "choose", defined above, producing another vector.
              // In this case it is just selecting the old byte or new byte based on byteEnable.
              Vector#(CheriBusBytes,Byte) maskedWriteVec = zipWith3(choose, unpack(dataRead.data), unpack(wop.data.data), wop.byteEnable);
              Data#(CheriDataWidth) maskedWrite = wop.data;
              maskedWrite.data = pack(maskedWriteVec);
              `ifdef USECAP
                // Fold in capability tags.
                CapTags capTags = dataRead.cap;
                $display("wop.byteEnable: %x, capTags: %x, wop.data.cap: %x", wop.byteEnable, capTags, wop.data.cap);
                Integer i;
                for (i=0; i<valueOf(CapsPerFlit); i=i+1) begin
                  Integer bot = i*valueOf(CapBytes);
                  Integer top = bot + valueOf(CapBytes) - 1;
                  Bit#(CapBytes) capBytes = pack(wop.byteEnable)[top:bot];
                  if (capBytes != 0) capTags[i] = wop.data.cap[i];
                end
                //$display("capTags: %x", capTags);
                maskedWrite.cap = capTags;
                `ifdef STATCOUNTERS
                  cacheCoreEvents.incSetTagWrite = pack(capTags) != 0;
                `endif
              `endif
              //Write updated line to cache.
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> wrote cache bank %x, way %x with %x",$time, cacheId, 
                                           {addr.key, addr.bank}, way, maskedWrite));
              dataRead = maskedWrite;
              data[way].write(DataKey{key:addr.key, bank:addr.bank}, dataRead);
              `ifdef WRITEBACK_DCACHE
                if (supportDirtyBytes) begin
                  // Update the dirty bytes if we didn't write through.  Could check performWritethrough, but possibly checking doMemRequest is more reliable.
                  if (!writeThrough && !doMemRequest) dirties = unpack(pack(dirties)|pack(wop.byteEnable)); // Mark newly written bytes as dirty.
                  else dirties = unpack(pack(dirties)&~pack(wop.byteEnable)); // If we have written through, these bytes are clean.
                  dirtyBytes[way].write(DataKey{key:addr.key, bank:addr.bank}, dirties);
                  debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> updated dirties bank %x, way %x with %x, doMemRequest: %d",$time, cacheId, 
                                            {addr.key, addr.bank}, way, dirties, doMemRequest));
                end
              `endif
              respValid = True;
            end
            // If this is a store conditional and we're not handling it,
            // the response is coming later.
            if (conditional && (performWritethrough)) dead = True;
            if (supportInvalidates && writethroughNext.notEmpty && doMemRequest && !dead) writethroughNext.deq;
            if (miss && (performWritethrough)) respValid = True;
            if (wop.uncached) respValid = True;
          end
        end

        if (dead) respValid = False;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Request Dead %x, noReqs %x, thisReqNext %x uncachedPending.notEmpty %x ", 
                                      $time, cacheId, dead, noReqs, thisReqNext, uncachedPending.notEmpty, fshow(cacheResp)));
        // Report the hit or miss of this lookup, only once per access.
        if (respValid) begin
          if (thisReqLast) begin
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Finishing request ", $time, cacheId, fshow(req)));
            // If this successful response came from the retry fifo, deq it now.
            if (retryReqs.notEmpty && getReqId(retryReqs.first) == getRespId(cacheResp)) begin
              deqRetryReqs = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> dequing retry reqs ", $time, cacheId, fshow(retryReqs.first)));
            end
            deqNext = True;
            deqId = getRespId(cacheResp);
            deqReqCommits = True;
            rspFlit = 0;
            ongoingResponse = False;
          end else begin
            rspFlit = rspFlit + 1;
            rspId = getRespId(cacheResp);
            ongoingResponse = True;
          end
          if (responseBehaviour == OnlyReadResponses) begin
            case (cacheResp.operation) matches
              tagged Read .rop: respValid = respValid; // Do nothing, we're only interested in the default case.
              tagged SC   .scr: respValid = respValid; // Do nothing, we're only interested in the default case.
              default: respValid = False;
            endcase
          end
          `ifdef STATCOUNTERS
            `ifdef USECAP
              if (cacheResp.operation matches tagged Read .rop &&& getRespId(cacheResp) != lastRespId) begin
                cacheCoreEvents.incSetTagRead = pack(cacheResp.data.cap) != 0;
              end
            `endif
            lastRespId <= getRespId(cacheResp);
          `endif
        end
        if (firstFresh) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enquing fresh request to retry reqs fifo ", $time, cacheId, fshow(cts.req)));
          enqRetryReq = True;
        end
      end
    endcase

    `ifdef STATCOUNTERS
      cacheCoreEventsWire <= cacheCoreEvents;
    `endif
    
    Bool needInvWriteback = False;
    if (supportInvalidates) begin
      // If we're meant to write an invalidate but we need to write tags for a regular lookup, mark the failure so we can retry.
      if (ct.invalidate.valid && tagsUpdate.doWrite) failedInvalidate = True;
    end
    if (tagsUpdate.doWrite) tags.write(tagsUpdate.key,tagsUpdate.newTags);
    else if (supportInvalidates && ct.invalidate.valid && !invalidateDone && !failedInvalidate ) begin
      Bool failedWriteback = False;
      TagLine#(tagBits) oldTag = invTags[ct.invalidate.way];
      needInvWriteback = oldTag.valid[0] && oldTag.dirty && !writeThrough;
      if (needInvWriteback) begin
        if (roomForWriteback && invalidateWritebacks.notFull) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Requesting eviction for invalidate! Address: %x ", 
                                      $time, cacheId, CacheAddress{tag: tag.tag, key: addr.key, bank: addr.bank, offset: 0}, fshow(ct.invalidate)));
          invalidateWritebacks.enq(AddrTagWay{
            way   : ct.invalidate.way,
            tag   : oldTag,
            addr  : CacheAddress{tag: oldTag.tag, key: ct.invalidate.key, bank: 0, offset: 0},
            cached: True,
            reqId : reqId
          });
        end else failedWriteback = True;
      end
      if (!failedWriteback) begin
        Vector#(ways,TagLine#(tagBits)) tagsToWrite = invTags;
        tagsToWrite[ct.invalidate.way] = invTag;
        invalidateDone = True;
        tags.write(ct.invalidate.key, tagsToWrite);
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Invalidate, wrote tags key: %x, ", $time, cacheId, ct.invalidate.key, fshow(tagsToWrite)));
        // If this way is also pending, wipe out the copy of the tags in the readReqReg (only works with oneInFlight)
        if (invPendWay matches tagged Valid .invWay) begin
          newReadReqReg.oldTags[invWay] = invTag;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Invalidated pending tag record, readReqReg.oldTags <- ", $time, cacheId, fshow(newReadReqReg.oldTags)));
        end
      end
      //failedInvalidate = failedWriteback;
    end
    if (supportInvalidates && ct.invalidate.valid) begin
      if (!invalidateDone) delayedInvalidates.enq(cts.invalidate);
      else begin
        invalidatesDone.enq(needInvWriteback);
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> enqued invalidates done, needInvWriteback: %x", $time, cacheId, needInvWriteback));
      end
    end
    if (oneInFlight) readReqReg <= newReadReqReg;
    
    if (ooo && retryReqs.notEmpty && !isValid(nextSet.isMember(getReqId(retryReqs.first)))) begin
      deqRetryReqs=True;
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> dequing retry reqs, not found in next", $time, cacheId, fshow(retryReqs.first)));
    end
    // Save all the state-changing writes for the get method.
    resps <= ResponseToken{
      resp: cacheResp,
      req: cts.req,
      rspFlit: rspFlit,
      rspId: (ongoingResponse) ? tagged Valid rspId:tagged Invalid,
      enqRetryReq: enqRetryReq,
      deqNext: deqNext,
      deqId: deqId,
      deqReqCommits: deqReqCommits,
      deqRetryReqs: deqRetryReqs
    };
    respsReady <= respValid;
    count <= count + 1; // Increment count to randomise way selection.
    if (respValid) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Setting valid response ", $time, cacheId, fshow(cacheResp)));
  endrule
  
  (* no_implicit_conditions *)
  rule deqNext(!missedResp); // Ensure that next is dequed every time it is requested to be dequed.
    ResponseToken rt = resps;
    if (rt.deqNext) begin
      if (ooo) begin
        nextSet.remove(rt.deqId);
        nextBankBag.remove(rt.deqId);
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing reqId from next ", $time, cacheId, fshow(rt.deqId)));
      end else begin
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed next, %x", $time, cacheId, next.first));
        next.deq;
      end
    end
    if (rt.deqReqCommits && req_commits.notEmpty) begin
      req_commits.deq;
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed req_commits ", $time, cacheId, fshow(req_commits.first)));
    end
    if (rt.deqRetryReqs && !oneInFlight) begin
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed retry reqs ", $time, cacheId, fshow(retryReqs.first)));
      retryReqs.deq;
    end
    if (rt.rspFlit != rspFlitReg || rt.deqNext || rt.deqReqCommits || rt.enqRetryReq)
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Updating cache state ", $time, cacheId, fshow(rt)));
  endrule
  
  // This function encapsulates the actions that should be taken to serve
  // the response wires if we will not consume them in the response method.
  // This may be done either in the catchResponse rule or in the method itself
  // if it chooses a write response.
  function Action updateStateNoResponse();
    action
      ResponseToken rt = resps;
      Bool updateState = False;
      //debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> updateStateNoResponse called ", $time, cacheId));
      if (!respsReady) begin
        updateState = True;
      end else if (rt.resp.operation matches tagged Write &&& writeResps.notFull) begin
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Missed Delivering write response, buffered it ", $time, cacheId, fshow(rt)));
        ReqIdWithSC enqToWriteResps = ReqIdWithSC{inId: getRespId(rt.resp), isSC: False, scResult: False};
        writeResps.enq(enqToWriteResps);
        updateState = True;
      end else if (rt.resp.operation matches tagged SC .sc &&& writeResps.notFull) begin
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Missed Delivering SC response, buffered it ", $time, cacheId, fshow(rt)));
        ReqIdWithSC enqToWriteResps = ReqIdWithSC{inId: getRespId(rt.resp), isSC: True, scResult: sc};
        writeResps.enq(enqToWriteResps);
        updateState = True;
      end else begin
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Missed Delivering response ", $time, cacheId, fshow(rt)));
        if (resps.enqRetryReq && !oneInFlight) begin
          if (!retryReqs.notFull) $display("Panic!  enqing retry reqs when full!");
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enqued retry reqs ", $time, cacheId, fshow(rt.req)));
          retryReqs.enq(resps.req);
        end
      end
      missedResp <= !updateState;
      if (updateState) begin
        //rspFlitReg <= rt.rspFlit;
        //rspIdReg <= rt.rspId;
        /*if (rt.deqNext) begin
          if (ooo) begin
            nextSet.remove(rt.deqId);
            nextBankBag.remove(rt.deqId);
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing reqId from next ", $time, cacheId, rt.deqId));
          end else begin
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed next, %x", $time, cacheId, next.first));
            next.deq;
          end
        end
        if (rt.deqReqCommits && req_commits.notEmpty) begin
          req_commits.deq;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed req_commits ", $time, cacheId, fshow(req_commits.first)));
        end
        if (rt.deqRetryReqs && !oneInFlight) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed retry reqs ", $time, cacheId, fshow(retryReqs.first)));
          retryReqs.deq;
        end*/
        if (rt.enqRetryReq && (!respsReady || !rt.deqNext) && !oneInFlight) begin
          if (!retryReqs.notFull) $display("Panic!  enqing retry reqs when full!");
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enqued retry reqs ", $time, cacheId, fshow(rt.req)));
          retryReqs.enq(rt.req);
        end
        //if (rt.rspFlit != rspFlitReg || rt.deqNext || rt.deqReqCommits || rt.enqRetryReq)
        //  debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Updating cache state ", $time, cacheId, fshow(rt)));
      end
    endaction
  endfunction
  
  rule catchResponse(!gotResp);
    updateStateNoResponse();
  endrule
  
  // These conditions tell us whether a new request will certainly be caught if it is inserted.
  Bool roomInNext = (ooo) ? !nextSet.full:next.notFull;
  Bool roomInRetryReqs = (oneInFlight) ? True:retryReqs.remaining >= truncate(8'h2);
  Reg#(ReqId) nextIncomingReqId <- mkRegU;
  Bool nextReqIdHasOutstandingRequest = isValid(memReqIds.isMember(nextIncomingReqId));
  
  Bool putCondition = (roomInNext && roomInRetryReqs && !nextReqIdHasOutstandingRequest && cacheState != Init && !writebacks.notEmpty);
  method Bool canPut() = putCondition;
  method Action put(CheriMemRequest req) if (putCondition);
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Putting new request", $time, cacheId, fshow(req)));
    CacheAddress#(keyBits, tagBits) ca = unpack(pack(req.addr));
    ReqId id = getReqId(req);
    if (ooo) begin
      nextSet.insert(id, ca.key);
      //debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Inserting reqId at bank in next ", $time, cacheId, getReqId(req), ca.bank));
      nextBankBag.insert(id, ca.bank);
    end else next.enq(id);
    newReq <= tagged Valid req;
    
    nextIncomingReqId <= ReqId{masterID: id.masterID, transactionID: id.transactionID + 1};
  endmethod
  
  interface CheckedGet response;
    method canGet = respsReady||writeResps.notEmpty;
    method CheriMemResponse peek;
      ResponseToken rt = resps;
      CheriMemResponse ret = rt.resp;
      if (writeResps.notEmpty) begin
        ret = defaultValue;
        ret.masterID = writeResps.first.inId.masterID;
        ret.transactionID = writeResps.first.inId.transactionID;
        ret.operation = writeResps.first.isSC ? tagged SC  writeResps.first.scResult : tagged Write;
      end
      return ret;
    endmethod
    method ActionValue#(CheriMemResponse) get;
      gotResp <= True;
      ResponseToken rt = resps;
      CheriMemResponse ret = rt.resp;
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> get called ", $time, cacheId));
      if (writeResps.notEmpty) begin
        ret = defaultValue;
        ret.masterID = writeResps.first.inId.masterID;
        ret.transactionID = writeResps.first.inId.transactionID;
        ret.operation = writeResps.first.isSC ? tagged SC  writeResps.first.scResult : tagged Write;
        writeResps.deq;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Delivering valid buffered write response ", $time, cacheId, fshow(ret)));
        updateStateNoResponse();
      end else begin
        if (respsReady) begin
          rspFlitReg <= rt.rspFlit;
          rspIdReg <= rt.rspId;
       
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Delivering valid response ", $time, cacheId, fshow(rt)));
          // If response is ready and the request is being completed (deqNext), don't put it in retryReqs.
          if (rt.enqRetryReq && !rt.deqNext && !oneInFlight) begin
            if (!retryReqs.notFull) $display("Panic!  enqing retry reqs when full!");
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enqued retry reqs ", $time, cacheId, fshow(rt.req)));
            retryReqs.enq(rt.req);
          end
        end else begin 
          if (rt.enqRetryReq && !oneInFlight) begin
            if (!retryReqs.notFull) $display("Panic!  enqing retry reqs when full!");
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enqued retry reqs ", $time, cacheId, fshow(rt.req)));
            retryReqs.enq(rt.req);
          end
        end
        // Update this state as requested whether we had a ready response or not.
        /*if (rt.deqNext) begin
          if (ooo) begin
            nextSet.remove(rt.deqId);
            nextBankBag.remove(rt.deqId);
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing reqId from next ", $time, cacheId, rt.deqId));
          end else begin
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed next, %x", $time, cacheId, next.first));
            next.deq;
          end
        end
        if (rt.deqReqCommits && req_commits.notEmpty) begin
          req_commits.deq;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed req_commits ", $time, cacheId, fshow(req_commits.first)));
        end*/
        /*if (rt.deqRetryReqs && !oneInFlight) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed retry reqs ", $time, cacheId, fshow(retryReqs.first)));
          retryReqs.deq;
        end*/
      end
      return ret;
    endmethod
  endinterface
  
  method Action nextWillCommit(Bool nextCommitting) if (req_commits.notFull);
    req_commits.enq(nextCommitting);
  endmethod
  
  method Action invalidate(CheriPhyAddr addr) if (invalidates.notFull && (delayedInvalidates.remaining > 4));
    if (supportInvalidates) invalidates.enq(addr);
  endmethod
  // The cache is ~consistent if there are no outstanding invalidates.
  method ActionValue#(Bool) invalidateDone() if (invalidatesDone.notEmpty);
    Bool ret = False;
    if (supportInvalidates) begin
      ret = invalidatesDone.first;
      invalidatesDone.deq;
    end
    return ret;
  endmethod

  `ifdef STATCOUNTERS
  interface Get cacheEvents;
      method ActionValue#(ModuleEvents) get;
          return tagged CacheCore_E cacheCoreEventsWire;
      endmethod
  endinterface
  `endif
endmodule
