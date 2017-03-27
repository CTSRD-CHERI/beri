/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2014 Jonathan Woodruff
 * Copyright (c) 2011 Steven J. Murdoch
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert N. M. Watson
 * Copyright (c) 2013-2016 Alexandre Joannou
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
import DReg :: *;
import ConfigReg :: *;
import Debug::*;
import FIFO :: *;
import FIFOF :: *;
import SpecialFIFOs::*;
import Vector::*;
import BuildVector::*;
import DCache :: *;
import ICache :: *;
import MemTypes :: *;
import Merge :: *;
`ifndef MICRO
  `ifndef CHERIOS
      import L2Cache :: *;
      import TLB :: *;
      import CP0 :: *;
  `endif // CHERIOS
`endif
import GetPut :: *;
`ifdef CAP
  import CapCop :: *;
  `define USECAP
`elsif CAP128
  import CapCop128 :: *;
  `define USECAP
`elsif CAP64
  import CapCop64 :: *;
  `define USECAP
`endif
`ifdef USECAP
  import TagController:: *;
`endif
`ifdef PFTCH
  import Prefetcher :: *;
`endif
`ifdef STATCOUNTERS
  import MasterSlaveStats :: *;
  import StatCounters :: *;
  import DefaultValue::*;
  import Debug::*;
`endif

interface DataMemory;
  //method Action startRead(Bit#(64) addr, MemSize size, Bool ll, Bool cap, InstId instId, Epoch epoch, Bool fromDebug);
  //method Action startWrite(Bit#(64) addr, SizedWord sizedData, MemSize size, InstId instId, Epoch epoch, Bool fromDebug, Bool storeConditional);
  //method Action startNull(InstId instId, Epoch epoch);
  //method Action startCacheOp(Bit#(64) addr, CacheOperation cop, InstId id, Epoch epoch);
  method Action startMem(MemOp mop, Bit#(64) addr, CacheOperation cop, SizedWord sizedData, MemSize size, Bool ll, Bool cap, InstId instId, Epoch epoch, Bool fromDebug, Bool storeConditional);
  //method Bool consistent;
  //method Action allConsistent(Bool ac);
  method ActionValue#(MemResponseDataT) getResponse(MIPSReg oldReg, Bool signExtend, Bit#(8) addr, MemSize size, Bool exception, Bool cacheOpResponse);
endinterface

interface InstructionMemory;
  method Action reqInstruction(Address addr, InstId   instId, InstructionT inst);
  method ActionValue#(CacheResponseInstT) getInstruction();
endinterface

interface MemConfiguration;
  method L1ChCfg dCacheGetConfig();
  method L1ChCfg iCacheGetConfig();
endinterface

interface MIPSMemory;
  interface DataMemory dataMemory;
  interface InstructionMemory instructionMemory;
  interface MemConfiguration configuration;
  `ifdef COP1
    interface Server#(CoProMemAccess, CoProReg) cop1Memory;
  `endif
  `ifdef MULTI
    method Action invalidateICache(PhyAddress addr); 
    method Action invalidateDCache(PhyAddress addr); 
    method ActionValue#(Bool) getInvalidateDone;
    interface Master#(CheriMemRequest, CheriMemResponse) dmemory;
    interface Master#(CheriMemRequest, CheriMemResponse) imemory;
  `else
    interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `endif
  method Action nextWillCommit(Bool commiting);
  `ifdef STATCOUNTERS
    interface StatCounters statCounters;
  `endif
endinterface

typedef struct {
  Exception exception;
  InstId    instId;
} ExceptionAndId deriving (Bits, Eq);

function Bit#(lineSize) insert(Bit#(insertSize) toInsert, Bit#(addrSize) addr)
  provisos(Add#(a__, insertSize, lineSize)); 
  return zeroExtend(toInsert) << addr;
endfunction

function Bit#(n) rotateAndReverseBytes(Bit#(n) x, Bit#(TSub#(TLog#(n),3)) rotate)
  provisos (Mul#(8,n8,n), Log#(n8, TSub#(TLog#(n), 3)));
  // Rotate right by shifting two copies right.
  // should be Bit#(TMul#(n,2)), but bsc chokes.
  let doubleWide = {x,x};
  doubleWide = doubleWide >> {rotate,3'b0};
  Vector#(n8,Bit#(8)) vx = unpack(truncate(doubleWide));
  return pack(Vector::reverse(vx));
endfunction

function Word selectWithSize(Bit#(64) oldReg, Line line, Bit#(3) addr, MemSize size, Bool sExtend);

  // Addr is the BIT ADDRESS of the desired data item.
  Bit#(6) naddr  = {addr,3'b0};
  // Shift amount address that will take into account Left and Right loads
  Bit#(3) snaddr = addr;
  if (size==WordRight)            snaddr = snaddr - 3;
  else if (size==DoubleWordRight) snaddr = snaddr - 7;
  let extendFN = (sExtend) ? signExtend : zeroExtend;
  Bit#(64) doubleWord = truncate(line);
  Bit#(64) shiftedLine = truncateLSB(rotateAndReverseBytes(doubleWord, snaddr));
  case(size)
    Byte: begin
      Bit#(8) temp = truncateLSB(shiftedLine);
      return extendFN(temp);
    end
    HalfWord: begin
      Bit#(16) temp = truncateLSB(shiftedLine);
      return extendFN(temp);
    end
    Word: begin
      Bit#(32) temp = truncateLSB(shiftedLine);
      return extendFN(temp);
    end
    WordLeft: begin
      Bit#(32) orig = oldReg[31:0];
      Bit#(32) temp = truncateLSB(shiftedLine);
      Bit#(5) shift = truncate(naddr);
      Bit#(32) mask = 32'hFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return extendFN(temp);
    end
    WordRight: begin
      Bit#(32) orig = oldReg[31:0];
      Bit#(32) temp = truncateLSB(shiftedLine);
      Bit#(5) shift = 24 - truncate(naddr);
      Bit#(32) mask = 32'hFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return extendFN(temp);
    end
    // This is the default case
    /*DoubleWord: begin
      Bit#(64) temp = truncateLSB(shiftedLine);
      return temp;
    end*/
    DoubleWordLeft: begin
      Bit#(64) orig = oldReg;
      Bit#(6) shift = truncate(naddr);
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF << shift;
      return (shiftedLine & mask) | (orig & ~mask);
    end
    DoubleWordRight: begin
      Bit#(64) orig = oldReg;
      Bit#(6) shift = 56 - truncate(naddr);
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF >> shift;
      return (shiftedLine & mask) | (orig & ~mask);
    end
    default: begin
      return shiftedLine;
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
    `ifdef USECAP
      CapWord: begin
        Bit#(TLog#(CapBytes)) ones = -1;
        return addr & ~zeroExtend(ones);
      end
    `endif
  endcase
endfunction

module mkMIPSMemory#(Bit#(16) coreId, CP0Ifc tlb)(MIPSMemory);
  Reg#(CacheRequestInstT)  iCacheFetch     <- mkConfigRegU;
  Reg#(Bool)               iCacheDelayed   <- mkConfigReg(False);
  FIFOF#(CacheRequestInstT) iCacheOp       <- mkUGSizedFIFOF(4);

  Reg#(CacheRequestDataT)  dCacheFetch     <- mkConfigRegU;
  Reg#(Bool)               dCacheDelayed   <- mkConfigReg(False);
  `ifdef STATCOUNTERS
    Reg#(MIPSMemEvents) mipsMemEvents <- mkConfigReg(defaultValue);
    Wire#(Bool) incByteRead   <- mkDWire(False);
    Wire#(Bool) incByteWrite  <- mkDWire(False);
    Wire#(Bool) incHWordRead  <- mkDWire(False);
    Wire#(Bool) incHWordWrite <- mkDWire(False);
    Wire#(Bool) incWordRead   <- mkDWire(False);
    Wire#(Bool) incWordWrite  <- mkDWire(False);
    Wire#(Bool) incDwordRead  <- mkDWire(False);
    Wire#(Bool) incDwordWrite <- mkDWire(False);
    `ifdef USECAP
    Wire#(Bool) incCapRead    <- mkDWire(False);
    Wire#(Bool) incCapWrite   <- mkDWire(False);
    `endif
    (* fire_when_enabled, no_implicit_conditions *)
    rule updateMipsMemEvents;
        mipsMemEvents <= MIPSMemEvents {
            id:             ?,
            incByteRead:	incByteRead,
            incByteWrite:	incByteWrite,
            incHWordRead:	incHWordRead,
            incHWordWrite:	incHWordWrite,
            incWordRead:	incWordRead,
            incWordWrite:	incWordWrite,
            incDwordRead:	incDwordRead,
            incDwordWrite:	incDwordWrite
            `ifdef USECAP
            ,
            incCapRead:	    incCapRead,
            incCapWrite:	incCapWrite
            `endif
        };
    endrule
  `endif

  // declare prefetcher when prefetch is turned on
  `ifdef PFTCH
    `ifdef CAPPFTCH
      `ifdef DCACHE_PFTCH
        PrefetcherIfc pftch <- mkCapPrefetcher(dcachePrefetch);
      `else
        PrefetcherIfc pftch <- mkCapPrefetcher(l2Prefetch);
      `endif
    `else
      `ifdef DCACHE_PFTCH
        PrefetcherIfc pftch <- mkSimplePrefetcher(dcachePrefetch);
      `else
        PrefetcherIfc pftch <- mkSimplePrefetcher(l2Prefetch);
      `endif
    `endif
  `endif

  `ifndef MULTI
    MergeIfc#(2)          theMemMerge  <- mkMergeFast(); // This module merges the Memory interfaces of the instruction and data caches.
    `ifdef USECAP
      TagControllerIfc    tagController <- mkTagController();
      `ifdef STATCOUNTERS
      MasterStats tagControllerMaster <- mkMasterStats(tagController.memory);
      let tagControllerMasterEvents = tagControllerMaster.events;
      let tagControllerMemory = tagControllerMaster.memory;
      `else
      let tagControllerMemory = tagController.memory;
      `endif
    `endif
  `endif
  
  CacheDataIfc            dCache    <- mkDCache(truncate({coreId,1'b1}));

  CacheInstIfc            iCache    <- mkICache(truncate({coreId,1'b0}));

  `ifndef MULTI         // L2Cache is instantiated in Multicore.bsv
      `ifndef CHERIOS
        L2CacheIfc          l2Cache   <- mkL2Cache();
        `ifdef STATCOUNTERS
        MasterStats l2CacheMaster <- mkMasterStats(l2Cache.memory);
        let l2CacheMasterEvents = l2CacheMaster.events;
        let l2CacheMemory = l2CacheMaster.memory;
        `else
        let l2CacheMemory = l2Cache.memory;
        `endif
      `endif // CHERIOS
  `endif

  `ifdef STATCOUNTERS
  `ifndef MULTI
  StatCounters statCnt <- mkStatCounters(
                            8, // output fifo depth
                            vec(
                            iCache.cacheEvents,                     // mapped to rdhwr 8
                            dCache.cacheEvents,                     // mapped to rdhwr 9
                            `ifndef CHERIOS
                              l2Cache.cacheEvents,                  // mapped to rdhwr 10
                            `else // CHERIOS
                              dfltCacheCoreEventGet,
                            `endif // CHERIOS
                            toGet(tagged MIPSMem_E mipsMemEvents),  // mapped to rdhwr 11
                            `ifdef USECAP
                              tagController.cacheEvents             // mapped to rdhwr 12
                            `else
                              dfltCacheCoreEventGet
                            `endif
                            ,l2CacheMasterEvents                    // mapped to rdhwr 13
                            `ifdef USECAP
                            ,tagControllerMasterEvents              // mapped to rdhwr 14
                            `endif
                            ));
  `endif
  `endif
  
  `ifndef MULTI
    mkConnection(iCache.memory, theMemMerge.slave[0]);
    mkConnection(dCache.memory, theMemMerge.slave[1]);
    `ifndef CHERIOS
        mkConnection(theMemMerge.merged, l2Cache.cache);
        let topMemIfc = l2CacheMemory;
    `else
        let topMemIfc = theMemMerge.merged;
    `endif // CHERIOS
    `ifdef USECAP
        `ifndef CHERIOS
          mkConnection(l2CacheMemory, tagController.cache);
        `else // CHERIOS
          mkConnection(theMemMerge.merged, tagController.cache);
        `endif // CHERIOS
        topMemIfc = tagControllerMemory;
    `endif
  `else
    let topImem = iCache.memory;
    let topDmem = dCache.memory;
  `endif

`ifndef CHERIOS
  rule feedICache(iCacheDelayed);
    CacheRequestInstT req = iCacheFetch;
    req.tr <- tlb.tlbLookupInstruction.response();
    iCache.put(req);
    debug2("memory", $display("<time %0t, core %0d, Memory> Delayed TLB lookup done! Submitting to iCache. ", $time, coreId, fshow(req.tr)));
    iCacheDelayed <= False;
  endrule
  rule feedDCache(dCacheDelayed);
    CacheRequestDataT req = dCacheFetch;
    req.tr <- tlb.tlbLookupData.response();
    dCache.put(req);
    dCacheDelayed <= False;
  endrule
`endif // CHERIOS
  
  rule iCacheOperation(iCacheOp.notEmpty && !iCacheDelayed);
    CacheRequestInstT cReq = iCacheOp.first;
    iCache.put(cReq);
    iCacheOp.deq;
    debug2("memory", $display("<time %0t, core %0d, Memory> Submitting Instruction Cache Operation.  Index = %X at time %t", 
                              $time, coreId, cReq.tr.addr,  $time()));
  endrule

  interface DataMemory dataMemory;
    method Action startMem(MemOp mop,
                           Bit#(64) addr,
                           CacheOperation cop,
                           SizedWord sizedData,
                           MemSize size,
                           Bool ll,
                           Bool cap,
                           InstId instId,
                           Epoch epoch,
                           Bool fromDebug,
                           Bool storeConditional
                          ) if (!dCacheDelayed);
      CacheRequestDataT req = CacheRequestDataT{
          `ifdef USECAP
            capability: False,
          `endif
          cop: CacheOperation{inst: CacheNop, indexed: False, cache: DCache},
          byteEnable: signExtend(4'h0),
          memSize: size,
          data: ?,
          instId: instId,
          epoch: epoch,
          tr: TlbResponse{
              valid: True,
              addr: truncate(addr),
              exception: None,
              write:False,
              ll:ll,
              cached:True,
              fromDebug:False,
              priv:Kernel,
              instId:instId
              `ifdef USECAP
                , noCapLoad: False,
                noCapStore: False
              `endif
            }
      };
      TlbRequest tlbReq = TlbRequest{
          addr: alignAddress(addr,size),
          write: mop==Write,
          ll: ll,
          fromDebug: fromDebug,
          exception: None,
          instId: instId
      };
      case (mop)
        Read: begin
          Bit#(TDiv#(CheriDataWidth,8)) byteMask = 0;
          CheriPhyByteOffset offset = truncate(addr);
          debug2("memory", $display("<time %0t, core %0d, Memory> Memory read request - addr:%x, ll:%x, cap:%x, MemSize:", $time, coreId, addr, ll, cap, fshow(size)));
          
          case(size)
            Byte:
              byteMask  = insert(1'b1, offset);
            HalfWord:
              byteMask  = insert(2'b11, offset);
            Word, WordLeft, WordRight: 
              byteMask  = insert(4'hF, offset);
            DoubleWord, DoubleWordLeft, DoubleWordRight: 
              byteMask  = insert(8'hFF, offset);
            `ifdef USECAP
              CapWord: begin
                Bit#(CapBytes) mask = -1;
                byteMask = insert(mask, offset);
              end
            `endif
          endcase
          `ifdef STATCOUNTERS
            case(size)
              Byte: begin
                  incByteRead  <= True;
                  debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incByteRead", $time));
              end
              HalfWord: begin
                  incHWordRead <= True;
                  debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incHWordRead", $time));
              end
              Word, WordLeft, WordRight: begin
                  incWordRead  <= True;
                  debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incWordRead", $time));
              end
              DoubleWord, DoubleWordLeft, DoubleWordRight: begin
                  incDwordRead <= True;
                  debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incDWordRead", $time));
              end
              `ifdef USECAP
              CapWord: begin
                  incCapRead   <= True;
                  debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incCapRead", $time));
              end
              `endif
            endcase
          `endif

          req = CacheRequestDataT{
                `ifdef USECAP
                  capability: cap,
                `endif
                cop: CacheOperation{inst: Read, indexed: False, cache: DCache},
                memSize: size,
                byteEnable: byteMask,
                data: ?,
                instId: instId,
                epoch: epoch,
                tr: ?
            };
          `ifdef PFTCH
            pftch.spyCacheReq(req);
          `endif
        end
        Write: begin
          Bit#(CheriDataWidth) writeLine = ?;
          Bit#(TDiv#(CheriDataWidth,8)) byteMask = 0;
          Bit#(64) data = ?;
          if (sizedData matches tagged DoubleWord .d) data = d;
          Bool isCapWrite = False;
          CheriPhyByteOffset offset = truncate(addr);
          CheriPhyByteOffset maskSelect = offset;
          CheriPhyBitOffset  dataSelect = {truncateLSB(offset), 3'b0};
          debug2("memory", $display("<time %0t, core %0d, Memory> Memory store request - addr:%x, storeCondional:%x, SizedData:", $time, coreId, addr, storeConditional, fshow(sizedData), fshow(size)));
          
          // The below cases produce the byteMask and writeLine that we need.
          case(size)
            Byte: begin
              writeLine[7:0] = data[ 7:0];
              byteMask  = 'b1;
            end
            HalfWord: begin
              writeLine[15:0] = reverseBytes(data[15:0]);
              byteMask  = 'b11;
            end
            Word: begin
              writeLine[31:0] = reverseBytes(data[31:0]);
              byteMask  = 'hF;
            end
            WordLeft: begin
              data[31:0] = reverseBytes(data[31:0]);
              Bit#(5) shift = {truncate(offset),3'b0};
              data[31:0] = data[31:0] << shift;
              Bit#(4) mask = 4'hF;
              mask = mask << offset[1:0];
              byteMask = zeroExtend(mask);
              dataSelect = {truncateLSB(offset), 5'b0};
              writeLine[31:0] = data[31:0];
              maskSelect = {truncateLSB(offset), 2'b0};
            end
            WordRight: begin
              data[31:0] = reverseBytes(data[31:0]);
              Bit#(5) shift = {(2'd3 - truncate(offset)),3'b0};
              data[31:0] = data[31:0] >> shift;
              Bit#(4) mask = 4'hF;
              mask = mask >> (2'd3 - offset[1:0]);
              byteMask = zeroExtend(mask);
              dataSelect = {truncateLSB(offset), 5'b0};
              writeLine[31:0] = data[31:0];
              maskSelect = {truncateLSB(offset), 2'b0};
            end
            DoubleWord: begin
              writeLine[63:0] = reverseBytes(data);
              byteMask  = 'hFF;
            end
            DoubleWordLeft: begin
              data = reverseBytes(data);
              Bit#(6) shift = {3'b0,truncate(offset)}*6'h8;
              writeLine[63:0] = data << shift;
              dataSelect = {truncateLSB(offset), 6'b0};
              Bit#(8) mask  = 8'hFF;
              mask = mask << offset[2:0];
              byteMask = zeroExtend(mask);
              maskSelect = {truncateLSB(offset), 3'b0};
            end
            DoubleWordRight: begin
              data = reverseBytes(data);
              Bit#(6) shift = (6'd7 - {3'b0,truncate(offset)})*6'h8;
              writeLine[63:0] = data >> shift;
              dataSelect = {truncateLSB(offset), 6'b0};
              Bit#(8) mask  = 8'hFF;
              mask = mask >> (3'd7 - offset[2:0]);
              byteMask = zeroExtend(mask);
              maskSelect = {truncateLSB(offset), 3'b0};
            end
            `ifdef USECAP
              CapWord: begin
                case (sizedData) matches
                  tagged Line    .l: writeLine = reverseBytes(l);
                  tagged CapLine .l: writeLine = zeroExtend(reverseBytes(l));
                endcase
                Bit#(CapBytes) mask  = -1;
                byteMask = zeroExtend(mask);
                if (sizedData matches tagged CapLine .l) isCapWrite = True;
              end
            `endif
            /*Line: begin
              if (sizedData matches tagged Line .l) writeLine = l;
              writeLine = reverseBytes(writeLine);
              byteMask = signExtend(4'hF);
            end*/
          endcase
          `ifdef STATCOUNTERS
          case(size)
            Byte: begin
                incByteWrite  <= True;
                debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incByteWrite", $time));
            end 
            HalfWord: begin
                incHWordWrite <= True;
                debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incHWordWrite", $time));
            end
            Word, WordLeft, WordRight: begin
                incWordWrite  <= True;
                debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incWordWrite", $time));
            end
            DoubleWord, DoubleWordLeft, DoubleWordRight: begin
                incDwordWrite <= True;
                debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incDWordWrite", $time));
            end
            `ifdef USECAP
            CapWord: begin
                incCapWrite   <= True;
                debug2("StatCounters", $display("<time %0t, StatCounters> Memory.bsv, incCapWrite", $time));
            end
            `endif
          endcase
          `endif
          writeLine = insert(writeLine, dataSelect);
          byteMask  = insert(byteMask, maskSelect);
          
          debug2("memory", $display("<time %0t, core %0d, Memory> Writing %X %X to memory at address %X at time %t", $time, coreId, writeLine, byteMask,
              addr, $time()));

          CacheInst copInst = Write;
          `ifdef MULTI 
            if (storeConditional) begin 
              copInst = StoreConditional; 
            end 
          `endif

          `ifdef USECAP
            req.capability = isCapWrite;
          `endif
          req.data = writeLine;
          req.byteEnable = byteMask;
          req.cop = CacheOperation{inst: copInst, indexed: False, cache: DCache};
          debug2("memory", $display("<time %0t, core %0d, Memory> Putting preliminary cache request for write: ", $time, coreId, fshow(req)));
        end
        ICacheOp, DCacheOp: begin
          Bit#(64) writeLine = ?;
          Bit#(8) byteMask = 0;
          debug2("memory", $display("<time %0t, core %0d, Memory> CacheOp at address %X at time %t", $time, coreId, addr, $time()));
          req.cop = CacheOperation{inst: CacheNop, indexed: False, cache: DCache};
          // An invalidation of the Level2 will go through the Data cache.
          if (cop.cache == DCache || cop.cache == L2) begin
            debug2("memory", $display("<time %0t, core %0d, Memory> Memory: Cache Operation DCache||L2", $time, coreId));
            req.cop = cop;
          end else if (cop.cache == ICache) begin
            debug2("memory", $display("<time %0t, core %0d, Memory> Memory: Cache Operation ICache", $time, coreId));
            TlbResponse tlb_rsp = ?;
            tlb_rsp.addr={addr[39:3],3'b0};
            tlb_rsp.exception=DTLBL;
            iCacheOp.enq(CacheRequestInstT{
              defaultInst: classifyMIPSInstruction(0),
              cop: cop,
              instId: instId,
              tr: tlb_rsp
            });
          end
          tlbReq.exception = DTLBL; // Prevent translation
        end
        None: begin
          tlbReq.exception = DTLBL; // Prevent translation
          `ifdef USECAP
            `ifdef PFTCH
            Tuple2#(TlbRequest,CacheRequestDataT) reqs <- pftch.getPftchReq();
            tlbreq = tpl_1(reqs);
            dcachereq = tpl_2(reqs);
            tlbreq.instId = instId;
            tlbreq.exception = None;
            dcachereq.instId = instId;
            dcachereq.epoch = epoch;
            `endif
          `endif
        end
      endcase
      //debug2("memory", $display("<time %0t, core %0d, Memory> Putting micro DTLB request: ", $time, coreId, fshow(tlbReq)));
      `ifndef CHERIOS
        req.tr <- tlb.tlbLookupData.request(tlbReq);
        debug2("memory", $display("<time %0t, core %0d, Memory> Got micro DTLB response: ", $time, coreId, fshow(req.tr)));
        if (req.tr.valid) begin
          dCache.put(req);
          debug2("memory", $display("<time %0t, core %0d, Memory> Putting DCache Request: ", $time, coreId, fshow(req)));
        end else begin
          dCacheFetch <= req;
          dCacheDelayed <= True;
          debug2("memory", $display("<time %0t, core %0d, Memory> micro DTLB miss, going to dCacheDelayed ", $time, coreId));
        end
      `else // CHERIOS
        req.tr = simpleDataTranslation(tlbReq);
        dCache.put(req);
      `endif // CHERIOS
    endmethod

    method ActionValue#(MemResponseDataT) getResponse(MIPSReg oldReg, Bool signExtend, Bit#(8) addr, MemSize size, Bool exception, Bool cacheOpResponse);
      CacheResponseDataT cr <- dCache.getResponse();
      CheriPhyByteOffset byteOffset = truncate(addr);
      `ifdef USECAP
        CheriCapAddress capAddr = unpack(zeroExtend(addr));
        capAddr.offset = 0;
        CheriPhyByteOffset capSel = truncate(pack(capAddr));
      `endif
      MemResponseDataT resp = MemResponseDataT{
        exception: cr.exception,
        scResult: cr.scResult,
        `ifdef USECAP
          isCap: cr.isCap,
          loadedCap: reverseBytes(truncate(cr.data)),
        `endif
        data: selectWithSize(oldReg, cr.data, truncate(byteOffset), size, signExtend)
      };
      debug2("memory", $display("<time %0t, core %0d, Memory> Memory response: ", $time, coreId, fshow(resp)));
      
      `ifdef PFTCH
        pftch.spyCacheRsp(cr);
      `endif
      return resp;
    endmethod
  endinterface

  interface InstructionMemory instructionMemory;
    // Only allow this method if there is a pending cache operation.
    method Action reqInstruction(Address addr, InstId   instId, InstructionT inst) if (!iCacheOp.notEmpty && !iCacheDelayed);
      Exception exception = (addr[1:0] == 0) ? None:IADEL;
      CacheRequestInstT req = CacheRequestInstT{
          cop: CacheOperation{inst: Read, indexed: False, cache: ICache},
          tr: ?,
          defaultInst: inst,
          instId: instId
        };
      TlbRequest tlbReq = TlbRequest{
                        addr: addr,
                        write: False,
                        fromDebug: False,
                        ll: False,
                        exception: exception,
                        instId: instId
                      };
      `ifndef CHERIOS
        req.tr <- tlb.tlbLookupInstruction.request(tlbReq);
        if (req.tr.valid) begin
          iCache.put(req);
          debug2("memory", $display("<time %0t, core %0d, Memory> Putting ICache request %x, microTLB hit", $time, coreId, addr));
        end else begin
          req.tr = ?;
          iCacheFetch <= req;
          iCacheDelayed <= True;
          debug2("memory", $display("<time %0t, core %0d, Memory> microTLB miss on %x, going to iCacheDelayed", $time, coreId, addr));
        end
      `else // CHERIOS
        req.tr = simpleInstructionTranslate(tlbReq);
        iCache.put(req);
      `endif // CHERIOS
    endmethod

    method ActionValue#(CacheResponseInstT) getInstruction();
      CacheResponseInstT resp <- iCache.getRead();
      debug2("memory", $display("<time %0t, core %0d, Memory> Instruction response: ", $time, coreId, fshow(resp)));
      return resp;
    endmethod
  endinterface

  interface MemConfiguration configuration;
    method iCacheGetConfig = iCache.getConfig;
    method dCacheGetConfig = dCache.getConfig;
  endinterface

  `ifndef MULTI
    interface memory = topMemIfc;
  `else
    `ifndef TIMEBASED
      interface  invalidateICache = iCache.invalidate;
      interface  invalidateDCache = dCache.invalidate;
      interface getInvalidateDone = dCache.getInvalidateDone;
    `endif
    interface imemory = topImem; 
    interface dmemory = topDmem; 
  `endif

  method nextWillCommit = dCache.nextWillCommit;
  `ifdef STATCOUNTERS
    `ifndef MULTI 
      interface statCounters = statCnt;
    `endif
  `endif
endmodule


`ifdef CHERIOS
`ifdef CAP64
function TlbResponse simpleInstructionTranslate(TlbRequest reqIn);
  TlbResponse simpleResponse = TlbResponse{
    addr: ?,
    exception: None,
    write:reqIn.write,
    ll:reqIn.ll,
    cached:True,
    fromDebug:reqIn.fromDebug,
    priv:Kernel,
    instId:reqIn.instId
    `ifdef USECAP
      , noCapLoad: False,
      noCapStore: False
    `endif
  };
  if ( reqIn.addr[1:0] != 0 || (reqIn.addr[63:31] != {reqIn.addr[31], reqIn.addr[63:32]})) begin // report misaligned instruction access.
    simpleResponse.exception = IADEL;
  end

  if (reqIn.addr[31:29] == 3'b101) begin
    simpleResponse.cached = False;
  end

    if(reqIn.addr[31:30] == 2'b10) begin
      simpleResponse.addr = {11'h000,reqIn.addr[28:0]}; // map kseg0, kseg1 to 0 - 0.5GiB
    end else if(reqIn.addr[31:29] == 3'b110) begin // map sseg to 1.5GiB - 2GiB
      simpleResponse.addr = {11'h003, reqIn.addr[28:0]};
      simpleResponse.cached = False;
    end else if(reqIn.addr[31:29] == 3'b111) begin // map kseg3 to 1GiB - 1.5GiB
      simpleResponse.addr = {11'h002, reqIn.addr[28:0]};
    end else if(reqIn.addr[31:29] == 3'b001) begin // map useg 1GiB - 1.5GiB to 0.5GiB - 1GiB
        simpleResponse.addr = {11'h001,reqIn.addr[28:0]};
        simpleResponse.priv = User;
    end else begin
        simpleResponse.exception = IADEL;
        simpleResponse.addr = reqIn.addr[39:0];
    end

    return simpleResponse;
endfunction

function TlbResponse simpleDataTranslation(TlbRequest reqIn);
  TlbResponse simpleResponse = TlbResponse{
    addr: ?,
    exception: None,
    write:reqIn.write,
    ll:reqIn.ll,
    cached:True,
    fromDebug:reqIn.fromDebug,
    priv:Kernel,
    instId:reqIn.instId
    `ifdef USECAP
      , noCapLoad: False,
      noCapStore: False
    `endif
  };

    if (reqIn.addr[63:31] != {reqIn.addr[31], reqIn.addr[63:32]}) begin // CHERIOS only works within 32-bit addr space
        simpleResponse.exception = (reqIn.write)? DTLBS : DTLBL;
    end

    if(reqIn.addr[31:30] == 2'b10) begin
      simpleResponse.addr = {11'h000,reqIn.addr[28:0]}; // map kseg0, kseg1 to 0 - 0.5GiB
    end else if(reqIn.addr[31:29] == 3'b110) begin // map sseg to 1.5GiB - 2GiB
      simpleResponse.addr = {11'h003, reqIn.addr[28:0]};
      simpleResponse.cached = False;
    end else if(reqIn.addr[31:29] == 3'b111) begin // map kseg3 to 1GiB - 1.5GiB
      simpleResponse.addr = {11'h002, reqIn.addr[28:0]};
    end else if(reqIn.addr[31:29] == 3'b001) begin // map useg 1GiB - 1.5GiB to 0.5GiB - 1GiB
        simpleResponse.addr = {11'h001,reqIn.addr[28:0]};
        simpleResponse.priv = User;
    end else begin
        simpleResponse.exception = (reqIn.write)? DTLBS : DTLBL;
        simpleResponse.addr = reqIn.addr[39:0];
    end

  return simpleResponse;
endfunction
`else
function TlbResponse simpleInstructionTranslate(TlbRequest reqIn);
  TlbResponse simpleResponse = TlbResponse{
    addr: ?,
    exception: None,
    write:reqIn.write,
    ll:reqIn.ll,
    cached:True,
    fromDebug:reqIn.fromDebug,
    priv:Kernel,
    instId:reqIn.instId
    `ifdef USECAP
      , noCapLoad: False,
      noCapStore: False
    `endif
  };
  if (reqIn.addr[63:56] == 8'h90 || (reqIn.addr[63:32] == 32'hFFFFFFFF && reqIn.addr[31:29] == 3'b101)) begin
    simpleResponse.cached = False;
  end
  if ( reqIn.addr[1:0] != 0 ) begin // report misaligned instruction access.
     simpleResponse.exception = IADEL;
   end
 
  if (case(reqIn.addr[63:56])
        8'h98: return True;
        8'h90: return True;
        8'hA0: return True;
        8'hA8: return True;
        8'hB0: return True;
        default: return False;
      endcase) begin // Simple translation for the xkphys regions which map into physical memory.
    simpleResponse.addr = reqIn.addr[39:0];
  end else if (reqIn.addr[63:32] == 32'hFFFFFFFF) begin
     if(reqIn.addr[31:30] == 2'b10) begin
      simpleResponse.addr = {11'b0,reqIn.addr[28:0]}; // Simple translation for the kseg1 & kseg0 regions which map into 512MB of physical memory.
     end else begin
      simpleResponse.addr = {8'b0, reqIn.addr[31:0]};
     end
  end else if(reqIn.addr[63:32] == 32'h00000000 && reqIn.addr[31:30] == 2'b01) begin
    simpleResponse.addr = {8'h00,reqIn.addr[31:0]};
    simpleResponse.priv = User;
  end else begin // Simple translation for the xkphys regions which map into physical memory.
    simpleResponse.exception = ITLB;
    Privilege priv = User;
    if (reqIn.addr[63:60] >= 4'h4) priv = Supervisor;
    if (reqIn.addr[63:60] >= 4'h8) priv = Kernel;
    simpleResponse.priv = priv;
    simpleResponse.addr = reqIn.addr[39:0];
  end
  return simpleResponse;
 endfunction
 
function TlbResponse simpleDataTranslation(TlbRequest reqIn);
  TlbResponse simpleResponse = TlbResponse{
    addr: ?,
    exception: None,
    write:reqIn.write,
    ll:reqIn.ll,
    cached:True,
    fromDebug:reqIn.fromDebug,
    priv:Kernel,
    instId:reqIn.instId
    `ifdef USECAP
      , noCapLoad: False,
      noCapStore: False
    `endif
  };
  if (reqIn.addr[63:56] == 8'h90 || (reqIn.addr[63:32] == 32'hFFFFFFFF && reqIn.addr[31:29] == 3'b101)) begin
    simpleResponse.cached = False;
  end
 
  if (case(reqIn.addr[63:56])
        8'h98: return True;
        8'h90: return True;
        8'hA0: return True;
        8'hA8: return True;
        8'hB0: return True;
        default: return False;
      endcase) begin // Simple translation for the xkphys regions which map into physical memory.
    simpleResponse.addr = reqIn.addr[39:0];
  end else if (reqIn.addr[63:32] == 32'hFFFFFFFF && (reqIn.addr[31:29] == 3'b100 || reqIn.addr[31:29] == 3'b101)) begin // Simple translation for the kseg1 & kseg0 regions which map into 512MB of physical memory.
    simpleResponse.addr = {11'b0,reqIn.addr[28:0]};
  end else if(reqIn.addr[63:32] == 32'h00000000 && reqIn.addr[31:28] == 4'h1) begin
    simpleResponse.addr = {12'h002,reqIn.addr[27:0]};
    simpleResponse.priv = User;
  end else begin // Simple translation for the xkphys regions which map into physical memory.
    simpleResponse.exception = (reqIn.write)? DTLBS : DTLBL;
    Privilege priv = User;
    if (reqIn.addr[63:60] >= 4'h4) priv = Supervisor;
    if (reqIn.addr[63:60] >= 4'h8) priv = Kernel;
    simpleResponse.priv = priv;
    simpleResponse.addr = reqIn.addr[39:0];
  end
   return simpleResponse;
 endfunction
 `endif // CAP64
 `endif // CHERIOS
