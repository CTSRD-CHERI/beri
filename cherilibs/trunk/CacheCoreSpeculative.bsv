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
  method Action invalidateDone();
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
  Way#(ways)    way;
  Bank          bank;
} DataKey#(numeric type ways, numeric type keyBits) deriving (Bits, Eq, Bounded, FShow);

typedef struct {
  CheriTransactionID id;
  Bool           commit;
} CacheCommit deriving (Bits, Eq, Bounded, FShow);

// TIME-BASED COHERENCE, constants 
`ifdef TIMEBASED
  `define TIMEBITS 4     // time-counter bits stored in Tags
  `define TIMEOUT 1      // time-counter increment value
  `define TIMEVALID 1000 // Number of cycles a cache line is valid
`endif

typedef struct {
  Tag#(tagBits)                     tag;
  Bool                          pendMem;
  Bool                            dirty;
  Vector#(TExp#(BankBits), Bool)  valid;
  // TIME-BASED COHERENCE, time stamp added to the tags
  `ifdef TIMEBASED
    Bit#(`TIMEBITS)           timeStamp;
  `endif
} TagLine#(numeric type tagBits) deriving (Bits, Eq, Bounded, FShow);

typedef enum {Init, Serving} CacheState deriving (Bits, Eq, FShow);
typedef enum {Nop, Serve, Invalidate, Writeback, MemResponse} LookupCommand deriving (Bits, Eq, FShow);

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
  LookupCommand                       command;
  CheriMemRequest                         req; // Original request that triggered the lookup.
  CacheAddress#(keyBits, tagBits)        addr; // Byte address of the frame that was fetched.
  DataKey#(ways, keyBits)             dataKey; // Datakey used in the fetch (which duplicates some of addr and adds the way).
  Bool                                   last;
  Bool                                  fresh;
  Bool                             invalidate; // This request was triggered by an invalidate request.
  Error                              rspError;
  Bool                         canTakeMemResp; // Pregenerate boolean to indicate if we will take a memory response if there is one for speed.
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
  TagLine#(tagBits)                oldTag;
  Way#(ways)                       oldWay;
  Bool                           oldDirty;
  Bool                              write;
  Bank                          noOfFlits;
} RequestRecord#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, Eq, FShow);

typedef struct {
  Bank first;
  Bank last;
} BankBurst deriving (Bits, Eq, FShow);

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
                    Bit#(6) memReqFifoSpace,
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
      Add#(0, TLog#(TMin#(TExp#(keyBits), 128)), wayPredIndexSize),
      Add#(smaller4, wayPredIndexSize, keyBits),
      Add#(smaller5, 4, keyBits),
      Add#(a__, TAdd#(TLog#(inFlight), 1), 8)
    );
  Bool oneInFlight = valueOf(inFlight) == 1;
  Wire#(Maybe#(CheriMemRequest))                                 newReq <- mkDWire(tagged Invalid);
  FF#(CheriMemRequest, inFlight)                              retryReqs <- mkUGFFDebug("CacheCore_retryReqs");
  FF#(ReqId,inFlight)                                              next <- (oneInFlight) ? mkUGLFF() : mkUGFFDebug("CacheCore_next");
  Bag#(inFlight, ReqId, Key#(keyBits))                          nextSet <- mkSmallBag;
  Bag#(inFlight, ReqId, Bank)                                  nextBank <- mkSmallBag;
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
  Wire#(Bool)                                                    putReq <- mkDWire(False);
  FF#(ReqId,TMul#(inFlight,2))                               writeResps <- mkUGFFDebug("CacheCore_writeResps");
  ControlToken#(ways, keyBits, tagBits) initCt = ?;
  initCt.req = defaultValue;
  initCt.command = Nop;
  initCt.last = True;
  Reg#(ControlToken#(ways, keyBits, tagBits))                       cts <- mkConfigReg(initCt);
  Reg#(CacheState)                                           cacheState <- mkConfigReg(Init);
  Reg#(Vector#(TMin#(TExp#(keyBits), 128), Way#(ways)))         wayHist <- mkConfigRegU;
  Vector#(ways,MEM#(Key#(keyBits), TagLine#(tagBits)))             tags <- replicateM(mkMEMNoFlow());
  MEM#(DataKey#(ways, keyBits), Data#(CheriDataWidth))             data <- mkMEMNoFlow();
  Reg#(Key#(keyBits))                                             count <- mkConfigReg(0);
  Reg#(Key#(keyBits))                                         initCount <- mkReg(0);
  Reg#(CheriTransactionID)                                       nextId <- mkConfigReg(0);
  Reg#(Bank)                                                     inFlit <- mkConfigReg(0);
  Reg#(Bank)                                                    lkpFlit <- mkConfigReg(0);
  Reg#(ReqId)                                                     lkpId <- mkConfigRegU;
  Reg#(Bank)                                                 rspFlitReg <- mkConfigReg(0);
  Reg#(Maybe#(ReqId))                                          rspIdReg <- mkConfigReg(tagged Invalid); // When this one is valid we are in the middle of a response.
  FF#(Bool, 16)                                             req_commits <- mkUGFFBypass(); // Plenty big!
  
  FIFOF#(AddrTagWay#(ways, keyBits, tagBits))                writebacks <- mkUGFIFOF1;
  Reg#(Bank)                                         writebackWriteBank <- mkConfigReg(0);
  FIFOF#(CheriPhyAddr)                                      invalidates <- mkSizedFIFOF(4);
  FIFOF#(Key#(keyBits))                              timedOutInvalidate <- mkUGSizedFIFOF(1);
  Reg#(Bit#(8))                                          invalidateTime <- mkReg(0);
  FIFOF#(Bit#(0))                                       invalidatesDone <- mkSizedFIFOF(4);
  
  FIFOF#(Bool)                                          uncachedPending <- mkUGFIFOF;  // The bool indicates a read response expected.
  Bag#(inFlight, ReqId, RequestRecord#(ways, keyBits, tagBits))readReqs <- mkSmallBag; // Hold data for outstanding memory requests
  Reg#(RequestRecord#(ways, keyBits, tagBits))               readReqReg <- mkRegU;      // Hold data for outstanding memory request if we have only one outstanding request.
  Bag#(inFlight, ReqId, Bit#(0))                              memReqIds <- mkSmallBag; // A searchable list of local request ids that have outstanding memory request.
  `ifdef STATCOUNTERS
    Wire#(CacheCoreEvents)                              cacheCoreEvents <- mkDWire(defaultValue);
  `endif

  // TIME-BASED COHERENCE, counters  
  `ifdef TIMEBASED
    Reg#(Bit#(`TIMEBITS))                                 timeCounter <- mkReg(0); // Primary time-counter, determines line expiry
    Reg#(Bit#(64))                                   timeCycleCounter <- mkReg(0); // Determines frequency of time-counter increments
  `endif

  ControlToken#(ways, keyBits, tagBits) null_ct = ?;
  null_ct.command = Nop;
  null_ct.req.operation = tagged CacheOp CacheOperation{inst: CacheNop, cache: whichCache, indexed: True};
  null_ct.fresh = False;
  null_ct.invalidate = False;
  
  Bool writeThrough = writeBehaviour==WriteThrough;
  Bool ooo = orderBehaviour==OutOfOrder;
  
  Bool roomForOneRequest = memReqFifoSpace >= 1;
  // If the cache is writethrough, we never need to writeback.
  Bool roomForWriteback        = (writeThrough) ? True:(memReqFifoSpace >= 4);
  Bool roomForReadAndWriteback = (writeThrough) ? roomForOneRequest:(memReqFifoSpace >= 5);
  
  CheriMemRequest waitingReq = (oneInFlight) ? cts.req:retryReqs.first;
  
  // Invalid tag constant to use for invalidating tags.
  TagLine#(tagBits) invTag = ?;
  invTag.valid = replicate(False);
  invTag.pendMem = False;
  // TIME-BASED COHERENCE, default time stamp value
  `ifdef TIMEBASED
    invTag.timeStamp = 0;
  `endif

  rule initialize(cacheState == Init);
    Integer i;
    for (i=0; i<valueOf(ways); i=i+1) tags[i].write(pack(initCount), invTag);
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Initializing tag %0d", $time, cacheId, initCount));
    if (initCount == 0-1) begin
      cacheState <= Serving;
      initCount <= 0;
    end
    else begin
      initCount <= initCount + 1;
    end
  endrule
  
  rule writeNextEmpty;
    nextEmpty <= (ooo) ? nextSet.empty:!next.notEmpty;
  endrule
  
  function ActionValue#(Maybe#(Way#(ways))) findWay(Vector#(ways,TagLine#(tagBits)) tagVec,Tag#(tagBits) tag, Bank bank);
    actionvalue
    function Bool pending(TagLine#(tagBits) t) = (tag==t.tag && t.valid[bank]);
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
    return unpack(pack(findIndex(pending, tagVec)));
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
    Way#(ways) way = 0; // Default value consistent with only one way.
    Bool last = True;
    
    Bank nLkpFlit = lkpFlit;
    Bool multiFlitReq = False;
    
    // If we have a valid new request, always run it immediatly.
    if (newReq matches tagged Valid .nr) begin
      // Just a cast so that we can pull out fields.
      //newCt.addr = unpack(pack(newCt.req.addr));
      newCt.fresh = True;
      nLkpFlit = 0;
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Selecting a fresh request ", $time, cacheId, fshow(newReq)));
      //lookupReq = nr;
      valid = True;
    end else begin
      // All the "non-fresh" cases which are less timing critical.
      CheriMemRequest lookupReq = defaultValue;
      if (!cts.last) begin
        // Continue lookup in register if the previous one was not the last.
        newCt = cts;
        //newCt.fresh = False;
        lookupReq = cts.req;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Selecting a continuing request ", $time, cacheId, fshow(lookupReq)));
        valid = True;
      end else if (oneInFlight && cts.command != Nop && (!nextEmpty||cts.fresh)) begin
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
    
    // Issuing a writeback request must not happen when we have a fresh request, but we block at
    // the put method when there is a writeback to do so that this will not happen.
    // This improves the critical path.
    if (writebacks.notEmpty /* && !newCt.fresh*/) begin // Take a writeback request with the highest priority.
      // Make sure it is obvious to an optimiser that a writethrough cache will not ever do this.
      if (!writeThrough) begin
        newCt.command = Writeback;
        AddrTagWay#(ways, keyBits, tagBits) evict = writebacks.first;
        way = evict.way;
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
    end else if (valid) begin
      //newCt.req = lookupReq;
      newCt.command = Serve;
      //newCt.addr = unpack(pack(newCt.req.addr));
      if (multiFlitReq) begin
        if (nLkpFlit == 3) last = True;
        else last = False;
        nLkpFlit = nLkpFlit + 1;
      end else nLkpFlit = 0;
      Bit#(wayPredIndexSize) wKey = truncate(newCt.addr.key);
      if (valueOf(ways) > 1) begin
        way = wayHist[wKey];
        debug2("CacheCore", $display("wayKey: %d preWay: %d", wKey, way));
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> cts.fresh:%x, newCt.fresh:%x, way: %x, wayKey: %x ", 
                                    $time, cacheId, cts.fresh, newCt.fresh, way, wKey));

      end
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Started memory request, lkpFlit:%x(%x), lkpId:%x(%x) last:%x started lookup ", 
                                    $time, cacheId, lkpFlit, nLkpFlit, lkpId, getReqId(newCt.req), last, fshow(newCt.addr), fshow(newCt.req)));
    end
    lkpFlit <= nLkpFlit;
    lkpId <= getReqId(newCt.req);
    // Always start the fetch so that memory responses can be consumed!
    newCt.dataKey = DataKey{key:newCt.addr.key, bank: newCt.addr.bank, way: way};
    newCt.last = last;
    newCt.canTakeMemResp = newCt.command != Writeback && !newCt.fresh;
    Integer i;
    // Start tag lookup
    for (i=0; i<valueOf(ways); i=i+1) tags[i].read.put(newCt.dataKey.key);
    // Start data lookup
    data.read.put(newCt.dataKey);
    cts <= newCt;
  endrule
  
  (* no_implicit_conditions *)
  rule finishLookup(cacheState != Init);
    // ===========================================================================================
    // First half of rule that looks at the present lookup and potentially writes 
    // ===========================================================================================
    Maybe#(Bool) commit = (req_commits.notEmpty) ? (tagged Valid req_commits.first()):(tagged Invalid);
    // If we are in the serving state and our unguarded fifos are not full.
    ControlToken#(ways, keyBits, tagBits) ct  =  cts;
    CacheAddress#(keyBits, tagBits)     addr  =  ct.addr;
    Vector#(ways,TagLine#(tagBits))     tagsRead = ?;
    Integer i;
    for (i=0; i<valueOf(ways); i=i+1) tagsRead[i] <- tags[i].read.get();
    Data#(CheriDataWidth)           dataRead  <- data.read.get();
    Maybe#(Way#(ways)) mWay = tagged Invalid;
    if (ct.command!=Nop) mWay <- findWay(tagsRead,addr.tag,addr.bank);
    Bool miss = !isValid(mWay);
    Way#(ways) way = fromMaybe(truncate(count),mWay);
    TagLine#(tagBits) tagUpdate = tagsRead[way];
    Bool wayMiss = False;
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
    
    // A function for returning the 64-bit word of interest for 1st level caches.
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
    Data#(CheriDataWidth) shiftedDataRead = shiftData(dataRead);

    // TIME-BASED COHERENCE, conditions for self-invalidation
    `ifdef TIMEBASED 
      Bool cacheSyncInstruction = False;
      if (whichCache == DCache) begin
        Bool conditionalOp = False;
        if (ct.req.operation matches tagged Write .wop) conditionalOp = wop.conditional;
        if (!miss && (tagsRead[way].timeStamp <= timeCounter) && !conditionalOp) begin
          miss = True;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Perform Self-Invalidate, timeCounter=%0d, tags(timeStamp)=%0d, conditional=%b", $time, cacheId, timeCounter, tagsRead[way].timeStamp, conditionalOp));
        end
      end
    `endif
 
    // Deal with any memory responses ====
    ReqId memRspId = getRespId(memRsps.first);
    
    CheriMemResponse memResp = memRsps.first;
    Bool last = getLastField(memResp);
    if (memRsps.notEmpty) begin
      if (memResp.operation matches tagged Write .wop) begin
        memRsps.deq;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received write memory response ", $time, cacheId, fshow(memResp)));
        if (uncachedPending.notEmpty && !uncachedPending.first) begin 
          uncachedPending.deq();
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, cacheId));
        end
      end else if (ct.canTakeMemResp) begin // Don't hijack a writeback command or a fresh request.
        memRsps.deq;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received memory response ", $time, cacheId, fshow(memResp)));
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Hijacked memory response lookup, last:%x ", $time, cacheId, last, fshow(ct.req)));                                    
        ct.command = MemResponse;
        Maybe#(RequestRecord#(ways, keyBits, tagBits)) mReqRec = (oneInFlight) ? tagged Valid readReqReg:readReqs.isMember(memRspId);
        RequestRecord#(ways, keyBits, tagBits) reqRec = fromMaybe(?,mReqRec); // Just grab the bits.
        way           = reqRec.oldWay;
        tagsRead[way] = reqRec.oldTag;
        CacheAddress#(keyBits, tagBits) tmpAddr = unpack(pack(ct.req.addr));
        // This not the bank of the response, but the bank of the original request.
        // In the !(ooo) case, the bank of the original request will simply be the existing bank in ct.
        ct.addr.bank = fromMaybe(tmpAddr.bank,nextBank.isMember(reqRec.inId));
        ct.addr.tag = tagsRead[way].tag;
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
        ct.dataKey = DataKey{key:ct.addr.key, bank: ct.addr.bank, way: way};
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
            
            ct.last = last;
            if (last) begin
              inFlit <= 0;
              ct.last = True;
            end else inFlit <= inFlit + 1;
          end
          tagged SC .scr: begin
            // Shoehorn the store conditional response into the request that the lookup will see.
            /*ct.req.operation = tagged Write {
                                uncached: False,
                                conditional: False,
                                byteEnable: replicate(True),
                                bitEnable: -1,
                                data: ?,
                                last: last
                              };*/
            scResult = scr;
            respondWithSC = True;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing %x from ID table", $time, cacheId, memRspId, fshow(scr)));
            if (!oneInFlight) readReqs.remove(memRspId);
            memReqIds.remove(getReqId(ct.req));
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> store conditional response lookup, scResult:%x, last:%x ", $time, cacheId, scResult, last, fshow(ct.req)));
          end
        endcase
      end
    end else if (timedOutInvalidate.notEmpty) begin
      // This case is only exercised if the invalidate fifo has not had the oportunity to drain normally.
      // This case will invalidate all ways at the index position without checking for a match.
      ct.command = Invalidate;
      ct.dataKey = DataKey{key:timedOutInvalidate.first, bank: 0, way: 0};
      timedOutInvalidate.deq;
    end
    
    // After potentially hijacking this lookup, actually serve this lookup properly ***********************
    
    CheriMemRequest req = ct.req;
    Bool dead = False;  // To allow us to kill this operation at any stage.
    
    // Check if we have a way miss
    Bit#(wayPredIndexSize) wayKey = truncate(addr.key);
    if (valueOf(ways) > 1) begin
      if (!miss && way != ct.dataKey.way) wayMiss = True;
    end

    if (req.operation matches tagged CacheOp .cop &&& cop.indexed) way = truncate(addr.tag);
    TagLine#(tagBits) tag = tagsRead[way];
    
    Bool cachedResponse = False;
    Bool cachedWrite = False;
    Bool returnTag = False;
    Bool writeback = False;
    Bool doInvalidate = False;
    Bool writeTags = False;    
    Bool expectResponse = False;
    Bool evict = ct.command==Writeback && ct.addr.bank == 2'b0; // Only register once per line.
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
    if (req.operation matches tagged CacheOp .cop &&& cop.inst == CacheInternalInvalidate) ct.invalidate = True;

    // If this is a write-through cache, then a lower level will handle ordering
    // of load-linked and store conditional.
    `ifndef MULTI
    Bool handleLinked = writeBehaviour!=WriteThrough;
    `else
    Bool handleLinked = whichCache==L2; 
    `endif
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
    if (ct.invalidate) thisReqNext = True;
    
    // If this is the last flit of transaction
    Bool thisReqLast = (!noReqs &&  (nextBank.last == nextBank.first + rspFlit));
    if (!noReqs && ct.command!=Nop) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> thisReqNext:%x, reqId:%x, nextReqId:%x, thisReqLast:%x, thisBank: %x, nextBank.last:%x, nextBank.first:%x, rspFlit:%x, rspId:%x, nextSet.isMember(reqId):%x, isValid(commit):%x",
                                       $time, cacheId, thisReqNext, reqId, nextReqId, thisReqLast, addr.bank, nextBank.last, nextBank.first, rspFlit, rspId, isValid(nextSet.isMember(reqId)), isValid(commit)));
    
    Bool respValid = False;
    CheriMemResponse cacheResp = defaultValue;
    cacheResp.masterID = req.masterID;
    cacheResp.transactionID = req.transactionID;
    cacheResp.error = ct.rspError;
    cacheResp.data = shiftedDataRead;
    if (memResp.operation matches tagged Read .rr &&& ct.canTakeMemResp && memRsps.notEmpty) cacheResp.data = shiftData(memResp.data);
    
    // These hold and control enqing the request to the retry fifo.
    CheriMemRequest memReq = req; // Request to forward to memory.
    Bool enqRetryReq = False;
    
    if (ct.command!=Nop && !noReqs) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Commit:%x, Serving request ", $time, cacheId, commit, fshow(ct), fshow(dataRead), fshow(tagsRead)));
    
    case (ct.command)
      Nop: begin
        dead = True;
      end
      Invalidate: begin
        if (writeBehaviour==WriteThrough) begin 
          for (i=0; i<valueOf(ways); i=i+1) tags[i].write(ct.dataKey.key, invTag);
        end
        else begin
          $display("Panic!  Invalidating lines in a writeback cache is very bad!");
        end
      end
      Writeback: begin
        // Make it obvious to the optimiser that this logic isn't required for a writethrough cache.
        if (!writeThrough) begin
          req.operation = tagged Write {
                      uncached: True,
                      conditional: False,
                      byteEnable: unpack(signExtend(4'hF)),
                      bitEnable: -1,
                      data: dataRead,
                      last: True
                  };
           req.addr = unpack(pack(ct.addr));
           req.masterID = truncate(cacheId);
           req.transactionID = nextId;
           nextId <= nextId+1;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Issuing external writeback memory request", $time, cacheId, fshow(req)));
          memReqs.enq(req);
          `ifdef STATCOUNTERS
            CacheCoreEvents newCCE = defaultValue;
            if (ct.addr.bank==0) newCCE.incEvict = True;
            cacheCoreEvents <= newCCE;
          `endif
        end
      end
      MemResponse: begin
        case (req.operation) matches
          tagged Write .wop: begin
            way = ct.dataKey.way;
            //reqId = getRespId(memRsps.first);
            if (!cached || ct.rspError!=NoError || respondWithSC) begin // We don't know the bank in this case!
              thisReqNext = (reqId == nextReqId)||(ooo && isValid(nextSet.isMember(reqId)));
              // Should check if commit is valid, but we can't structurally handle the case where it is not. 
              // Ignore the flit/bank number in this case, and this should be guaranteed to match for uncached responses.
              thisReqLast = True; // Assuming no bursts for read errors.
            end
            if (cached) begin
              way = ct.dataKey.way;
              // Do fill
              data.write(ct.dataKey, wop.data);        
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> filled cache bank %x, way %x with %x, wayHist[%x]<=%x", 
                                          $time, cacheId, ct.dataKey, ct.dataKey.way, wop.data, wayKey, way));
              tag.valid[addr.bank] = True;
              if (ct.last) tag.pendMem = False;
              tags[way].write(ct.dataKey.key, tag);
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Wrote tags key=0x%0x", $time, cacheId, addr.key, fshow(tag)));
              RequestRecord#(ways, keyBits, tagBits) reqRec = RequestRecord{
                                                                    key: ct.dataKey.key, 
                                                                    inId: reqId, 
                                                                    cached: cached,
                                                                    oldTag: tag,
                                                                    oldWay: way,
                                                                    oldDirty: tag.dirty&&any(id,tag.valid),
                                                                    write: respForWrite,
                                                                    noOfFlits: noOfFlits
                                                                 };
              // Only update if it is still in the set.
              if (!ct.last) begin
                if (oneInFlight) readReqReg <= reqRec;
                else readReqs.insert(memRspId, reqRec); // Update tag record!
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Updating %x in ID table", $time, cacheId, memRspId, fshow(reqRec)));
              end
              if (ct.dataKey.bank==0) begin
                wayHist[wayKey] <= way;
                debug2("CacheCore", $display("wayHist[%d] <= %d", wayKey, way));
              end
            end else if (respondWithSC) begin
              cacheResp.operation = tagged SC scResult;
              //respValid = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> cached and store conditional ", $time, cacheId, fshow(cacheResp)));
              //dead = True;
              // Clear the "pendMem" flag in the tags for this line.
              tag.pendMem = False;
              tags[way].write(ct.dataKey.key, tag);
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Wrote tags key=0x%0x", $time, cacheId, addr.key, fshow(tag)));
            end

            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> thisReqNext:%x, pendMem:%x, respForWrite:%x, reqId:%x, nextReqId:%x, thisReqLast:%x",
                                       $time, cacheId, thisReqNext, pendMem, respForWrite, reqId, nextReqId, thisReqLast));
            // Send a response if this memory response was for the request that is next, 
            // and if this request was not a write request.
            if (thisReqNext && (!respForWrite || respondWithSC)) begin
              if (!respondWithSC) begin
                cacheResp.operation = tagged Read {
                  last: thisReqLast
                };
              end
              respValid = True;
              if (thisReqLast) begin
                if (!cts.fresh) begin
                  deqRetryReqs = True;
                  debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> dequing retry reqs ", $time, cacheId, fshow(retryReqs.first)));
                end
                deqNext = True;
                deqId = getReqId(req);
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
          default: dynamicAssert(False, "only write requests expected for a fill!");
        endcase
      end
      Serve: begin
        Bool doMemRequest = False;
        function ActionValue#(Bool) doWriteback = actionvalue
          Bool doingEviction = False;
          if (tag.valid[addr.bank] && tag.dirty && !writeThrough) begin
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Requesting eviction! Address: %x", $time, cacheId, CacheAddress{tag: tag.tag, key: addr.key, bank: addr.bank, offset: 0}));
            writebacks.enq(AddrTagWay{
              way   : way,
              tag   : tag,
              addr  : CacheAddress{tag: tag.tag, key: addr.key, bank: addr.bank, offset: 0},
              cached: False,
              reqId : reqId
            });
            doingEviction = True;
          end
          return doingEviction;
        endactionvalue;
        
        Bool needWriteback = False;
        Bool dontCommit = False;
        if (commit matches tagged Valid .cb &&& !cb) dontCommit = True;
        if (ct.invalidate) dontCommit = False;
        if (thisReqNext && dontCommit) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Don't commit, NULL response! ", $time, cacheId));
          Bool giveReadResponse = False;
          if (req.operation matches tagged Read .rop)  giveReadResponse = True;
          if (req.operation matches tagged CacheOp .cop &&& cop.inst == CacheLoadTag) giveReadResponse = True;
          if (giveReadResponse) cacheResp.operation = tagged Read {
                                    last: thisReqLast
                                };
          respValid = True;
        // This case will skip an attempt at success for now under the following conditions:
        end else if (noReqs
                      /*|| (pendMem && (ooo||!isRead))*/ // Allow reads of pending locations to succeed if cache is in-order.
                      || (!thisReqNext&&!cached)  // Execute uncached operations strictly in order.
                      || uncachedPending.notEmpty // Don't do anything if an uncached operation is outstanding.
                      || writebacks.notEmpty // If there is an unfinished writeback request so that we don't overfill request fifo.
                      || (nextSet.dataMatch(addr.key)&&ct.fresh) // Don't lookup out of order if there is another request on this key
                    ) begin
          // If this request is uncached and not next, don't do a lookup because an uncached load must be at the head of the queue
          // when the response comes back or the response will be dropped on the floor because it is not stored in the cache.
          // If it is in the head of the queue when we first issue the request, it will certainly be there when it gets back.
          //
          // Cached requests can begin early (though we will still respond in order).
          dead = True;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> failing early ", $time, cacheId));
        end else begin
          case (req.operation) matches
            tagged CacheOp .cop &&& (!prefetchMissLocal): begin
              wayMiss = False;
              if (cop.cache == whichCache) begin
                if (pendMem) dead = True; // If there is a pending request on this line, kill it for this go-round.
                else begin
                  if (cop.indexed) miss = False;
                  case (cop.inst) matches
                    CacheInternalInvalidate &&& (!miss): begin
                      ct.invalidate = True;
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
                    // TIME-BASED COHERENCE, manage barrier instructions
                    CacheSync: begin
                      `ifdef TIMEBASED 
                        cacheSyncInstruction = True; 
                        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Cache SYNC received", $time, cacheId));
                      `endif
                    end
                  endcase
                  respValid = True;
                end
              end else begin
                doMemRequest = True;
                if (cop.inst == CacheLoadTag) begin
                  expectResponse = True;
                end else begin
                  respValid = True;
                end
              end
            end
            tagged Read .rop &&& (!miss && cached && !passConditional): begin
              cachedResponse=True;
            end
            tagged Write .wop &&& (!miss && cached && !passConditional): begin
              cachedWrite = True;
              tagUpdate = TagLine{
                tag      : tag.tag,
                dirty    : (writeThrough) ? False:True,
                pendMem  : tagUpdate.pendMem,
                // TIME-BASED COHERENCE
                `ifdef TIMEBASED
                  timeStamp: tag.timeStamp,
                `endif
                valid    : tag.valid
              };
              writeTags = True;
              if (writeThrough) doMemRequest = True;
            end
            tagged Write .wop &&& (!cached): begin
              //Write directly to memory.
              doMemRequest = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Uncached Write - Invalidating key=0x%0x", $time, cacheId, addr.key));
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Sending ", $time, cacheId, fshow(memReq)));
              if (!miss) doInvalidate = True;
            end
            `ifndef MULTI
            tagged Write .wop &&& writeThrough: begin
            `else
            tagged Write .wop &&& (writeThrough || passConditional): begin
            `endif
              doMemRequest = True;
              if (conditional) begin
                if (!miss) doInvalidate = True;
                expectResponse = True;
              end
            end
            default: begin
              // If it's a cached operation, align the access.
              if (cached) begin 
                memReq.addr = unpack(pack(CacheAddress{
                                          tag: addr.tag, 
                                          key: addr.key, 
                                          bank: 0,
                                          offset:0
                                       }));
                writeTags = True;
                needWriteback = True;
              end
              
              memReq.operation = tagged Read {
                                    uncached: !cached,
                                    linked: (cached) ? linked:False,
                                    noOfFlits: (cached) ? 3:0,
                                    bytesPerFlit: (cached) ? cheriBusBytes : (case (req.operation) matches
                                        tagged Read .rop : return rop.bytesPerFlit;
                                      endcase)
                                };
              debug2("CacheCore", $display("CacheCore - Fetch on write Miss / cached Miss ", fshow(req)));
              doMemRequest = True;
              expectResponse = True;
            end
          endcase 
          
          if (!thisReqNext) begin // If this is not the next request, kill the external request under two conditions...
            if (!cached) dead = True;
            // Kill the operation if it is not a read, which (probably) has no side effects.
            if (req.operation matches tagged Read .rop) begin
            end else dead = True;
          end
          Bool writeTagsEvenIfDead = False;
          if (doMemRequest && !dead) begin
            // Don't issue a memory request if:
            //   Our table of outstanding memory requests if full
            //   If we don't have room for one more request in the output FIFO
            //   If this line already has an outstanding memory request
            Bool doMemRequestShouldSucceed = (!memReqIds.full && roomForOneRequest && !pendMem);
            if (!doMemRequestShouldSucceed) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> External memory request failing: readReqs.full:%x, roomForOneRequest:%x", $time, cacheId, readReqs.full, roomForOneRequest));
            // If the conditions for a fill are good and we need to, do an eviction.
            if (needWriteback && tag.dirty && doMemRequestShouldSucceed) begin
              if (roomForReadAndWriteback) writeback <- doWriteback;
              else dead = True;
            end
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
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Issuing external memory request, memReqs.notFull:%x, memReqFifoSpace:%x", 
                                            $time, cacheId, memReqs.notFull, memReqFifoSpace, fshow(memReq)));
              if (expectResponse) begin
                if (cached) begin
                  tagUpdate = TagLine{
                    tag    : addr.tag,
                    pendMem: True,
                    valid  : replicate(False),
                    // TIME-BASED COHERENCE, prepare for a new cache line fill 
                    // and update the timeStamp
                    `ifdef TIMEBASED
                      timeStamp: timeCounter + `TIMEOUT,
                    `endif
                    dirty  : False
                  };
                  writeTags = True;  // This must happen!
                  writeTagsEvenIfDead = True;
                end
                
                RequestRecord#(ways, keyBits, tagBits) reqRec = RequestRecord{
                                                                  key: addr.key, 
                                                                  inId: reqId, 
                                                                  cached: cached,
                                                                  oldTag: tagUpdate,
                                                                  oldWay: way,
                                                                  oldDirty: tag.dirty&&any(id,tag.valid),
                                                                  write: isWrite,
                                                                  noOfFlits: noOfFlits
                                                               };
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Inserting %x into ID table", $time, cacheId, outReqId, fshow(reqRec)));
                // Insert info about the outstanding request keyed by external request id.
                if (oneInFlight) readReqReg <= reqRec;
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
            cacheCoreEvents <= CacheCoreEvents {
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
            };
          `endif
          
          if (wayMiss) begin
            if (valueOf(ways) > 1 && thisReqNext)
              debug2("CacheCore", $display("Way miss, %x != %x, wayHist[%d]<=%d", way, ct.dataKey.way, wayKey, way));
            wayHist[wayKey] <= way;
            dead = True;
          end else if (cachedResponse) begin
            cacheResp.operation = tagged Read {
                last: thisReqLast
            };
            respValid = True;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> returning @0x%0x:0x%0x", $time, cacheId, addr, dataRead));
          end 
          
          // From this point on, kill the request completely if it is not next or if there is an outstanding memory request on this line.
          if (!thisReqNext || pendMem) dead = True;
          
          // Do any tag update that has been requested if this update is committing (or if we issued a memory request).
          if (!dead||writeTagsEvenIfDead) begin
            if (doInvalidate) begin
              tags[way].write(addr.key, invTag);
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Invalidating key=0x%0x", $time, cacheId, addr.key));
              //writeTags = True;
            end else if (writeTags) begin
              // TIME-BASED COHERENCE, update time stamp
              `ifdef TIMEBASED 
                tagUpdate.timeStamp = timeCounter + `TIMEOUT;
              `endif
              tags[way].write(addr.key, tagUpdate);
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Wrote tags key=0x%0x", $time, cacheId, addr.key, fshow(tagUpdate)));
            end
          end
          
          // Only finish the write if this is the next operation in order, and if this is not a way miss.
          if (req.operation matches tagged Write .wop &&& !dead) begin
            cacheResp.operation = tagged Write;
            if (cachedWrite) begin
              //Construct new line.
              function Byte choose(Byte o, Byte n, Bool sel) = (sel) ? ((n&wop.bitEnable)|(o&~wop.bitEnable)):o;
              // zipWith3 combines the three vectors with the function "choose", defined above, producing another vector.
              // In this case it is just selecting the old byte or new byte based on byteEnable.
              Vector#(CheriBusBytes,Byte) maskedWriteVec = zipWith3(choose, unpack(dataRead.data), unpack(wop.data.data), wop.byteEnable);
              debug2("CacheCore", $display("zipped write in Tag Cache: byteEnable: %x, bitEnable: %x, oldData: %x, newData: %x", 
                                           wop.byteEnable, wop.bitEnable, dataRead.data, wop.data.data, fshow(maskedWriteVec)));
              Data#(CheriDataWidth) maskedWrite = wop.data;
              maskedWrite.data = pack(maskedWriteVec);
              `ifdef USECAP
                // Fold in capability tags.
                CapTags capTags = dataRead.cap;
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
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> wrote cache bank %x, way %x with %x",$time, cacheId, DataKey{key:addr.key, way:way, bank:addr.bank},way, maskedWrite));
              data.write(DataKey{key:addr.key, way:way, bank:addr.bank}, maskedWrite);
              respValid = True;
            end
            if (miss && writeThrough) respValid = True;
            // If this is a store conditional and we're not handling it,
            // the response is coming later.
            if (conditional && writeThrough) dead = True;
            if (wop.uncached) respValid = True;
          end
        end

        // Make sure it's dead if it's not next, and if this line has an outstanding memory request.
        if (!thisReqNext || pendMem) dead = True;
        if (dead) respValid = False;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Request Dead %x, noReqs %x, thisReqNext %x ", 
                                      $time, cacheId, dead, noReqs, thisReqNext, fshow(cacheResp)));
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
            if (!ct.invalidate) deqReqCommits = True;
            rspFlit = 0;
            ongoingResponse = False;
          end else begin
            rspFlit = rspFlit + 1;
            rspId = getRespId(cacheResp);
            ongoingResponse = True;
          end
          if (responseBehaviour == OnlyReadResponses) begin
            case (cacheResp.operation) matches
              tagged Read .rop: respValid = respValid;
              default: respValid = False;
            endcase
          end
          if (ct.invalidate) respValid = False;
        end
        // Only enq this one if it is fresh and not done.
        if (firstFresh) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enquing fresh request to retry reqs fifo ", $time, cacheId, fshow(cts.req)));
          enqRetryReq = True;
        end
      end
    endcase
    
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

    // TIME-BASED COHERENCE, mechanism for modifying the time counter 
    `ifdef TIMEBASED 
      if (whichCache == DCache) begin
        Bit#(`TIMEBITS) timeOffset = 0;
        Bit#(`TIMEBITS) tmpTimeCount = timeCounter;
        Bool tcFull = False;
        if (cacheSyncInstruction) begin
          timeOffset = `TIMEOUT;
          timeCycleCounter <= 0;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> SYNC modify timeOffset", $time, cacheId)); 
        end
        else begin
          if (timeCycleCounter > `TIMEVALID) begin
            timeOffset = `TIMEOUT;
            timeCycleCounter <= 0;
            tcFull = True;
          end
          else begin
            timeCycleCounter <= timeCycleCounter + 1;
          end
        end

        tmpTimeCount = tmpTimeCount + timeOffset;

        if ((timeCounter == -1 && tcFull) || (tmpTimeCount < timeCounter)) begin
          timeCounter <= 0;
          cacheState <= Init;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> timeCounter rollover, tmpTimeCount=%0d, timeCounter=%0d, timeCycleCounter=%0d, tcFull=%b, ", $time, cacheId, tmpTimeCount, timeCounter, timeCycleCounter, tcFull)); 
        end
        else begin
          timeCounter <= tmpTimeCount;
        end 
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> timeCounter update, timeCounter=%0d, timeCycleCounter=%0d, tmpTimeCount=%0d, timeOffset=%0d", $time, cacheId, timeCounter, timeCycleCounter, tmpTimeCount, timeOffset)); 
      end
    `endif

  endrule
  
  // This function encapsulates the actions that should be taken to serve
  // the response wires if we will not consume them in the response method.
  // This may be done either in the catchResponse rule or in the method itself
  // if it chooses a write response.
  function Action updateStateNoResponse();
    action
      ResponseToken rt = resps;
      Bool updateState = False;
      if (!respsReady) begin
        updateState = True;
      end else if (rt.resp.operation matches tagged Write) begin
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Missed Delivering write response, buffered it ", $time, cacheId, fshow(rt)));
        writeResps.enq(getRespId(rt.resp));
        updateState = True;
      end else begin
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Missed Delivering response ", $time, cacheId, fshow(rt)));
        if (resps.enqRetryReq && !oneInFlight) begin
          if (!retryReqs.notFull) $display("Panic!  enqing retry reqs when full!");
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enqued retry reqs ", $time, cacheId, fshow(rt.req)));
          retryReqs.enq(resps.req);
        end
      end
      if (updateState) begin
        //rspFlitReg <= rt.rspFlit;
        //rspIdReg <= rt.rspId;
        if (rt.deqNext) begin
          if (ooo) begin
            nextSet.remove(rt.deqId);
            nextBank.remove(rt.deqId);
            //debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing reqId from next ", $time, cacheId, rt.deqId));
          end else next.deq;
        end
        if (rt.deqReqCommits && req_commits.notEmpty) begin
          req_commits.deq;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed req_commits ", $time, cacheId, fshow(req_commits.first)));
        end
        if (rt.deqRetryReqs && !oneInFlight) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed retry reqs ", $time, cacheId, fshow(retryReqs.first)));
          retryReqs.deq;
        end
        if (rt.enqRetryReq && (!respsReady || !rt.deqNext) && !oneInFlight) begin
          if (!retryReqs.notFull) $display("Panic!  enqing retry reqs when full!");
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enqued retry reqs ", $time, cacheId, fshow(rt.req)));
          retryReqs.enq(rt.req);
        end
        if (rt.rspFlit != rspFlitReg || rt.deqNext || rt.deqReqCommits || rt.enqRetryReq)
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Updating cache state ", $time, cacheId, fshow(rt)));
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
  
  (* descending_urgency = "injectInvalidate, invalidateTimeOut" *)
  rule invalidateTimeOut(timedOutInvalidate.notFull);
    if (invalidateTime == 255) begin
      CacheAddress#(keyBits, tagBits) ca = unpack(pack(invalidates.first));
      timedOutInvalidate.enq(ca.key);
      debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enqued timed out invalidate: %x", $time, cacheId, invalidates.first));
      invalidates.deq();
      invalidatesDone.enq(?);
    end
    invalidateTime <= invalidateTime + 1;
  endrule
  rule injectInvalidate(roomInNext && roomInRetryReqs && !nextReqIdHasOutstandingRequest && cacheState != Init);
    CheriMemRequest req = defaultValue;
    req.addr = invalidates.first;
    invalidates.deq();
    invalidatesDone.enq(?);
    req.operation = tagged CacheOp CacheOperation{
                                      inst: CacheInternalInvalidate, 
                                      cache: whichCache,
                                      indexed: False
                                    };
    req.masterID = truncate(cacheId);
    req.transactionID = nextIncomingReqId.transactionID;
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Started invalidation: ", $time, cacheId, fshow(req)));
    CacheAddress#(keyBits, tagBits) ca = unpack(pack(req.addr));
    ReqId id = getReqId(req);
    if (ooo) begin
      nextSet.insert(id, ca.key);
      //debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Inserting reqId at bank in next ", $time, cacheId, getReqId(req), ca.bank));
      nextBank.insert(id, ca.bank);
    end else next.enq(id);
    newReq <= tagged Valid req;
    invalidateTime <= 0;
  endrule
  
  Bool putCondition = (roomInNext && roomInRetryReqs && !nextReqIdHasOutstandingRequest && cacheState != Init && !invalidates.notEmpty && !writebacks.notEmpty);
  method Bool canPut() = putCondition;  
  method Action put(CheriMemRequest req) if (putCondition);
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Putting new request", $time, cacheId, fshow(req)));
    CacheAddress#(keyBits, tagBits) ca = unpack(pack(req.addr));
    ReqId id = getReqId(req);
    if (ooo) begin
      nextSet.insert(id, ca.key);
      //debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Inserting reqId at bank in next ", $time, cacheId, getReqId(req), ca.bank));
      nextBank.insert(id, ca.bank);
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
        ret.masterID = writeResps.first.masterID;
        ret.transactionID = writeResps.first.transactionID;
        ret.operation = tagged Write;
      end
      return ret;
    endmethod
    method ActionValue#(CheriMemResponse) get;
      gotResp <= True;
      ResponseToken rt = resps;
      CheriMemResponse ret = rt.resp;
      if (writeResps.notEmpty) begin
        ret = defaultValue;
        ret.masterID = writeResps.first.masterID;
        ret.transactionID = writeResps.first.transactionID;
        ret.operation = tagged Write;
        writeResps.deq;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Delivering valid buffered write response ", $time, cacheId, fshow(ret)));
        updateStateNoResponse();
      end else if (respsReady) begin
        rspFlitReg <= rt.rspFlit;
        rspIdReg <= rt.rspId;
        if (rt.deqNext) begin
          if (ooo) begin
            nextSet.remove(rt.deqId);
            nextBank.remove(rt.deqId);
            //debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing reqId from next ", $time, cacheId, rt.deqId));
          end else next.deq;
        end
        if (rt.deqReqCommits && req_commits.notEmpty) begin
          req_commits.deq;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed req_commits ", $time, cacheId, fshow(req_commits.first)));
        end
        if (rt.deqRetryReqs && !oneInFlight) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequed retry reqs ", $time, cacheId, fshow(retryReqs.first)));
          retryReqs.deq;
        end
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Delivering valid response ", $time, cacheId, fshow(rt)));
        // If response is ready and the request is being completed (deqNext), don't put it in retryReqs.
        if (rt.enqRetryReq && !rt.deqNext && !oneInFlight) begin
          if (!retryReqs.notFull) $display("Panic!  enqing retry reqs when full!");
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enqued retry reqs ", $time, cacheId, fshow(rt.req)));
          retryReqs.enq(rt.req);
        end
      end
      return ret;
    endmethod
  endinterface
  
  method Action nextWillCommit(Bool nextCommitting) if (req_commits.notFull);
    req_commits.enq(nextCommitting);
  endmethod
  
  method Action invalidate(CheriPhyAddr addr);
    invalidates.enq(addr);
  endmethod
  
  // The cache is ~consistent if there are no outstanding invalidates.
  method Action invalidateDone();
    invalidatesDone.deq;
  endmethod
  `ifdef STATCOUNTERS
  interface Get cacheEvents;
      method ActionValue#(ModuleEvents) get;
          return tagged CacheCore_E cacheCoreEvents;
      endmethod
  endinterface
  `endif
endmodule
