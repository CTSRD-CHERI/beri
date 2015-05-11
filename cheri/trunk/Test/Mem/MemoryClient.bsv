/*-
 * Copyright (c) 2015 Matthew Naylor
 * All rights reserved.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
 * project, funded by EPSRC grant EP/K008528/1.
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

// This module has been developed for the purpose of testing the
// (shared) memory sub-system.  It aims to provide a neat Bluespec
// interface to memory resembling the memory instructions of the MIPS
// ISA.  Given a fiddley MIPSMemory interface we return a neat
// MemoryClient interface.

// Types ======================================================================

typedef 4 AddrWidth;

typedef struct {
  Bit#(AddrWidth) addr;
} Addr
  deriving (Bits, Eq, Bounded, Literal);

typedef Bit#(16) Data;

typedef struct {
  Bit#(5) regId;
} Register
  deriving (Bits, Eq, Bounded, Literal);

typedef struct {
  Bool isLoad;         // True for load, False for store
  Bool isSC;           // Is it a store-conditional?
  Register dest;       // Destination register for load or SC
  Addr addr;           // Address of load or store
  Bool cancel;         // Cancelled request (ignore response)
} OutstandingMemInstr
  deriving (Bits);

// D cache or L2 cache?
typedef enum { DCache, L2 } CacheName
  deriving (Bits, Eq, Bounded, FShow);

// Interface ==================================================================

interface MemoryClient;
  // Load value at address into register
  method Action load(Register dest, Addr addr);

  // Store data to address
  method Action store(Data data, Addr addr);

  // Uncommitted load
  method Action cancelledLoad(Register dest, Addr addr);

  // Uncommitted store
  method Action cancelledStore(Data data, Addr addr);

  // Load-linked
  method Action loadLinked(Register dest, Addr addr);

  // Store-conditional
  method Action storeConditional(Register dest, Data data, Addr addr);

  // Writeback
  method Action writeback(CacheName cache, Addr addr);

  // Invalidate & writeback
  method Action invalidateWriteback(CacheName cache, Addr addr);

  // Ensure all outstanding operations have completed
  method Action commit;

  // Obtain value of register
  method Data value(Register r);
endinterface

// Functions ==================================================================

// Convert from Addr to 64-bit address
function Bit#(64) fromAddr(Addr x) =
    { 4'h9, 4'h8, 36'h00_0000_000
    , 4'b0, x.addr[3:2]
    , 8'b0, x.addr[1], 1'b0, x.addr[0], 3'b0};

// Convert from Data to 64-bit data
function Bit#(64) fromData(Data x) = zeroExtend(x);

// Convert from 64-bit data to Data
function Data toData(Bit#(64) x) = x[15:0];

// Show addresses
instance FShow#(Addr);
  function Fmt fshow (Addr addr);
    Bit#(64) fullAddr = fromAddr(addr);
    return $format("0x%h", fullAddr);
  endfunction
endinstance

// Show registers
instance FShow#(Register);
  function Fmt fshow (Register r) =
    $format("R%0d", r.regId);
endinstance

// Convert integer to register
function Register register(Integer i);
  Register r;
  r.regId = fromInteger(i);
  return r;
endfunction

// Memory client module =======================================================

module mkMemoryClient#(MIPSMemory mipsMemory) (MemoryClient);

  // Register file (for storing results of load instructions)
  //RegFile#(Register, Data) regFile <- mkRegFileFull;
  Vector#(TExp#(SizeOf#(Register)), Reg#(Data)) regFile <- replicateM(mkReg(0));

  // FIFO storing details of outstanding loads/stores
  FIFOF#(OutstandingMemInstr) outstandingFIFO <-
    mkSizedFIFOF(16);

  // FIFO storing cancellation flag for each outstanding request
  FIFOF#(Bool) cancelFIFO <- mkBypassFIFOF;

  // Insert delays using a not-very-arbitrary counter
  Reg#(Bool) insertDelays <- mkReg(False);
  Reg#(Bit#(2)) arbitrary <- mkReg(0);

  // ID of memory instruction
  Reg#(InstId) instrId <- mkReg(0);

  // Initialisation
  Reg#(Bool) init       <- mkReg(True);
  Reg#(Register) regNum <- mkReg(minBound);

  rule initialise (init);
    //if (regNum == maxBound)
    //  init <= False;
    //else
    //  regNum <= unpack(pack(regNum)+1);
    //regFile.upd(regNum, 0);
    let b <- $test$plusargs("delays");
    insertDelays <= b;
    init <= False;
  endrule

  rule incArbitrary (!init);
    if (insertDelays) begin
      arbitrary <= arbitrary+1;
    end
  endrule

  rule handleResponses (!init && arbitrary == 0);
    let x = outstandingFIFO.first;
    outstandingFIFO.deq;

    `ifdef MULTI
        let resp <- mipsMemory.dataMemory.getResponse(
                         0, False, fromAddr(x.addr)[7:0], DoubleWord,
                         False, x.isSC, False);
    `else
        let resp <- mipsMemory.dataMemory.getResponse(
                         0, False, fromAddr(x.addr)[7:0], DoubleWord,
                         False, False);
    `endif

    if (! x.cancel)
      begin
        if (x.isLoad)
          begin
            if (resp.data matches tagged DoubleWord .d)
               regFile[x.dest.regId] <= toData(d);
               //regFile.upd(x.dest, toData(d));
          end
        else if (x.isSC)
          begin
            if (resp.data matches tagged Line .line)
               regFile[x.dest.regId] <= zeroExtend(line[0]);
               //regFile.upd(x.dest, zeroExtend(line[0]));
          end
      end
  endrule

  rule handleCancels (!init && arbitrary == 0);
    mipsMemory.nextWillCommit(!cancelFIFO.first);
    cancelFIFO.deq;
  endrule

  // Functions
  function Action loadGeneric(Register dest, Addr addr,
                              Bool ll, Bool cancel) =
    action
      mipsMemory.dataMemory.startRead(
        fromAddr(addr), DoubleWord, ll, False, instrId, ?, False);
      cancelFIFO.enq(cancel);
      instrId <= instrId+1;

      OutstandingMemInstr out;
      out.isLoad = True;
      out.isSC   = False;
      out.addr   = addr;
      out.dest   = dest;
      out.cancel = cancel;
      outstandingFIFO.enq(out);
    endaction;

  function Action storeGeneric(Register dest, Data data, Addr addr,
                               Bool sc, Bool cancel) =
    action
      mipsMemory.dataMemory.startWrite(
        fromAddr(addr), tagged DoubleWord (fromData(data)),
        DoubleWord, instrId, ?, False, sc);
      cancelFIFO.enq(cancel);
      instrId <= instrId + 1;

      OutstandingMemInstr out;
      out.isLoad = False;
      out.isSC   = sc;
      out.addr   = addr;
      out.dest   = dest;
      out.cancel = cancel;
      outstandingFIFO.enq(out);
    endaction;

  function Action cacheGeneric(CacheOperation op, Addr addr) =
    action
      mipsMemory.dataMemory.startCacheOp(
        fromAddr(addr), op, instrId, ?);
      cancelFIFO.enq(False);
      instrId <= instrId + 1;

      OutstandingMemInstr out;
      out.isLoad = False;
      out.isSC   = False;
      out.addr   = addr;
      out.dest   = ?;
      out.cancel = False;
      outstandingFIFO.enq(out);
    endaction;

  // Load value at address into register
  method Action load(Register r, Addr addr) if (!init);
    loadGeneric(r, addr, False, False);
  endmethod

  // Store data to address
  method Action store(Data data, Addr addr) if (!init);
    storeGeneric(?, data, addr, False, False);
  endmethod

  // Load value at address into register
  method Action cancelledLoad(Register r, Addr addr) if (!init);
    loadGeneric(r, addr, False, True);
  endmethod

  // Store data to address
  method Action cancelledStore(Data data, Addr addr) if (!init);
    storeGeneric(?, data, addr, False, True);
  endmethod

  // Load linked
  method Action loadLinked(Register r, Addr addr) if (!init);
    loadGeneric(r, addr, True, False);
  endmethod

  // Store conditional
  method Action storeConditional(Register r, Data data, Addr addr) if (!init);
    storeGeneric(r, data, addr, True, False);
  endmethod

  // Writeback
  method Action writeback(CacheName cache, Addr addr) if (!init);
    CacheOperation op;
    op.inst    = CacheWriteback;
    op.cache   = cache == L2 ? L2 : DCache;
    op.indexed = False;
    cacheGeneric(op, addr);
  endmethod

  // Invalidate & writeback
  method Action invalidateWriteback(CacheName cache, Addr addr) if (!init);
    CacheOperation op;
    op.inst    = CacheInvalidateWriteback;
    op.cache   = cache == L2 ? L2 : DCache;
    op.indexed = False;
    cacheGeneric(op, addr);
  endmethod

  // Commit (ensure all outstanding operations have completed)
  method Action commit if (!init);
    await(!outstandingFIFO.notEmpty);
  endmethod

  // Obtain value of register
  method Data value(Register r) if (!init);
    return regFile[r.regId];
    //return regFile.sub(r);
  endmethod
endmodule

// Golden memory client =======================================================

module mkMemoryClientGolden (MemoryClient);

  // Golden memory unit
  MEM#(Addr, Data) mem <- mkMEMfast;

  // Register file (for storing results of load instructions)
  RegFile#(Register, Data) regFile <- mkRegFileFull;

  // FIFO storing target of outstanding loads
  FIFOF#(Register) outstandingFIFO <- mkSizedFIFOF(16);

  // Initialisation
  Reg#(Bool)     initMem <- mkReg(True);
  Reg#(Addr)     memAddr <- mkReg(minBound);
  Reg#(Bool)     initReg <- mkReg(True);
  Reg#(Register) regNum  <- mkReg(minBound);
  Bool           init    =  initMem || initReg;

  rule initialiseMem(initMem);
    if (memAddr == maxBound)
      initMem <= False;
    else
      memAddr.addr <= memAddr.addr + 1;
    mem.write(memAddr, 0);
  endrule

  rule initialiseRegs(initReg);
    if (regNum == maxBound)
      initReg <= False;
    else
      regNum <= unpack(pack(regNum) + 1);
    regFile.upd(regNum, 0);
  endrule

  rule handleResponses(!init);
    let r = outstandingFIFO.first;
    outstandingFIFO.deq;
    let data <- mem.read.get();
    regFile.upd(r, data);
  endrule

  // Load value at address into register
  method Action load(Register r, Addr addr) if (!init);
    outstandingFIFO.enq(r);
    mem.read.put(addr);
  endmethod

  // Store data to address
  method Action store(Data data, Addr addr) if (!init);
    mem.write(addr, data);
  endmethod

  // Commit (ensure all outstanding operations have completed)
  method Action commit = await(!outstandingFIFO.notEmpty);

  // Obtain value of register
  method Data value(Register r) = regFile.sub(r);

endmodule
