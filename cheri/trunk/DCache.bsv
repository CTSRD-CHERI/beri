/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Alex Horsman
 * Copyright (c) 2013, 2014 Alexandre Joannou
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
import MIPS::*;
import List::*;
import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import GetPut::*;
import MasterSlave::*;
import Vector::*;
import ConfigReg::*;
import MEM::*;
import Clocks::*;  
`ifdef NOCACHE
  import PISM::*;
`endif

typedef Bit#(9) Key;
typedef Bit#(26) Tag;
`ifdef MULTI_DONT_USE
  typedef Bit#(16) TagShort;
`endif

typedef struct {
  Tag tag;
  `ifdef CAP
    Bool capability;
  `endif
  Bool valid;
} TagLine deriving (Bits, Eq, Bounded);

typedef struct {
  Tag tag;
  Key key;
  FillType fillType;
} FillRequest deriving (Bits, Eq, Bounded);

typedef enum {Miss, Uncached} FillType deriving (Bits, Eq, Bounded);

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
  FIFO#(CacheRequestDataT)      req_fifo <- mkFIFO;
  FIFO#(FillRequest)            fillReqs <- mkFIFO;
  FIFO#(CacheResponseDataT)     rsp_fifo <- mkBypassFIFO;
  FIFOF#(Bool)               commit_fifo <- mkSizedBypassFIFOF(4);
  Reg#(CacheState)            cacheState <- mkConfigReg(Init);
  FIFOF#(PhyAddress)      invalidateFifo <- mkSizedFIFOF(20);
  MEM#(Key, TagLine)                tags <- mkMEM();
  MEM#(Key, Bit#(256))              data <- mkMEM();
  FIFOF#(CheriMemRequest)    memReq_fifo <- mkFIFOF;
  FIFOF#(CheriMemResponse)  memResp_fifo <- mkFIFOF;
  Reg#(UInt#(9))                   count <- mkReg(0);
  `ifdef MULTI
    FIFOF#(CacheRequestDataT) screq_fifo <- mkBypassFIFOF;
  `endif
  `ifdef MULTI_DONT_USE
    MEM#(Key, TagShort)        shortTags <- mkMEM();
  `endif
  
  TagLine tagInvalid = TagLine{
    `ifdef CAP
      capability: ?,
    `endif
    tag:   ?,
    valid: False
  };

  rule initialize(cacheState == Init);
    debug2("dcache", $display("<time %0t, core %0d, DCache> Initializing tag %0d", $time, coreId, count));
    tags.write(pack(count), tagInvalid);
    `ifdef MULTI_DONT_USE
      shortTags.write(pack(count), ?);
    `endif
    count <= count + 1;
    if (count == 511) cacheState <= Serving;
  endrule

  rule invalidateEntry(cacheState == Serving && invalidateFifo.notEmpty);
    Key key = invalidateFifo.first[13:5];
    invalidateFifo.deq();
    `ifdef MULTI_DONT_USE
      TagShort shortTagsRead <- shortTags.read.get();
      Bit#(16) shortInvAddr = invalidateFifo.first[29:14];
      debug($display("DCache shortInvAddr= %x, shortTag= %x", shortInvAddr, shortTagsRead));

      if (shortTagsRead == shortInvAddr) begin
        tags.write(key, tagInvalid);
        shortTags.write(key, ?);
        debug($display("DCache Invalidate key = %x, shortTag = %x", key, shortTagsRead));
        debug2("dcache", $display("<time %0t, core %0d, DCache> Invalidating key %0d", $time, coreId, key));
      end
    `else
      tags.write(key, tagInvalid);
      debug($display("DCache Invalidate key = %x", key));
      debug2("dcache", $display("<time %0t, core %0d, DCache> Invalidating key %0d", $time, coreId, key));
    `endif
  endrule
  
  rule putDRAMRequest(cacheState == Serving && !invalidateFifo.notEmpty);
    CacheRequestDataT req = req_fifo.first;
    CacheOperation cop = req.cop;
    debug($display("DCache Request: ", fshow(req)));
    Key key = unpack(req.tr.addr[13:5]);
    Bool exception = !commit_fifo.first;
    commit_fifo.deq;
    
    TagLine tagsRead <- tags.read.get();
    Bit#(256) dataRead <- data.read.get();

    Bool cached = req.tr.cached; // If the tlb tells us that it is uncached.
    Bool miss = !((truncateLSB(req.tr.addr) == tagsRead.tag) && tagsRead.valid);
    if (!exception) exception = (req.tr.exception!=None); // If we didn't have an exception already, we may have one from the TLB.
    debug2("dcache", $display("<time %0t, core %0d, DCache> Serving request ", $time, coreId, fshow(req)));
    
    CacheResponseDataT resp = CacheResponseDataT {
      `ifdef CAP
        capability: tagsRead.capability,
      `endif
      data: ?,
      exception: req.tr.exception
    };

    `ifdef MULTI
      // A load linked causes the cache to miss so that the shared L2Cache is accessed 
      if (req.tr.ll) begin
        debug($display("tr_ll addr:%x", req.tr.addr));
        cached = False;
      end
    `endif
   
    case (cop.inst)
      Read: begin
        cycReport($display("[$DL1R%s]", (miss)?"M":"H"));
        if (exception) begin // If it was a TLB miss, we have an exception anyway.
          resp.data = tagged Line 256'b0;
          rsp_fifo.enq(resp);
          req_fifo.deq;
        end else if (!miss && cached) begin // If it's a hit...
          `ifdef CAP
            resp.capability = tagsRead.capability;
            if (resp.capability && req.tr.noCapLoad && resp.exception == None) begin
              resp.exception = CTLBL;
              exception = True;
            end
          `endif
          resp.data = tagged Line dataRead;
          rsp_fifo.enq(resp);
          req_fifo.deq;
          debug($display("DCache Read Hit! %x=%x", key, resp.data));
          debug2("dcache", $display("<time %0t, core %0d, DCache> Returning response ", $time, coreId, fshow(resp)));
        end else begin // If it is a miss or uncached.
          FillRequest fillReq = FillRequest{tag: truncateLSB(req.tr.addr), key: key, fillType: (cached) ? Miss:Uncached};
          fillReqs.enq(fillReq);
          cacheState <= Fill;
          `ifdef MULTI
            if (req.tr.ll) begin
              // We want the read to pass though the L1 but get registered in the L2 and
              // the LL operation must be cached. 
              cached = True;                        
            end
          `endif
          function BytesPerFlit memSizeTobpf(MemSize m);
            return case (m) matches
              Byte : BYTE_1;
              HalfWord: BYTE_2;
              Word: BYTE_4;
              DoubleWord: BYTE_8;
              //: BYTE_16;
              Line: BYTE_32;
            endcase;
          endfunction
          CheriMemRequest mem_req = defaultValue;
          mem_req.addr = unpack(req.tr.addr);
          mem_req.masterID = unpack(truncate({coreId,1'b1}));
          mem_req.operation = tagged Read {
                                uncached: ! cached,
                                linked: req.tr.ll,
                                noOfFlits: 0,
                                bytesPerFlit: (cached) ? BYTE_32 : memSizeTobpf(req.memSize)
                              };
          memReq_fifo.enq(mem_req);
          debug($display("%t: DCache memory request : ", $time, fshow(mem_req)));
          debug2("dcache", $display("<time %0t, core %0d, DCache> Sending ", $time, coreId, fshow(mem_req)));
        end
      end
      Write: begin
        cycReport($display("[$DL1W%s]", (miss)?"M":"H"));
        debug($display("DCache write test.  tlbAddr:%x, tag:%x", req.tr.addr, {tagsRead.tag,12'b0}));
        for (Integer i = 0; i < 32; i=i+1) begin
          Integer top = i*8+7;
          Integer bot = i*8;
          if (req.byteEnable[i]==1'b1) begin
            Bit#(8) mod = req.data[top:bot];
            dataRead[top:bot] = mod;
          end
        end
        `ifdef CAP
          if (req.capability && req.tr.noCapStore && resp.exception == None) begin
            resp.exception = CTLBS;
            exception = True;
          end
        `endif
        if (!exception) begin // If there hasn't been an exception, do the write.
          if (!miss && cached) begin // If it's a hit...
            data.write(key, dataRead);
            `ifdef CAP
              tagsRead.capability = req.capability;
            `endif
            tags.write(key, tagsRead);
            `ifdef MULTI_DONT_USE
              shortTags.write(key, tagsRead.tag[15:0]);
              debug($display("DCache Write Hit! shortTags %x", tagsRead.tag[15:0]));
            `endif
            debug($display("DCache Write Hit! %x=%x", key, dataRead));
            debug2("dcache", $display("<time %0t, core %0d, DCache> Writing @0x%0x=0x%0x", $time, coreId, key, dataRead));
          end else begin // If it is a miss or uncached.
            if (!cached) begin // Just write to the avalon bus directly.
              debug($display("UnCached Write"));
              // If it was a hit, but this is an uncached access, invalidate the line.
              if (!miss) begin
                tags.write(key, tagInvalid);
                `ifdef MULTI_DONT_USE
                  shortTags.write(key, ?);
                `endif
              end
            end else if (miss) begin // Put in the memory request if the tag didn't match and update the tag for the new value.
              debug($display("DCache Write Miss on key %x", key));
            end
          end
          CheriMemRequest mem_req = defaultValue;
          mem_req.addr = unpack(req.tr.addr);
          mem_req.masterID = unpack(truncate({coreId,1'b1}));
          mem_req.operation = tagged Write {
                                uncached: ! cached,
                                conditional: False,
                                byteEnable: unpack(req.byteEnable),
                                data: Data{
                                  `ifdef CAP
                                  cap: unpack(pack(req.capability)),
                                  `endif
                                  data: req.data
                                },
                                last: True
                              };
          memReq_fifo.enq(mem_req);
          debug($display("%t: DCache memory request : ", $time, fshow(mem_req)));
          debug2("dcache", $display("<time %0t, core %0d, DCache> Sending ", $time, coreId, fshow(mem_req)));
        end
        rsp_fifo.enq(resp);
        req_fifo.deq;
      end
      `ifdef MULTI 
        StoreConditional: begin 
          `ifdef CAP     
            if (req.capability && req.tr.noCapStore && resp.exception == None) begin 
              resp.exception = CTLBS;
              exception = True;  
            end 
          `endif 
          if (!exception) begin // If there hasn't been an exception, do the write.
            if (!miss) begin // If it's a hit... 
              // If the SC operation gets a hit in the L1 we must invalidate the line
              tags.write(key, tagInvalid); 
              `ifdef MULTI_DONT_USE
                shortTags.write(key, ?);
              `endif
            end   
            CheriMemRequest mem_req = defaultValue;
            mem_req.addr = unpack(pack(req.tr.addr));
            mem_req.masterID = unpack(truncate({coreId,1'b1}));
            mem_req.operation = tagged Write {
                                    uncached: !cached,
                                    conditional: True,
                                    byteEnable: unpack(pack(req.byteEnable)),
                                    data: Data{
                                      `ifdef CAP
                                      cap: unpack(pack(req.capability)),
                                      `endif
                                      data: req.data
                                    },
                                    last: True
                                  };
            cacheState <= StoreConditional; 
            memReq_fifo.enq(mem_req); 
            debug($display("DCache Store Conditional L2 Request, DataReg:0x%x", dataRead));
            debug2("dcache", $display("<time %0t, core %0d, DCache> Sending ", $time, coreId, fshow(mem_req)));
            FillRequest fillReq = FillRequest{tag: truncateLSB(req.tr.addr), key: key, fillType: (cached) ? Miss:Uncached}; 
            fillReqs.enq(fillReq); 
          end  
          else begin 
            // Store Conditional Fail   
            resp.data = tagged Line 256'b0;  
            rsp_fifo.enq(resp);   
            req_fifo.deq; 
          end   
        end  
      `endif 
      default: begin
        if (cop.cache == DCache) begin
          Bool doInvalidate = (cop.indexed) ? True:!miss;
          if (doInvalidate) begin
            case (cop.inst)
              CacheInvalidate, CacheInvalidateWriteback: begin
                tags.write(key, tagInvalid);
                `ifdef MULTI_DONT_USE
                  shortTags.write(key, ?);
                `endif
                debug($display("Invalidated Cache line: key=%x at time %d", key, $time));
                debug2("dcache", $display("<time %0t, core %0d, DCache> Invalidating key 0x%0x ", $time, coreId, key));
              end
            endcase
          end
        end else if (cop.cache == L2) begin
          CheriMemRequest mem_req = defaultValue;
          mem_req.addr = unpack(req.tr.addr);
          mem_req.masterID = unpack(truncate({coreId,1'b1}));
          mem_req.operation = tagged CacheOp cop;
          memReq_fifo.enq(mem_req);
          debug($display("DCache memory request : ", fshow(mem_req)));
          debug2("dcache", $display("<time %0t, core %0d, DCache> Sending ", $time, coreId, fshow(mem_req)));
        end
        resp.exception = None; // Cache instructions don't throw TLB exceptions.
        rsp_fifo.enq(resp);
        req_fifo.deq;
      end
    endcase
  endrule
 
`ifdef MULTI  
  rule getStoreConditionalResponse(cacheState == StoreConditional);
    FillRequest req = fillReqs.first; 
    CheriMemResponse bigResponse <- toGet(memResp_fifo).get;
    if (bigResponse.operation matches tagged SC .scop) begin
      debug($display("DCache Store Conditional response :\n%s", fshow(bigResponse))); 
      debug2("dcache", $display("<time %0t, core %0d, DCache> Memory SC response ", $time, coreId, fshow(bigResponse)));
      CacheResponseDataT resp = CacheResponseDataT {
        `ifdef CAP
        capability: ?,
        `endif
        data: scop ? tagged Line 256'h1 : tagged Line 256'h0,
        exception: None
      };
      rsp_fifo.enq(resp);
      req_fifo.deq;
      fillReqs.deq; 
      cacheState <= Serving;
    end else dynamicAssert(False, "An SC response was expected");
  endrule  
`endif
 
  rule getDRAMResponse(cacheState == Fill);
    FillRequest req = fillReqs.first;
    CheriMemResponse bigResponse <- toGet(memResp_fifo).get;
    debug($display("DCache memory response :\n%s", fshow(bigResponse)));
    debug2("dcache", $display("<time %0t, core %0d, DCache> Memory response ", $time, coreId, fshow(bigResponse)));

    case (bigResponse.operation) matches
      tagged Read .r : begin
        CacheResponseDataT resp = CacheResponseDataT{
          `ifdef CAP
          capability: unpack(pack(r.data.cap)),
          `endif
          data: tagged Line r.data.data,
          exception: None
        };
        `ifdef CAP
        if (resp.capability && req_fifo.first.tr.noCapLoad && resp.exception == None) begin
          resp.exception = CTLBL;
        end
        `endif
        rsp_fifo.enq(resp);
        req_fifo.deq;
        if (req.fillType != Uncached) begin
          debug($display("DCache dataWrite = %x", r.data.data));
          debug2("dcache", $display("<time %0t, core %0d, DCache> Writing @0x%0x=0x%0x", $time, coreId, req.key, r.data.data));
          data.write(req.key, unpack(r.data.data));
          tags.write(req.key, TagLine{
            `ifdef CAP
              capability: resp.capability,
            `endif
            tag: req.tag,
            valid: True
          });
          `ifdef MULTI_DONT_USE
            shortTags.write(req.key, req.tag[15:0]);
            debug($display("DCache dataWrite shortTags = %x", req.tag[15:0]));
          `endif
        end else
          debug($display("It was an uncached Read in the DCache! %x = %x", req.tag, resp));
        fillReqs.deq;
        cacheState <= Serving;
      end
      default : begin
        dynamicAssert(False, "Only read a read response is expected");
      end
    endcase
  endrule

  method Action put(CacheRequestDataT reqIn) if (cacheState == Serving);
    Key key = pack(reqIn.tr.addr[13:5]);
    req_fifo.enq(reqIn);
    tags.read.put(key);
    data.read.put(key);
  endmethod
  
  method ActionValue#(CacheResponseDataT) getResponse();
    actionvalue
      CacheResponseDataT resp = rsp_fifo.first;
      rsp_fifo.deq;
      return resp;
    endactionvalue
  endmethod

  method Action invalidate(PhyAddress addr) if (invalidateFifo.notFull);
    invalidateFifo.enq(addr);
    `ifdef MULTI_DONT_USE
      Key key = pack(addr[13:5]);
      shortTags.read.put(key);
    `endif
  endmethod

  method L1ChCfg getConfig();
    return L1ChCfg{
            a:0,  //  Associativity = A+1.  (A=0 for direct mapped)
            l:4,  //  Cache line size = 2*2^L.  L=0 if there is no cache. (32)
            s:3   //  Number of Cache index positions is 64 * 2^S. Mult by Associativity for total number of cache lines. (128)
          };
  endmethod
  
  method Action nextWillCommit(Bool nextCommitting);
    commit_fifo.enq(nextCommitting);
  endmethod
  
  interface Master memory;
    interface request  = toCheckedGet(memReq_fifo);
    interface response = toCheckedPut(memResp_fifo);
  endinterface
endmodule
