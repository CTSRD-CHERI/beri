/*-
 * Copyright (c) 2010-2013 Jonathan Woodruff
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
 * Copyright (c) 2014 Alexandre Joannou
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
 * Authors:
 *   Nirav Dave <ndave@csl.sri.com>
 *   Jonathan Woodruff <jonathan.woodruff@cl.cam.ac.uk>
 *   Robert M. Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Memory SubSystem
 *
 ******************************************************************************/

import FIFO::*;
import FIFOF::*;
import RegFile::*;
import SpecialFIFOs::*;
import GetPut::*;
import ClientServer::*;
import MasterSlave::*;
import Connectable::*;


import Vector::*;
import BuildVector::*;
import FShow::*;

import Library::*;
import Debug::*;
import EHR::*;
import Bram::*;

import MIPS::*;
import CHERITypes::*;
import CP0::*;
import TLB::*;
import MemoryCompute::*;
import MemTypes::*;
import DefaultValue::*;
import Assert::*;
import CheriAxi::*;

`ifndef VERIFY2
import L2Cache::*;
`ifdef CAP
import TagCache::*;
`endif
`endif


function Bool watchHit(ThreadState ts, Bool instruction, Bool write, Address va);
`ifndef NOWATCH
  let mask     = {52'hfffffffffffff, ~pack(ts.watchMask)};
  let vaddrHit = (va[63:3] & mask) == (ts.watchVaddr & mask);
  let asidHit  = ts.watchG || (ts.watchASID == ts.asid);
  let modeHit  = instruction ? ts.watchI : (write ? ts.watchW : ts.watchR);
  return vaddrHit && asidHit && modeHit;
`else
  return False;
`endif
endfunction

//-----------------------------------------------------------------------------
// DMem Interface
//-----------------------------------------------------------------------------

typedef struct {
   Bool     valid;
   Bit#(24)   tag; // XXX rmn30: should define in terms of PABTIS
   `ifdef CAP
   Bool    memTag;
   `endif
} DCache_tag deriving(Bounded, Bits, Eq, FShow);

//-----------------------------------------------------------------------------------------
// L1 Data Cache.
//
// A virtually indexed, physically tagged, write-through cache with
// support for ll/sc, tagged memory and a configurable number of ways
// (via DWays BlueSpec declaration).
//
// Cache lines are 256-bits in order to support capabilities. There
// are 128 lines which means the index only includes bits of the 4k
// page offset. This avoids potential problems with aliasing due to
// virtual indexing.
//
// ll/sc is implemented via an extension to the tags to record the
// most recent thread to perform a load link for each line. Only that
// thread can then perform a successful sc to that line (providing it
// is still valid and not replaced).
//
// Support for tagged memory is implemented with an extra bit in the
// cache tag.
//
// Note that we do not implement store to load forwarding but we do
// not need to stall loads because the invalidation will be forwarded
// by the BRAM.
// -----------------------------------------------------------------------------------------

module mkDCache#(Memory dmemPort, TLB tlb, MemInvalidate imemInval)(CHERITypes::DCache);
  // rmn30 XXX fix these FIFOs
  FIFO#(Tuple3#(ThreadID, ThreadState, VirtualMemRequest)) dmem_reqQ <- mkLFIFO;
  // This FIFO must be no bigger than one entry if store->load
  // invalidation forwarding via bram is to work.
  let dmem_respQ                               <- mkPipeFIFO;

  Reg#(DWayIdx)               nextVictim <- mkReg(0);

  // rmn30 ZZZ would be nice not to hard code cache size
  function initialTag(idx)             =  DCache_tag{valid: False, tag:?
     `ifdef CAP
     , memTag: ?
     `endif
     };
  let                        initBrams <- replicateM(mkInitialisedBram(initialTag));
  function bramFromInitBram(ib)        =  ib.bram;
  Vector#(DWays, Bram#(Bit#(7), DCache_tag)) tag_brams = map(bramFromInitBram, initBrams);
  Vector#(DWays, Bram#(Bit#(7), Bit#(256)))  data_brams <- replicateM(mkBram);
  Vector#(NumThreads, Reg#(Maybe#(PAddress)))   llAddrs <- replicateM(mkReg(Invalid));

  method ActionValue#(Exception) req(ThreadID thread,
                                     ThreadState ts,
                                     VirtualMemRequest request);
    // Is this a write? For this purpose we treat Cache operations as
    // reads because they shouldn't lead to TLB Mod exceptions.
    let isWrite = request.operation matches tagged Write .wop ? True : False;
    let watchEx = case (request.operation) matches
                    tagged CacheOp .cop : begin
                      let mode = currentMode(ts.modeBits, ts.exceptionLevel, ts.errorLevel);
                      return mode > KSU_K ? Ex_CoProcess1 : Ex_None;
                    end
                    default: return watchHit(ts, False, isWrite, unpack(pack(request.addr))) ? Ex_Watch : Ex_None;
                  endcase;
    if (watchEx == Ex_None)
      begin
        tlb.lookups[1].req(TLBRequest {thread: thread,
                                       ts: ts,
                                       write: isWrite,
                                       addr: unpack(pack(request.addr))});
        dmem_reqQ.enq(tuple3(thread, ts, request));

        function readReqBr(br) = br.readReq(pack(request.addr)[11:5]);
        let x1 <- mapM(readReqBr, tag_brams);
        let x2 <- mapM(readReqBr, data_brams);
      end
    debug2("dcache", $display("DCache: req ", fshow(request), " 0x%x -> ",  request.addr, fshow(watchEx)));
    return watchEx;
  endmethod

  method ActionValue#(Exception) commit(Bool committing);
    match {.thread, .ts, .req} <- popFIFO(dmem_reqQ);
    let va = req.addr;

    TLBResponse tlbResp <- tlb.lookups[1].resp;
    // Indexed CACHE ops cannot throw TLB exceptions, so ignore them.
    let tlbEx   = req.operation matches tagged CacheOp .cop &&& cop.indexed ? Ex_None : tlbResp.exception;
`ifdef CAP
    // Throw an exception on an attempt to store a valid capability to a page with nostorecap set.
    let tlbStoreCapEx = req.operation matches tagged Write .wop &&& tlbResp.nostorecap && wop.data.cap == vec(True) ? Ex_CoProcess2 : Ex_None;
    tlbEx = joinException(tlbEx, tlbStoreCapEx);
`endif
    let commitFinal = committing && (tlbEx == Ex_None);
    req.addr    = unpack(pack(tlbResp.addr));
    let cached  = tlbResp.cache == CA_CACHED; // XXX rmn30 need to support other cache modes

    function readResp(br) = br.readResp();
    let tags  <- mapM(readResp, tag_brams);
    let datas <- mapM(readResp, data_brams);

    // Did the tag match the request?
    function Bool wasCacheHit(DCache_tag t);
      return (pack(req.addr)[35:12] == t.tag) && t.valid;
    endfunction
    let cacheHits = map(wasCacheHit, tags);
    let mHitIdx   = findIndex(id, cacheHits);
    let cacheHit  = isValid(mHitIdx);

    debug2("dcache", $display("DCache: getResp tid=%d ll=%b\n     tags=", thread, ts.llBit, fshow(tags), "\n    datas=", fshow(datas), "\n    hits=%b", pack(cacheHits)));

    let tag  = mHitIdx matches tagged Valid .idx ? tags[idx] : ?;
    let data = mHitIdx matches tagged Valid .idx ? datas[idx] : ?;

    // Was the request a load?
    let load     = req.operation matches tagged Read .* ? True : False;
    // Was the request a cached load which hit?
    // Always treat ll as a miss so that it updates the tags and passes through to next level.
    let ll = req.operation matches tagged Read .rop &&& rop.linked ? True : False;
    let loadHit  = load && cached && cacheHit && ! ll;
    // Was the request a store?
    let store    = req.operation matches tagged Write .* ? True : False;
    // Was the request a store conditional?
    let sc       = req.operation matches tagged Write .wop &&& wop.conditional ? True : False;
    // Was the request a store conditional which failed?
    let llAddrMatch = llAddrs[thread] matches tagged Valid .addr &&& addr == req.addr ? True : False;
    let scFailed = sc && !( ts.llBit && cached && llAddrMatch);
    // Was the request a Cache operation for either L1 cache? If so we don't need to pass through the request.
    let isL1CacheOp = req.operation matches tagged CacheOp .cop &&& (cop.cache == DCache || cop.cache == ICache) ? True : False;

    // Update the llAddr register
    if (commitFinal && ll)
      begin
        // Store llAddr for load linked
        llAddrs[thread] <= Valid (req.addr);
      end
    else if (commitFinal && store && !scFailed)
      begin
        // Invalidate matching llAddrs on store.  NB we must not
        // invalidate for sc fail as this could lead to making no
        // forward progress. We do invalidate on sc success -- even
        // for the thread which did the sc. This means that only one
        // sc can be performed per ll i.e. For sequence ll, sc, sc the
        // second sc will fail. Not clear whether this is OK by mips
        // spec, but probably doesn't matter as it wouldn't be very
        // useful in cached memory.
	function Maybe#(PAddress) updateLLAddr(Maybe#(PAddress) mpa);
	  let llAddrMatch = mpa matches tagged Valid .addr &&& addr == req.addr ? True : False;
	  if (llAddrMatch)
	    return Invalid;
	  else
	    return mpa;
	endfunction
	writeVReg(llAddrs, map(updateLLAddr, readVReg(llAddrs)));
      end

    // Something to put in the response queue.
    CheriMemResponse hitRsp = defaultValue;
    hitRsp.operation = tagged Read {
        last: True,
        data: Data {
            `ifdef CAP
            cap: unpack(pack(tag.memTag)),
            `endif
            data: data
        }
    };
    let loadHitResp = tagged Valid hitRsp;
    CheriMemResponse oRsp = defaultValue;
    oRsp.operation = tagged Read {
        last: True,
        data: Data {
            `ifdef CAP
            cap: ?,
            `endif
            data: 0
        }
    };
    let otherResp = tagged Valid oRsp;

    // If there was a hit and in some other cases we can return a response straight away.
    let response = (isL1CacheOp || scFailed || !commitFinal) ? otherResp : (loadHit ? loadHitResp : Invalid);

    // If we were unable to return an immediate response then pass the request to the next level
    // Note that the exception is always Ex_None so can safely be ignored.
    CheriMemRequest newReq = virtualToPhyMemReq(req);
    case (req.operation) matches
      tagged Read .rop : begin
        if (cached) newReq.addr = unpack(pack(newReq.addr) & ~ 'h1F);
        newReq.operation = tagged Read {
            uncached : ! cached,
            linked : rop.linked,
            noOfFlits : rop.noOfFlits,
            bytesPerFlit : cached ? BYTE_32 : rop.bytesPerFlit
        };
      end
      tagged Write .wop : begin
        newReq.operation = tagged Write {
            uncached : ! cached,
            conditional : wop.conditional,
            byteEnable : wop.byteEnable,
            data : wop.data,
            last : wop.last
        };
      end
    endcase
    if (!isValid(response))
      dmemPort.req(newReq);

    // Select a way to update. If there was a hit we must update that way, otherwise choose a way which is not
    // valid, else choose a random victim.
    function Bool tagInvalid(DCache_tag t);
      return !t.valid;
    endfunction
    let mFirstInvalidIdx = findIndex(tagInvalid, tags);
    DWayIdx way = mHitIdx matches tagged Valid .idx ?
      pack(idx) : mFirstInvalidIdx matches tagged Valid .idx2 ?
      pack(idx2) : nextVictim;
    nextVictim <= nextVictim + 1;
`ifdef CAP
    // Squash the tag on loads from pages with the noloadcap bit set
    Bool squashTag = tlbResp.noloadcap;
`else
    Bool squashTag = ?;
`endif
    dmem_respQ.enq(tuple8(thread, newReq, va, response, commitFinal, cacheHit, way, squashTag));
    return tlbEx;
  endmethod

  method ActionValue#(CheriMemResponse) resp();
    match { .thread, .req, .va, .m_Resp, .committing, .cacheHit, .way, .squashTag}  <- popFIFO(dmem_respQ);
    let load       = req.operation matches tagged Read .* ? True : False;
    let idx        = pack(req.addr)[11:5];
    let loadCached = req.operation matches tagged Read .rop &&& ! rop.uncached ? True : False;
    // Get response (either from memory or from above).
    let memresp <- fromMaybeAV(dmemPort.resp(), m_Resp);
`ifdef CAP
    // Overwrite the capability tag with 0 for loads from pages with noloadcap set
    //  -- all this to change a single field (hooray for tagged unions)!
    if (squashTag)
        memresp.operation = (memresp.operation) matches tagged Read .rop &&& True ? 
        tagged Read {data: Data { cap: vec(False), data: rop.data.data}, last: rop.last} : memresp.operation;
`endif
    if (committing && !isValid(m_Resp))
      begin
        // This means anything which caused a memory request i.e. a
        // non-load, an uncached or missed load, or a load linked
        // (otherwise there was a load hit, an exception, or an sc
        // failure)
        if (loadCached || cacheHit)
          begin
            // Write valid tag for load cached, invalidate for any
            // other hit.  Note that as a side-effect uncached loads
            // will invalidate the cache if they happen to hit.
            //
            // ZZZ rmn30 we could cache the data on write hit but
            // currently we just invalidate and write through.
            let tag = DCache_tag{
               `ifdef CAP
               memTag: memresp.operation matches tagged Read .rop &&& pack(rop.data.cap) != 0 ? True : False,
               `endif
               valid: loadCached,
               tag: pack(req.addr)[35:12]
               };
            let tags = tag_brams[way];
            tags.write(idx, tag);
            debug2("dcache", $display("DCache: write way=%d line=0x%x tag=", way, idx, fshow(tag)));
          end
      end
    else
      begin
        if (req.operation matches tagged CacheOp .cop)
          if (cop.cache == ICache)
            imemInval.invalidate(zeroExtend(pack(req.addr))); // treat all operations as invalidate
          else
            begin
              // Must be L1 Data, invalidate all ways
              // ZZZ rmn30 should check cacheOp.index and only invalidate on hit.
              function Action invalidateWay(Bram#(Bit#(7),DCache_tag) tb);
                return tb.write(pack(req.addr)[11:5], 
                   DCache_tag{
                      valid:False, 
                      `ifdef CAP
                      memTag: ?,
                      `endif
                      tag:?
                   });
              endfunction
              mapM_(invalidateWay, tag_brams);
            end
      end

    if (committing && loadCached)
      begin
        // Store data for missed cached loads. We also do the write
        // for hit loads but this makes no difference.
        if (memresp.operation matches tagged Read .rop) begin
          debug2("dcache", $display("DCache: write line 0x%x way %d data=%x", idx, way, rop.data.data));
          let datas = data_brams[way];
          datas.write(idx, rop.data.data);
        end else dynamicAssert(False, "Only Read responses are expected");
      end

    if (committing)
      begin
        debug_dmem($write("DMEM T%d:", thread, " va:0x%x pa:0x%x", va, pack(req.addr)));
        case (req.operation) matches
          tagged Read .rop:
            begin
              if (memresp.operation matches tagged Read .rrop)
                debug_dmem($write(" rd 0x%x ", rrop.data.data,
                   `ifdef CAP
                   "tag=%b ", pack(rrop.data.cap),
                   `endif
                   fshow(rop.bytesPerFlit), rop.uncached ? " uncached" : "", rop.linked ? " linked" : "" ));
            end
          tagged Write .wop: debug_dmem($write(" wr 0x%x be=0x%x",
             wop.data.data, pack(wop.byteEnable),
             `ifdef CAP
             " tag=%b", pack(wop.data.cap),
             `endif
             wop.uncached ? " uncached" : "", wop.conditional ? " conditional" : "" ));
          tagged CacheOp .cop: debug_dmem($write(" CacheOp ", fshow(cop)));
        endcase
        debug_dmem($write("\n"));
      end
    return memresp;
  endmethod
endmodule

//
// DMem Wrapper around the DCache which implements the various MIPS
// access modes which vary in width, sign, handedness etc...
//
module mkDMem#(DCache cache)(DMem);
  MemoryCompute                             mc <- mkMemoryCompute();
  let q <- mkSizedFIFO(3);

  method ActionValue#(Exception)           req(ThreadID thread, ThreadState ts, MemOperation op, Address a, Value v);
    match {.respdata, .calcEx, .request} <- mc.calcMEMReq(op, a, v); // rmn30 not really Action
    let ex <- (calcEx == Ex_None) ? cache.req(thread,
                                              ts,
                                              request) : toAV(calcEx);
    if (ex == Ex_None)
      q.enq(tuple2(respdata, v));
    return ex;
  endmethod

  method ActionValue#(Exception) commit(Bool c) = cache.commit(c);

  method ActionValue#(Value) resp();
    match {.respdata, .old} <- popFIFO(q);
    let memresp <- cache.resp();
    let rv <- mc.handleMEMResp(old, memresp, respdata);
    return rv;
  endmethod
endmodule

//-----------------------------------------------------------------------------
// IMem Interface
//-----------------------------------------------------------------------------

//
// Virtually Indexed, Physically Tagged Direct Mapped L1 Instruction cache.
//

typedef struct {
   Bool     valid;
   Bit#(24)   tag;
} ICache_tag deriving(Bounded, Bits, Eq, FShow);

module mkIMem#(Memory imemPort, TLB tlb)(IMem);
  /* For IMEM */
   //let imem_reqQ                   <- mkPipeFIFO;
  let imem_missQ                  <- mkFIFO;
  `ifndef VERIFY
  let imem_wasMiss                <- mkBypassFIFO;
  let imem_hitBP                  <- mkBypassFIFO;
  let imem_missBP                 <- mkBypassFIFO;
  `else
  let imem_wasMiss                <- mkSizedFIFO(1);
  let imem_hitBP                  <- mkSizedFIFO(1);
  let imem_missBP                 <- mkSizedFIFO(1);
  `endif

  function initialTag(idx)        =  ICache_tag{valid:False, tag:?};
  Vector#(IWays, InitialisedBram#(Bit#(7),ICache_tag)) initBrams <- replicateM(mkInitialisedBram(initialTag));
  function bramFromInitBram(ib)   =  ib.bram;
  let                   tag_brams =  map(bramFromInitBram, initBrams);
  Vector#(IWays, Bram#(Bit#(7), Bit#(256))) data_brams <- replicateM(mkBram);

  Reg#(IWayIdx) nextVictim <- mkReg(0);

  rule getResp;
    let tlbResp   <- tlb.lookups[0].resp();
    function readResp(x) = x.readResp;
	let cacheTags <- mapM(readResp, tag_brams);
	let cacheDatas <- mapM(readResp, data_brams);

    let pa        = tlbResp.addr;
    let tlbEx     = tlbResp.exception;
    let isCached  = tlbResp.cache == CA_CACHED;
    function Bool cacheHit(ICache_tag t);
      return t.valid && t.tag == pa[35:12];
    endfunction
    let cacheHits = map(cacheHit, cacheTags);
    let mHitIdx   = findIndex(id, cacheHits);
    let hit       = isValid(mHitIdx);
    let isEx      = tlbEx != Ex_None;
    let doReq     = (!isCached || !hit) && !isEx;
    let cacheData = mHitIdx matches tagged Valid .idx ? cacheDatas[idx] : ?;
    if (doReq)
      begin
        CheriMemRequest mreq = defaultValue;
        mreq.addr = unpack(truncate(pack(pa) & ~'h1f));
        mreq.masterID = ?;
        mreq.transactionID = ?;
        mreq.operation = tagged Read {
            uncached: ! isCached,
            linked: False,
            noOfFlits: 0,
            bytesPerFlit: BYTE_32
        };
        function Bool notValid (ICache_tag ct);
          return !ct.valid;
        endfunction
        let mFirstInvalid = findIndex(notValid, cacheTags);
        let  way = mFirstInvalid matches tagged Valid .idx ? pack(idx) : nextVictim;
        imemPort.req(mreq);
        imem_missQ.enq(tuple3(isCached, way, pa));
      end
    else
      begin
        imem_hitBP.enq(tuple2(tlbEx, cacheData));
      end
    nextVictim <= nextVictim + 1;
    debug2("imem", $display("IMEM: getResp pa=0x%x hits=%b %s", pa, pack(cacheHits), doReq ? "miss" : "hit/ex"));
    // 32-bit word within the cache line. Inverted because of
    // big-endian madness.
    let word = ~pa[4:2];
    imem_wasMiss.enq(tuple2(doReq, word));
  endrule

  rule fillMiss;
    CheriMemResponse rsp  <- imemPort.resp();
    if (rsp.operation matches tagged Read .r) begin
        match {.cached, .way, .pa} <- popFIFO(imem_missQ);
        if (cached)
          begin
            let tags = tag_brams[way];
            let data = data_brams[way];
            tags.write(pa[11:5], ICache_tag{valid:True, tag:pa[35:12]});
            data.write(pa[11:5], r.data.data);
          end
        imem_missBP.enq(tuple2(Ex_None, r.data.data));
        debug2("imem", $display("IMEM: fillMiss way=%d pa=0x%x resp=0x%x", way, pa, r.data.data));
    end else dynamicAssert(False, "Only read responses are expected");
  endrule

  method ActionValue#(Exception) req(ThreadID thread, ThreadState ts, Address a);
    let watchEx         = watchHit(ts, True, False, a) ? Ex_Watch : Ex_None;
    let addrEx          = (a[1:0] != 0) ? Ex_AddrErrInst : Ex_None;
    let ex              = convertToInstructionException(joinException(addrEx, watchEx));
    if (ex == Ex_None)
      begin
        tlb.lookups[0].req(TLBRequest {thread: thread,
                                       ts: ts,
                                       write: False,
                                       addr: a});
        let idx = a[11:5];
        function tbReadReq(tb) = tb.readReq(idx);
        function dbReadReq(db) = db.readReq(idx);
        let x1 <- mapM(tbReadReq, tag_brams);
        let x2 <- mapM(dbReadReq, data_brams);
      end
    debug2("imem", $display("IMEM Req thread=%d pc=0x%x -> ", {1'b0,thread}, a, fshow(ex)));
    return ex;
  endmethod

  method ActionValue#(Tuple2#(Exception, Bit#(32))) resp();
    match {.wasMiss, .word} <- popFIFO(imem_wasMiss);
    match {.e, .val}       <- (wasMiss) ? popFIFO(imem_missBP) : popFIFO(imem_hitBP);
    Vector#(8, Bit#(32)) words = unpack(pack(val));
    let inst = words[word];
    debug2("imem", $display("IMEM Resp inst=0x%x ex=", inst, fshow(e)));
    return tuple2(convertToInstructionException(e), inst);
  endmethod

  interface MemInvalidate invalidate;
     method Action invalidate(Address x);
       function Action invalidateWay(Bram#(Bit#(7),ICache_tag) tb);
	  return tb.write(x[11:5], ICache_tag{valid:False, tag:?});
       endfunction
       mapM_(invalidateWay, tag_brams);
    endmethod
  endinterface
endmodule
/*
module mkMemoryPortReplicator#(Memory mem)(Vector#(n, Memory)) provisos(Log#(n,ln));
  Vector#(n, FIFO#(CheriMemRequest))    reqQs  <- replicateM(mkFIFO);
  Vector#(n, FIFO#(CheriMemResponse))   respQs <- replicateM(mkFIFO);
  FIFO#(Bit#(ln)) portQ <- mkSizedFIFO(2); //rmn30 XXX how big?

  module mkMemIFC#(Integer i)(Memory);
    let ii = fromInteger(i);

    rule doReq;
      let r <- popFIFO(reqQs[i]);
      mem.req(r);
      portQ.enq(ii);
    endrule

    rule getResp if (portQ.first() == ii);
      let r <- mem.resp();
      respQs[i].enq(r);
      portQ.deq;
    endrule

    method Action req(x);
      //debug($display("MEMPORT %d: Request (%h, 0x%h, 0x%h)", ii, x.op, x.addr, x.val));
      reqQs[i].enq(x);
    endmethod

    method ActionValue#(CheriMemResponse) resp;
      //debug($display("MEMPORT %d: Response", ii));
      let r <- popFIFO(respQs[i]);
      return r;
    endmethod
  endmodule

  let ms <- genWithM(mkMemIFC);
  return ms;
endmodule
*/

module mkMemoryPortReplicator#(Memory mem)(Vector#(n, Memory))
   provisos(Log#(n,ln));
   FIFO#(Bit#(ln)) portQ <- mkSizedFIFO(valueof(n)); //rmn30 XXX how big?
   Vector#(n, FIFO#(CheriMemRequest))    reqQs  <- replicateM(mkBypassFIFO);

   module mkMemIFC#(Integer i)(Memory);
      let ii = fromInteger(i);

      rule doReq;
	 let r <- popFIFO(reqQs[i]);
	 mem.req(r);
	 portQ.enq(ii);
      endrule

      method Action req(x);
	 reqQs[i].enq(x);
      endmethod

      method ActionValue#(CheriMemResponse) resp() if (portQ.first() == ii);
	 let r <- mem.resp();
	 portQ.deq;
	 return r;
      endmethod
   endmodule

   let ms <- genWithM(mkMemIFC);
   return ms;
endmodule

//-----------------------------------------------------------------------------
// Backing Memory
//
// Server which converts from cheri2's MemReq/MemResp to the 256-bit
// MemoryRequest/MemoryResponse structs used by the L2 and TagCache.
//
//-----------------------------------------------------------------------------

interface MemoryServer;
  interface Memory mem;
  interface Master#(CheriMemRequest,CheriMemResponse) master;
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkMemServer(MemoryServer);
  `ifdef NOL2
  let lsQ <- mkFIFO();
  `endif
  `ifndef VERIFY
  let reqQ <- mkFIFOF();
  let respQ <- mkFIFOF();
  `else
  let reqQ <- mkSizedFIFOF(1);
  let respQ <- mkSizedFIFOF(1);
  `endif
  Reg#(CheriTransactionID) nextTransactionID <- mkRegU;

  interface Memory mem;
    method Action req(CheriMemRequest request);
      CheriMemRequest ereq = request;
      ereq.transactionID = nextTransactionID;
      nextTransactionID <= nextTransactionID + 1;
      // internal memories on little endian, so we reverse order
      // (but note that 64-bit words within the line must be stored
      // in reverse order so that this does the right thing)
      if(request.operation matches tagged Write .wop) begin
        ereq.operation = tagged Write {
          uncached: wop.uncached,
          conditional: False, /// XXX L2 is broken so don't attempt sc (handled by L1)
          byteEnable: unpack(reverseBits(pack(wop.byteEnable))),
          data : Data {
            `ifdef CAP
            cap: wop.data.cap,
            `endif
            data: unpack(reverseBytes(pack(wop.data.data)))
          },
          last: wop.last
        };
      end
      debug2("memserv", $display("MEMSERV: ", fshow(ereq)));

      `ifdef NOL2
      // The tag cache cannot handle cache requests.
      let cacheop = request.operation matches tagged CacheOp .* ? True : False;
      lsQ.enq(cacheop);
      if (!cacheop)
        begin
          reqQ.enq(ereq);
        end
      `else
      reqQ.enq(ereq);
      `endif
    endmethod

    method ActionValue#(CheriMemResponse) resp();
      CheriMemResponse response = ?;
      // The tag cache cannot handle cache requests.
`ifdef NOL2
      let cacheop <- popFIFO(lsQ);
      if (!cacheop)
        response <- popFIFOF(respQ);
`else
      response <- popFIFOF(respQ);
`endif
      debug2("memserv", $display("MEMSERV: ", fshow(response)));
      case (response.operation) matches 
        tagged Read .rop:
          begin
            // reverse byte order as per above
            response.operation = tagged Read {
              data: Data {
                `ifdef CAP
                cap: rop.data.cap,
                `endif
                data: reverseBytes(rop.data.data)
              },
              last: rop.last
            };
          end
        tagged SC .scSuccess:
          dynamicAssert(False, "XXX SC response not handled yet");
        default:
        begin
          // In cheri2 writes and cache operations need a response.
          // Only the data part is used -- it indicates conditional store
          // success/failure (currently always success).
          response.operation = tagged Read {
             data: Data {
                `ifdef CAP
                cap: ?,
                `endif
                data: pack(Vector::replicate(64'b1)) // for SC success
            },
             last: True
          };
        end
      endcase
      return response;
    endmethod
  endinterface
  interface Master master;
    interface request  = toCheckedGet(reqQ);
    interface response = toCheckedPut(respQ);
  endinterface
endmodule

//-----------------------------------------------------------------------------
// Memory Hierarchy
//-----------------------------------------------------------------------------

interface MemoryHierarchy;
  interface Master#(CheriMemRequest,CheriMemResponse) extMemory;

  interface IMem            imem;
  interface DMem            dmem;
  interface CP0RegisterFile  cp0;

  method Bool       isFlushed(); // no in-flight ops / dirty cache entries
  method Bool     isCommitted(); //dirty cache entries

  interface DCache        capMem;
  interface Display#(void) debug;
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkMemoryHierarchy(MemoryHierarchy);
  MemoryServer                theMem <- mkMemServer();
  Vector#(2, Memory)         memifcs <- mkMemoryPortReplicator(theMem.mem);
  let                       imemPort =  memifcs[0];
  let                       dmemPort =  memifcs[1];
  CP0                       cp0_base <- mkCP0();
  IMem                       theImem <- mkIMem(imemPort, cp0_base.tlb);
  DCache                   theDCache <- mkDCache(dmemPort, cp0_base.tlb, theImem.invalidate);
  DMem                       theDmem <- mkDMem(theDCache);
`ifdef VERIFY2
  RegFile#(Bit#(35), Bool)                  captagMem <- mkRegFileFull();
  Vector#(32, RegFile#(Bit#(35), Bit#(8)))   basemems <- replicateM(mkRegFileFull());
  let topMem = theMem.master;

`else
  let topMem = theMem.master;
`ifndef NOL2
  L2CacheIfc                 l2Cache <- mkL2Cache();
  mkConnection(theMem.master, l2Cache.cache);
  topMem = l2Cache.memory;
`endif
`ifdef CAP
  let                       tagCache <- mkTagCache();
  mkConnection(topMem, tagCache.cache);
  topMem = tagCache.memory;
`endif
`endif

`ifdef VERIFY2
   //XXX ndave: This is only an approximation of the memory's behavior
   // rule verifyMemoryOperation;
   //   MemoryRequest#(35, 32) req <- theMem.client.request.get();
   //   let a = req.addr;
	 // case (req.op)
	 //   Read, Cache:
   //       begin
   //         function readRF(rf) = rf.sub(a);
	 //       let vals = map(readRF, basemems);
   //         `ifdef CAP
   //           let resp = MemoryResponse{data: pack(vals), capability: captagMem.sub(a) };
   //         `else
   //           let resp = MemoryResponse{data: pack(vals)};
   //         `endif
   //         theMem.client.response.put(resp);
	 // 	 end
	 //   Write:
   //        begin
   // 		   Vector#(32, Bit#(8))  bytes   = unpack(req.data);
	 // 	   Vector#(32, Bool)     enables = unpack(req.byteenable);
 	 // 	   for(Integer i = 0; i < 32; i = i + 1)
	 // 		 begin
	 // 		   if (enables[i]) basemems[i].upd(a,bytes[i]);
   //           end
   //         captagMem.upd(a, req.capability);
	 // 	 end
   //   endcase
   // endrule
`endif

  let                         extMem = topMem;

  interface IMem   imem = theImem;//cp0_base.imem;
  interface DMem   dmem = theDmem;//cp0_base.dmem;

  method isCommitted = True;
  method isFlushed   = True; //XXX

  interface cp0        = cp0_base.regs;
  interface extMemory  = extMem;
  interface capMem     = theDCache;

  interface Display debug;
    method Action debug_display(void x);
      $display("Mem Hierarchy:");
    endmethod
  endinterface
endmodule
