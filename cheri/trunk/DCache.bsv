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

import Debug::*;
import MemTypes::*;
import DefaultValue::*;
import MIPS::*;
import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import FF::*;
import GetPut::*;
import MasterSlave::*;
import MEM::*;
import CacheCore::*;
import BeriUGBypassFIFOF::*;
`ifdef NOCACHE
  import PISM::*;
`endif
`ifdef CAP
  `define USECAP 1
`elsif CAP128
  `define USECAP 1
`endif

/* =================================================================
 DCache
 =================================================================*/

typedef enum {Init, Serving, Fill
  `ifdef MULTI
    , StoreConditional
  `endif
} CacheState deriving (Bits, Eq);

`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkDCache#(Bit#(16) coreId)(CacheDataIfc);
  FIFOF#(CacheResponseDataT)         preRsp_fifo <- mkSizedFIFOF(4);
  FIFO#(Bool)                       nextFromRead <- mkSizedFIFO(4);
  FIFO#(Bool)                       nextFromCore <- mkSizedFIFO(4);
  FIFOF#(CheriMemResponse)              rsp_fifo <- mkBeriUGBypassFIFOF;
  FF#(CheriMemRequest, 2)                memReqs <- mkUGFF();
  FIFOF#(CheriMemResponse)               memRsps <- mkUGFIFOF();
  // The DCache doesn't generate evictions, so the limits are not important.
  CacheCore#(1, 7)                          core <- mkCacheCore(coreId, WriteThrough, DCache, 
                                                                zeroExtend(memReqs.remaining()),
                                                                ff2fifof(memReqs), memRsps);
  FIFOF#(PhyAddress)              invalidateFifo <- mkUGFIFOF;
  Reg#(CheriTransactionID)        transactionNum <- mkReg(0);
  
  rule runCache;
    Maybe#(CheriMemResponse) memResp <- core.get(rsp_fifo.notFull);
    if (memResp matches tagged Valid .mr) begin
      Bool enqRspFifo = False;
      if (mr.operation matches tagged Read .rop) begin
        enqRspFifo = True;
      end
      `ifdef MULTI
        if (mr.operation matches tagged SC .scr) begin
          enqRspFifo = True;
          debug2("dcache", $display("<time %0t, cache %0d, DCache> got store conditional response! ", $time, coreId));
        end
      `endif
      if (enqRspFifo) begin
        debug2("dcache", $display("<time %0t, cache %0d, DCache> got response! ", $time, coreId, fshow(mr)));
        rsp_fifo.enq(mr);
      end
    end
  endrule

  method Action put(CacheRequestDataT reqIn);
    debug2("dcache", $display("<time %0t, cache %0d, DCache> putting DCache request ", $time, coreId, fshow(reqIn)));
    Bool cached = reqIn.tr.cached;
    CheriMemRequest mem_req = defaultValue;
    mem_req.addr = unpack(reqIn.tr.addr);
    if (cached) mem_req.addr.byteOffset = 0;
    mem_req.masterID = unpack(truncate(coreId));
    mem_req.transactionID = transactionNum;
    CacheOperation cop = reqIn.cop;
    Bool putToCore = True;
    // Indicate that we smuggled an invalidate in a NOP.
    Bool nopInvalidate = False;
    
    CacheResponseDataT resp = CacheResponseDataT {
      `ifdef USECAP
        capability: !reqIn.tr.noCapLoad,
      `endif
      data: ?,
      exception: reqIn.tr.exception
    };
    Bool readResponse=False;
    
    case (cop.inst)
      CacheNop: begin
        if (invalidateFifo.notEmpty) begin
          mem_req.addr = unpack(invalidateFifo.first);
          mem_req.operation = tagged CacheOp CacheOperation{
                                                inst: CacheInvalidate, 
                                                cache: DCache,
                                                indexed: False
                                             };
          debug2("dcache", $display("<time %0t, cache %0d, DCache> invalidating ", $time, coreId, fshow(mem_req)));
          invalidateFifo.deq();
          nopInvalidate = True;
        end else putToCore = False; // We didn't put a request to the core in this case!
        resp.exception = None;
      end
      Read: begin
        if (resp.exception == None) begin
          mem_req.operation = tagged Read {
                            uncached: !cached,
                            linked: reqIn.tr.ll,
                            noOfFlits: 0,
                            bytesPerFlit: (cached) ? cheriBusBytes : memSizeTobpf(reqIn.memSize)
                          };
          readResponse = True;
        end else putToCore = False;
      end
      Write, StoreConditional: begin
        `ifdef USECAP
          if (reqIn.tr.noCapStore && reqIn.capability) 
            resp.exception = CTLBS;
        `endif
        if (resp.exception == None) begin
          mem_req.operation = tagged Write {
                            uncached: !cached,
                            conditional: cop.inst==StoreConditional,
                            byteEnable: unpack(pack(reqIn.byteEnable)),
                            data: Data{
                              `ifdef USECAP
                                cap: unpack(pack(reqIn.capability)),
                              `endif
                              data: reqIn.data
                            },
                            last: True
                          };
          `ifdef MULTI
            if (cop.inst == StoreConditional) begin
              readResponse = True;
              debug2("dcache", $display("<time %0t, cache %0d, DCache> store conditional set readResponse ", $time, coreId));
            end
          `endif
        end else putToCore = False;
      end
      default: begin
        mem_req.operation = tagged CacheOp cop;
        if (cop.inst == CacheLoadTag) readResponse = True;
        resp.exception = None;
      end
    endcase
    
    if (putToCore) begin
      core.put(mem_req);
      // Ensure that the core never sees the same transaction ID twice.
      transactionNum <= transactionNum + 1;
    end
    resp.data = tagged Byte zeroExtend(pack(nopInvalidate));
    preRsp_fifo.enq(resp);
    nextFromRead.enq(readResponse);
    nextFromCore.enq(putToCore);
  endmethod
  
  method ActionValue#(CacheResponseDataT) getResponse() if (!nextFromRead.first || rsp_fifo.notEmpty);
    CacheResponseDataT resp <- toGet(preRsp_fifo).get;
    Bool fromCore <- toGet(nextFromRead).get;
    if (fromCore) begin
      CheriMemResponse mr <- toGet(rsp_fifo).get;
      case (mr.operation) matches
        tagged Read .rr: begin
          resp.data = tagged Line pack(rr.data.data);
          `ifdef USECAP
            // And the TLB capability flag with what was returned.
            resp.capability = resp.capability&&rr.data.cap[0];
          `endif
        end
        tagged SC .scr: begin
          Bit#(8) scResult = (scr)?1:0;
          resp.data = tagged Byte scResult;
          debug2("dcache", $display("<time %0t, cache %0d, DCache> store conditional response ", $time, coreId, fshow(resp)));
        end
      endcase
    end
    debug2("dcache", $display("<time %0t, cache %0d, DCache> returning DCache response ", $time, coreId, fshow(resp)));
    return resp;
  endmethod

  method Action invalidate(Bit#(40) addr) if (invalidateFifo.notFull);
    invalidateFifo.enq(addr);
  endmethod

  method L1ChCfg getConfig();
    /*L1ChCfg{
      a:0,  //  Associativity = A+1.  (A=0 for direct mapped)
      l:6,  //  Cache line size = 2*2^L.  L=0 if there is no cache. (32)
      s:1   //  Number of Cache index positions is 64 * 2^S. Mult by Associativity for total number of cache lines. (128)
    };*/
    `ifdef MEM256
      L1ChCfg ret = L1ChCfg{ a:0, l:6, s:1};
    `elsif MEM128
      L1ChCfg ret = L1ChCfg{ a:0, l:5, s:1};
    `elsif MEM64
      L1ChCfg ret = L1ChCfg{ a:0, l:4, s:1};
    `endif
    return ret;
  endmethod
  
  method Action nextWillCommit(Bool nextCommitting);
    //req_commits.enq(nextCommitting);
    if (nextFromCore.first) begin
      core.nextWillCommit(nextCommitting);
      debug2("dcache", $display("<time %0t, cache %0d, DCache> Put commit %x ", $time, coreId, nextCommitting));
    end
    nextFromCore.deq();
  endmethod
  
  interface Master memory;
    interface request  = toCheckedGet(ff2fifof(memReqs));
    interface response = toCheckedPut(memRsps);
  endinterface
endmodule
