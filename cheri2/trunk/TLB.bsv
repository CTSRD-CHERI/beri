/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
 * Copyright (c) 2012 Jonathan Woodruff
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
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
 *
 ******************************************************************************
 *
 * Author: Nirav Dave <ndave@csl.sri.com>
 *         Robert M. Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: CHERI2 Translation Lookaside Buffer
 *
 ******************************************************************************/

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Assert::*;

import MIPS::*;
import CHERITypes::*;
import Library::*;
import Debug::*;
import Bram::*;
import GenericCache::*;
import EHR::*;

//----------------------------------------------------------------------------

typedef Address VAddress;
typedef Address PAddress;

typedef struct {
  ThreadID      thread;
  ThreadState       ts;
  Bool           write; // is the access a write access?
`ifdef CAP
  Bool           capop; // is this a read/write of capability operation
`endif
  VAddress        addr;
} TLBRequest deriving (Bits, Eq, FShow);

typedef struct {
  Address        addr;
  Exception exception;
  CacheCA       cache;
} TLBResponse deriving(Bits, Eq, FShow);

`ifndef TLBSIZE
`define TLBSIZE 6
`endif
typedef `TLBSIZE       TLBIndexBits;
typedef Bit#(TLBIndexBits) TLBIndex;
typedef TExp#(TLBIndexBits) TLBSize;

interface TLBLookup;
  method Action req(TLBRequest x);
  method ActionValue#(TLBResponse) resp();             // PAddress
endinterface

typedef struct {
  Bit#(2)           r;  // Address space privilige, high order bits of the VPN. // 0=xuseg, 1=sxxeg, 2=xkphys, 3=xkseg
  Bit#(VPN2BITS) vpn2;  // Virtual Page Number.  Each Hi entry represents 2 Lo entries, so the last bit isn't matched.
  ASID           asid;  // Address Space Identifier.
} TLBEntryHi deriving(Bits, Eq, FShow); // 64 bits

typedef struct {
`ifdef CAP
  Bool        nostorecap; // Whether capability stores are disabled for the page
  Bool         noloadcap; // Whether capability loads are disabled for the page
`endif
  Bit#(PFNBITS)      pfn;  // Physical address of the page.
  CacheCA cacheAlgorithm;    // (c) Cache algorithm or cache coherency attribute for multi-processor systems.
  Bool             dirty;    // (d) Dirty - True if writes are allowed.  Writes will cause exception otherwise.
  Bool             valid;    // (v) Valid - If False, attempts to use this location cause an exception.
} TLBEntryLo deriving(Bits, Eq, FShow, Bounded); // 64 bits

// This version of TLBEntryLo is identical to the above except that it
// used for the CP0 registers which, weirdly, have a global bit which
// comes from the EntryHi.
typedef struct {
   TLBEntryLo          lo;
   Bool            global;    // (g) Global
} TLBEntryLoReg deriving(Bits, Eq, FShow, Bounded); // 64 bits

typedef struct {
  TLBEntryHi  entryHi;
  Bool          valid;    // Always valid for a stored entry.  Will be returned invalid if there is no entry.
  PageMask   pageMask;    // Always 0!  We'll only do 4k pages.
  Bool         global;    // (g) Global.  This virtual address maps in all spaces.
} TLBAssociativeEntry deriving(Bits, Eq, FShow); // 32 bits

typedef struct{
  TLBAssociativeEntry   assoc;
  Vector#(2,TLBEntryLo)    lo;
} TLBEntry deriving(Bits, Eq, FShow);

interface TLBUpdate;
  method Action                         probe_req(ThreadID thread, ASID asid, VAddress va);
  method ActionValue#(Maybe#(TLBIndex)) probe_resp;
  method Action                         read_req(ThreadID thread, TLBIndex idx);
  method ActionValue#(TLBEntry)         read_resp;
  method Action                         write(ThreadID thread, TLBIndex idx, TLBEntry entry);
endinterface

typedef struct {
  ThreadID thread;
  ASID       asid;
  VAddress     va;
   } TLBSearchReq deriving (Bits, FShow);
typedef Maybe#(Tuple2#(TLBIndex, TLBEntry)) TLBSearchResp;
typedef CacheIfc#(TLBSearchReq, TLBSearchResp) TLBSearch;

// Number of bits of VA used to index L1 TLB cache, must be at least 1
typedef 4 TLBCacheBits;
typedef TAdd#(TLBCacheBits, 12) TLBCacheIndexTop;
typedef TAdd#(TLBCacheBits, 13) TLBCacheTagStart;
typedef TSub#(59, TLBCacheBits) TLBCacheTagSize;

typedef enum {TLB_STATE_READY, TLB_STATE_SEARCHING, TLB_STATE_READ, TLB_STATE_WRITE_1, TLB_STATE_WRITE_2} TLBState deriving (Bits, Eq);

interface TLB;
  interface Vector#(2, TLBLookup)  lookups; //VA -> PA lookup
  interface TLBUpdate               update;
endinterface

function Bool entryMatches(TLBEntry entry, ASID asid, VAddress va);
      VAddr vaddr = unpack(va);
      TLBAssociativeEntry e = entry.assoc;
      return (e.valid &&                            // entry valid
             (e.entryHi.r == vaddr.r) &&            // region match
             (e.entryHi.vpn2 == vaddr.vpn2) &&      // virtual page match XXX page mask
             (e.global || e.entryHi.asid == asid)); // asid match
endfunction

function TLBResponse getTLBResponse(TLBRequest x, Maybe#(TLBEntry) m_entry);
  let privLevel = currentMode(x.ts.modeBits, x.ts.exceptionLevel, x.ts.errorLevel);
  match {.mode, .mapped, .cacheCA, .compat32, .addrErr} = decodeAddr(x.addr, x.ts.cacheAlgorithm);
  let evenOddBit   = 12; // rmn30 XXX deal with pagemask != 0
  let entry        = fromMaybe(?, m_entry);
  let entryLo      = (x.addr[evenOddBit] == 1) ? entry.lo[1] :  entry.lo[0];
  let mappedAddr   = zeroExtend({entryLo.pfn, x.addr[11:0]});
  // physical address on unmapped requests
  let unmappedAddr = (compat32) ? {35'd0, x.addr[28:0]} : {8'b00, x.addr[55:0]};
  let noPrivEx     = x.write ? Ex_AddrErrStore : Ex_AddrErrLoad;
  let tlbMissEx    = x.write ? Ex_TLBStore     : Ex_TLBLoad;
  let tlbInvEx     = x.write ? Ex_TLBStoreInv  : Ex_TLBLoadInv;
  let havePriv     = privLevel <= mode;
  let translatedAddr = mapped ? mappedAddr : unmappedAddr;
  let exception = Ex_None;
  if (addrErr || !havePriv)
    exception = noPrivEx;
  else if (mapped) begin
    if (!isValid(m_entry))
      exception = tlbMissEx;
    else if (!entryLo.valid)
      exception = tlbInvEx;
    else if (x.write && !entryLo.dirty)
      exception = Ex_Modify;
`ifdef CAP
    else if (x.capop && x.write && entryLo.nostorecap)
      exception = Ex_TLBStoreCap;
    else if (x.capop && !x.write && entryLo.noloadcap)
      exception = Ex_TLBLoadCap;
`endif
  end else if (translatedAddr > 64'h7fffffff)
    // XXX rmn30 kill access to invalid addresses that will cause AXI to hang.
    // These addresses can be generated during instruction fetch of cancelled 
    // instructions due to a hazard with pcc.
    exception = Ex_DataBusErr;
  return TLBResponse {
     addr      : translatedAddr,
     exception : exception,
     cache     : mapped ? entryLo.cacheAlgorithm : cacheCA
  };
endfunction
  
//----------------------------------------------------------------------------

`ifdef SIMPLE_TLB
`include "SimpleTLB.bsv"
`else

//(* synthesize, options="-aggressive-conditions" *) rmn30: causes conflicting methods in writeback
module mkTLB(TLB);
  function getInitialEntry(idx)                        =  TLBEntry{assoc:TLBAssociativeEntry{valid:False}};
  let                                         initBram <- mkInitialisedBramNoWriteForward(getInitialEntry);
  Bram#(Bit#(SizeOf#(Tuple2#(ThreadID, TLBIndex))), TLBEntry) entries =  initBram.bram;

  EHR#(2, TLBState) tlbState <- mkEHR(TLB_STATE_READY);
  let               readReqQ <- mkSizedFIFOF(1);
  let              readRespQ <- mkSizedFIFO(1);
  let                 writeQ <- mkSizedFIFOF(1);
  let             searchReqQ <- mkFIFOF;
  let            searchRespQ <- mkFIFO;
  Reg#(TLBIndex) searchIndex <- mkReg(minBound);

  module mkTLBSearch(TLBSearch);
    method Action req(TLBSearchReq request);
      searchReqQ.enq(request);
    endmethod

    method ActionValue#(TLBSearchResp) resp;
      let ret <- popFIFO(searchRespQ);
      return ret;
    endmethod
  endmodule

  module mkSearchArbiter#(TLBSearch search)(Vector#(n, TLBSearch)) provisos (Log#(n, logn));
    Vector#(n, FIFOF#(TLBSearchReq)) reqQs  <- replicateM(mkFIFOF);
    Vector#(n, FIFO#(TLBSearchResp)) respQs <- replicateM(mkFIFO);

    FIFO#(UInt#(logn))      portQ <- mkFIFO;

    module mkSearchPort#(Integer i)(TLBSearch);
      rule doReq;
        let r <- popFIFOF(reqQs[i]);
        search.req(r);
        portQ.enq(fromInteger(i));
      endrule

      rule getResp(portQ.first == fromInteger(i));
        portQ.deq();
        let r <- search.resp();
        respQs[i].enq(r);
      endrule

      method Action req(TLBSearchReq r);
        debug_tlb($display("tlbSearch req %d: ", i, fshow(r)));
        reqQs[i].enq(r);
      endmethod

      method ActionValue#(TLBSearchResp) resp;
        let r <- popFIFO(respQs[i]);
        debug_tlb($display("tlbSearch resp %d: ", i, fshow(r)));
        return r;
      endmethod
    endmodule

    let ports <- genWithM(mkSearchPort);
    return ports;
  endmodule

  // Direct mapped cache of TLB entries indexed by ThreadID and lower bits of virtual page number
  // TLBCacheBits determines the index width and hence cache size.
  module mkTLBCache#(TLBSearch nextLevel)(TLBSearch) provisos (Add#(ThreadSZ, TLBCacheBits, iSZ));
    function Bit#(iSZ) getTLBCacheIndex(TLBSearchReq req) = pack(tuple2(req.thread, req.va[valueOf(TLBCacheIndexTop):13]));
    function Bit#(TLBCacheTagSize) getTLBCacheTag(TLBSearchReq req)   = pack(tuple2(req.asid, req.va[63:valueOf(TLBCacheTagStart)]));
    function Bool      isTLBCacheable(TLBSearchReq req, TLBSearchResp resp)   = isValid(resp);

    // XXX rmn30 for now these are identify functions, should save space by eliminating index and tag bits from getData...
    function TLBSearchResp getTLBCacheData(TLBSearchResp resp) = resp;
    function TLBSearchResp toTLBCacheResp(TLBSearchResp data)  = data;

    TLBSearch cache <- mkSimpleDirectMappedCache(
       getTLBCacheIndex,
       getTLBCacheTag,
       isTLBCacheable,
       getTLBCacheData,
       toTLBCacheResp,
       nextLevel);
    return cache;
  endmodule

  let                      searcher <- mkTLBSearch;
  Vector#(3, TLBSearch) searchPorts <- mkSearchArbiter(searcher);
  Vector#(2, TLBSearch)   tlbCaches <- mapM(mkTLBCache, tail(searchPorts));


  //-------------------------------------------------------------------------
  //TLB Backend: If the TLB caches miss we must perform a linear
  //search of the entries bram. These rules implement this and also
  //handle read/write operations from CP0.  They are mutually
  //exclusive except for searchNextIndex which fires after
  //readTLBEntry in the same cycle to make the readReqs and readResps
  //nicely pipelined.  These must be in different rules because they
  //conflict.  We need an EHR to so that we don't do an extra readReq
  //when the search finishes.  For TLB writes we have to first read
  //the old value at the given index so that we can invalidate the L1
  //caches by VPN.

  rule startRequest (tlbState[0] == TLB_STATE_READY);
    case (tlbState[0]) matches
      TLB_STATE_READY:
      begin
        if (writeQ.notEmpty)
          begin
            match {.thread, .idx, .entry} = writeQ.first;
            debug_tlb($display("TLB Write Entry thread=%d idx=0x%x", {1'b0, thread}, idx));
            entries.readReq(pack(tuple2(thread, idx)));
            tlbState[0] <= TLB_STATE_WRITE_1;
          end
        else if (readReqQ.notEmpty)
          begin
            match {.thread, .idx} = readReqQ.first;
            debug_tlb($display("TLB Read Entry thread=%d idx=0x%x", {1'b0, thread}, idx));
            entries.readReq(pack(tuple2(thread, idx)));
            tlbState[0] <= TLB_STATE_READ;
          end
        else if (searchReqQ.notEmpty)
          begin
            TLBIndex startIndex = 0;
            debug_tlb($display("TLB Search Start thread=%d idx=%d", {1'b0, searchReqQ.first.thread}, startIndex));
            entries.readReq(pack(tuple2(searchReqQ.first.thread, startIndex)));
            searchIndex <= startIndex;
            tlbState[0] <= TLB_STATE_SEARCHING;
          end
      end
    endcase
  endrule

  rule searchNextIndex(tlbState[1] == TLB_STATE_SEARCHING);
    let nextIndex = searchIndex + 1;
    debug_tlb($display("TLB Search Read Next thread=%d idx=%d", {1'b0, searchReqQ.first.thread}, nextIndex));
    entries.readReq(pack(tuple2(searchReqQ.first.thread, nextIndex)));
    searchIndex <= nextIndex;
  endrule

  rule readTLBEntry;
    TLBEntry           e <- entries.readResp();
    case (tlbState[0]) matches
      TLB_STATE_SEARCHING:
      begin
        TLBSearchReq request = searchReqQ.first();
        Bool matched = entryMatches(e, request.asid, request.va);
        let      idx = searchIndex;
        debug_tlb($display("TLB Search: 0x%x %s entry %d ", request.va, matched ? "matches" : "doesn't match", idx, fshow(e)));
        if (matched)
          searchRespQ.enq(Valid(tuple2(idx, e)));
        else if (idx == maxBound)
          searchRespQ.enq(Invalid);
        if (matched || idx == maxBound)
          begin
            searchReqQ.deq();
            tlbState[0] <= TLB_STATE_READY;
          end
      end
      TLB_STATE_READ:
      begin
        readReqQ.deq;
        readRespQ.enq(e);
        tlbState[0] <= TLB_STATE_READY;
      end
      TLB_STATE_WRITE_1:
      begin
        match {.thread, .idx, .entry} = writeQ.first;
        if (e.assoc.valid)
          begin
            let toInvalidate = TLBSearchReq{thread:thread, asid:e.assoc.entryHi.asid, va: {e.assoc.entryHi.r, zeroExtend(e.assoc.entryHi.vpn2), 13'b0}};
            tlbCaches[0].invalidate(toInvalidate);
            tlbCaches[1].invalidate(toInvalidate);
          end
        tlbState[0] <= TLB_STATE_WRITE_2;
      end
      default:
      dynamicAssert(False, "Unexpected tlbState in readTLBEntry.");
    endcase
  endrule

  rule tlbWriteStage2 if (tlbState[0] == TLB_STATE_WRITE_2);
    match {.thread, .idx, .entry} <- popFIFOF(writeQ);
    entries.write(pack(tuple2(thread, idx)), entry);
    tlbState[0] <= TLB_STATE_READY;
  endrule

  module mkTLBLookup#(Integer i)(TLBLookup);
    let reqQ <- mkPipeFIFO;
    let search  = tlbCaches[i];

    method Action req(TLBRequest x);
      debug_tlb($display("TLB Lookup %d:", i, fshow(x)));
      reqQ.enq(x);
      match {.mode, .mapped, .cacheCA, .compat32, .addrErr} = decodeAddr(x.addr, x.ts.cacheAlgorithm);
      if (mapped)
        search.req(TLBSearchReq{thread: x.thread, asid:x.ts.asid, va: x.addr});
    endmethod

    method ActionValue#(TLBResponse) resp;
      let x           <- popFIFO(reqQ);
      match {.mode, .mapped, .cacheCA, .compat32, .addrErr} = decodeAddr(x.addr, x.ts.cacheAlgorithm);
      let search_resp <- mapped ? search.resp : toAV(Invalid);
      let m_entry     =  liftM(tpl_2, search_resp);
      let r = getTLBResponse(x, m_entry);
      debug_tlb($display("TLB Resp %d:", i, fshow(r)));
      return r;
    endmethod
  endmodule

  //-------------------------------------------------------------------------
  // Interface

  // construct vector of lookups
  let lookupMods <- mapM(mkTLBLookup, genVector);
  interface lookups = lookupMods;

  interface TLBUpdate update;
    method Action probe_req(ThreadID thread, ASID asid, VAddress va);
      searchPorts[0].req(TLBSearchReq{thread:thread, asid: asid, va: va});
    endmethod

    method ActionValue#(Maybe#(TLBIndex)) probe_resp;
      let m_Resp                  <- searchPorts[0].resp;
      return (liftM(fst, m_Resp));
    endmethod

    method Action read_req(ThreadID thread, TLBIndex idx);
      readReqQ.enq(tuple2(thread, idx));
    endmethod

    method ActionValue#(TLBEntry) read_resp;
      let e <- popFIFO(readRespQ);
      return e;
    endmethod

    method Action write(ThreadID thread, TLBIndex idx, TLBEntry entry);
      writeQ.enq(tuple3(thread, idx, entry));
    endmethod
  endinterface
endmodule

`endif
