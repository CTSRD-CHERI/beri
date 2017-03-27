/*-
 * Copyright (c) 2013, 2014 Jonathan Woodruff
 * Copyright (c) 2013 Alex Horsman
 * Copyright (c) 2013, 2014, 2015 Alexandre Joannou
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

import Vector :: *;
import Debug::*;
import MemTypes::*;
import DefaultValue::*;
import ConfigReg::*;
import DReg::*;
import MIPS::*;
import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import FF::*;
import GetPut::*;
import MasterSlave::*;
import MEM::*;
import Bag::*;
//`ifndef MULTI
  import CacheCore::*;
//`else
//  import CacheCore::*;
//`endif
import BeriUGBypassFIFOF::*;
`ifdef NOCACHE
  import PISM::*;
`endif
`ifdef CAP
  `define USECAP 1
`elsif CAP128
  `define USECAP 1
`elsif CAP64
  `define USECAP 1
`endif
`ifdef STATCOUNTERS
import StatCounters::*;
`endif

`ifdef WRITEBACK_DCACHE
  // Number of modified lines allowed in the DCache.
  typedef 4 MNum;
  typedef Bit#(TSub#(38,TLog#(CheriBusBytes))) LineNum;
`endif

`ifdef TIMEBASED
  `define TIMEVALID 262144 // Maximum number of cycles a cache line is valid, average is 1/2 this number.
`endif

/* =================================================================
 DCache
 =================================================================*/

typedef enum {Serving, FlushModified, SyncInvalidatesA, WaitForWritebacks, SyncWrites, SyncInvalidatesB, WaitForCoreSync} CacheState deriving (Bits, Eq);

`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkDCache#(Bit#(16) cacheId)(CacheDataIfc);
  FIFOF#(CacheResponseDataT)         preRsp_fifo <- mkLFIFOF;
  Reg#(CacheRequestDataT)              reqInWire <- mkWire;
  FF#(CheriMemRequest,1)                 coreReq <- mkFFBypass1;
  `ifndef WRITEBACK_DCACHE
    FF#(CheriMemRequest, 2)              memReqs <- mkUGFFDebug("memReqs");
  `else
    // Multicore directory protocol requires a larger buffer
    FF#(CheriMemRequest, 16)              memReqs <- mkUGFFDebug("memReqs");
    Bag#(MNum, LineNum, Bit#(0))     modLinesBag <- mkSmallBag;
    FF#(LineNum, TAdd#(MNum,1))       modLinesFF <- mkUGFFDebug("modLines");
    FF#(LineNum, 2)                   writebacks <- mkUGFFDebug("writebacks");
    Reg#(Bit#(16))                    evictCount <- mkReg(0);
    Reg#(Bit#(8))                      syncCount <- mkRegU;
  `endif
  // TIME-BASED COHERENCE, counters  
  `ifdef TIMEBASED
    Reg#(Bit#(32))              instructionCounter <- mkReg(0); // Determines frequency of time-counter increments
  `endif
  FIFOF#(CheriMemResponse)               memRsps <- mkUGFIFOF();
  WriteMissBehaviour wmb = WriteThrough;
  `ifdef WRITEBACK_DCACHE
    wmb = WriteAllocate;
  `endif
  CacheCore#(4, TSub#(Indices,1), 1)        core <- mkCacheCore(cacheId, wmb, RespondAll, InOrder, DCache, 
                                                                zeroExtend(memReqs.remaining()), ff2fifof(memReqs), memRsps);

  Reg#(CheriTransactionID)        transactionNum <- mkReg(0);
  Reg#(CacheState)                         state <- mkReg(Serving);
  
  FF#(Bit#(0), 32)                        writes <- mkUGFFDebug("writes");
  Reg#(Bit#(6))                            invIn <- mkConfigReg(0);
  Reg#(Bit#(6))                          invDone <- mkConfigReg(0);
  Reg#(Bit#(6))                        invEnough <- mkConfigReg(0);
  
  CheriMemRequest next_mem_req = defaultValue;
  next_mem_req.masterID = unpack(truncate(cacheId));
  next_mem_req.transactionID = transactionNum;

  `ifdef WRITEBACK_DCACHE
    rule writeBackModified(state==FlushModified);
      if (writebacks.notEmpty) begin
        CheriPhyAddr addr = unpack({writebacks.first,0});
        core.invalidate(addr);
        writebacks.deq;
        invIn <= invIn + 1;
        debug2("dcache", $display("<time %0t, cache %0d, DCache>  put internal Invalidate in flush state! invIn:%d, invEnough:%d, invDone:%d, invIn-invDone:%d, invEnough-invDone:%d addr:%x", 
                      $time, cacheId, invIn+1, invEnough, invDone, (invIn+1)-invDone, invEnough-invDone, addr));
      end else if (modLinesFF.notEmpty) begin
        CheriPhyAddr addr = unpack({modLinesFF.first,0});
        core.invalidate(addr);
        modLinesBag.remove(modLinesFF.first);
        modLinesFF.deq;
        invIn <= invIn + 1;
        debug2("dcache", $display("<time %0t, cache %0d, DCache>  put internal Invalidate in flush state! invIn:%d, invEnough:%d, invDone:%d, invIn-invDone:%d, invEnough-invDone:%d addr:%x", 
                      $time, cacheId, invIn+1, invEnough, invDone, (invIn+1)-invDone, invEnough-invDone, addr));
      end else begin
        debug2("dcache", $display("<time %0t, cache %0d, DCache> flush modified done ", $time, cacheId));
        state <= SyncInvalidatesA;
        syncCount <= 0;
      end
    endrule
    
    rule syncInvalidatesA(state==SyncInvalidatesA);
      // If they are equal or invDone is greater than invEnough (or the difference is more than half of the range, which is not possible in the positive direction).
      //if (invEnough==invDone || msb(invEnough-invDone)==1'b1) begin
      if (invIn==invDone) begin // Guaranteed to happen?
        debug2("dcache", $display("<time %0t, cache %0d, DCache> sync invalidatesA released ", $time, cacheId));
        state <= WaitForWritebacks;
        syncCount <= 0;
      end else debug2("dcache", $display("<time %0t, cache %0d, DCache> waiting for sync invalidatesA, invIn: %d, invDone: %d", $time, cacheId, invIn, invDone));
    endrule
    
    // After an invalidate response, we 4 cycles for the flushed line to actually fetch and 
    // write back all of its frames.
    rule waitForWritebacks(state==WaitForWritebacks);
      syncCount <= syncCount + 1;
      // Wait 6 just to be sure.
      if (syncCount>6) state <= SyncWrites;
    endrule
    
    rule syncWrites(state==SyncWrites);
      if (!memReqs.notEmpty && !writes.notEmpty /*&& syncCount > 0*/) begin // Skip invalidate check for the moment to avoid lockup.
        debug2("dcache", $display("<time %0t, cache %0d, DCache> sync writes released ", $time, cacheId));
        state <= SyncInvalidatesB;
        invEnough <= invIn; // Freeze the required invalidates at this level.
      end else debug2("dcache", $display("<time %0t, cache %0d, DCache> waiting for sync writes", $time, cacheId));
      syncCount <= syncCount + 1;
    endrule
    
    rule syncInvalidatesB(state==SyncInvalidatesB);
      // If they are equal or invDone is greater than invEnough (or the difference is more than half of the range, which is not possible in the positive direction).
      if (invIn==invDone) begin
        debug2("dcache", $display("<time %0t, cache %0d, DCache> sync invalidatesB released ", $time, cacheId));
        // Start actual SYNC operation  
        CheriMemRequest mem_req = next_mem_req;
        mem_req.operation = tagged CacheOp CacheOperation{
                                      inst: CacheSync,
                                      cache: DCache,
                                      indexed: False
                                    };
        coreReq.enq(mem_req);
        //core.put(mem_req);
        transactionNum <= transactionNum + 1;
        state <= WaitForCoreSync;
      end else debug2("dcache", $display("<time %0t, cache %0d, DCache> waiting for sync invalidatesB, invEnough: %d, invDone: %d", $time, cacheId, invEnough, invDone));
    endrule
    
    // After an invalidate response, we 4 cycles for the flushed line to actually fetch and 
    // write back all of its frames.
    rule waitForCoreSync(state==WaitForCoreSync);
      syncCount <= syncCount + 1;
      // Wait 6 just to be sure.
      if (syncCount>6) state <= Serving;
    endrule
  
    rule insertInvalidate(writebacks.notEmpty && state!=FlushModified);
      CheriPhyAddr addr = unpack({writebacks.first,0});
      core.invalidate(addr);
      writebacks.deq;
      invIn <= invIn + 1;
      debug2("dcache", $display("<time %0t, cache %0d, DCache>  put internal Invalidate! invIn:%d, invEnough:%d, invDone:%d, invIn-invDone:%d, invEnough-invDone:%d addr:%x", 
                    $time, cacheId, invIn+1, invEnough, invDone, (invIn+1)-invDone, invEnough-invDone, addr));
    endrule
    
    `ifdef CHERIOS
      rule alwaysGetInvDone;
        invDone <= invDone + 1;
        debug2("dcache", $display("<time %0t, cache %0d, DCache>  finished Invalidate. invIn:%d, invEnough:%d, invDone:%d, invIn-invDone:%d, invEnough-invDone:%d", 
                        $time, cacheId, invIn, invEnough, (invDone+1), invIn-(invDone+1), invEnough-(invDone+1)));
        Bool ret <- core.invalidateDone();
      endrule
    `endif
  `endif
  
  // The getInvalidateDoneRule is only used in some configurations.
  // Just using this bool which is statically set or unset to avoid writing the rule twice.
  Bool doGetInvalidateDoneRule = False;
  `ifdef WRITEBACK_DCACHE
    doGetInvalidateDoneRule = True;
    `ifdef MULTI
      `ifndef TIMEBASED
        doGetInvalidateDoneRule = False;
      `endif
    `endif
  `endif
  rule getInvalidateDoneRule(doGetInvalidateDoneRule);
    invDone <= invDone + 1;
    debug2("dcache", $display("<time %0t, cache %0d, DCache>  finished Invalidate in rule. invIn:%d, invEnough:%d, invDone:%d, invIn-invDone:%d, invEnough-invDone:%d", 
            $time, cacheId, invIn, invEnough, (invDone+1), invIn-(invDone+1), invEnough-(invDone+1)));
    Bool ret <- core.invalidateDone();
  endrule
  
  function CheriMemRequest firstMemReq;
    CheriMemRequest memReq = memReqs.first;
    return memReq;
  endfunction
  
  Bool putReady = (state==Serving && preRsp_fifo.notFull() && coreReq.notFull());
  `ifdef WRITEBACK_DCACHE
    putReady = putReady && writebacks.notFull;
  `endif
  
  rule feedCore(core.canPut);
    CheriMemRequest mem_req <- toGet(ff2fifof(coreReq)).get();
    debug2("dcache", $display("<time %0t, cache %0d, DCache> feeding core ", $time, cacheId, fshow(mem_req)));
    core.put(mem_req);
  endrule
  
  rule doPut(putReady);
    CacheRequestDataT reqIn = reqInWire;
    debug2("dcache", $display("<time %0t, cache %0d, DCache> putting DCache request ", $time, cacheId, fshow(reqIn)));
    Bool cached = reqIn.tr.cached;
    CheriPhyAddr addr = unpack(reqIn.tr.addr);
    CheriMemRequest mem_req = next_mem_req;
    mem_req.addr = addr;
    //if (cached) mem_req.addr.byteOffset = 0;
    CacheOperation cop = reqIn.cop;
    // willPutToCore indicates that we will put an operation in a later state.
    Bool willPutToCore = False;
    Bool expectCoreResponse = False;
    `ifdef TIMEBASED
      Bit#(32) newInstructionCounter = instructionCounter + 1;
    `endif
    
    CacheResponseDataT resp = CacheResponseDataT {
      `ifdef USECAP
        isCap: !reqIn.tr.noCapLoad,
      `endif
      data: {?,pack(addr)},
      exception: reqIn.tr.exception,
      scResult: False
    };
    
    case (cop.inst)
      CacheNop: begin
        `ifdef WRITEBACK_DCACHE
          evictCount <= evictCount + 1;
          if (writebacks.notEmpty) begin
            mem_req.addr = unpack({writebacks.first,0});
            writebacks.deq;
            mem_req.operation = tagged CacheOp CacheOperation{
                                                  inst: CacheWriteback,
                                                  cache: DCache,
                                                  indexed: False
                                                };
            debug2("dcache", $display("<time %0t, cache %0d, DCache> Too few empty records in modLines, evicted %x", $time, cacheId, mem_req.addr));
          end else if (evictCount==0 && modLinesFF.notEmpty) begin
            modLinesBag.remove(modLinesFF.first);
            modLinesFF.deq();
            mem_req.addr = unpack({modLinesFF.first,0});
            mem_req.operation = tagged CacheOp CacheOperation{
                                                  inst: CacheWriteback,
                                                  cache: DCache,
                                                  indexed: False
                                                };
            debug2("dcache", $display("<time %0t, cache %0d, DCache> Occasional evict, evicted %x", $time, cacheId, mem_req.addr));
          end
        `endif
        `ifdef TIMEBASED
          if (instructionCounter > `TIMEVALID) begin
            `ifdef WRITEBACK_DCACHE
              // If this is a writeback cache, we need to flush out all modified lines before dropping the contents of the cache.
              state <= FlushModified;
              willPutToCore = True;
            `else
              mem_req.operation = tagged CacheOp CacheOperation{
                                                    inst: CacheSync,
                                                    cache: DCache,
                                                    indexed: False
                                                  };
            `endif
            newInstructionCounter = 0;
          end
        `endif
        resp.exception = None;
      end
      `ifdef USECAP
        `ifdef CAPPFTCH
          CachePrefetch: begin
            if (resp.exception == None)
              mem_req.operation = tagged CacheOp cop;
            resp.exception = None;
          end
        `endif
      `endif
      Read: begin
        if (resp.exception == None) begin
          mem_req.operation = tagged Read {
                            uncached: !cached,
                            linked: reqIn.tr.ll,  // XXX must fix load linked for Multi case
                            noOfFlits: 0,
                            bytesPerFlit: (cached) ? cheriBusBytes : memSizeTobpf(reqIn.memSize)
                          };
          expectCoreResponse = True;
        end
      end
      Write, StoreConditional: begin
        `ifdef USECAP
          if (resp.exception == None && reqIn.tr.noCapStore && reqIn.capability) 
            resp.exception = CTLBS;
          Bit#(TLog#(TDiv#(CheriDataWidth,CapWidth))) capSelect = truncateLSB(addr.byteOffset);
          Vector#(TDiv#(CheriDataWidth,CapWidth),Bool)  caps = replicate(False);
          caps[capSelect] = reqIn.capability;
          debug2("dcache", $display("<time %0t, cache %0d, DCache> capSelect: %x ", $time, cacheId, capSelect, fshow(caps)));
        `endif
        if (resp.exception == None || cop.inst==StoreConditional) begin
          mem_req.operation = tagged Write {
                            uncached: !cached,
                            conditional: cop.inst==StoreConditional,
                            byteEnable: unpack(reqIn.byteEnable),
                            bitEnable: -1,
                            data: Data{
                              `ifdef USECAP
                                cap: caps,
                              `endif
                              data: reqIn.data
                            },
                            last: True
                          };
          `ifdef MULTI
            if (cop.inst == StoreConditional) begin
              debug2("dcache", $display("<time %0t, cache %0d, DCache> store conditional request ", $time, cacheId));
              expectCoreResponse = True;
            end
          `endif
          `ifdef WRITEBACK_DCACHE  
            if (!isValid(modLinesBag.isMember(truncateLSB(addr.lineNumber))) && cached) begin
              if (modLinesFF.remaining <= 1) begin // Need to "clean" modified entry.
                // Remove an old one.
                modLinesBag.remove(modLinesFF.first);
                writebacks.enq(modLinesFF.first);
                modLinesFF.deq();
                CheriPhyAddr adr = unpack({modLinesFF.first,0});
                debug2("dcache", $display("<time %0t, cache %0d, DCache> put writeback request: %x ", $time, cacheId, adr));
              end
              
              // Insert the new one.
              modLinesBag.insert(truncateLSB(addr.lineNumber),?);
              modLinesFF.enq(truncateLSB(addr.lineNumber));
              debug2("dcache", $display("<time %0t, cache %0d, DCache> inserted addr %x into modLinesBag", $time, cacheId, addr));
              
            end
          `endif
        end
      end
      CacheSync: begin
        debug2("dcache", $display("<time %0t, cache %0d, DCache> performed Cache Sync ", $time, cacheId));
        `ifdef WRITEBACK_DCACHE
          state <= FlushModified;
          willPutToCore = True;
        `endif
        `ifdef TIMEBASED
          newInstructionCounter = 0;
        `endif
        mem_req.operation = tagged CacheOp cop;
        resp.exception = None;
      end
      default: begin
        mem_req.operation = tagged CacheOp cop;
        resp.exception = None;
      end
    endcase
    
    `ifdef TIMEBASED
      instructionCounter <= newInstructionCounter;
    `endif
    
    debug2("dcache", $display("<time %0t, cache %0d, DCache> put to core ", $time, cacheId, fshow(mem_req)));
    //core.put(mem_req);
    `ifdef WRITEBACK_DCACHE
      if (!willPutToCore) 
    `endif
    coreReq.enq(mem_req);
    // Ensure that the core never sees the same transaction ID twice.
    transactionNum <= transactionNum + 1;
    preRsp_fifo.enq(resp);
  endrule
  
  method Action put(CacheRequestDataT reqIn) if (putReady);
    reqInWire <= reqIn;
  endmethod
  
  method ActionValue#(CacheResponseDataT) getResponse() if (core.response.canGet());
    CacheResponseDataT resp <- toGet(preRsp_fifo).get;
    `ifdef USECAP
      CheriPhyByteOffset addr = truncate(resp.data);
      Bit#(TLog#(CapsPerFlit)) select = truncateLSB(addr);
    `endif
    //Bool fromCore <- toGet(expectResponseFromCore).get;
    CheriMemResponse mr <- core.response.get;
    resp.data = mr.data.data;
    `ifdef USECAP
      // And the TLB capability flag with what was returned.
      resp.isCap = resp.isCap && mr.data.cap[0];
    `endif
    case (mr.operation) matches
      tagged SC .scr: begin
        resp.scResult = scr;
        debug2("dcache", $display("<time %0t, cache %0d, DCache> store conditional response ", $time, cacheId, fshow(resp)));
      end
    endcase
    debug2("dcache", $display("<time %0t, cache %0d, DCache> returning DCache response ", $time, cacheId, fshow(resp)));
    return resp;
  endmethod

  
  method Action invalidate(PhyAddress addr) if (state!=FlushModified);
    `ifdef MULTI
      `ifndef TIMEBASED
        core.invalidate(unpack(addr));
      `endif
    `endif
    invIn <= invIn + 1;
    debug2("dcache", $display("<time %0t, cache %0d, DCache>  put Invalidate! invIn:%d, invEnough:%d, invDone:%d, invIn-invDone:%d, invEnough-invDone:%d addr:%x", 
                  $time, cacheId, invIn+1, invEnough, invDone, (invIn+1)-invDone, invEnough-invDone, addr));
  endmethod
  method ActionValue#(Bool) getInvalidateDone if (!doGetInvalidateDoneRule);
    invDone <= invDone + 1;
    debug2("dcache", $display("<time %0t, cache %0d, DCache>  finished Invalidate. invIn:%d, invEnough:%d, invDone:%d, invIn-invDone:%d, invEnough-invDone:%d", 
                    $time, cacheId, invIn, invEnough, (invDone+1), invIn-(invDone+1), invEnough-(invDone+1)));
    Bool ret <- core.invalidateDone();
    return ret;
  endmethod

  method L1ChCfg getConfig();
    /*L1ChCfg{
      a:0,  //  Associativity = A+1.  (A=0 for direct mapped)
      l:6,  //  Cache line size = 2*2^L.  L=0 if there is no cache. (32)
      s:1   //  Number of Cache index positions is 64 * 2^S. Mult by Associativity for total number of cache lines. (128)
    };*/
    `ifdef MEM128
      L1ChCfg ret = L1ChCfg{ a:3, l:5, s:indicesMinus6-1};
    `elsif MEM64
      L1ChCfg ret = L1ChCfg{ a:3, l:4, s:indicesMinus6-1};
    `else
      L1ChCfg ret = L1ChCfg{ a:3, l:6, s:indicesMinus6-1};
    `endif
    return ret;
  endmethod
  
  method Action nextWillCommit(Bool nextCommitting);
    core.nextWillCommit(nextCommitting);
    debug2("dcache", $display("<time %0t, cache %0d, DCache> Put commit %x ", $time, cacheId, nextCommitting));
  endmethod
  
  interface Master memory;
    interface CheckedGet request;
      method canGet = memReqs.notEmpty;
      method CheriMemRequest peek if (memReqs.notEmpty);
        return firstMemReq;
      endmethod
      method ActionValue#(CheriMemRequest) get if (memReqs.notEmpty);
        debug2("dcache", $display("<time %0t, cache %0d, DCache> delivered memory request ", $time, cacheId, fshow(firstMemReq)));
        if (expectWriteResponse(firstMemReq)) writes.enq(?);
        memReqs.deq;
        return firstMemReq;
      endmethod
    endinterface

    interface CheckedPut response;
      method canPut = memRsps.notFull;
      method Action put(CheriMemResponse d) if (memRsps.notFull);
        debug2("dcache", $display("<time %0t, cache %0d, DCache> received memory response ", $time, cacheId, fshow(d)));
        if (d.operation matches tagged Write) writes.deq;
        memRsps.enq(d);
      endmethod
    endinterface
  endinterface
  `ifdef STATCOUNTERS
  interface Get cacheEvents;
    method ActionValue#(ModuleEvents) get () = core.cacheEvents.get();
  endinterface
  `endif
endmodule
