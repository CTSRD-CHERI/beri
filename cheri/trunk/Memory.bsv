/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2014 Jonathan Woodruff
 * Copyright (c) 2011 Steven J. Murdoch
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert N. M. Watson
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

import MIPS :: *;

import MasterSlave :: *;
import ClientServer :: *;
import Connectable :: *;
import GetPut :: *;
import FIFO :: *;
import FIFOF :: *;
import SpecialFIFOs::*;
import Vector::*;
`ifndef DCACHECORE
  import DCacheClassic :: *;
`else
  import DCache :: *;
`endif
`ifndef ICACHECORE
  import ICacheClassic :: *;
`else
  import ICache :: *;
`endif
import MemTypes :: *;
import Merge :: *;
`ifndef MICRO
  import L2Cache :: *;
  import TLB :: *;
  import CP0 :: *;
`endif
import GetPut :: *;
`ifdef CAP
  import CapCop :: *;
  import TagCache :: *;
  `define USECAP
`elsif CAP128
  import CapCop128 :: *;
  import TagCache :: *;
  `define USECAP
`endif

interface DataMemory;
  method Action startRead(Bit#(64) addr, MemSize size, Bool ll, Bool cap, InstId instId, Epoch epoch, Bool fromDebug);
  method Action startWrite(Bit#(64) addr, SizedWord sizedData, MemSize size, InstId instId, Epoch epoch, Bool fromDebug, Bool storeConditional);
  method Action startNull(InstId instId, Epoch epoch);
  method Action startCacheOp(Bit#(64) addr, CacheOperation cop, InstId id, Epoch epoch);
  `ifndef MULTI
    method ActionValue#(CacheResponseDataT) getResponse(MIPSReg oldReg, Bool signExtend, Bit#(8) addr, MemSize size, Bool exception, Bool cacheOpResponse);
  `else 
    method ActionValue#(CacheResponseDataT) getResponse(MIPSReg oldReg, Bool signExtend, Bit#(8) addr, MemSize size, Bool exception, Bool scStatus, Bool cacheOpResponse);
  `endif
endinterface

interface InstructionMemory;
  method Action reqInstruction(Address addr, InstId   instId);
  method ActionValue#(CacheResponseInstT) getInstruction();
  method Action debugDump();
endinterface

interface MemConfiguration;
  method L1ChCfg dCacheGetConfig();
  method L1ChCfg iCacheGetConfig();
endinterface

`ifdef USECAP
  interface CapabilityMemory;
    interface Server#(CapMemAccess, Capability) server;
    method ActionValue#(Exception) getException(InstId instId);
    method Action confirmWriteback(Bool commit);
  endinterface
`endif

interface MIPSMemory;
  interface DataMemory dataMemory;
  interface InstructionMemory instructionMemory;
  interface MemConfiguration configuration;
  `ifdef COP1
    interface Server#(CoProMemAccess, CoProReg) cop1Memory;
  `endif
  // Interface below is required for the multiport L2Cache
  //interface Client#(MemoryRequest#(35, 32), BigMemoryResponse#(256)) memory;
  `ifdef MULTI
    method Action invalidateICache(PhyAddress addr); 
    method Action invalidateDCache(PhyAddress addr); 
    interface Master#(CheriMemRequest, CheriMemResponse) dmemory;
    interface Master#(CheriMemRequest, CheriMemResponse) imemory;
  `else
    interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `endif
  method Action nextWillCommit(Bool commiting);
endinterface

typedef struct {
  Exception exception;
  InstId    instId;
} ExceptionAndId deriving (Bits, Eq);

function Bit#(lineSize) insert(Bit#(insertSize) toInsert, Bit#(addrSize) addr)
  provisos(Add#(a__, insertSize, lineSize)); 
  return zeroExtend(toInsert) << addr;
endfunction

function Bit#(outSize) selectF(Bit#(lineSize) val, Bit#(lineAddrSize) off) provisos (Add#(a__, outSize, lineSize));
  return truncate(val >> off);
endfunction

function Bit#(n) reverseBytes(Bit#(n) x) provisos (Mul#(8,n8,n));
  Vector#(n8,Bit#(8)) vx = unpack(x);
  return pack(Vector::reverse(vx));
endfunction

function SizedWord selectWithSize(Bit#(64) oldReg, Line line, CheriPhyBitOffset addr, MemSize size);

  // Addr is the BIT ADDRESS of the desired data item.
  CheriPhyBitOffset addrMask = truncate(8'hF8);
  case(size)
    Byte:
      return tagged Byte selectF(line, addr & addrMask);
    HalfWord: begin
      Bit#(16) temp = selectF(line, addr & addrMask);
      return tagged HalfWord (reverseBytes(temp));
    end
    Word: begin
      Bit#(32) temp = selectF(line, addr & addrMask);
      return tagged Word (reverseBytes(temp));
    end
    WordLeft: begin
      Bit#(32) orig = oldReg[31:0];
      addrMask = truncate(8'hE0);
      Bit#(32) temp = selectF(line, addr & addrMask);
      temp = reverseBytes(temp);
      Bit#(5) shift = truncate(addr);
      temp = temp << shift;
      Bit#(32) mask = 32'hFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged Word (temp);
    end
    WordRight: begin
      Bit#(32) orig = oldReg[31:0];
      addrMask = truncate(8'hE0);
      Bit#(32) temp = selectF(line, addr & addrMask);
      temp = reverseBytes(temp);
      Bit#(5) shift = 24 - truncate(addr);
      temp = temp >> shift;
      Bit#(32) mask = 32'hFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged Word (temp);
    end
    DoubleWord: begin
      Bit#(64) temp = selectF(line, addr & addrMask);
      return tagged DoubleWord (reverseBytes(temp));
    end
    DoubleWordLeft: begin
      Bit#(64) orig = oldReg;
      addrMask = truncate(8'hC0);
      Bit#(64) temp = selectF(line, addr & addrMask);
      temp = reverseBytes(temp);
      Bit#(6) shift = truncate(addr);
      temp = temp << shift;
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord (temp);
    end
    DoubleWordRight: begin
      Bit#(64) orig = oldReg;
      addrMask = truncate(8'hC0);
      Bit#(64) temp = selectF(line, addr & addrMask);
      temp = reverseBytes(temp);
      Bit#(6) shift = 56 - truncate(addr);
      temp = temp >> shift;
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord (temp);
    end
    Line: begin
      Bit#(CheriDataWidth) temp = reverseBytes(line);
      return tagged Line (temp);
    end
  endcase
endfunction

function Address alignAddress(Address addr, MemSize size);
  case(size)
    Byte:
      return addr;
    HalfWord: 
      return addr & signExtend(~8'b1);
    Word,WordLeft,WordRight: 
      return addr & signExtend(~8'b11);
    DoubleWord,DoubleWordLeft,DoubleWordRight: 
      return addr & signExtend(~8'b111);
    Line: 
      return addr & signExtend(~8'b11111);
  endcase
endfunction

module mkMIPSMemory#(Bit#(16) coreId, CP0Ifc tlb)(MIPSMemory);
  FIFOF#(CacheRequestInstT)   iCacheFetch  <- mkBypassFIFOF;
  FIFOF#(CacheRequestInstT)   iCacheOp  <- mkBypassFIFOF;

  FIFOF#(CacheRequestDataT) dCacheStd  <- mkBypassFIFOF;

  `ifndef MULTI
    MergeIfc#(2)          theMemMerge  <- mkMergeFast(); // This module merges the Memory interfaces of the instruction and data caches.
    `ifdef USECAP
      TagCacheIfc         tagCache  <- mkTagCache();
    `endif
  `endif
  
  `ifndef DCACHECORE
    CacheDataIfc            dCache    <- mkDCacheClassic(coreId);
  `else
    CacheDataIfc            dCache    <- mkDCache(truncate({coreId,1'b1}));
  `endif

  `ifndef ICACHECORE
    CacheInstIfc            iCache    <- mkICacheClassic(truncate({coreId,1'b0}));
  `else
    CacheInstIfc            iCache    <- mkICache(coreId);
  `endif
  `ifndef MULTI         // L2Cache is instantiated in Multicore.bsv
    L2CacheIfc          l2Cache   <- mkL2Cache();
  `endif
  
  `ifndef MULTI
    //OrderingLimiterIfc ordLim <- mkOrderingLimiter();
    mkConnection(iCache.memory, theMemMerge.slave[0]);
    mkConnection(dCache.memory, theMemMerge.slave[1]);
    mkConnection(theMemMerge.merged, l2Cache.cache);
    //mkConnection(l2Cache.memory, ordLim.slave);
    let topMemIfc = l2Cache.memory;
    `ifdef USECAP
      mkConnection(l2Cache.memory, tagCache.cache);
      topMemIfc = tagCache.memory;
    `endif
  `else
    let topImem = iCache.memory;
    let topDmem = dCache.memory;
  `endif

  rule iCacheOperation(iCacheOp.notEmpty);
    CacheRequestInstT cReq = iCacheOp.first;
    iCache.put(cReq);
    iCacheOp.deq;
    debug($display("Submitting Instruction Cache Operation.  Index = %X at time %t", cReq.tr.addr,  $time()));
  endrule

  rule iCacheInstructionFetch(iCacheFetch.notEmpty && !iCacheOp.notEmpty);
    iCacheFetch.deq;
    CacheRequestInstT cReq = iCacheFetch.first;
    cReq.tr <- tlb.tlbLookupInstruction.response.get();
    iCache.put(cReq);
    debug($display("<%0t> <Memory.IFetch> Submitting Instruction Fetch.  Index = %X", $time, cReq.tr.addr));
    //trace($display("<%0t> <Memory.IFetch> Submitting Instruction Fetch.  Index = %X", $time, cReq.tr.addr));
  endrule

  //(* descending_urgency = "dCacheStdAccess, dCache_core_runLookup" *)
  rule dCacheStdAccess;
      dCacheStd.deq();
      CacheRequestDataT req = dCacheStd.first;
      req.tr <- tlb.tlbLookupData.response.get();
      dCache.put(req);
  endrule

  interface DataMemory dataMemory;
    method Action startRead(Bit#(64) addr, MemSize size, Bool ll, Bool cap, InstId instId, Epoch epoch, Bool fromDebug);
      Exception exception = None;

      CacheRequestDataT req = CacheRequestDataT{
            `ifdef USECAP
              capability: cap,
            `endif
            cop: CacheOperation{inst: Read, indexed: False, cache: DCache},
            memSize: size,
            byteEnable: ?,
            data: ?,
            instId: instId,
            epoch: epoch,
            tr: ?
         };
      //dCacheStd.enq(tuple2(req,False));
      dCacheStd.enq(req);

      tlb.tlbLookupData.request.put(TlbRequest{
          addr: alignAddress(addr,size),
          write: False,
          ll: ll,
          exception: exception,
          fromDebug: fromDebug,
          instId: instId
        });

      debug($display("Starting read to block ram from address %X at time %t", addr[12:3],  $time()));
    endmethod
    
    method Action startNull(InstId instId, Epoch epoch);
      dCacheStd.enq(CacheRequestDataT{
            `ifdef USECAP
              capability: False,
            `endif
            cop: CacheOperation{inst: CacheNop, indexed: False, cache: DCache},
            byteEnable: ?,
            memSize: ?,
            data: ?,
            instId: instId,
            epoch: epoch,
            tr: ?
         });

      tlb.tlbLookupData.request.put(TlbRequest{
          addr: ?,
          write: False,
          ll: False,
          exception: DTLBL,
          fromDebug: False,
          instId: instId
        });
    endmethod

    method Action startWrite(Bit#(64) addr, SizedWord sizedData, MemSize size, InstId instId, Epoch epoch, Bool fromDebug, Bool storeConditional);
      Bit#(CheriDataWidth) writeLine = ?;
      Bit#(TDiv#(CheriDataWidth,8)) byteMask = 0;
      Exception exception = None;
      Bit#(64) data = ?;
      if (sizedData matches tagged DoubleWord .d) data = d;
      Bool cap = False;
      CheriPhyByteOffset offset = truncate(addr);
      // These are only used in Left/Right operations and make the width of selectors unambigious.
      CheriPhyByteOffset maskSelect = {truncateLSB(offset), 3'b0};
      CheriPhyBitOffset  dataSelect = {truncateLSB(offset), 6'b0};
      
      case(size)
        Byte: begin
          writeLine = insert(reverseBytes(data[ 7:0]), {offset, 3'b0});
          byteMask  = insert(1'b1, offset);
        end
        HalfWord: begin
          writeLine = insert(reverseBytes(data[15:0]), {offset, 3'b0});
          byteMask  = insert(2'b11, offset);
        end
        Word: begin
          writeLine = insert(reverseBytes(data[31:0]), {offset, 3'b0});
          byteMask  = insert(4'hF, offset);
        end
        WordLeft: begin
          data[31:0] = reverseBytes(data[31:0]);
          Bit#(5) shift = {truncate(offset),3'b0};
          data[31:0] = data[31:0] << shift;
          Bit#(4) mask = 4'hF;
          mask = mask << offset[1:0];
          dataSelect = {truncateLSB(offset), 5'b0};
          writeLine = insert(data[31:0], dataSelect);
          maskSelect = {truncateLSB(offset), 2'b0};
          byteMask  = insert(mask, maskSelect);
        end
        WordRight: begin
          data[31:0] = reverseBytes(data[31:0]);
          Bit#(5) shift = {(2'd3 - truncate(offset)),3'b0};
          data[31:0] = data[31:0] >> shift;
          Bit#(4) mask = 4'hF;
          mask = mask >> (2'd3 - offset[1:0]);
          dataSelect = {truncateLSB(offset), 5'b0};
          writeLine = insert(data[31:0], dataSelect);
          maskSelect = {truncateLSB(offset), 2'b0};
          byteMask  = insert(mask, maskSelect);
        end
        DoubleWord: begin
          writeLine = insert(reverseBytes(data), {offset, 3'b0});
          byteMask  = insert(8'hFF, offset);
        end
        DoubleWordLeft: begin
          data = reverseBytes(data);
          Bit#(6) shift = {3'b0,truncate(offset)}*6'h8;
          writeLine = insert(data << shift, dataSelect);
          Bit#(8) mask  = 8'hFF;
          mask = mask << offset[2:0];
          byteMask  = insert(mask, maskSelect);
        end
        DoubleWordRight: begin
          data = reverseBytes(data);
          Bit#(6) shift = (6'd7 - {3'b0,truncate(offset)})*6'h8;
          writeLine = insert(data >> shift, dataSelect);
          Bit#(8) mask  = 8'hFF;
          mask = mask >> (3'd7 - offset[2:0]);
          byteMask  = insert(mask, maskSelect);
        end
        Line: begin
          if (sizedData matches tagged Line .l) writeLine = l;
          `ifdef USECAP
            else if (sizedData matches tagged CapLine .l) begin
              writeLine = l;
              cap = True;
            end
          `endif
          writeLine = reverseBytes(writeLine);
          byteMask = signExtend(4'hF);
        end
      endcase
      debug($display("Writing %X %X to memory at address %X at time %t", writeLine, byteMask,
          addr, $time()));

      CacheInst copInst = Write;
      `ifdef MULTI 
        if (storeConditional) begin 
          copInst = StoreConditional; 
        end 
      `endif

      CacheRequestDataT req = CacheRequestDataT{
            `ifdef USECAP
              capability: cap,
            `endif
            cop: CacheOperation{inst: copInst, indexed: False, cache: DCache},
            byteEnable: byteMask,
            memSize: size,
            data: writeLine,
            instId: instId,
            epoch: epoch,
            tr: ?
          };
      //dCacheStd.enq(tuple2(req,False));
      dCacheStd.enq(req);

      //iCache.invalidate(addr[11:0]); // Ensure Coherence

      tlb.tlbLookupData.request.put(TlbRequest{
        addr: alignAddress(addr,size),
        write: True,
        ll: False,
        fromDebug: fromDebug,
        exception: exception,
        instId: instId
      });
    endmethod

    method Action startCacheOp(Bit#(64) addr, CacheOperation cop, InstId id, Epoch epoch) if (iCacheOp.notFull);
      Bit#(64) writeLine = ?;
      Bit#(8) byteMask = 0;
      debug($display("CacheOp at address %X at time %t", addr, $time()));
      // An invalidation of the Level2 will go through the Data cache.
      if (cop.cache == DCache || cop.cache == L2) begin
        debug($display("Memory: Cache Operation DCache||L2"));
        dCacheStd.enq(CacheRequestDataT{
            `ifdef USECAP
              capability: False,
            `endif
            epoch: epoch,
            cop: cop,
            byteEnable: signExtend(4'h0),
            memSize: ?,
            data: ?,
            instId: id,
            tr: ?
           });
        if (cop.indexed) addr[63:56] = 8'h90;
        tlb.tlbLookupData.request.put(TlbRequest{
            addr: addr,
            write: False,
            ll: False,
            exception: DTLBL,
            fromDebug: False,
            instId: id
          });
      end else if (cop.cache == ICache) begin
        debug($display("Memory: Cache Operation ICache"));
        dCacheStd.enq(CacheRequestDataT{
            `ifdef USECAP
              capability: False,
            `endif
            cop: CacheOperation{inst: CacheNop, indexed: False, cache: DCache},
            byteEnable: ?,
            memSize: ?,
            data: ?,
            instId: id,
            epoch: epoch,
            tr: ?
        });
        tlb.tlbLookupData.request.put(TlbRequest{
            addr: ?,
            write: False,
            ll: False,
            exception: DTLBL,
            fromDebug: False,
            instId: id
          });
        TlbResponse tlb_rsp = ?;
        tlb_rsp.addr={addr[39:3],3'b0};
        tlb_rsp.exception=DTLBL;
        iCacheOp.enq(CacheRequestInstT{
          cop: cop,
          instId: id,
          tr: tlb_rsp
         });
      end
    endmethod

   `ifndef MULTI
      method ActionValue#(CacheResponseDataT) getResponse(MIPSReg oldReg, Bool sExtend, Bit#(8) addr, MemSize size, Bool exception, Bool cacheOpResponse);
    `else 
      method ActionValue#(CacheResponseDataT) getResponse(MIPSReg oldReg, Bool sExtend, Bit#(8) addr, MemSize size, Bool exception, Bool scStatus, Bool cacheOpResponse); 
    `endif 
      CacheResponseDataT resp <- dCache.getResponse();

      `ifdef MULTI 
        if (!scStatus) begin 
      `endif
        if (!cacheOpResponse) begin 
          if (resp.data matches tagged Line .l) begin
            CheriPhyByteOffset byteOffset = truncate(addr);
            resp.data = selectWithSize(oldReg, l, {byteOffset, 3'b0}, size);
          end
          `ifdef USECAP
            if (resp.data matches tagged Line .l &&& resp.capability==True)
              resp.data = tagged CapLine l;
          `endif

          debug($display("shiftAmount: %d, readresult: %x", {addr[2:0], 3'b0}, resp.data));

          let extendFN = (sExtend) ? signExtend : zeroExtend;

          case (resp.data) matches
            tagged Byte       .b  : resp.data = tagged DoubleWord extendFN(b);
            tagged HalfWord   .hw : resp.data = tagged DoubleWord extendFN(hw);
            tagged Word       .w  : resp.data = tagged DoubleWord extendFN(w);
            tagged DoubleWord .dw : resp.data = tagged DoubleWord extendFN(dw);
          endcase
        end
      `ifdef MULTI 
        end 
      `endif 
      return resp;
    endmethod
  endinterface

  interface InstructionMemory instructionMemory;
    method Action reqInstruction(Address addr, InstId   instId) if (iCacheFetch.notFull);
      Exception exception = (addr[1:0] == 0) ? None:IADEL;
      CacheRequestInstT req = CacheRequestInstT{
          cop: CacheOperation{inst: Read, indexed: False, cache: ICache},
          tr: ?,
          instId: instId
        };
      iCacheFetch.enq(req);

      tlb.tlbLookupInstruction.request.put(TlbRequest{
          addr: addr,
          write: False,
          fromDebug: False,
          ll: False,
          exception: exception,
          instId: instId
        });
    endmethod

    method ActionValue#(CacheResponseInstT) getInstruction();
      CacheResponseInstT resp <- iCache.getRead();
      return resp;
    endmethod

    method Action debugDump = iCache.debugDump;
  endinterface

  interface MemConfiguration configuration;
    method iCacheGetConfig = iCache.getConfig;
    method dCacheGetConfig = dCache.getConfig;
  endinterface

  `ifndef MULTI
    interface memory = topMemIfc;
  `else
    interface invalidateICache = iCache.invalidate;
    interface invalidateDCache = dCache.invalidate;
    interface imemory = topImem; 
    interface dmemory = topDmem; 
  `endif

  method nextWillCommit = dCache.nextWillCommit;
endmodule
