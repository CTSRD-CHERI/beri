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
`ifdef STATCOUNTERS
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
  `ifdef STATCOUNTERS
  interface Get#(CacheCoreEvents) cacheEvents;
  `endif
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
  Bool                          pendMem;
  Bool                            dirty;
  Vector#(TExp#(BankBits), Bool)  valid;
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
  Bool                valid;
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

typedef struct {
  LookupCommand                                 command;
  CheriMemRequest                                   req; // Original request that triggered the lookup.
  CacheAddress#(keyBits, tagBits)                  addr; // Byte address of the frame that was fetched.
  DataKey#(ways, keyBits)                       dataKey; // Datakey used in the fetch (which duplicates some of addr and adds the way).
  Bool                                             last;
  Bool                                            fresh;
  Bool                                       invalidate; // This request was triggered by an invalidate request.
  Error                                        rspError;
} FetchToken#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, FShow);

instance DefaultValue#(FetchToken#(ways, keyBits, tagBits));
  function FetchToken#(ways, keyBits, tagBits) defaultValue;
    FetchToken#(ways, keyBits, tagBits) dv = unpack(0);
    dv.req = defaultValue;
    dv.command = Nop;
    dv.fresh = False;
    dv.invalidate = False;
    dv.rspError = NoError;
    dv.last = True;
    return dv;
  endfunction
endinstance

typedef struct {
  FetchToken#(ways, keyBits, tagBits)                ft;
  Bank                                        noOfFlits;
  Bool                                           cached;
  Bool                                     respForWrite;
  Bool                                         scResult;
  Bool                                    respondWithSC;
  Bool                                      thisReqNext;
  Bool                                      thisReqLast;
  Bool                                       firstFresh;
  Bool                                    noWaitingReqs;
  Bool                                     nextSetMatch;
  Maybe#(Bool)                                   commit;
  Way#(ways)                                        way;
  Bit#(keyBits)                            wayUpdateKey;
  Way#(ways)                                  wayUpdate;
  Bool                                      doWayUpdate;
  Vector#(ways,TagLine#(tagBits))              tagsRead;
  Data#(CheriDataWidth)                        dataRead;
  CacheCommitToken#(ways, keyBits, tagBits) cacheCommit;
  ResponseToken                                      rt;
} ControlToken#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, FShow);

instance DefaultValue#(ControlToken#(ways, keyBits, tagBits));
  function ControlToken#(ways, keyBits, tagBits) defaultValue;
    ControlToken#(ways, keyBits, tagBits) dv = unpack(0);
    dv.ft = defaultValue;
    dv.noOfFlits = 0;
    dv.cached = True;
    dv.respForWrite = False;
    dv.scResult = False;
    dv.respondWithSC = False;
    dv.thisReqNext = False;
    dv.thisReqLast = False;
    dv.noWaitingReqs = True;
    dv.nextSetMatch = True;
    dv.doWayUpdate = False;
    dv.commit = tagged Invalid;
    dv.cacheCommit = CacheCommitToken{
      memReq: defaultValue,
      doMemReq: False,
      key: unpack(0),
      tags: ?,
      writeTags: False,
      data: ?,
      writeData: False,
      readRec: ?,
      readId: ?,
      insertReadRec: False,
      reqId: ?,
      insertReqId: False,
      pendingResponse: ?,
      enqPending: False
    };
    dv.rt = ResponseToken{
      valid: False,
      resp: defaultValue,
      req: defaultValue,
      rspFlit: 0,
      rspId: tagged Invalid,
      enqRetryReq: False,
      deqNext: False,
      deqId: ?,
      deqReqCommits: False,
      deqRetryReqs: False
    };
    return dv;
  endfunction
endinstance

typedef struct {
  CheriMemRequest                             memReq;
  Bool                                      doMemReq;
  DataKey#(ways, keyBits)                        key;
  Vector#(ways,TagLine#(tagBits))               tags;
  Bool                                     writeTags;
  Data#(CheriDataWidth)                         data;
  Bool                                     writeData;
  RequestRecord#(ways, keyBits, tagBits)     readRec;
  ReqId                                       readId;
  Bool                                 insertReadRec;
  ReqId                                        reqId;
  Bool                                   insertReqId;
  Bool                               pendingResponse;
  Bool                                    enqPending;
} CacheCommitToken#(numeric type ways, numeric type keyBits, numeric type tagBits) deriving (Bits, FShow);

typedef struct {
  CheriMasterID      masterID;
  CheriTransactionID transactionID;
} ReqId deriving (Bits, Eq, FShow);

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

interface CacheCoreWriteback#(numeric type ways,
                     numeric type keyBits,
                     numeric type tagBits);
  method Action put(AddrTagWay#(ways, keyBits, tagBits) atw);
  method Bool canPut;
  method ActionValue#(FetchToken#(ways, keyBits, tagBits)) get;
  method Bool canGet;
endinterface: CacheCoreWriteback

interface CacheCoreServe#(numeric type ways,
                         numeric type keyBits,
                         numeric type tagBits
                         );
  method ActionValue#(ControlToken#(ways, keyBits, tagBits)) serveCacheRequest(ControlToken#(ways, keyBits, tagBits) ct);
  `ifdef STATCOUNTERS
  interface Get#(CacheCoreEvents) cacheEvents;
  `endif
endinterface: CacheCoreServe

interface CacheCoreFill#(numeric type ways,
                         numeric type keyBits,
                         numeric type tagBits,
                         numeric type inFlight
                        );
  method Action reportRequest(CacheCommitToken#(ways, keyBits, tagBits) cct);
  method ActionValue#(ControlToken#(ways, keyBits, tagBits)) getAnyMemoryResponse(ControlToken#(ways, keyBits, tagBits) ct);
  method Bool noMoreReadReqs();
  method Bool outstandingRequest(ReqId id);
  method Bool uncachedPending();
endinterface: CacheCoreFill
