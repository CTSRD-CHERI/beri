/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2011 Steven J. Murdoch
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Jonathan Woodruff
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
import Vector:: *;
`ifndef GENERICL1
import ICache :: *;
import DCache :: *;
`else
import GenericICache :: *;
import GenericDCache :: *;
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
`endif

interface DataMemory;
  method Action startRead(Bit#(64) addr, MemSize size, Bool ll, Bool cap, InstId instId, Epoch epoch, Bool fromDebug);
  method Action startWrite(Bit#(64) addr, SizedWord sizedData, MemSize size, InstId instId, Epoch epoch, Bool fromDebug, Bool storeConditional);
  method Action startNull(InstId instId, Epoch epoch);
  method Action startCacheOp(Bit#(64) addr, CacheOperation cop, InstId id, Epoch epoch);
  `ifndef MULTI
    method ActionValue#(CacheResponseDataT) getResponse(MIPSReg oldReg, Bool signExtend, Bit#(8) addr, MemSize size, Bool exception);
  `else 
    method ActionValue#(CacheResponseDataT) getResponse(MIPSReg oldReg, Bool signExtend, Bit#(8) addr, MemSize size, Bool exception, Bool scStatus);
  `endif
  //method ActionValue#(Exception)        confirmWrite(Bool exception);
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

`ifdef CAP
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
  `ifdef COP3
    interface Server#(CoProMemAccess, CoProReg) cop3Memory;
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

//XXX ndave: remove this loop in favor of simpler folds
function Bit#(lineSize) insert(Bit#(lineSize) line, Bit#(insertSize) toInsert, Bit#(addrSize) addr)
  //Needed to satisfy type system I think it's just saying insertSize < lineSize
  provisos(Add#(a__, insertSize, lineSize),
    Log#(lineSize, addrSize));


  Integer i;
  Integer insertSizeI = valueOf(insertSize);

  Bit#(lineSize) result = 0;
  Bit#(insertSize) partResult = 0;

  for(i = 0;i < valueOf(lineSize); i = i + insertSizeI) begin
    if(addr == fromInteger(i)) begin
      result[i + insertSizeI - 1 : i] = toInsert;
    end else begin
      partResult = line[i + insertSizeI - 1: i];
      result[i + insertSizeI - 1: i] = partResult;
    end
  end

  return result;
endfunction

function Bit#(outSize) selectF(Bit#(lineSize) val, Bit#(lineAddrSize) off) provisos (Add#(a__, outSize, lineSize));
  return truncate(val >> off);
endfunction

function Bit#(n) reverseBytes(Bit#(n) x) provisos (Mul#(8,n8,n));
  Vector#(n8,Bit#(8)) vx = unpack(x);
  return pack(Vector::reverse(vx));
endfunction

function SizedWord selectWithSize(Bit#(64) oldReg, Line line, Bit#(8) addr, MemSize size);

  // A line is 256 bits.
  // Addr is the BIT ADDRESS of the desired data item.
  case(size)
    Byte:
      return tagged Byte selectF(line, addr & 8'hF8);
    HalfWord: begin
      Bit#(16) temp = selectF(line, addr & 8'hF0);
      return tagged HalfWord (reverseBytes(temp));
    end
    Word: begin
      Bit#(32) temp = selectF(line, addr & 8'hE0);
      return tagged Word (reverseBytes(temp));
    end
    WordLeft: begin
      Bit#(32) orig = oldReg[31:0];
      Bit#(32) temp = selectF(line, addr & 8'hE0);
      temp = reverseBytes(temp);
      Bit#(5) shift = addr[4:0];
      temp = temp << shift;
      Bit#(32) mask = 32'hFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged Word (temp);
    end
    WordRight: begin
      Bit#(32) orig = oldReg[31:0];
      Bit#(32) temp = selectF(line, addr & 8'hE0);
      temp = reverseBytes(temp);
      Bit#(5) shift = 24 - addr[4:0];
      //debug($display("Shift: %d, orig: %x, temp: %x", shift, orig, temp));
      temp = temp >> shift;
      Bit#(32) mask = 32'hFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged Word (temp);
    end
    DoubleWord: begin
      Bit#(64) temp = selectF(line, addr & 8'hC0);
      return tagged DoubleWord (reverseBytes(temp));
    end
    DoubleWordLeft: begin
      Bit#(64) orig = oldReg;
      Bit#(64) temp = selectF(line, addr & 8'hC0);
      temp = reverseBytes(temp);
      Bit#(6) shift = addr[5:0];
      temp = temp << shift;
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord (temp);
    end
    DoubleWordRight: begin
      Bit#(64) orig = oldReg;
      Bit#(64) temp = selectF(line, addr & 8'hC0);
      temp = reverseBytes(temp);
      Bit#(6) shift = 56 - addr[5:0];
      temp = temp >> shift;
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord (temp);
    end
    Line: begin
      Bit#(256) temp = reverseBytes(line);
      return tagged Line (temp);
    end
  endcase
endfunction

`ifdef COP3
  `define Coprocessors
`endif

module mkMIPSMemory#(Bit#(16) coreId, CP0Ifc tlb)(MIPSMemory);
  FIFOF#(CacheRequestInstT)   iCacheFetch  <- mkBypassFIFOF;
  FIFOF#(CacheRequestInstT)   iCacheOp  <- mkBypassFIFOF;

  FIFOF#(CacheRequestDataT) dCacheStd  <- mkBypassFIFOF;

  `ifndef MULTI
    MergeIfc#(2)            theMemMerge  <- mkMergeFast(); // This module merges the Memory interfaces of the instruction and data caches.
  `endif
  `ifdef Coprocessors
    MergeIfc#(2)          dramMerge <- mkMergeFast();
  `endif
  `ifdef CAP
    `ifndef MULTI         // Tagcache is instantiated in Multicore.bsv
      TagCacheIfc         tagCache  <- mkTagCache();
    `endif
  `endif
  `ifndef GENERICL1
  CacheInstIfc            iCache    <- mkICache(coreId);
  CacheDataIfc            dCache    <- mkDCache(coreId);
  `else
  //CacheInstIfc#(1,512,32)   iCache  <- mkGenericICache(coreId);
  CacheInstIfc#(4,128,32)   iCache  <- mkGenericICache(coreId);
  //CacheDataIfc#(1,512,32)   dCache  <- mkGenericDCache(coreId);
  CacheDataIfc#(4,128,32)   dCache  <- mkGenericDCache(coreId);
  `endif
  `ifndef MICRO
    `ifndef MULTI         // L2Cache is instantiated in Multicore.bsv
      L2CacheIfc          l2Cache   <- mkL2Cache();
    `endif
  `endif

  `ifndef MULTI
    mkConnection(iCache.memory, theMemMerge.server[0]);
    mkConnection(dCache.memory, theMemMerge.server[1]);
  `endif
  
  `ifdef MICRO
    `ifdef Coprocessor
      mkConnection(theMemMerge.merged, dramMerge.server[0]);
      `ifdef CAP
        // CAP, MICRO, Coprocessors
        mkConnection(dramMerge.merged, tagCache.cache);
      `endif
    `else
      `ifdef CAP
        // CAP, MICRO, !Coprocessors
        mkConnection(theMemMerge.merged, tagCache.cache);
      `endif
    `endif
  `else // !MICRO
    `ifndef MULTI // All connections are made in Multicore.bsv
      mkConnection(theMemMerge.merged, l2Cache.cache);
      `ifdef Coprocessors
        mkConnection(l2Cache.memory, dramMerge.server[0]);
        `ifdef CAP
          // CAP, !MICRO, Coprocessors
          mkConnection(dramMerge.merged, tagCache.cache);
        `endif
      `else
        `ifdef CAP
          // CAP, !MICRO, !Coprocessors
          mkConnection(l2Cache.memory, tagCache.cache);
        `endif
      `endif
    `endif
  `endif

  `ifdef CAP
    `ifndef MULTI
      let topMemIfc = tagCache.memory;
    `else // MULTI defined
      let topImem = iCache.memory;
      let topDmem = dCache.memory;
    `endif
  `else
    `ifdef Coprocessors
      let topMemIfc = dramMerge.merged;
    `else
      `ifdef MICRO
        let topMemIfc = theMemMerge.merged;
      `else // !CAP && !MICRO && !MULTI
        `ifndef MULTI
          let topMemIfc = l2Cache.memory;
        `else // !CAP && !MICRO && MULTI 
          let topImem = iCache.memory;
          let topDmem = dCache.memory;
        `endif
      `endif
    `endif
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
            `ifdef CAP
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
          addr: addr,
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
            `ifdef CAP
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
      Bit#(256) writeLine = ?;
      Bit#(32) byteMask = 0;
      Exception exception = None;
      Bit#(64) data = ?;
      if (sizedData matches tagged DoubleWord .d) data = d;
      Bool cap = False;
     
      case(size)
        Byte: begin
          writeLine = insert(writeLine, reverseBytes(data[ 7:0]), {addr[4:0], 3'b0});
          byteMask  = insert(byteMask, 1'b1, addr[4:0]);
        end
        HalfWord: begin
          writeLine = insert(writeLine, reverseBytes(data[15:0]), {addr[4:1], 4'b0});
          byteMask  = insert(byteMask, 2'b11, {addr[4:1], 1'b0});
        end
        Word: begin
          writeLine = insert(writeLine, reverseBytes(data[31:0]), {addr[4:2]  , 5'b0});
          byteMask  = insert(byteMask, 4'hF, {addr[4:2], 2'b0});
        end
        WordLeft: begin
          data[31:0] = reverseBytes(data[31:0]);
          Bit#(5) shift = {addr[1:0],3'b0};
          data[31:0] = data[31:0] << shift;
          Bit#(4) mask = 4'hF;
          mask = mask << addr[1:0];
          writeLine = insert(writeLine, data[31:0], {addr[4:2], 5'b0});
          byteMask  = insert(32'h0, mask, {addr[4:2], 2'b0});
        end
        WordRight: begin
          data[31:0] = reverseBytes(data[31:0]);
          Bit#(5) shift = {(2'd3 - addr[1:0]),3'b0};
          data[31:0] = data[31:0] >> shift;
          Bit#(4) mask = 4'hF;
          mask = mask >> (2'd3 - addr[1:0]);
          writeLine = insert(writeLine, data[31:0], {addr[4:2], 5'b0});
          byteMask  = insert(32'h0, mask, {addr[4:2], 2'b0});
        end
        DoubleWord: begin
          writeLine = insert(writeLine, reverseBytes(data), {addr[4:3], 6'b0});
          byteMask  = insert(32'h0, 8'hFF, {addr[4:3], 3'b0});
        end
        DoubleWordLeft: begin
          data = reverseBytes(data);
          Bit#(6) shift = {3'b0,addr[2:0]}*6'h8;
          writeLine = insert(writeLine, data << shift, {addr[4:3], 6'b0});
          Bit#(8) mask  = 8'hFF;
          mask = mask << addr[2:0];
          byteMask  = insert(32'h0, mask, {addr[4:3], 3'b0});
        end
        DoubleWordRight: begin
          data = reverseBytes(data);
          Bit#(6) shift = (6'd7 - {3'b0,addr[2:0]})*6'h8;
          writeLine = insert(writeLine, data >> shift, {addr[4:3], 6'b0});
          Bit#(8) mask  = 8'hFF;
          mask = mask >> (3'd7 - addr[2:0]);
          byteMask  = insert(32'h0, mask, {addr[4:3], 3'b0});
        end
        Line: begin
          if (sizedData matches tagged Line .l) writeLine = l;
          `ifdef CAP
            else if (sizedData matches tagged CapLine .l) begin
              writeLine = l;
              cap = True;
            end
          `endif
          writeLine = reverseBytes(writeLine);
          byteMask = 32'hFFFFFFFF;
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
            `ifdef CAP
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
        addr: addr,
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
      // An invalidation of Data will also invalidate Level2.
      if (cop.cache == DCache || cop.cache == L2) begin
        dCacheStd.enq(CacheRequestDataT{
            `ifdef CAP
              capability: False,
            `endif
            epoch: epoch,
            cop: cop,
            byteEnable: 32'h0,
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
        dCacheStd.enq(CacheRequestDataT{
            `ifdef CAP
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
        tlb_rsp.exception=None;
        tlb_rsp.exception=DTLBL;
        iCacheOp.enq(CacheRequestInstT{
          cop: cop,
          instId: id,
          tr: tlb_rsp
         });
      end
    endmethod

   `ifndef MULTI
      method ActionValue#(CacheResponseDataT) getResponse(MIPSReg oldReg, Bool sExtend, Bit#(8) addr, MemSize size, Bool exception);
    `else 
      method ActionValue#(CacheResponseDataT) getResponse(MIPSReg oldReg, Bool sExtend, Bit#(8) addr, MemSize size, Bool exception, Bool scStatus); 
    `endif 
      CacheResponseDataT resp <- dCache.getResponse();

      `ifdef MULTI 
        if (!scStatus) begin 
      `endif 
        //if (dataByte.notEmpty && dataSize.notEmpty) begin
        if (resp.data matches tagged Line .l)
          resp.data = selectWithSize(oldReg, l, {addr[4:0], 3'b0}, size);
        `ifdef CAP
          if (resp.data matches tagged Line .l &&& resp.capability==True)
            resp.data = tagged CapLine l;
        `endif

        debug($display("shiftAmount: %d, readresult: %x", {addr[2:0], 3'b0}, resp.data));
        //end else readResult = tagged DoubleWord (reverseBytes(resp.data));

        let extendFN = (sExtend) ? signExtend : zeroExtend;

        case (resp.data) matches
          tagged Byte       .b  : resp.data = tagged DoubleWord extendFN(b);
          tagged HalfWord   .hw : resp.data = tagged DoubleWord extendFN(hw);
          tagged Word       .w  : resp.data = tagged DoubleWord extendFN(w);
          tagged DoubleWord .dw : resp.data = tagged DoubleWord extendFN(dw);
        endcase
      `ifdef MULTI 
        end  
      `endif 

      return resp;
    endmethod
    /*
    method ActionValue#(Exception) confirmWrite(Bool exception);
      Exception exceptionResponse <- dCache.getWrite(exception);
      return exceptionResponse;
    endmethod
    */
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

  `ifdef MULTI
    interface invalidateICache = iCache.invalidate;
    interface invalidateDCache = dCache.invalidate; 
  `endif

  `ifdef COP3
    interface Server cop3Memory;
      interface Put request;
        method Action put(CoProMemAccess copPacket);
          cop3Packets.enq(copPacket);
          TlbRequest tr = TlbRequest{
            addr: copPacket.address,
            write: copPacket.memOp==Write,
            ll: False,
            exception: None,
            instId: ? // This should be fixed
          };
          tlb.tlbLookupCoprocessors[valueOf(Cop3TLBNum)].request.put(tr);
        endmethod
      endinterface
      interface Get response;
        method ActionValue#(CoProReg) get();
          MemoryResponse#(256) data <- dramMerge.server[1].response.get();
          MemoryResponse#(256) resp = reverseBytes(data);
          return unpack(resp);
        endmethod
      endinterface
    endinterface
  `endif

  `ifndef MULTI
    interface memory = topMemIfc;
  `else
    interface imemory = topImem; 
    interface dmemory = topDmem; 
  `endif

  method Action nextWillCommit(Bool nextCommitting);
    dCache.nextWillCommit(nextCommitting);
  endmethod
endmodule
