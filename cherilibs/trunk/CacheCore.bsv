/*-
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
 
interface CacheCore#(numeric type ways,
                      numeric type keyBits);/*,
                  numeric type sets_per_way,
                  numeric type bytes_per_line);*/
  method Action put(CheriMemRequest req);
  method ActionValue#(Maybe#(CheriMemResponse)) get(Bool willConsume);
  method Action nextWillCommit(Bool nextCommitting);
  //interface Master#(CheriMemRequest, CheriMemResponse) memory;
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

typedef struct {
  Tag#(tagBits)                     tag;
  Bool                          pending;
  Bool                            dirty;
  Vector#(TExp#(BankBits), Bool)  valid;
} TagLine#(numeric type tagBits) deriving (Bits, Eq, Bounded, FShow);

typedef enum {Init, Serving} CacheState deriving (Bits, Eq, FShow);
typedef enum {Nop, Serve, Writeback, MemResponse} LookupCommand deriving (Bits, Eq, FShow);

typedef enum {WriteThrough, WriteAllocate} WriteMissBehaviour deriving (Bits, Eq, FShow);

typedef struct {
  CacheAddress#(keyBits, tagBits) addr;
  TagLine#(tagBits)                tag;
  Way#(ways)                       way;
  Bool                          cached;
  ReqId                          reqId;
} AddrTagWay#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, FShow);

typedef struct {
  LookupCommand                       command;
  CheriMemRequest                         req;
  CacheAddress#(keyBits, tagBits)        addr;
  Vector#(ways,TagLine#(tagBits))        tags;
  DataKey#(ways, keyBits)             dataKey;
  Data#(CheriDataWidth)                  data;
  Bool                                   last;
  Bool                                  fresh;
  Error                              rspError;
} ControlToken#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, FShow);

typedef struct {
  CheriMasterID      masterID;
  CheriTransactionID transactionID;
} ReqId deriving (Bits, Eq, FShow);

typedef struct {
  Key#(keyBits)                       key;
  ReqId                              inId;
  Bool                             cached;
  Vector#(ways,TagLine#(tagBits)) oldTags;
  Way#(ways)                       oldWay;
  Bool                           oldDirty;
} RequestRecord#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, Eq, FShow);

typedef struct {
  Bank first;
  Bank last;
} BankBurst deriving (Bits, Eq, FShow);

typedef struct {
  CheriMemRequest             req;
  DataKey#(ways, keyBits) dataKey;
} DataRefetch#(numeric type ways, numeric type keyBits) deriving (Bits, FShow);

`ifdef MEM128
  typedef 16 BusBytes;
`elsif MEM64
  typedef 8 BusBytes;
`else
  typedef 32 BusBytes;
`endif

module mkCacheCore#(Bit#(16) coreId, 
                    WriteMissBehaviour writeBehaviour, 
                    WhichCache whichCache,
                    // Must be > 5 or we can't issue reads with evictions!
                    // This means that a write-allocate cache must have >=5 capacity in the output fifo.
                    Bit#(6) memReqFifoSpace,
                    FIFOF#(CheriMemRequest) memReqs,
                    FIFOF#(CheriMemResponse) memRsps)
                   (CacheCore#(ways, keyBits))
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
      Add#(smaller4, TLog#(TMin#(TExp#(keyBits), 16)), keyBits),
      Add#(smaller5, 4, keyBits)
    );
  Wire#(Maybe#(CheriMemRequest))                                 newReq <- mkDWire(tagged Invalid);
  FFNext#(CheriMemRequest,2)                                       reqs <- mkUGFFNext;
  FIFO#(ControlToken#(ways, keyBits, tagBits))                      cts <- mkFIFO;
  Reg#(CacheState)                                           cacheState <- mkConfigReg(Init);
  Reg#(Vector#(TMin#(TExp#(keyBits), 16), Way#(ways)))          wayHist <- mkConfigRegU;
  MEM#(Key#(keyBits), Vector#(ways,TagLine#(tagBits)))             tags <- mkMEM();
  MEM#(DataKey#(ways, keyBits), Data#(CheriDataWidth))             data <- mkMEM();
  Reg#(Key#(keyBits))                                             count <- mkConfigReg(0);
  Reg#(CheriTransactionID)                                       nextId <- mkConfigReg(0);
  Reg#(Bank)                                                     inFlit <- mkConfigReg(0);
  Reg#(Bank)                                                    lkpFlit <- mkConfigReg(0);
  Reg#(Bank)                                                 rspFlitReg <- mkConfigReg(0);
  FF#(Bool, 16)                                             req_commits <- mkUGFFBypass(); // Plenty big!
  
  FIFOF#(AddrTagWay#(ways, keyBits, tagBits))                writebacks <- mkUGFIFOF1;
  Reg#(Bank)                                         writebackWriteBank <- mkConfigReg(0);
  
  FIFOF#(Bool)                                          uncachedPending <- mkUGFIFOF;  // The bool indicates a read response expected.
  Bag#(4, ReqId, RequestRecord#(ways, keyBits, tagBits))       readReqs <- mkSmallBag;
  
  ControlToken#(ways, keyBits, tagBits) null_ct = ?;
  null_ct.command = Nop;
  null_ct.req.operation = tagged CacheOp CacheOperation{inst: CacheNop, cache: whichCache, indexed: True};
  null_ct.fresh = False;
  
  Bool writeThrough = writeBehaviour==WriteThrough;
  
  Bool roomForOneRequest = memReqFifoSpace >= 1;
  // If the cache is writethrough, we never need to writeback.
  Bool roomForWriteback        = (writeThrough) ? True:(memReqFifoSpace >= 4);
  Bool roomForReadAndWriteback = (writeThrough) ? roomForOneRequest:(memReqFifoSpace >= 5);
  
  // Invalid tag constant to use for invalidating tags.
  TagLine#(tagBits) invTag = ?;
  invTag.valid = replicate(False);
  invTag.pending = False;
  Vector#(ways,TagLine#(tagBits)) invTagVec = replicate(invTag);
  rule initialize(cacheState == Init);
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Initializing tag %0d", $time, coreId, count));
    tags.write(pack(count), invTagVec);
    count <= count + 1;
    if (count == 0-1) cacheState <= Serving;
  endrule
  
  function Action startLookup(Bool validIn, CheriMemRequest req);
    action
      Bool valid = validIn;
      ControlToken#(ways, keyBits, tagBits) ct = null_ct;
      ct.req = req;
      ct.rspError = NoError;
      Bool last = True;
      // If we have a valid new request, always run it immediatly.
      if (validIn) begin
        // Just a cast so that we can pull out fields.
        ct.addr = unpack(pack(ct.req.addr));
        ct.fresh = True;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Selecting a fresh request ", $time, coreId, fshow(req)));
        reqs.enq(req);
      end else if (reqs.nextNotEmpty) begin
        req = reqs.next();
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Selecting a recycled request ", $time, coreId, fshow(req)));
        valid = True;
      end
      Bool multiFlitReq = False;
      if (req.operation matches tagged Read .rop &&& rop.noOfFlits > 0) multiFlitReq = True;
      
      Way#(ways) way = 0; // Default value consistent with only one way.
      // Only issue a writeback there are no outstanding requests, just to be safe.
      if (writebacks.notEmpty) begin // Take a fresh request if you've got one!
        // Make sure it is obvious to an optimiser that a writethrough cache will not ever do this.
        if (!writeThrough) begin
          ct.command = Writeback;
          AddrTagWay#(ways, keyBits, tagBits) evict = writebacks.first;
          way = evict.way;
          ct.req = defaultValue;
          evict.addr.bank = writebackWriteBank;
          ct.req.addr = unpack(pack(evict.addr));
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Started Eviction, evict write bank: %x ", $time, coreId, writebackWriteBank, fshow(evict)));
          last = (writebackWriteBank == 3); // Signal the last eviction frame to the lookup stage.
          Bank nextFetch = writebackWriteBank + 1;
          if (writebackWriteBank == 3) begin
            writebacks.deq();
            writebackWriteBank <= 0;
          end else writebackWriteBank <= nextFetch;
        end else writebacks.deq();
      end else if (valid) begin
        ct.req = req;
        ct.command = Serve;
        ct.addr = unpack(pack(ct.req.addr));
        if (multiFlitReq) begin
          // Just a cast so that we can pull out the bank.
          ct.addr = unpack(pack(ct.req.addr));
          ct.addr.bank = ct.addr.bank + lkpFlit;
          ct.req.addr = unpack(pack(ct.addr));
          lkpFlit <= lkpFlit + 1;
        end
        // Predict the way for a lookup.
        Bit#(wayPredIndexSize) wayKey = truncate(ct.addr.key);
        if (valueOf(ways) > 1) way = wayHist[wayKey];
        // Only issue another request if there are more flits that must be served from the cache.
        /*if (ct.req.operation matches tagged Read .rop &&& !rop.uncached && rop.noOfFlits > 0) begin
          last = False;
          fetchNext <= True;
        end*/
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Started memory request, last:%x started lookup ", $time, coreId, last, fshow(req)));
      end
      // Always start the fetch so that memory responses can be consumed!
      ct.addr = unpack(pack(ct.req.addr));
      ct.dataKey = DataKey{key:ct.addr.key, bank: ct.addr.bank, way: way};
      ct.last = last;
      // Start tag lookup
      tags.read.put(ct.dataKey.key);
      // Start data lookup
      data.read.put(ct.dataKey);
      cts.enq(ct);
    endaction
  endfunction
  
  function ActionValue#(ControlToken#(ways, keyBits, tagBits)) getLookup();
    actionvalue
      ControlToken#(ways, keyBits, tagBits) ct = cts.first;
      cts.deq();
      ct.tags <- tags.read.get();
      ct.data <- data.read.get();
      return ct;
    endactionvalue
  endfunction
  
  rule runLookup;
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> runLookup Fired", $time, coreId));
    startLookup(isValid(newReq), fromMaybe(?,newReq));
  endrule
  
  function ActionValue#(Maybe#(Way#(ways))) findWay(Vector#(ways,TagLine#(tagBits)) tagVec,Tag#(tagBits) tag, Bank bank);
    actionvalue
    Maybe#(Way#(ways)) way = Invalid;
    for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
      if (tag==tagVec[i].tag && tagVec[i].valid[bank]) begin
        if (isValid(way)) $display("Panic! Duplicate ways match in cache!");
        way = Valid(fromInteger(i));
      end
      debug2("CacheCore", $display("i:%d, valid:%x, dirty: %x, pending:%x, tagIn:%x, tagCmp:%x, found: %x, way:%x", 
              i, tagVec[i].valid, tagVec[i].dirty, tagVec[i].pending, tag, tagVec[i].tag, isValid(way), fromMaybe(0,way)));
    end 
    return way;
    endactionvalue
  endfunction
  
  function ActionValue#(Maybe#(Way#(ways))) findPendingWay(Vector#(ways,TagLine#(tagBits)) tagVec);
    actionvalue
    Maybe#(Way#(ways)) way = Invalid;
    for (Integer i = 0; i < valueOf(ways); i = i + 1) begin
      if (tagVec[i].pending) way = Valid(fromInteger(i));
      /*debug2("CacheCore", $display("i:%d, valid:%x, dirty: %x, pending:%x, tagIn:%x, found: %x, way:%x", 
              i, tagVec[i].valid, tagVec[i].dirty, tagVec[i].pending, tagVec[i].tag, isValid(way), fromMaybe(0,way)));*/
    end
    return way;
    endactionvalue
  endfunction
  
  method Action put(CheriMemRequest req) if (reqs.notFull);
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Triggering new lookup from FIFO", $time, coreId, fshow(req)));
    startLookup(True, req);
    //newReq <= tagged Valid req;
  endmethod
  
  method ActionValue#(Maybe#(CheriMemResponse)) get(Bool willConsume) if (cacheState == Serving);
    Maybe#(Bool) commit = (req_commits.notEmpty) ? (tagged Valid req_commits.first()):(tagged Invalid);
    // If we are in the serving state and our unguarded fifos are not full.
    ControlToken#(ways, keyBits, tagBits) ct <- getLookup();
    CacheAddress#(keyBits, tagBits)     addr  = ct.addr;
    Vector#(ways,TagLine#(tagBits)) tagsRead  = ct.tags;
    Data#(CheriDataWidth)           dataRead  = ct.data;
    Vector#(ways,TagLine#(tagBits)) tagUpdate = tagsRead;
    Maybe#(Way#(ways)) mWay = tagged Invalid;
    if (ct.command!=Nop) mWay <- findWay(tagsRead,addr.tag,addr.bank);
    Bool miss = !isValid(mWay);
    Way#(ways) way = fromMaybe(truncate(count),mWay);
    Bool wayMiss = False;
    // Check if there is a pending transaction for this index.
    mWay <- findPendingWay(tagsRead); // For this case, we just need to find the way that is expecting a fill, if there is one.
    Bool pending = isValid(mWay); // If this index has a pending memory transaction.
   
    `ifdef MULTI
      Bool scResult = False;
      Bool respondWithSC = False;
    `endif
 
    // Deal with any memory responses ================================================
    ReqId rspReqId = ReqId{masterID: memRsps.first.masterID, transactionID: memRsps.first.transactionID};
    
    CheriMemResponse memResp = memRsps.first;
    Bool last = getLastField(memResp);
    if (memRsps.notEmpty) begin
      if (memResp.operation matches tagged Write .wop) begin
        memRsps.deq;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received write memory response ", $time, coreId, fshow(memResp)));
        if (uncachedPending.notEmpty && !uncachedPending.first) begin 
          uncachedPending.deq();
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, coreId));
        end
      end else if (ct.command != Writeback) begin // Don't hijack a writeback command.
        case (memResp.operation) matches
          tagged Read .rr: begin
            memRsps.deq;
            ct.command = MemResponse; // Hijack this request and turn it into a fill.
            Bool cached = ?;
            ct.addr = unpack(0);                                     
            // Construct reqId to recall key. 
            Maybe#(RequestRecord#(ways, keyBits, tagBits)) mReqRec = readReqs.isMember(rspReqId);
            if (mReqRec matches tagged Valid .reqRec) begin
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Found %x in ID table", $time, coreId, rspReqId, fshow(reqRec)));
              way         = reqRec.oldWay;
              tagsRead    = reqRec.oldTags;
              ct.addr.tag = reqRec.oldTags[way].tag;
              ct.addr.key = reqRec.key;
              cached      = reqRec.cached;
              ct.req.masterID      = reqRec.inId.masterID;
              ct.req.transactionID = reqRec.inId.transactionID;
              //if (reqRec.oldDirty) ct.command = MemResponseWriteback; // Also do a writeback
              if (!reqRec.cached) begin
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Dequing pending uncached request", $time, coreId));
                uncachedPending.deq();
              end
              if (last) begin
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Removing %x from ID table", $time, coreId, rspReqId, fshow(reqRec)));
                readReqs.remove(rspReqId);
              end
            end else $display("<time %0t, cache %0d, CacheCore> Panic!  received response for index that was not expected!", $time, coreId);
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> received memory response ", $time, coreId, fshow(memResp)));
            ct.rspError = memResp.error;
            // This is only accurate if the response is cached (assuming that external cached reads are bursts aligned on cache lines).
            ct.addr.bank = truncate(pack(inFlit));
            // Shoehorn the response data and properties into the request that the lookup will see.
            ct.req.operation = tagged Write {
                                uncached: !cached,
                                conditional: False,
                                byteEnable: replicate(True),
                                data: rr.data,
                                last: last
                              };
            ct.req.addr = unpack(pack(ct.addr)); // Update address of request.
            addr = ct.addr;
            ct.dataKey = DataKey{key:ct.addr.key, bank: ct.addr.bank, way: way};
            ct.last = last;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Hijacked memory response lookup, last:%x ", $time, coreId, last, fshow(ct.req)));
            if (last) begin
              inFlit <= 0;
              ct.last = True;
            end else inFlit <= inFlit + 1;
          end
          tagged SC .scr: begin
            memRsps.deq;
            ct.command = MemResponse;
            Data#(CheriDataWidth) retData = ?;
            retData.data = zeroExtend(pack(scr));
            // Shoehorn the store conditional response into the request that the lookup will see.
            ct.req.operation = tagged Write {
                                uncached: True,
                                conditional: False,
                                byteEnable: replicate(True),
                                data: retData,
                                last: last
                              };
            `ifdef MULTI
              scResult = scr;
              respondWithSC = True;
            `endif          

            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> store conditional response lookup, last:%x ", $time, coreId, last, fshow(ct.req)));
          end
        endcase
      end
    end
    
    // ===============================================================================
    
    CheriMemRequest req = ct.req;
    Bool dead = False;  // To allow us to kill this operation at any stage.
    
    // Check if we have a way miss
    Bit#(wayPredIndexSize) wayKey = truncate(addr.key);
    if (valueOf(ways) > 1) begin
      if (!miss && way != ct.dataKey.way) wayMiss = True;
    end

    if (req.operation matches tagged CacheOp .cop &&& cop.indexed) way = truncate(addr.tag);
    TagLine#(tagBits) tag = tagsRead[way];
    
    // Parameterisable properties
    Bool handleLinked = writeBehaviour!=WriteThrough;
    
    Bool cachedResponse = False;
    Bool cachedWrite = False;
    Bool returnTag = False;
    Bool writeback = False;
    Bool doInvalidate = False;
    Bool writeTags = False;    
    Bool deqData = False;
    Bool expectResponse = False;
    Bool linked = {case (req.operation) matches
                      tagged Read .rop:  return rop.linked;
                      default: return False;
                    endcase};
    Bool conditional = {case (req.operation) matches
                      tagged Write .wop: 
                        `ifndef MULTI
                          return wop.conditional;
                        `else
                          return respondWithSC;
                        `endif
                      default: return False;
                    endcase};
    Bool cached = {case (req.operation) matches
                      tagged Read .rop:  return !rop.uncached;
                      tagged Write .wop: return !wop.uncached;
                      default: return False;
                    endcase};
    // If this cache doesn't handle load linked, then force a miss.
    Bool passConditional = (!handleLinked && (linked||conditional));

    ReqId reqId     = ReqId{masterID: req.masterID, transactionID: req.transactionID};
    ReqId nextReqId = ReqId{masterID: reqs.first.masterID, transactionID: reqs.first.transactionID};
    Bank rspFlit = rspFlitReg;
    Bool isRead = False;
    if (reqs.first.operation matches tagged Read .rop) isRead = True;
    // Derive the bank range for the pending request
    CacheAddress#(keyBits, tagBits) reqAddr = unpack(pack(reqs.first.addr));
    Bank lastBank = reqAddr.bank;
    if (reqs.first.operation matches tagged Read .rop) begin
      lastBank = reqAddr.bank + truncate(pack(rop.noOfFlits));
    end
    BankBurst nextBank = BankBurst{first: reqAddr.bank, last: lastBank};
    Bool thisReqNext = (reqs.notEmpty && 
                        reqId == nextReqId && 
                        addr.bank == nextBank.first + rspFlit &&
                        isValid(commit)); // If this is the next flit expected
    // If this is the last flit of transaction
    Bool thisReqLast = (reqs.notEmpty &&  (nextBank.last == nextBank.first + rspFlit));
    if (reqs.notEmpty && ct.command!=Nop) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> thisReqNext:%x, thisReqLast:%x, thisBank: %x, nextBank.last:%x, nextBank.first:%x, rspFlit:%x",
                                       $time, coreId, thisReqNext, thisReqLast, addr.bank, nextBank.last, nextBank.first, rspFlit));
    
    Maybe#(CheriMemResponse) resp = tagged Invalid;
    CheriMemResponse cacheResp = defaultValue;
    cacheResp.masterID = req.masterID;
    cacheResp.transactionID = req.transactionID;
    cacheResp.error = ct.rspError;
        
    Bool tmpCap = False;
    `ifdef CAP
      tmpCap = dataRead.cap[0];
    `endif
    
    if (ct.command!=Nop) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Commit:%x, Serving request ", $time, coreId, commit, fshow(ct), fshow(dataRead), fshow(tagsRead)));
    
    case (ct.command)
      Nop: begin
        dead = True;
      end
      Writeback: begin
        // Make it obvious to the optimiser that this logic isn't required for a writethrough cache.
        if (!writeThrough) begin
          req.operation = tagged Write {
                      uncached: True,
                      conditional: False,
                      byteEnable: unpack(signExtend(4'hF)),
                      data: Data {
                          `ifdef CAP
                            cap: dataRead.cap,
                          `endif
                          data: pack(dataRead.data)
                      },
                      last: True
                  };
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Issuing external writeback memory request", $time, coreId, fshow(req)));
          memReqs.enq(req);
        end
      end
      MemResponse: begin
        case (req.operation) matches
          tagged Write .wop: begin
            way = ct.dataKey.way;
            if (!cached || ct.rspError!=NoError) begin // We don't know the bank in this case!
              thisReqNext = (reqs.notEmpty && 
                             reqId == nextReqId &&
                             isValid(commit)); 
              // Ignore the flit/bank number in this case, and this should be guaranteed to match for uncached responses.
              thisReqLast = True; // Assuming no bursts for read errors.
            end
            if (cached) begin
              way = ct.dataKey.way;

              // Do fill
              data.write(ct.dataKey, wop.data);        
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> filled cache bank %x, way %x with %x, wayHist[%x]<=%x", 
                                          $time, coreId, ct.dataKey, ct.dataKey.way, wop.data, wayKey, way));
              tagsRead[way].valid[addr.bank] = True;
              if (ct.last) tagsRead[way].pending = False;
              tags.write(ct.dataKey.key, tagsRead);
              RequestRecord#(ways, keyBits, tagBits) reqRec = RequestRecord{
                                                                    key: ct.dataKey.key, 
                                                                    inId: reqId, 
                                                                    cached: cached,
                                                                    oldTags: tagsRead,
                                                                    oldWay: way,
                                                                    oldDirty: tagsRead[way].dirty&&any(id,tagsRead[way].valid)
                                                                 };
              // Only update if it is still in the set.
              if (!ct.last) begin
                readReqs.insert(rspReqId, reqRec); // Update tag record!
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Updating %x in ID table", $time, coreId, rspReqId, fshow(reqRec)));
              end
              wayHist[wayKey] <= way;
            end

            `ifdef MULTI
              if (respondWithSC) begin
                cacheResp.operation = tagged SC scResult;
                resp = tagged Valid cacheResp;
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> cached and store conditional ", $time, coreId, fshow(resp)));
                dead = True;
              end
            `endif

            Bool nextWrite = False;
            if (reqs.notEmpty)
              if (reqs.first.operation matches tagged Write .wop) nextWrite = True;
            // Only respond here for read operations that are next, and only when the caller has space.
            if (thisReqNext && !nextWrite && willConsume) begin
              cacheResp.operation = tagged Read {
                  data: wop.data,
                  last: thisReqLast
              };
              resp = tagged Valid cacheResp;
              if (thisReqLast) begin
                reqs.deq;
                req_commits.deq;
                cycReport($display("[$%s%s%s]", 
                  case (whichCache)
                    ICache: return "IL1";
                    DCache: return "DL1";
                    L2:     return "L2";
                  endcase, "R","M"));
                rspFlit = 0;
              end else rspFlit = rspFlit + 1;
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
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Requesting eviction! Address: %x", $time, coreId, CacheAddress{tag: tag.tag, key: addr.key, bank: addr.bank, offset: 0}));
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
        
        Bool dontCommit = False;
        if (commit matches tagged Valid .cb &&& !cb) dontCommit = True;
        if (thisReqNext && dontCommit) begin
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Don't commit, NULL response! ", $time, coreId));
          Bool giveReadResponse = False;
          if (req.operation matches tagged Read .rop)  giveReadResponse = True;
          if (req.operation matches tagged CacheOp .cop &&& cop.inst == CacheLoadTag) giveReadResponse = True;
          if (giveReadResponse) cacheResp.operation = tagged Read {
                                    data: ?,
                                    last: thisReqLast
                                };
          resp = tagged Valid cacheResp;
        // This case will skip an attempt at success for now under the following conditions:
        end else if ((pending && !isRead) // Allow reads of pending locations to succeed.
                      || (!thisReqNext&&!cached)  // Execute uncached operations strictly in order.
                      || uncachedPending.notEmpty // Don't do anything if an uncached operation is outstanding.
                      || writebacks.notEmpty // If there is an unfinished writeback request.
                    ) begin
          // If this request is uncached and not next, don't do a lookup because an uncached load must be at the head of the queue
          // when the response comes back or the response will be dropped on the floor because it is not stored in the cache.
          // If it is in the head of the queue when we first issue the request, it will certainly be there when it gets back.
          //
          // Cached requests can begin early (though we will still respond in order).
          dead = True;
          debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> failing early ", $time, coreId));
        end else begin
          case (req.operation) matches
            tagged CacheOp .cop: begin
              wayMiss = False;
              if (cop.cache == whichCache) begin
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
                endcase
                resp = tagged Valid cacheResp;
              end else begin
                doMemRequest = True;
                if (cop.inst == CacheLoadTag) begin
                  expectResponse = True;
                end else begin
                  resp = tagged Valid cacheResp;
                end
              end
            end
            tagged Read .rop &&& (!miss && cached && !passConditional): begin
              cachedResponse=True;
            end
            tagged Write .wop &&& (!miss && cached && !passConditional): begin
              cachedWrite = True;
              tagUpdate[way] = TagLine{
                tag      : tag.tag,
                dirty    : (writeThrough) ? False:True,
                pending  : tagUpdate[way].pending,
                valid    : tag.valid
              };
              writeTags = True;
              if (writeThrough) doMemRequest = True;
            end
            tagged Write .wop &&& (!cached): begin
              //Write directly to memory.
              doMemRequest = True;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Uncached Write - Invalidating key=0x%0x", $time, coreId, addr.key));
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Sending ", $time, coreId, fshow(req)));
              if (!miss) doInvalidate = True;
            end
            tagged Write .wop &&& writeThrough: begin
              doMemRequest = True;
              if (conditional) begin
                if (!miss) doInvalidate = True;
              end
            end
            default: begin
              // If it's a cached operation, align the access.
              if (cached) begin 
                req.addr = unpack(pack(CacheAddress{
                                          tag: addr.tag, 
                                          key: addr.key, 
                                          bank: 0, 
                                          offset:0
                                       }));
                writeTags = True;
                if (tag.dirty) begin
                  if (roomForReadAndWriteback) writeback <- doWriteback;
                  else dead = True;
                end
              end
              
              req.operation = tagged Read {
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
              count <= count + 1; // Increment count at least once for every fill to randomise way selection.
            end
          endcase
          
          if (!thisReqNext) begin // If this is not the next request, kill the external request under two conditions...
            if (!cached) dead = True;
            // Kill the operation if it is not a read, which (probably) has no side effects.
            if (req.operation matches tagged Read .rop) begin
            end else dead = True;
          end
          if (doMemRequest && !dead) begin
            if (!readReqs.full && roomForOneRequest && !pending) begin // And if this is the next request in the queue.
              ReqId outReqId = ReqId{masterID: req.masterID, transactionID: nextId};
              req.masterID = outReqId.masterID;
              req.transactionID = outReqId.transactionID;
              nextId <= nextId + 1;
              memReqs.enq(req);
              if (!cached) begin
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Enquing pending uncached request", $time, coreId));
                uncachedPending.enq(expectResponse);
              end
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Issuing external memory request", $time, coreId, fshow(req)));
              if (expectResponse) begin
                if (cached) begin
                  tagUpdate[way] = TagLine{
                    tag    : addr.tag,
                    pending: True,
                    valid  : replicate(False),
                    dirty  : False
                  };
                  writeTags = True;  // This must happen!
                end
                RequestRecord#(ways, keyBits, tagBits) reqRec = RequestRecord{
                                                                  key: addr.key, 
                                                                  inId: reqId, 
                                                                  cached: cached,
                                                                  oldTags: tagUpdate,
                                                                  oldWay: way,
                                                                  oldDirty: tagsRead[way].dirty&&any(id,tagsRead[way].valid)
                                                               };
                debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Inserting %x into ID table", $time, coreId, outReqId, fshow(reqRec)));
                readReqs.insert(outReqId, reqRec);
              end
            end else begin // Kill the operation if we were meant to send a memory request but couldn't
              dead = True;
              // Don't write tags for fill if we didn't send a request.
              if (expectResponse) writeTags = False;
            end
          end

          if (!dead) begin
            if (doInvalidate) begin
              tagUpdate[way] = invTag;
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Invalidating key=0x%0x", $time, coreId, addr.key));
              writeTags = True;
            end
            if (writeTags) tags.write(addr.key, tagUpdate);
          end
          
          if (wayMiss) begin
            if (valueOf(ways) > 1)
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Way miss, %x != %x, wayHist[%x]<=%x", 
                                            $time, coreId, way, ct.dataKey.way, wayKey, way));
            wayHist[wayKey] <= way;
            dead = True;
          end else if (cachedResponse) begin
            //Return cached data.
            cacheResp.operation = tagged Read {
                data: Data {
                    `ifdef CAP
                      cap: dataRead.cap,
                    `endif
                    data: pack(dataRead.data)
                },
                last: thisReqLast
            };
            resp = tagged Valid cacheResp;
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> returning @0x%0x:0x%0x", $time, coreId, addr, dataRead));
          end else if (returnTag) begin
            Bit#(CheriDataWidth) tagLo = 0;
            tagLo[30] = (tag.valid[addr.bank])?1:0;
            tagLo[29:0] = zeroExtend(tag.tag);
            debug2("CacheCore", $display("CacheCore: CacheLoadTag resp=%x", tagLo));
            cacheResp.operation = tagged Read {
              data: Data {
                `ifdef CAP
                cap: dataRead.cap,
                `endif
                data: pack(tagLo)
               },
              last: thisReqLast
            };
            resp = tagged Valid cacheResp;
          end
          
          // From this point on, kill the request completely if it is not next
          if (!thisReqNext) dead = True;
          
          // Only finish the write if this is the next operation in order, and if this is not a way miss.
          if (req.operation matches tagged Write .wop &&& !dead) begin
            cacheResp.operation = tagged Write;
            if (cachedWrite) begin
              //Construct new line.
              Data#(CheriDataWidth) maskedWrite = dataRead;
              Vector#(BusBytes,Byte) maskedWriteVec = unpack(maskedWrite.data);
              Vector#(BusBytes,Byte) writeDataVec = unpack(wop.data.data);
              for (Integer i = 0; i < valueOf(BusBytes); i=i+1) begin
                if (wop.byteEnable[i]) begin
                    maskedWriteVec[i] = writeDataVec[i];
                end
              end
              maskedWrite.data = pack(maskedWriteVec);
              `ifdef CAP
                maskedWrite.cap = wop.data.cap;
              `endif
              //Write updated line to cache.
              debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> wrote cache bank %x, way %x with %x",$time, coreId, DataKey{key:addr.key, way:way, bank:addr.bank},way, maskedWrite));
              data.write(DataKey{key:addr.key, way:way, bank:addr.bank}, maskedWrite);
              resp = tagged Valid cacheResp;
            end
            if (miss && writeThrough) resp = tagged Valid cacheResp;
            // If this is a store conditional and we're not handling it,
            // the response is coming later.
            if (conditional && writeThrough) dead = True;
            if (wop.uncached) resp = tagged Valid cacheResp;
          end
        end

        // Make sure it's dead if it's not next, and also if there is no capacity in the receiver.
        if (!thisReqNext || !willConsume) dead = True;
        if (dead) resp = tagged Invalid;
        debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Request Dead %x, reqs.notEmpty %x, thisReqNext %x ", 
                                      $time, coreId, dead, reqs.notEmpty, thisReqNext, fshow(resp)));
        // Report the hit or miss of this lookup, only once per access.
        if (isValid(resp)) begin
          if (thisReqLast) begin
            debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Finishing request ", $time, coreId, fshow(reqs.first)));
            reqs.deq;
            req_commits.deq;
            rspFlit = 0;
            cycReport($display("[$%s%s%s]", 
              case (whichCache)
                ICache: return "IL1";
                DCache: return "DL1";
                L2:     return "L2";
              endcase,
              req.operation matches tagged Read .* ?"R":"W",(miss)?"M":"H"));
          end else rspFlit = rspFlit + 1;
        end
      end
    endcase
    rspFlitReg <= rspFlit;
    if (isValid(resp)) debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Delivering valid response, addr=%x, reqId ", $time, coreId, addr, fshow(reqId), fshow(resp)));
    return (resp);
  endmethod
  
  method Action nextWillCommit(Bool nextCommitting);
    req_commits.enq(nextCommitting);
  endmethod
endmodule
