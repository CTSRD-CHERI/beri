/* Copyright 2015 Matthew Naylor
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
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream
 * Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
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

import MemTypes     :: *;
import MIPS         :: *;
import MEM          :: *;
import Memory       :: *;
import StmtFSM      :: *;
import RegFile      :: *;
import FIFO         :: *;
import FIFOF        :: *;
import SpecialFIFOs :: *;
import Vector       :: *;
import BlueCheck    :: *;

// This module has been developed for the purpose of testing the
// (shared) memory sub-system.  It aims to provide a neat Bluespec
// interface to memory resembling the memory instructions of the MIPS
// ISA.  Given a fiddley MIPSMemory interface we return a neat
// MemoryClient interface.

`ifdef CAP
`define USECAP=1
`endif

`ifdef CAP128
`define USECAP=1
`endif

// Interface ==================================================================

interface MemoryClient;
  // Null Memory Request
  method Action nullRequest();

  // Load value at address
  method Action load(Addr addr);

  // Store data to address
  method Action store(Data data, Addr addr);

  // Load instruction
  method Action instrLoad(Addr addr);

  // Sync
  method Action sync();

  // Uncommitted load
  method Action cancelledLoad(Addr addr);

  // Uncommitted store
  method Action cancelledStore(Data data, Addr addr);

  // Load-linked
  method Action loadLinked(Addr addr);

  // Store-conditional
  method Action storeConditional(Data data, Addr addr);

  // Store-conditional ignore
  method Action storeCondIgnore(Data data, Addr addr);

  // Writeback
  method Action writeback(CacheName cache, Addr addr);

  // Invalidate & writeback
  method Action invalidateWriteback(CacheName cache, Addr addr);

  `ifdef USECAP
  // Store capability
  method Action storeCap(Data data, Addr addr);

  // Load capability
  method Action loadCap(Addr addr);
  `endif

  // Get response
  method ActionValue#(MemoryClientResponse) getResponse;
  method ActionValue#(MemoryClientResponse) getInstrResponse;
  method Bool canGetResponse;

  // Check if all outstanding operations have been consumed
  method Bool done;

  // Set mapping from Addr values to physical address
  method Action setAddrMap(AddrMap map);
endinterface

// Types ======================================================================

typedef 4 NumAddrBits;

typedef struct {
  Bit#(NumAddrBits) addr;
  Bit#(1) dword;
} Addr
  deriving (Bits, Eq, Bounded);

typedef Bit#(16) Data;

typedef union tagged {
  void WriteResponse;
  Data DataResponse;
  Bit#(1) SCResponse;
  Data InstrResponse;
  Maybe#(Data) CapResponse;
} MemoryClientResponse
  deriving (Bits, Eq, FShow);

typedef struct {
  Bool isLoad;           // True for load, False for store to data mem
  Bool isCap;            // Is capability access?
  Bool isSC;             // Is it a store-conditional?
  Bool ignoreSCResponse; // Ignore SC response?
  Bit#(8) lowAddr;       // Lower 8-bits of address
  Bool cancel;           // Cancelled request (ignore response)
} OutstandingMemInstr
  deriving (Bits);

// D cache or L2 cache?
typedef enum { DCache, L2 } CacheName
  deriving (Bits, Eq, Bounded, FShow);

// How to map an Addr to a 24-bit physical address offset
typedef struct {
  Vector#(NumAddrBits, Bit#(5)) index;
} AddrMap deriving (Bits, Eq, Bounded);

// Functions ==================================================================

// Convert from Data to 64-bit data
function Bit#(64) fromData(Data x) = zeroExtend(x);

// Convert from 64-bit data to Data
function Data toData(Bit#(64) x) = x[15:0];

// Show addresses
instance FShow#(Addr);
  function Fmt fshow (Addr a) =
    $format("%x:%x", a.addr, a.dword);
endinstance

// Show address map
instance FShow#(AddrMap);
  function Fmt fshow(AddrMap map) =
    $format("<" , map.index[3],
            ", ", map.index[2],
            ", ", map.index[1],
            ", ", map.index[0],
            ">");
endinstance

// Custom generators ==========================================================

// Custom generator for AddrMap.  Each value in an AddrMap must be
// unique and lie in the range 0..23 inclusive.
module [BlueCheck] genAddrMap (Gen#(AddrMap));
  Gen#(Vector#(NumAddrBits, Bit#(3))) offsetsGen <- mkGenDefault;
  method ActionValue#(AddrMap) gen;
    Vector#(NumAddrBits, Bit#(3)) offsets <- offsetsGen.gen;
    AddrMap map;
    Bit#(5) offset = 0;
    for (Integer i = 0; i < valueOf(NumAddrBits); i = i+1) begin
      Bit#(5) newOffset = offset + zeroExtend(bound(offsets[i], 2));
      map.index[i] = newOffset;
      offset = newOffset+1;
    end
    return map;
  endmethod
endmodule

instance MkGen#(AddrMap);
  mkGen = genAddrMap;
endinstance

// Memory client module =======================================================

module mkMemoryClient#(MIPSMemory mipsMemory) (MemoryClient);

  // Response FIFO
  FIFOF#(MemoryClientResponse) responseFIFO <- mkSizedFIFOF(4);
  FIFOF#(MemoryClientResponse) instrResponseFIFO <- mkSizedFIFOF(4);

  // FIFO storing details of outstanding loads/stores
  FIFOF#(OutstandingMemInstr) outstandingFIFO <- mkSizedFIFOF(4);

  // FIFO storing cancellation flag for each outstanding request
  FIFOF#(Bool) cancelFIFO <- mkSizedFIFOF(4);

  // ID of memory instruction
  Reg#(InstId) instrId <- mkReg(0);

  // Address mapping
  Reg#(AddrMap) addrMap <- mkRegU;

  // Convert an Addr to a 64-bit MIPS virtual address
  function Bit#(64) fromAddr(Addr x);
    Bit#(24) offset = 0;
    for (Integer i = 0; i < valueOf(NumAddrBits); i=i+1)
      offset[addrMap.index[i]] = x.addr[i];
    `ifdef USECAP
      Bit#(TLog#(CapBytes)) line = extend({x.dword, 3'b000});
    `else
      Bit#(TLog#(CheriBusBytes)) line = extend({x.dword, 3'b000});
    `endif
    return { 8'h98, 0, offset, line };
  endfunction

  // Insert delays using a not-very-arbitrary counter
  Reg#(Bit#(2)) arbitrary <- mkReg(0);

  rule incArbitrary;
    let b <- $test$plusargs("delays");
    if (b) arbitrary <= arbitrary+1;
  endrule

  // Fill response FIFO
  rule handleResponses (arbitrary == 0);
    let x = outstandingFIFO.first;
    outstandingFIFO.deq;
/*
    `ifdef MULTI
        let resp <- mipsMemory.dataMemory.getResponse(
                         0, False, x.lowAddr,
                         x.isCap ? CapWord : DoubleWord,
                         False, x.isSC, False);
    `else
        let resp <- mipsMemory.dataMemory.getResponse(
                         0, False, x.lowAddr,
                         x.isCap ? CapWord : DoubleWord,
                         False, False);
    `endif
*/
    let resp <- mipsMemory.dataMemory.getResponse(
                         0, False, x.lowAddr,
                         x.isCap ? CapWord : DoubleWord,
                         False, False);
 
    if (! x.cancel)
      begin
        if (x.isLoad)
          begin
            if (x.isCap)
              begin 
                `ifdef USECAP
                    if (resp.isCap) begin
                      Bit#(64) tmp = truncateLSB(resp.loadedCap);
                      responseFIFO.enq(CapResponse(Valid(truncate(tmp))));
                    end else
                      responseFIFO.enq(CapResponse(Invalid));
                `endif
              end
            else responseFIFO.enq(DataResponse(toData(resp.data)));
          end
        else if (x.isSC)
          begin
            if (x.ignoreSCResponse == False) begin
              responseFIFO.enq(SCResponse(extend(pack(resp.scResult))));
            end 
          end
      end
  endrule

  rule handleCancels (arbitrary == 0);
    mipsMemory.nextWillCommit(!cancelFIFO.first);
    cancelFIFO.deq;
  endrule

  rule handleInstrResponses (arbitrary == 0);
    let instr <- mipsMemory.instructionMemory.getInstruction();
    let d = toData(zeroExtend(pack(instr.inst)[31:0]));
    instrResponseFIFO.enq(InstrResponse(d));
  endrule

  // Functions
  function Action loadGeneric(Addr addr, Bool ll, Bool cancel, Bool cap) =
    action
      Bit#(64) fullAddr = fromAddr(addr);
      CacheOperation cop = CacheOperation{inst: Read, indexed: False, cache: DCache};
      mipsMemory.dataMemory.startMem(
        Read,
        fullAddr,
        cop,
        ?,
        cap ? CapWord : DoubleWord,
        ll,
        cap,
        instrId,
        ?,
        False,
        False
      );
      cancelFIFO.enq(cancel);
      instrId <= instrId+1;

      OutstandingMemInstr out;
      out.isLoad  = True;
      out.isCap   = cap;
      out.isSC    = False;
      out.ignoreSCResponse = False;
      out.lowAddr = fullAddr[7:0];
      out.cancel  = cancel;
      outstandingFIFO.enq(out);
    endaction;

  function Action storeGeneric(Data data, Addr addr,
                               Bool sc, Bool cancel, Bool cap,
                               Bool ignoreSCResp) =
    action
      Bit#(64) fullAddr = fromAddr(addr);
      CacheOperation cop = CacheOperation{inst: Write, indexed: False, cache: DCache};
      mipsMemory.dataMemory.startMem(
        Write, 
        fullAddr, 
        cop,
        `ifdef USECAP
          cap ? tagged CapLine ({fromData(data), 0}) :
        `endif
        tagged DoubleWord (fromData(data)),
        cap ? CapWord : DoubleWord,
        False,
        cap,
        instrId, 
        ?, 
        False, 
        sc
      );
      cancelFIFO.enq(cancel);
      instrId <= instrId + 1;

      OutstandingMemInstr out;
      out.isLoad  = False;
      out.isCap   = cap;
      out.isSC    = sc;
      out.ignoreSCResponse = ignoreSCResp;
      out.lowAddr = fullAddr[7:0];
      out.cancel  = cancel;
      outstandingFIFO.enq(out);
    endaction;

  function Action cacheGeneric(CacheOperation op, Addr addr) =
    action
      Bit#(64) fullAddr = fromAddr(addr);
      //CacheOperation cop = CacheOperation{inst: op, indexed: False, cache: DCache};
      mipsMemory.dataMemory.startMem(
        DCacheOp, fullAddr, op, ?, ?, False, False, instrId, ?, False, False);
      cancelFIFO.enq(False);
      instrId <= instrId + 1;

      OutstandingMemInstr out;
      out.isLoad  = False;
      out.isCap   = False;
      out.isSC    = False;
      out.ignoreSCResponse = False;
      out.lowAddr = fullAddr[7:0];
      out.cancel  = False;
      outstandingFIFO.enq(out);
    endaction;

  // Null Memory Request
  method Action nullRequest();
    CacheOperation cop = CacheOperation{inst: CacheNop, indexed: False, cache: DCache};
    mipsMemory.dataMemory.startMem(
      DCacheOp, ?, cop, ?, ?, False, False, instrId, ?, False, False);
    cancelFIFO.enq(False);
    instrId <= instrId + 1;

    OutstandingMemInstr out;
    out.isLoad  = False;
    out.isCap   = False;
    out.isSC    = False;
    out.ignoreSCResponse = False;
    out.lowAddr = ?;
    out.cancel  = False;
    outstandingFIFO.enq(out);
  endmethod

  // Load value at address into register
  method Action load(Addr addr);
    loadGeneric(addr, False, False, False);
  endmethod

  // Store data to address
  method Action store(Data data, Addr addr);
    storeGeneric(data, addr, False, False, False, False);
  endmethod

  // Load instruction
  method Action instrLoad(Addr addr);
    let newAddr = fromAddr(addr);
    //newAddr[2] = 1;
    mipsMemory.instructionMemory.reqInstruction(newAddr, instrId, unpack(0));
    instrId <= instrId + 1;
  endmethod

  // Sync
  method Action sync();
    CacheOperation op;
    op.inst    = CacheSync;
    op.cache   = DCache;
    op.indexed = ?;
    cacheGeneric(op, ?);
  endmethod

  // Load value at address into register
  method Action cancelledLoad(Addr addr);
    loadGeneric(addr, False, True, False);
  endmethod

  // Store data to address
  method Action cancelledStore(Data data, Addr addr);
    storeGeneric(data, addr, False, True, False, False);
  endmethod

  // Load linked
  method Action loadLinked(Addr addr);
    loadGeneric(addr, True, False, False);
  endmethod

  // Store conditional
  method Action storeConditional(Data data, Addr addr);
    storeGeneric(data, addr, True, False, False, False);
  endmethod

  // Store-conditional (ignoring failure/success response)
  method Action storeCondIgnore(Data data, Addr addr);
    storeGeneric(data, addr, True, False, False, True);
  endmethod

  // Writeback
  method Action writeback(CacheName cache, Addr addr);
    CacheOperation op;
    op.inst    = CacheWriteback;
    op.cache   = cache == L2 ? L2 : DCache;
    op.indexed = False;
    cacheGeneric(op, addr);
  endmethod

  // Invalidate & writeback
  method Action invalidateWriteback(CacheName cache, Addr addr);
    CacheOperation op;
    op.inst    = CacheInvalidateWriteback;
    op.cache   = cache == L2 ? L2 : DCache;
    op.indexed = False;
    cacheGeneric(op, addr);
  endmethod

  `ifdef USECAP
  // Store capability
  method Action storeCap(Data data, Addr addr);
    addr.dword = 0;
    storeGeneric(data, addr, False, False, True, False);
  endmethod

  // Load capability
  method Action loadCap(Addr addr);
    addr.dword = 0;
    loadGeneric(addr, False, False, True);
  endmethod
  `endif

  // Responses
  method ActionValue#(MemoryClientResponse) getResponse;
    responseFIFO.deq;
    return responseFIFO.first;
  endmethod

  method Bool canGetResponse = responseFIFO.notEmpty;

  // Instruction responses
  method ActionValue#(MemoryClientResponse) getInstrResponse;
    instrResponseFIFO.deq;
    return instrResponseFIFO.first;
  endmethod

  // Check if all outstanding operations have been consumed
  method Bool done = !outstandingFIFO.notEmpty &&
                     !responseFIFO.notEmpty &&
                     !instrResponseFIFO.notEmpty;

  // Set mapping from Addr values to physical address
  method Action setAddrMap(AddrMap map);
    addrMap <= map;
  endmethod

endmodule

// Golden memory client =======================================================

module mkMemoryClientGolden (MemoryClient);

  // Response FIFO
  FIFOF#(MemoryClientResponse) responseFIFO <- mkSizedFIFOF(4);
  FIFOF#(MemoryClientResponse) instrResponseFIFO <- mkSizedFIFOF(4);

  // Golden memory unit (one mem per dword)
  RegFile#(Bit#(NumAddrBits), Data) memA <- mkRegFileFull;
  RegFile#(Bit#(NumAddrBits), Data) memB <- mkRegFileFull;

  // Keep track of tag bits
  RegFile#(Bit#(NumAddrBits), Bool) tagMem <- mkRegFileFull;

  // Initialisation
  Reg#(Bool) init <- mkReg(True);
  Reg#(Bit#(NumAddrBits)) memAddr <- mkReg(minBound);

  rule initialiseMem(init);
    if (memAddr == maxBound)
      init <= False;
    else
      memAddr <= memAddr + 1;
    memA.upd(memAddr, 0);
    memB.upd(memAddr, 0);
    tagMem.upd(memAddr, False);
  endrule

  // Load value at address into register
  method Action load(Addr addr) if (!init);
    let dA = memA.sub(addr.addr);
    let dB = memB.sub(addr.addr);
    responseFIFO.enq(DataResponse(addr.dword == 1 ? dB : dA));
  endmethod

  // Store data to address
  method Action store(Data data, Addr addr) if (!init);
    if (addr.dword == 1)
      memB.upd(addr.addr, data);
    else
      memA.upd(addr.addr, data);
    tagMem.upd(addr.addr, False);
  endmethod

  // Load instruction
  // (Always return 0 for now)
  method Action instrLoad(Addr addr);
    instrResponseFIFO.enq(InstrResponse(0));
  endmethod

  // Check if all outstanding operations have been consumed
  method Bool done = !responseFIFO.notEmpty &&
                     !instrResponseFIFO.notEmpty;

  // Responses
  method ActionValue#(MemoryClientResponse) getResponse;
    responseFIFO.deq;
    return responseFIFO.first;
  endmethod

  method Bool canGetResponse = responseFIFO.notEmpty;

  // Instruction responses
  method ActionValue#(MemoryClientResponse) getInstrResponse;
    instrResponseFIFO.deq;
    return instrResponseFIFO.first;
  endmethod

  `ifdef USECAP
  // Store capability
  method Action storeCap(Data data, Addr addr) if (!init);
    tagMem.upd(addr.addr, True);
    memA.upd(addr.addr, data);
    memB.upd(addr.addr, 0);
  endmethod

  // Load capability
  method Action loadCap(Addr addr) if (!init);
    let d = memA.sub(addr.addr);
    let tag = tagMem.sub(addr.addr);
    if (tag)
      responseFIFO.enq(CapResponse(Valid(zeroExtend(d))));
    else
      responseFIFO.enq(CapResponse(Invalid));
  endmethod
  `endif

endmodule
