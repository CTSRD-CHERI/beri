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

// ============================================================================
// Single-core
// ============================================================================

// Test equivalance against the golden model.
module [BlueCheck] checkSingle#( MemoryClient core
                               , MemoryClient gold
                               ) ();

  Reg#(Bool) init <- mkReg(True);
  Reg#(Bool) testCacheOps <- mkReg(False);
  Reg#(Bool) testCancelledOps <- mkReg(False);

  EnsureMsg ensure <- getEnsureMsg;

  // This statement is run at the end of each test sequence.  It commits
  // all outstanding loads to the register file, and compares the
  // register contents against the golden model.
  Stmt commitAndCompare =
    seq
      action
        core.commit;
        gold.commit;
        Bool ok = True;
        Fmt msg = $format("");
        for (Integer i = 0; i < valueOf(SizeOf#(Register)); i=i+1)
          begin
            Register r = register(i);
            Data x     = core.value(r);
            Data y     = gold.value(r);
            if (x != y)
              begin
                msg = $format("Register ", fshow(r), " differs: ",
                              "you say ", x, ", golden model says ", y);
                ok = False;
              end
          end
        ensure(ok, msg);
      endaction
    endseq;

  // Test explicit writeback operations only when enabled via command line
  function Action writeback(Bool invalidate, CacheName cache, Addr addr) =
    action
      await(testCacheOps);
      if (invalidate)
        core.invalidateWriteback(cache, addr);
      else
        core.writeback(cache, addr);
    endaction;
 
  // Test cancalled load only when enabled via command line
  function Action cancelledLoad(Register dest, Addr addr) =
    action
      await(testCancelledOps);
      core.cancelledLoad(dest, addr);
    endaction;

  // Test cancalled store only when enabled via command line
  function Action cancelledStore(Data data, Addr addr) =
    action
      await(testCancelledOps);
      core.cancelledStore(data, addr);
    endaction;
 
  equivf(2, "load" , core.load , gold.load);
  equivf(2, "store", core.store, gold.store);
  prop("writeback", writeback(False));
  prop("invalidateWriteback", writeback(True));
  prop("cancelledLoad", cancelledLoad);
  prop("cancelledStore", cancelledStore);
  addPostStmt(commitAndCompare);

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

  EnsureMsg ensure <- getEnsureMsg;

  // This statement is run at the end of each test sequence.  It commits
  // all outstanding loads to the register file, and compares the
  // register contents against the golden model.
  function Stmt commitAndCompare(Integer coreId) =
    seq
      action
        core[coreId].commit;
        gold[coreId].commit;
        Bool ok = True;
        Fmt msg = $format("");
        for (Integer i = 0; i < valueOf(SizeOf#(Register)); i=i+1)
          begin
            Register r = register(i);
            Data x     = core[coreId].value(r);
            Data y     = gold[coreId].value(r);
            if (x != y)
              begin
                msg = $format("Register ", fshow(r), " differs: ",
                              "you say ", x, ", golden model says ", y);
                ok = False;
              end
          end
        ensure(ok, msg);
      endaction
    endseq;

  // Load exclusively of other core
  function Action loadEx(Vector#(CORE_COUNT, MemoryClient) client,
                         Register r, Addr a) =
    client[a.addr[0]].load(r, a);

  // Store exclusively of other core
  function Action storeEx(Vector#(CORE_COUNT, MemoryClient) client,
                          Data d, Addr a) =
    client[a.addr[0]].store(d, a);

  equiv("load", loadEx(core) , loadEx(gold));
  equiv("store", storeEx(core), storeEx(gold));
  for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1)
    addPostStmt(commitAndCompare(i));

endmodule
`endif

// ============================================================================
// Check shared memory model
// ============================================================================

`ifdef MULTI

// Various memory models
typedef enum {
    SC         = 0
  , TSO        = 1
  , PSO        = 2
  , RMO        = 3
  , SCMinusSA  = 4
  , TSOMinusSA = 5
  , PSOMinusSA = 6
  , RMOMinusSA = 7
} Model deriving (Bits, FShow);

// Various operations, e.g. load word, store word
typedef enum { LW, SW } Op
  deriving (Bits, Bounded, Eq, FShow);

// Axe interface
import "BDPI" function Action axeInit(Model model);
import "BDPI" function Action axeLoad(
  Bit#(2) threadId, Bit#(8) dest, Bit#(64) addr);
import "BDPI" function Action axeStore(
  Bit#(2) threadId, Bit#(32) data, Bit#(64) addr);
import "BDPI" function Action axeSetReg(
  Bit#(2) threadId, Bit#(8) dest, Bit#(32) data);
import "BDPI" function ActionValue#(Bool) axeCheck(Bool showTrace);

// Number of different variable locations to use
typedef 1 LOG_NUM_VARS;

// BlueCheck spec
module [BlueCheck] checkMemoryModel#(
   Vector#(CORE_COUNT, MemoryClient) core
) ();

  Reg#(Model) memoryModel <- mkReg(SC);
  Reg#(Bool) showTrace <- mkReg(False);
  Vector#(CORE_COUNT, Reg#(Register)) destReg <- replicateM(mkReg(0));
  Vector#(CORE_COUNT, Reg#(Bit#(13))) uniqueData <- replicateM(mkReg(1));
  Reg#(Bool) init <- mkReg(True);
  EnsureMsg ensure <- getEnsureMsg;
  Reg#(Vector#(TExp#(LOG_NUM_VARS), Addr)) vars <- mkReg(replicate(0));
  Reg#(Bool) varsChosen <- mkReg(False);

  rule initRule (init);
    init <= False;
    Bool tso <- $test$plusargs("tso");
    Bool pso <- $test$plusargs("pso");
    Bool rmo <- $test$plusargs("rmo");
    Bool tsoMinusSA <- $test$plusargs("tsomsa");
    Bool trace <- $test$plusargs("showtrace");

    Model m = SC;
    if (tsoMinusSA)
      m = TSOMinusSA;
    else if (tso)
      m = TSO;
    else if (pso)
      m = PSO;
    else if (rmo)
      m = RMO;
    memoryModel <= m;
    showTrace <= trace;

    $display("Testing memory model: ", fshow(m));
  endrule

  // The statement is run before each test sequence.
  Stmt initialise =
    seq
      await(!init);
      action
        for (Integer c = 0; c < valueOf(CORE_COUNT); c=c+1) begin
          destReg[c] <= 0;
          uniqueData[c] <= 1;
        end
        axeInit(memoryModel);
        varsChosen <= False;
      endaction
      delay(512);
    endseq;

  // This statement is run at the end of each test sequence.
  Stmt commitAndCheck =
    seq
      action
        for (Integer c = 0; c < valueOf(CORE_COUNT); c=c+1)
          core[c].commit;
      endaction
      action
        for (Integer c = 0; c < valueOf(CORE_COUNT); c=c+1)
          for (Integer i = 0; i < valueOf(TExp#(SizeOf#(Register))); i=i+1)
            begin
              Register r = register(i);
              Data x     = core[c].value(r);
              axeSetReg(fromInteger(c), extend(r.regId), extend(x));
            end
      endaction
      action
        Bool ok <- axeCheck(showTrace);
        Fmt msg = $format("Failed!");
        ensure(ok, msg);
      endaction
    endseq;

  function Action chooseVars(Vector#(TExp#(LOG_NUM_VARS), Addr) addrs) =
    action
      await(!varsChosen);
      vars <= addrs;
      varsChosen <= True;
    endaction;

  function Action operation(Integer coreId, Op op, Bit#(LOG_NUM_VARS) index) =
    action
      await(varsChosen);
      let a = vars[index];
      if (op == LW) begin
        destReg[coreId].regId <= destReg[coreId].regId+1;
        core[coreId].load(destReg[coreId], a);
        axeLoad(fromInteger(coreId), extend(destReg[coreId].regId)
                                   , extend(a.addr));
      end
      else if (op == SW) begin
        Data d = { uniqueData[coreId], fromInteger(coreId) };
        uniqueData[coreId] <= uniqueData[coreId]+1;
        core[coreId].store(extend(d), a);
        axeStore(fromInteger(coreId), extend(d), extend(a.addr));
      end
    endaction;

  Vector#(CORE_COUNT, String) strs;
  for (Integer i = 0; i < valueOf(CORE_COUNT); i=i+1) begin
    strs[i] = sprintf("core[%d].op", i);
    prop(strs[i], operation(i));
  end
  prop("chooseVars", chooseVars);
  parallel(toList(strs));
  addPreStmt(initialise);
  addPostStmt(commitAndCheck);

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

  // Generate checker
  Stmt s <- mkModelChecker(checkMemoryModel(core), params);
  mkAutoFSM(s);

endmodule
`endif
