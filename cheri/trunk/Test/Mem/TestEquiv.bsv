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

import MemoryClient :: *;
import Vector       :: *;
import BlueCheck    :: *;
import MemTypes     :: *;
import StmtFSM      :: *;
import Memory       :: *;
import Clocks       :: *;
import FIFOF        :: *;
import Assert       :: *;
import Printf       :: *;

`ifdef CAP
`define USECAP=1
`endif

`ifdef CAP128
`define USECAP=1
`endif

// ============================================================================
// Single-core
// ============================================================================

// Test equivalance against the golden model.
module [BlueCheck] checkSingle#( MemoryClient core
                               , MemoryClient gold
                               ) ();

  Reg#(Bit#(16)) timeout <- mkReg(0);
  Reg#(Bool) init <- mkReg(True);
  Reg#(Bool) testCacheOps <- mkReg(False);
  Reg#(Bool) testCancelledOps <- mkReg(False);

  // Test explicit writeback operations only when enabled via command line
  function Action writeback(Bool invalidate, CacheName cache, Addr addr) =
    action
      await(testCacheOps);
      if (invalidate)
        core.invalidateWriteback(cache, addr);
      else
        core.writeback(cache, addr);
    endaction;
 
  // Test cancelled load only when enabled via command line
  function Action cancelledLoad(Addr addr) =
    action
      await(testCancelledOps);
      core.cancelledLoad(addr);
    endaction;

  // Test cancelled store only when enabled via command line
  function Action cancelledStore(Data data, Addr addr) =
    action
      await(testCancelledOps);
      core.cancelledStore(data, addr);
    endaction;
 
  // For simple LL/SC testing
  function Stmt llsc(Data data, Addr addr) = 
    seq
      action
        core.loadLinked(addr);
        gold.load(addr);
      endaction
      action
        core.storeCondIgnore(data, addr);
        gold.store(data, addr);
      endaction
    endseq;

  pre("setAddrMap", core.setAddrMap);
  equivf(3, "load" , core.load , gold.load);
  equivf(3, "store", core.store, gold.store);
  equivf(3, "nop"  , core.nullRequest , gold.nullRequest);
  equivf(3, "getResponse", core.getResponse, gold.getResponse);

  //propf(3, "nullRequest", core.nullRequest);

  `ifdef USECAP
  equiv("loadCap", core.loadCap, gold.loadCap);
  equiv("storeCap", core.storeCap, gold.storeCap);
  `endif

  equiv("instrLoad", core.instrLoad, gold.instrLoad);
  equiv("getInstrResponse", core.getInstrResponse, gold.getInstrResponse);

  prop("writeback", writeback(False));
  prop("invalidateWriteback", writeback(True));
  prop("cancelledLoad", cancelledLoad);
  prop("cancelledStore", cancelledStore);

  // Read command-line arguments
  rule initialise (init);
    let b1 <- $test$plusargs("cacheops");
    testCacheOps <= b1;
    let b2 <- $test$plusargs("cancelled");
    testCancelledOps <= b2;
    init <= False;
  endrule

endmodule

// ============================================================================
// Dual-core exclusive
// ============================================================================

// Have a memory client and golden model for each core.
// Check equivalence when accessing exclusive address range: one
// client uses only odd addresses, the other only even ones.
// In other words, no locations are shared (but lines are).

`ifdef MULTI
module [BlueCheck] checkDualExclusive#(
   Vector#(CORE_COUNT, MemoryClient) core
 , Vector#(CORE_COUNT, MemoryClient) gold
) ();

  // Load exclusively of other core
  function Action loadEx(Vector#(CORE_COUNT, MemoryClient) client, Addr a) =
    client[a.dword].load(a);

  // Store exclusively of other core
  function Action storeEx(Vector#(CORE_COUNT, MemoryClient) client,
                          Data d, Addr a) =
    client[a.dword].store(d, a);

  function Action setSameAddrMap(AddrMap map) =
    action
      for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1)
        core[i].setAddrMap(map);
    endaction;

  pre("setAddrMap", setSameAddrMap);
  equiv("load", loadEx(core) , loadEx(gold));
  equiv("store", storeEx(core), storeEx(gold));
  for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1)
    equiv("getResponse", core[i].getResponse, gold[i].getResponse);

endmodule
`endif

// ============================================================================
// Check shared memory model
// ============================================================================

`ifdef MULTI

// Various memory models
typedef enum {
    SC  = 0
  , TSO = 1
  , PSO = 2
  , WMO = 3
  , POW = 4
  , TIM = 5
} Model deriving (Bits, FShow);

// ==========
// Operations
// ==========

// Load word, store word, read-modify-write, sync
typedef enum { LW, SW, NOP, RMW, SYNC } Op
  deriving (Bits, Bounded, Eq, FShow);

// Custom generator for Op.  LW and SW more likely than RMW and SYNC.
// RMW and SYNC also have to be enabled via command line.
module [BlueCheck] genOp (Gen#(Op));
  Gen#(Bit#(4)) numGen <- mkGenDefault;
  method ActionValue#(Op) gen;
    Bool sync <- $test$plusargs("sync");
    Bool llsc <- $test$plusargs("llsc");

    Op op;
    let n <- numGen.gen;
    if      (n < 8)  op = LW;
    else if (n < 12) op = SW;
    else if (n < 13) op = NOP;
    else if (n < 14) op = RMW;
    else             op = SYNC;

    if      (op == SYNC && !sync) op = NOP;
    else if (op == RMW  && !llsc) op = NOP;

    return op;
  endmethod
endmodule

instance MkGen#(Op);
  mkGen = genOp;
endinstance

// =============
// Axe interface
// =============

import "BDPI" function Action axeInit(Model model);
import "BDPI" function Action axeLoad(
  Bit#(2) threadId, Bit#(64) addr, Bit#(32) reqTime);
import "BDPI" function Action axeStore(
  Bit#(2) threadId, Bit#(32) data, Bit#(64) addr, Bit#(32) reqTime);
import "BDPI" function Action axeRMW(
  Bit#(2) threadId, Bit#(32) data, Bit#(64) addr, Bit#(32) reqTime);
import "BDPI" function Action axeSync(Bit#(2) threadId, Bit#(32) reqTime);
import "BDPI" function Action axeResponse(
  Bit#(2) threadId, Bit#(32) data, Bit#(32) respTime);
import "BDPI" function ActionValue#(Bool) axeCheck(Bool showTrace);

// =====================
// Memory model checking
// =====================

// Number of different variable locations to use
typedef 2 LOG_NUM_VARS;

// BlueCheck spec
module [BlueCheck] checkMemoryModel#(
   Vector#(CORE_COUNT, MemoryClient) core
) ();
  Reg#(Model) memoryModel <- mkReg(SC);
  Reg#(Bool) showTrace <- mkReg(False);
  Vector#(CORE_COUNT, Reg#(Bit#(13))) uniqueData <- replicateM(mkReg(1));
  Reg#(Bool) init <- mkReg(True);
  Reg#(Bool) active <- mkReg(False);
  Reg#(Vector#(TExp#(LOG_NUM_VARS), Addr)) vars <- mkReg(replicate(?));
  EnsureMsg ensure <- getEnsureMsg;
  Vector#(CORE_COUNT, Reg#(Bool)) rmwInProgress <- replicateM(mkReg(False));
  Vector#(CORE_COUNT, Reg#(Addr)) rmwAddr <- replicateM(mkRegU);
  Reg#(Bit#(32)) timestamp <- mkReg(0);

  rule initRule (init);
    init <= False;
    Bool tso <- $test$plusargs("tso");
    Bool pso <- $test$plusargs("pso");
    Bool wmo <- $test$plusargs("wmo");
    Bool pow <- $test$plusargs("pow");
    Bool tim <- $test$plusargs("tim");
    Bool trace <- $test$plusargs("showtrace");
    Model m = SC;
    if (tso)      m = TSO;
    else if (pso) m = PSO;
    else if (wmo) m = WMO;
    else if (pow) m = POW;
    else if (tim) m = TIM;
    memoryModel <= m;
    showTrace <= trace;
    $display("Testing memory model: ", fshow(m));
  endrule

  rule incTimestamp;
    timestamp <= timestamp+1;
  endrule

  // Set same address map on each memory client
  function Action setSameAddrMap(AddrMap map) =
    action
      for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1)
        core[i].setAddrMap(map);
    endaction;

  // The statement is run before each test sequence.
  Stmt initialise =
    seq
      await(!init);
      action
        for (Integer c = 0; c < valueOf(CORE_COUNT); c=c+1) begin
          uniqueData[c] <= 1;
          rmwInProgress[c] <= False;
        end
        axeInit(memoryModel);
        active <= True;
      endaction
      timestamp <= 0;
      delay(512);
    endseq;

  function Action chooseVars(Vector#(TExp#(LOG_NUM_VARS), Addr) addrs) =
    action
      vars <= addrs;
    endaction;

  function Action operation(Integer coreId, Op op, Bit#(LOG_NUM_VARS) index) =
    action
      await(!rmwInProgress[coreId] || op == RMW);
      let a = vars[index];
      if (!rmwInProgress[coreId]) begin
        if (op == LW) begin
          core[coreId].load(a);
          axeLoad(fromInteger(coreId), extend(pack(a)), timestamp);
        end
        else if (op == SW) begin
          Data d = { uniqueData[coreId], fromInteger(coreId) };
          uniqueData[coreId] <= uniqueData[coreId]+1;
          core[coreId].store(extend(d), a);
          axeStore(fromInteger(coreId), extend(d), extend(pack(a)), timestamp);
        end
        else if (op == NOP) begin
          core[coreId].nullRequest();
          //axeLoad(fromInteger(coreId), extend(pack(a)));
        end
        else if (op == RMW) begin
          rmwInProgress[coreId] <= True;
          rmwAddr[coreId] <= a;
          core[coreId].loadLinked(a);
          Data d = { uniqueData[coreId], fromInteger(coreId) };
          axeRMW(fromInteger(coreId), extend(d), extend(pack(a)), timestamp);
        end
        else if (op == SYNC) begin
          core[coreId].sync();
          axeSync(fromInteger(coreId), timestamp);
        end
      end else if (op == RMW) begin
        rmwInProgress[coreId] <= False;
        Data d = { uniqueData[coreId], fromInteger(coreId) };
        uniqueData[coreId] <= uniqueData[coreId]+1;
        core[coreId].storeConditional(extend(d), rmwAddr[coreId]);
      end
    endaction;

  function Action response(Bool guard, Integer i) =
    action
      await(guard);
      let resp <- core[i].getResponse;
      case (resp) matches
        tagged DataResponse .d:
          axeResponse(fromInteger(i), extend(d), timestamp);
        tagged SCResponse .d:
          begin
            axeResponse(fromInteger(i), extend(d), timestamp);
          end
        default: $display("Unexpected response");
      endcase
    endaction;

  function Bool allResponsesConsumed();
    Bool b = True;
    for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1)
      b = b && core[i].done;
    return b;
  endfunction

  function Bool anyResponseAvailable();
    Bool b = False ;
    for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1)
      b = b || core[i].canGetResponse;
    return b;
  endfunction

  function Stmt consumeResponses();
    Stmt s = seq delay(1); endseq;
    for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1)
      s = seq s; if (!core[i].done) action response(!active, i); endaction
    endseq;
    return s;
  endfunction

  // Wedge detection
  Reg#(Bit#(10)) timer <- mkReg(0);
  Bit#(10) timeout = 900;

  // This is run at the end of each test sequence.
  Stmt check =
    seq
      action timer <= 0; active <= False; endaction
      while (timer < timeout && !allResponsesConsumed()) seq
        if (anyResponseAvailable())
          seq timer <= 0; consumeResponses(); endseq
        else
          timer <= timer+1;
      endseq

      if (timer == timeout)
        ensure(False, $format("Probable wedge"));

      action
        Bool ok <- axeCheck(showTrace);
        Fmt msg = $format("Failed!");
        ensure(ok, msg);
      endaction
    endseq;

  pre("", initialise);
  pre("setAddrMap", setSameAddrMap);
  pre("chooseVars", chooseVars);

  Vector#(CORE_COUNT, String) strs;
  Vector#(CORE_COUNT, String) rstrs;
  for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1) begin
    strs[i] = sprintf("core[%d].op", i);
    prop(strs[i], operation(i));
    rstrs[i] = sprintf("core[%d].getResponse", i);
    prop(rstrs[i], response(active, i));
  end
  //parallelf(6, toList(append(strs, rstrs)));
  post("", check);
endmodule

`endif

// ============================================================================
// Top-level testbenches
// ============================================================================

// Single-core
module [Module] mkTestMemSingle#(MIPSMemory mipsMemory, MakeResetIfc r) ();
  // Implementation
  MemoryClient core <- mkMemoryClient(mipsMemory, reset_by r.new_rst);

  // Golden model
  MemoryClient gold <- mkMemoryClientGolden(reset_by r.new_rst);

  // BlueCheck parameters
  BlueCheck_Params params = bcParamsID(r);
  params.wedgeDetect = True;
  function double(x) = x*2;
  params.id.incDepth = double;
  params.id.initialDepth = 4;
  params.id.testsPerDepth = 1000;
  params.numIterations = 12;

  // Generate checker
  Stmt s <- mkModelChecker(checkSingle(core, gold), params);
  mkAutoFSM(s);
endmodule

// Dual-core exclusive
`ifdef MULTI
module [Module] mkTestMemDualExclusive#(
    Vector#(CORE_COUNT, MIPSMemory) mipsMemories
  , MakeResetIfc r
) ();

  // Currently only dual-core supported
  staticAssert(valueOf(CORE_COUNT) == 2, "MULTI != 2");

  // Implementation
  Vector#(CORE_COUNT, MemoryClient) core;

  // Golden model
  Vector#(CORE_COUNT, MemoryClient) gold;

  // Construct
  for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1) begin
    MemoryClient c <- mkMemoryClient(mipsMemories[i], reset_by r.new_rst);
    MemoryClient g <- mkMemoryClientGolden(reset_by r.new_rst);
    core[i] = c;
    gold[i] = g;
  end

  // BlueCheck parameters
  BlueCheck_Params params = bcParamsID(r);
  params.wedgeDetect = True;
  function double(x) = x*2;
  params.id.incDepth = double;
  params.numIterations = 8;

  // Generate checker
  Stmt s <- mkModelChecker(checkDualExclusive(core, gold), params);
  mkAutoFSM(s);

endmodule
`endif

// Memory-model checking
`ifdef MULTI
module [Module] mkTestMemoryModel#(
    Vector#(CORE_COUNT, MIPSMemory) mipsMemories
  , MakeResetIfc r
) ();

  // Implementation
  Vector#(CORE_COUNT, MemoryClient) core;

  // Construct
  for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1) begin
    MemoryClient c <- mkMemoryClient(mipsMemories[i], reset_by r.new_rst);
    core[i] = c;
  end

  // BlueCheck parameters
  BlueCheck_Params params = bcParamsID(r);
  params.wedgeDetect = True;
  params.id.initialDepth = 32;
  function incr(x) = x+(x>>1); // x=x*1.5
  params.id.incDepth = incr;
  params.numIterations = 16;
  params.id.testsPerDepth = 1000;
  params.useShrinking = True;//False;
  
  // Generate checker
  Stmt s <- mkModelChecker(checkMemoryModel(core), params);
  mkAutoFSM(s);

endmodule
`endif
