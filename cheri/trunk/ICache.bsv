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
import Vector::*;
`ifdef NOCACHE
  import PISM::*;
`endif

/* =================================================================
 ICache
 =================================================================*/

`ifdef MEM256
  typedef 8 BusInsts;
`elsif MEM128
  typedef 4 BusInsts;
`elsif MEM64
  typedef 2 BusInsts;
`endif

typedef SizeOf#(CheriPhyByteOffset) ByteOffsetSize;
 
typedef enum {Init, Serving, Fill
  `ifdef MULTI
    , StoreConditional
  `endif
} CacheState deriving (Bits, Eq);

`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkICache#(Bit#(16) coreId)(CacheInstIfc);
  FIFOF#(CacheResponseInstT)         preRsp_fifo <- mkFIFOF;
  FIFO#(CheriPhyByteOffset)                addrs <- mkFIFO;
  FIFO#(Bool)                       nextFromCore <- mkFIFO;
  FIFOF#(Bool)                        returnNext <- mkUGSizedFIFOF(16); // Lots of room due to being unguarded.
  FIFOF#(CheriMemResponse)              rsp_fifo <- mkBeriUGBypassFIFOF;
  FF#(CheriMemRequest, 2)                memReqs <- mkUGFF();
  FIFOF#(CheriMemResponse)               memRsps <- mkUGFIFOF;
  CacheCore#(1, 7)                          core <- mkCacheCore(coreId, WriteThrough, ICache, 
                                                                zeroExtend(memReqs.remaining()), 
                                                                ff2fifof(memReqs), memRsps);
  FIFOF#(PhyAddress)              invalidateFifo <- mkUGFIFOF;
  Reg#(CheriTransactionID)        transactionNum <- mkReg(0);
  
  rule runCache;
    Maybe#(CheriMemResponse) memResp <- core.get(rsp_fifo.notFull);
    if (memResp matches tagged Valid .mr) begin
      if (mr.operation matches tagged Read .rop &&& returnNext.first) begin
        debug2("icache", $display("<time %0t, cache %0d, ICache> got response! ", $time, coreId, fshow(mr)));
        rsp_fifo.enq(mr);
      end
      returnNext.deq();
    end
  endrule

  method Action put(CacheRequestInstT reqIn);
    debug2("icache", $display("<time %0t, cache %0d, ICache> putting ICache request ", $time, coreId, fshow(reqIn)));
    Bool cached = reqIn.tr.cached;
    CheriMemRequest mem_req = defaultValue;
    mem_req.addr = unpack(reqIn.tr.addr);
    if (cached) mem_req.addr.byteOffset = 0;
    mem_req.masterID = unpack(truncate(coreId));
    mem_req.transactionID = transactionNum;
    CacheOperation cop = reqIn.cop;
    Bool putToCore = (reqIn.tr.exception == None);
    // Indicate that we smuggled an invalidate in a NOP.
    Bool nopInvalidate = False;
    Bool returnInst = False;
    
    CacheResponseInstT resp = CacheResponseInstT {
      inst: classifyMIPSInstruction(32'b0),
      exception: reqIn.tr.exception
    };
    
    case (cop.inst)
      CacheNop: begin
        if (invalidateFifo.notEmpty) begin
          mem_req.addr = unpack(invalidateFifo.first);
          mem_req.operation = tagged CacheOp CacheOperation{
                                                inst: CacheInvalidate, 
                                                cache: ICache,
                                                indexed: False
                                             };
          debug2("icache", $display("<time %0t, cache %0d, ICache> invalidating ", $time, coreId, fshow(mem_req)));
          invalidateFifo.deq();
          nopInvalidate = True;
        end
      end
      Read: begin
        if (resp.exception == None) begin
          mem_req.operation = tagged Read {
                            uncached: !cached,
                            linked: reqIn.tr.ll,
                            noOfFlits: 0,
                            bytesPerFlit: BYTE_4
                          };
        end else putToCore = False;
        returnInst = True;
      end
      default: begin
        mem_req.operation = tagged CacheOp cop;
        resp.exception = None;
        putToCore = True;
      end
    endcase
    
    Bool expectResponse = True;
    if (putToCore) begin
      debug2("icache", $display("<time %0t, cache %0d, ICache> putting to core ", $time, coreId, fshow(mem_req)));
      core.put(mem_req);
      core.nextWillCommit(True);
      // Ensure that the core never sees the same transaction ID twice.
      transactionNum <= transactionNum + 1;
      returnNext.enq(returnInst);
      // If we put it to the core, but will not return an instruction, don't expect a response.  A Cache instruction, for example.
      expectResponse = returnInst;
    end
    if (expectResponse) begin
      resp.inst = unpack(zeroExtend(pack(nopInvalidate)));
      preRsp_fifo.enq(resp);
      nextFromCore.enq(putToCore);
      addrs.enq(truncate(reqIn.tr.addr));
    end
  endmethod
  
  method ActionValue#(CacheResponseInstT) getRead() if (!nextFromCore.first || rsp_fifo.notEmpty);
    CacheResponseInstT resp <- toGet(preRsp_fifo).get;
    CheriPhyByteOffset addr <- toGet(addrs).get;
    Bool    fromCore <- toGet(nextFromCore).get;
    if (fromCore) begin
      CheriMemResponse mr <- toGet(rsp_fifo).get;
      if (mr.operation matches tagged Read .rr) begin
        Vector#(BusInsts,Bit#(32)) instArray = unpack(rr.data.data);
        Integer top = valueOf(ByteOffsetSize)-1;
        Bit#(TSub#(ByteOffsetSize,2)) index = addr[top:2];
        Vector#(4,Bit#(8)) instBits = unpack(instArray[index]);
        resp.inst = classifyMIPSInstruction(pack(Vector::reverse(instBits)));
      end
    end else resp.inst = classifyMIPSInstruction(32'b0);
    debug2("icache", $display("<time %0t, cache %0d, ICache> returning ICache response ", $time, coreId, fshow(resp)));
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
  
  interface Master memory;
    interface request  = toCheckedGet(ff2fifof(memReqs));
    interface response = toCheckedPut(memRsps);
  endinterface
endmodule
