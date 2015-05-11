/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Alan A. Mujumdar
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
   
typedef struct {
  Bit#(26)  tag;
  Bool    valid;
} TagT deriving (Bits, Eq);

`ifdef MULTI_DONT_USE
  typedef Bit#(16) TagShort;
`endif

/* =================================================================
mkCache
 =================================================================*/

typedef enum {Init, Serving, MissRead, MissFill} CacheState deriving (Bits, Eq);
`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkICache#(Bit#(16) coreId)(CacheInstIfc ifc);
  FIFO#(CacheRequestInstT)   req_fifo       <- mkLFIFO;
  Reg#(PhyAddress)           phyAddrReg     <- mkRegU;
  Reg#(Bool)                 missCached     <- mkReg(False); // Store whether the miss was cached or uncached.
  Reg#(Vector#(4,Bit#(64)))  updateReg      <- mkRegU;
  Reg#(Bool)                 validFillLine  <- mkReg(False);
  Reg#(Bit#(2))              fillCount      <- mkReg(2);
  FIFOF#(PhyAddress)         invalidateFifo <- mkSizedFIFOF(20);
  FIFO#(CacheResponseInstT)  out_fifo       <- mkBypassFIFO;
  FIFOF#(CheriMemRequest)       memReq_fifo    <- mkFIFOF;
  FIFOF#(CheriMemResponse)      memResp_fifo   <- mkFIFOF;
  `ifdef NOCACHE
    RegFile#(Bit#(15), Bit#(64)) rom  <- mkRegFileFullLoad("mem64.hex");
  `endif
  MEM#(Bit#(9), TagT)           tags <- mkMEM();
  Vector#(512, Reg#(TagT)) tagsDebug <- replicateM(mkRegU());
  MEM#(Bit#(11), Bit#(64))      data <- mkMEM();// Total size is 16 kbytes.
  //Vector#(2048, Bit#(64))         bankDebug;
  // Aliasing isn't a problem for iCache because it is read only.

  Reg#(CacheState)    cacheState   <- mkConfigReg(Init);
  Reg#(UInt#(9))      count        <- mkReg(0);

  `ifdef MULTI_DONT_USE
    MEM#(Bit#(9), TagShort) shortTags <- mkMEM();
  `endif
  
  Bool requestMatchesFill = req_fifo.first.tr.addr[39:5] == phyAddrReg[39:5] && req_fifo.first.cop.inst == Read && validFillLine;

  rule initialize(cacheState == Init);
    debug2("icache", $display("<time %0t, core %0d, ICache> Initializing tag %0d", $time, coreId, count));
    tags.write(pack(count), TagT{valid:False, tag: ?});
    `ifdef MULTI_DONT_USE
      shortTags.write(pack(count), ?);
    `endif
    tagsDebug[pack(count)] <= TagT{valid: False, tag: ?};
    count <= count + 1;
    if (count == 511) begin
      cacheState <= Serving;
    end
  endrule
  
  (* descending_urgency = "doRead, doCacheInstructions, invalidateEntry" *)
  rule invalidateEntry(cacheState == Serving && invalidateFifo.notEmpty);
    Bit#(9) key = invalidateFifo.first[13:5];
    invalidateFifo.deq();
    `ifdef MULTI_DONT_USE
      TagShort shortTagsRead <- shortTags.read.get();
      Bit#(16) shortInvAddr = invalidateFifo.first[29:14];
      debug($display("ICache shortInvAddr= %x, shortTag= %x", shortInvAddr, shortTagsRead));

      if (shortTagsRead == shortInvAddr) begin 
        shortTags.write(key, ?);
        tags.write(key, TagT{valid:False, tag: ?});
        tagsDebug[key]<= TagT{valid: False, tag: ?};
        debug2("cTrace", $display("ICache Invalidate key = %x", key));
        debug2("icache", $display("<time %0t, core %0d, ICache> Invalidating %0d", $time, coreId, key));
      end
    `else
      tags.write(key, TagT{valid:False, tag: ?});
      tagsDebug[key]<= TagT{valid: False, tag: ?};
      debug2("cTrace", $display("ICache Invalidate key = %x", key));
      debug2("icache", $display("<time %0t, core %0d, ICache> Invalidating %0d", $time, coreId, key));
    `endif
  endrule
  
  rule doCacheInstructions(cacheState == Serving && req_fifo.first.cop.inst != Read && req_fifo.first.cop.inst != Write && !invalidateFifo.notEmpty);
    let reqIn = req_fifo.first;
    Bit#(9) key = pack(reqIn.tr.addr)[13:5];
    req_fifo.deq;
    case (reqIn.cop.inst)
      CacheInvalidate, CacheInvalidateWriteback: begin
        tags.write(key, TagT{valid:False, tag: ?});
        `ifdef MULTI_DONT_USE
          shortTags.write(key, ?);
        `endif
        tagsDebug[key]<= TagT{valid: False, tag: ?};
        debug2("cTrace", $display("Invalidated Cache line: key=%x at time %d", key, $time));
        debug2("icache", $display("<time %0t, core %0d, ICache> Invalidating %0d", $time, coreId, key));
      end
    endcase
  endrule
  
  rule doRead(cacheState == Serving && !invalidateFifo.notEmpty);
    let req = req_fifo.first;
    let addr = req.tr.addr;
    TagT tagsRead;
    Bit#(64) dataRead;
    Bool miss = True;
    Bool uncached = False;
    CacheResponseInstT resp = CacheResponseInstT{inst: ?, exception: None};
    
    tagsRead <- tags.read.get();
    dataRead <- data.read.get();
    
    debug($display("Cache Read Request: ", fshow(req)));
    debug2("icache", $display("<time %0t, core %0d, ICache> Serving ", $time, coreId, fshow(req)));
    if (req.tr.exception!=None) begin // If it was a TLB miss, we have an exception anyway.
      debug($display("TLB Miss, returning exception from Cache..."));
      resp.exception = req.tr.exception;
      resp.inst = classifyMIPSInstruction(32'b0);
      out_fifo.enq(resp); // If it's a read
      req_fifo.deq;
    end else begin
      uncached = !req.tr.cached; // If the tlb tells us that it is uncached.
      debug($display("Cache read test.  tlbAddr:%x, tag:%x", req.tr.addr, {tagsRead.tag,12'b0}));
      miss = !(tagsRead.tag == truncateLSB(req.tr.addr) && tagsRead.valid);
      cycReport($display("[$IL1%s]", (miss)?"M":"H"));
      if (!miss && !uncached) begin // If it's a hit...
        Vector#(4,Bit#(8)) instruction_bits = (addr[2] == 1) ? unpack(dataRead[63:32]) : unpack(dataRead[31:0]); // this is the mux
        resp.inst = classifyMIPSInstruction(pack(Vector::reverse(instruction_bits)));
        out_fifo.enq(resp); // If it's a read
        req_fifo.deq;
        debug($display("Hit! %x=%x", addr, resp.inst));
        debug2("icache", $display("<time %0t, core %0d, ICache> Returning response ", $time, coreId, fshow(resp)));
      end else begin // If it is a miss or uncached.
        `ifdef NOCACHE
          PismData pdata = pdef;
          pdata.addr = {zeroExtend(req.tr.addr[39:5]), 5'b0};
          Vector#(8,Bit#(4)) bten = replicate(0);
          bten[addr[4:2]] = 4'b1111;
          pdata.byteenable = pack(bten);
          pdata.write = 8'h0;
          if (pism_addr_valid(pdata)) begin
            pism_request_put(pdata);
            Bit#(512) presp_Bit <- pism_response_get();
            PismData presp = unpack(presp_Bit);
            resp.inst = from256to32(presp.data, addr[4:2]);
            out_fifo.enq(resp);
            req_fifo.deq;
          end else begin
            resp.inst = (addr[2]==1) ? (rom.sub(req.tr.addr[17:3]))[63:32] : (rom.sub(req.tr.addr[17:3]))[31:0];
            out_fifo.enq(resp);
            req_fifo.deq;
          end
          if (True) begin
            miss = True;
          end
          else
        `endif
        missCached <= req.tr.cached;
        phyAddrReg <= req.tr.addr;
        validFillLine <= False;
        cacheState <= MissRead;
        if (uncached) begin
          // Prepare byte enables for memory request;
          Vector#(8,Bit#(4)) bten = replicate(0);
          bten[addr[4:2]] = 4'b1111;
          debug($display("ICache Read Uncached"));
          CheriMemRequest mem_req = defaultValue;
          mem_req.addr = unpack(pack(req.tr.addr));
          mem_req.masterID = unpack(truncate({coreId,1'b0}));
          mem_req.operation = tagged Read {
                                uncached: True,
                                linked: False,
                                noOfFlits: 0,
                                bytesPerFlit: BYTE_4
                              };
          memReq_fifo.enq(mem_req);
          debug($display("ICache memory request : ", fshow(mem_req)));
          debug2("icache", $display("<time %0t, core %0d, ICache> Sending ", $time, coreId, fshow(mem_req)));
        end else if (miss) begin
          debug($display("ICache Read Miss"));
          CheriMemRequest mem_req = defaultValue;
          mem_req.addr = unpack(pack(req.tr.addr));
          mem_req.masterID = unpack(truncate({coreId,1'b0}));
          mem_req.operation = tagged Read {
                                uncached: False,
                                linked: False,
                                noOfFlits: 0,
                                bytesPerFlit: BYTE_32
                              };
          memReq_fifo.enq(mem_req);
          debug($display("ICache memory request : ", fshow(mem_req)));
          debug2("icache", $display("<time %0t, core %0d, ICache> Sending ", $time, coreId, fshow(mem_req)));
          tags.write(addr[13:5], TagT{valid:False, tag: ?});
          `ifdef MULTI_DONT_USE
            shortTags.write(addr[13:5], ?);
          `endif
          tagsDebug[addr[13:5]]<= TagT{valid: False, tag: ?};
        end
      end
    end
  endrule

  rule getMemoryResponse(cacheState == MissRead);
    let addr = phyAddrReg;
    CacheResponseInstT resp = CacheResponseInstT{inst: ?, exception: None};
    CheriMemResponse bigResponse <- toGet(memResp_fifo).get();
    debug($display("ICache memory response : ", fshow(bigResponse)));
    debug2("icache", $display("<time %0t, core %0d, ICache> Memory response ", $time, coreId, fshow(bigResponse)));
    case (bigResponse.operation) matches
      tagged Read .r : begin
        Vector#(8, Bit#(32)) line = unpack(pack(r.data.data));
        Vector#(4, Bit#(8)) instruction_bits = unpack(pack(line[addr[4:2]]));
        updateReg <= unpack(pack(line));
        resp.inst = classifyMIPSInstruction(pack(Vector::reverse(instruction_bits)));
        out_fifo.enq(resp);
        req_fifo.deq;
        if (missCached) begin
          validFillLine <= True;
          cacheState <= MissFill;
          data.write({addr[13:5], 0}, {line[1],line[0]});
          debug($display("Stored Cache Record! %x = %x", {addr[11:5], 2'b0, 3'b0}, line[0]));
          debug2("icache", $display("<time %0t, core %0d, ICache> Writing @0x%0x=0x%0x", $time, coreId, {addr[11:5], 2'b0, 3'b0}, line[0]));
          fillCount <= 1;
        end else begin
          debug($display("It was an uncached Read! %x = %x", addr, resp));
          cacheState <= Serving;
        end
      end
      default : begin
        dynamicAssert(False, "Only a read response is expected in ICache MissRead state");
      end
    endcase
  endrule

  rule updateCache(cacheState == MissFill);
    PhyAddress addr = phyAddrReg;
    data.write({addr[13:5], fillCount}, updateReg[fillCount]);
    debug($display("Stored Cache Record! %x = %x", {addr[11:5], fillCount, 3'b0}, updateReg[fillCount]));
    debug2("icache", $display("<time %0t, core %0d, ICache> Writing @0x%0x=0x%0x", $time, coreId, {addr[11:5], fillCount, 3'b0}, updateReg[fillCount]));
    if (fillCount == 3) begin
      debug($display("Write Cache tags for addr %x", {addr[39:5], 5'b0}));
      tags.write(addr[13:5],TagT{valid:True, tag: truncateLSB(addr)});
      `ifdef MULTI_DONT_USE
        shortTags.write(addr[13:5], addr[29:14]);
      `endif
      tagsDebug[addr[13:5]]<= TagT{valid: True, tag: truncateLSB(addr)};
      cacheState <= Serving;
    end else begin
      fillCount <= fillCount + 1;
    end
  endrule
  
  rule respondDuringUpdate(cacheState != MissRead && cacheState != Serving && requestMatchesFill);
    TagT tagsRead <- tags.read.get();
    Bit#(64) dataRead <- data.read.get();
    CacheResponseInstT resp = CacheResponseInstT{inst: ?, exception: req_fifo.first.tr.exception};
    cycReport($display("[$IL1H]"));
    Vector#(2,Vector#(4,Bit#(8))) instruction_bits = unpack(updateReg[req_fifo.first.tr.addr[4:3]]);
    resp.inst = classifyMIPSInstruction(pack(Vector::reverse(instruction_bits[req_fifo.first.tr.addr[2]])));
    debug2("icache", $display("<time %0t, core %0d, ICache> Returning response ", $time, coreId, fshow(resp)));
    out_fifo.enq(resp);
    req_fifo.deq;
  endrule

  method Action put(reqIn) if (cacheState != Init);
    Bit#(11) key = pack(reqIn.tr.addr)[13:3];
    case (reqIn.cop.inst)
      Read, Write: begin
        `ifdef NOCACHE
          delay = False;
        `endif
        
        tags.read.put(key[10:2]);
        data.read.put(key);
        req_fifo.enq(reqIn);
        debug($display("Put in Cache Request: ", fshow(reqIn)));
      end
      CacheInvalidate, CacheInvalidateWriteback: begin
        req_fifo.enq(reqIn);
      end
    endcase
  endmethod
  
  method ActionValue#(CacheResponseInstT) getRead();// if (cacheState == Serving);
    debug($display("Delivering Word from the Cache: %x at time %d",  out_fifo.first, $time));
    out_fifo.deq;
    return out_fifo.first;
  endmethod

  method Action invalidate(PhyAddress addr) if (invalidateFifo.notFull);
    invalidateFifo.enq(addr);
    `ifdef MULTI_DONT_USE
      Bit#(9) key = addr[13:5];
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

  method Action debugDump();
    for (Integer i=0; i<512; i=i+1) begin
      debugInst($display("DEBUG ICACHE TAG ENTRY %3d Valid=%x Tag value=%x", i, tagsDebug[i].valid, tagsDebug[i].tag));
    end
  endmethod
  
  interface Master memory;
    interface request  = toCheckedGet(memReq_fifo);
    interface response = toCheckedPut(memResp_fifo);
  endinterface

endmodule
