/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Robert N. M. Watson
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014 Colin Rothwell
 * Copyright (c) 2014 Alexandre Joannou
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

/***** MIPSTop.bsv *****
MIPSTop.bsv is the top of the 64-bit MIPS processor implementation and
exports a generic memory client interface, as well as a debug interface
and interrupt lines. Both the pipeline and cache hierarchy are contained
in the mkMIPSTop module in this file.
************************/

import ClientServer::*;
import MasterSlave::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;
import ConfigReg::*;
import MemTypes::*;

// MIPS.bsv contains types and interface declarations that are common among many
// files.
import MIPS::*;
// Memory.bsv describes the memory hierarchy.
import Memory::*;
// ForwardingPipelinedRegFile.bsv describes the register file.
import ForwardingPipelinedRegFile::*;
// Scheduler.bsv describes the register rename stage of the pipeline, the second
// stage.
import Scheduler::*;
// Decode.bsv describes the decode stage of the pipeline, the third stage.
import Decode::*;
// Execute.bsv describes the execute stage of the pipeline, the fourth stage.
import Execute::*;
// MemAccess.bsv describes the memory access stage of the pipeline, the fifth
// stage.
import MemAccess::*;
// Writeback.bsv describes the writeback stage of the pipeline, the sixth stage.
import Writeback::*;
// DebugUnit.bsv describes the debug unit of the processor.
import DebugUnit::*;
// The MICRO version of CHERI has a simplified CP0 (system control processor)
// and branch predictor.
`ifndef MICRO
  // CP0.bsv describes the system control processor holding privileged state
  // such as the TLB.
  import CP0::*;
  // Branch.bsv describes the branch predictor.
  import Branch::*;
`else
  // CP0Micro.bsv describes a simplified system control processor with basic
  // interrupt support but no TLB.
  import CP0Micro::*;
  // BranchSimple.bsv describes a minimal branch predictor.
  import BranchSimple::*;
`endif
// CoProX.bsv describes a generic coprocessor.
//import CoProX::*;
// CoProNull.bsv describes a null coprocessor to satisfy the interface but do
// nothing.
import CoProNull::*;
// ResetBuffer.bsv exports a reset wire so we can reset ourselves and the system.
import ResetBuffer::*;
`ifdef CAP
  // CapCop.bsv describes the optional "Capabilty" coprocessor for enhanced
  // memory protection.
  import CapCop::*;
`endif
// The COP1 flag enables the inclusion of the optional floating point unit.
`ifdef COP1
  // CoProFP.bsv describes the optional floating point unit.
  import CoProFP::*;
  // CoProFPTypes.bsv describes the types for the floating point implementation.
  import CoProFPTypes::*;
  import CoProFPInst::*;
`endif

// MIPSTopIfc is the interface for the processor top level, exporting the memory
// interface as well as interrupts and a debug interface.
interface MIPSTopIfc;
  `ifdef MULTI
    // Instruction cache invalidate interface
    method Action invalidateICache(PhyAddress addr);
    // Data cache invalidate interface
    method Action invalidateDCache(PhyAddress addr);
  interface Master#(CheriMemRequest, CheriMemResponse) imemory;
  interface Master#(CheriMemRequest, CheriMemResponse) dmemory;
  `else
  // Memory client interface (which initializes transactions), 256 bit data
  // width, 35-bit WORD address width. As there are 2^5 = 32 bytes per word,
  // this is equivalent to a 35 + 5 = 40-bit byte address.
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `endif
  // interface below is required for the multiport L2Cache
  //interface Client#(MemoryRequest#(35, 32), BigMemoryResponse#(256)) memory;
  // 5 interrupt lines, matching the standard MIPS spec.
  method Action putIrqs(Bit#(5) interruptLines);
  // Deliver common state to this core.
  method Action putState(Bit#(48) count, Bool pause);
  // Tell the system to pause.  This should pause all cores.
  method Bool getPause();
  // The debug interface is a byte stream interface, a channel of bytes in and a
  // channel of bytes out.
  interface Server#(Bit#(8), Bit#(8)) debugStream;
    // Also a reset out interface. This allows us to reset the system and also
    // ourselves (if it is fed back in).
  method Bool reset_n();
  // Whether we want the trace unit to be recording at each cycle.
endinterface


/***** mkMIPSTop *****
The mkMIPSTop module instantiates the main processor pipeline and memory hierarchy.
**********************/
(* synthesize *)
module mkMIPSTop#(Bit#(16) coreId)(MIPSTopIfc);
  // nextId holds the instruction ID for the next instruction to issue. nextId
  // must have enough bits for a unique id for every instruction in the
  // pipeline, as it will wrap naturally and we do not check that there are no
  // duplicates.
  Reg#(InstId) nextId <- mkConfigReg(0);
  // toScheduler is the first pipeline fifo between instruction fetch and the
  // scheduler (register rename). Like the rest of the pipeline stages, it holds
  // the "ControlTokenT" type which contains all temporary state needed for the
  // execution of an instruction in the pipeline.
  FIFO#(ControlTokenT) toScheduler <- mkFIFO;

  // The MICRO flag will use a simplified CP0 (system control processor) with no
  // TLB and also a simple branch predictor.
  `ifndef MICRO
    // theCP0 is the system control processor containing the TLB and handling
    // exception logic.
    CP0Ifc theCP0 <- mkCP0(coreId);
    // branch is the higher performance branch predictor with a branch history
    // and call stack.
    BranchIfc branch <- mkBranch();
  `else
    // mkCP0Micro makes a CP0 with exception support but no TLB.
    CP0Ifc theCP0 <- mkCP0Micro();
    // BranchSimple is a branch predictor that makes due with nothing but a
    // target buffer.
    BranchIfc branch <- mkBranchSimple();
  `endif
  // If COP1 is defined, instantiate the floating point unit. Otherwise,
  // instantiate a null version so that interfaces still work pass type checks
  // having to `ifdef everywhere.
  `ifdef COP1
    CoProIfc cop1 <- mkCoProFP();
  `else
    CoProIfc cop1 <- mkCoProNull();
  `endif
  // Coprocessor 3 is not a supported coprocessor at this time but can be used
  // for extensions. A null stub is compiled in by default.
  `ifdef COP3
    CoProIfc cop3 <- mkCoPro();
  `else
    CoProIfc cop3 <- mkCoProNull();
  `endif
  // theDebug is the debug unit that is able to control the pipeline and insert
  // instructions. theDebug also consumes an instruction report for each
  // instruction and can report those over the byte stream interface.
  DebugIfc theDebug <- mkDebug();
  // theRF is the general purpose register file with 2 read ports and one write
  // port, enough to not stall for all general purpose MIPS instructions.
  ForwardingPipelinedRegFileIfc#(MIPSReg) theRF <- mkForwardingPipelinedRegFile();
  // theMem is the memory hierarchy which needs the system control processor
  // for TLB integration.
  MIPSMemory theMem <- mkMIPSMemory(coreId,theCP0);
  // The decode stage of the pipeline gets the result of register fetches
  // and therefore has access to any module interface which contains
  // registers the may be used by an instruction.
  PipeStageIfc decode <- mkDecode(theCP0);
  // These are the module instantiations for the "Capability" case which
  // includes our memory protection extensions.
  `ifdef CAP
      // theCapCop is the "Capability coprocessor", logically MIPS coprocessor
      // 2, which inserts itself into the general purpose pipeline for register
      // reads and writes and which also becomes part of the memory path.
      CapCopIfc theCapCop <- mkCapCop(coreId);
      // memAccess is the memory access stage of the pipeline which imports data
      // memory and the capability coprocessor interface
      PipeStageIfc memAccess <- mkMemAccess(theMem.dataMemory, theCapCop);
      // The writeback stage of the pipeline imports lots of interfaces because
      // it updates all system state that results from an instruction commit.
      WritebackIfc writeback <- mkWriteback(theMem, theRF, theCP0, branch, theDebug, cop1, theCapCop, cop3, memAccess);
      // The scheduler pulls the instruction out of the instruction memory interface
      // and reports any branches to the branch unit. The scheduler also submits
      // register read addresses to the register file
      PipeStageIfc scheduler <- mkScheduler(branch, theRF, theCP0, cop1, theCapCop, cop3, theMem.instructionMemory);
      // The execute stage of the pipeline has access to the coprocessor
      // interfaces since they may hold their own uncommitted temporary values,
      // and also the decode interface which it directly accesses so that it can
      // check conditions of the next instruction before consuming and also the
      // writeback interface so that it can receive values loaded from memory
      // for forwarding.
      PipeStageIfc execute <- mkExecute(theRF, writeback, theCP0, cop1, theCapCop, cop3, decode);
  `else
      // memAccess is the memory access stage of the pipeline which imports the
      // data memory interface.
      PipeStageIfc memAccess <- mkMemAccess(theMem.dataMemory);
      // The writeback stage of the pipeline imports lots of interfaces because
      // it updates all system state that results from an instruction commit.
      WritebackIfc writeback <- mkWriteback(theMem, theRF, theCP0, branch, theDebug, cop1, cop3, memAccess);
      // The scheduler pulls the instruction out of the instruction memory interface
      // and reports any branches to the branch unit. The scheduler also submits
      // register read addresses to the register file
      PipeStageIfc scheduler <- mkScheduler(branch, theRF, theCP0, cop1, cop3, theMem.instructionMemory);
      // The execute stage of the pipeline has access to the coprocessor
      // interfaces since they may hold their own uncommitted temporary values,
      // and also the decode interface which it directly accesses so that it can
      // check conditions of the next instruction before consuming and also the
      // writeback interface so that it can receive values loaded from memory
      // for forwarding.
      PipeStageIfc execute <- mkExecute(theRF, writeback, theCP0, cop1, cop3, decode);
  `endif
  // resetBuffer facilitates a system reset triggered from within the processor,
  // currently by the debug unit.
  ResetBufferIfc resetBuffer <- mkResetBuffer();
  
  Reg#(Bool) pause <- mkReg(False);
  
  Reg#(Bool) init0 <- mkReg(True);
  rule doInit0(init0);
    theRF.writeRaw(0,0);
    init0 <= False;
  endrule

  // If coprocessor 1 is present, feed memory requests to memory and responses
  // to the coprocessor. The default coprocessor 1 is the floating point unit
  // which does not use this interface (which is designed for moving 256-bit
  // words directly from the coprocessor), so these rules do nothing without a
  // custom coprocessor.
  `ifdef COP1
    rule cop1ToMem;
      CoProMemAccess memReq <- cop1.coProMem.request.get();
      theMem.cop1Memory.request.put(memReq);
    endrule
    rule memToCop1;
      CoProReg response <- theMem.cop1Memory.response.get();
      cop1.coProMem.response.put(response);
    endrule
  `endif
  
  // If a coprocessor 3 is present, feed memory requests to memory and responses
  // to the coprocessor. This is for 256-bit loads and stores directly from the
  // optional coprocessor.
  `ifdef COP3
    rule cop3ToMem;
      CoProMemAccess memReq <- cop3.coProMem.request.get();
      theMem.cop3Memory.request.put(memReq);
    endrule
    rule memToCop3;
      CoProReg response <- theMem.cop3Memory.response.get();
      cop3.coProMem.response.put(response);
    endrule
  `endif
  // Just put the cache configuration from the cache into the system control
  // coprocessor. This is pretty much static and should reduce to a register
  rule reportCacheConfig;
    theRF.putDebugRegs(theDebug.getOpA(), theDebug.getOpB());
    theCP0.putCacheConfiguration(theMem.configuration.iCacheGetConfig,theMem.configuration.dCacheGetConfig);
    theCP0.putDeterministicCycleCount(theDebug.getDeterministicCycleCount);
  endrule
  
  rule reportCommittingToL2Cache;
    Bool commit <- writeback.nextWillCommit();
    theMem.nextWillCommit(commit);
  endrule

  /*  This pipeline has 6 stages:
      Instruction Fetch -> Scheduler -> Decode -> Execute -> Memory Access -> Writeback
        Instruction Fetch: Submits PC to memory.
        Scheduler: Receives instruction from memory, does a pre-decode noting
        dependencies and submits requests to Register File.
        Decode: Receives from Register File and does Decode.
        Execute: Performs execute on decoded instruction and registers.
        Memory Access: Conditionally submits request to memory.

        Writeback: Possibly receives from memory and performs register writeback
        and initiates exceptions.
  */

  // Rules //

  // This is the instruction fetch stage of the pipeline. Its key functions are
  // to get the next PC, request the instruction from the memory system, and
  // construct a control token to insert into the pipeline.
  rule instructionFetch(!pause);
    // Get the next program counter (and current epoch) from the branch
    // predictor. The epoch is a rolling counter that is constant for each
    // stream of instructions between branch misses. When we get a miss, we
    // change the current epoch and all instructions from the previous epoch
    // must be flushed.
    PcAndEpoch pce <- branch.getPc(nextId, False);
    // Get the pc from the PcAndEpoch data structure.
    Address nextPC = pce.pc;
    // Check if this address is a breakpoint according to the debug unit.
    Bool breakpoint <- theDebug.checkPC(nextPC);
    // Initialize a default control token to insert in the pipeline.
    ControlTokenT ct = defaultControlToken;
    // Initialize fields of the control token, namely, the epoch it belongs to
    // and the instruction ID for this instruction.
    ct.epoch = pce.epoch;
    ct.id = nextId;
    // Also assign the next PC of the control token.
    ct.pc = nextPC;
    /*
    // If this program counter was a breakpoint in the debug unit, kill this
    // instruction and flush the pipe. The debug unit will pause the pipe and
    // prevent this rule from firing again until directed to do so.
    if (breakpoint) begin
      ct.dead = True;
      ct.flushPipe = True;
    end
    */
    `ifdef MULTI
      // Insert the coreID and/or the threadID into the Control Token. This will
      // allow core or thread identification during debugging.
      ct.coreCount = fromInteger(valueOf(CORE_COUNT) - 1);
      ct.coreID = coreId;
      ct.threadID = 0;
    `endif
    // Enq this control token to the toScheduler FIFO to be consumed when the
    // instruction is also ready to be consumed.
    toScheduler.enq(ct);
    // Increment the instruction ID for the next fetch.
    nextId <= nextId + 1;
    // Submit the read request to instruction memory.
    theMem.instructionMemory.reqInstruction(nextPC, ct.id);
    debug($display("Fetching from %X at time %t, Id=%d", nextPC, $time(), nextId));
  endrule
  // This rule, debug instruction fetch, is similar to the previous rule but
  // fetches the instruction from the Debug unit. The debug unit may insert
  // instructions into the pipeline to perform arbitrary functions. Common uses
  // might be reading a memory location, the program counter, or the value of a
  // register. All writebacks to register 0 from instructions from the debug
  // unit go back to the debug unit. All usual interfaces must also be used
  // (though their results may not be) to ensure the pipeline does not stall.
  rule debugInstructionFetch(pause);
    // Fetch the pc and epoch, though they are not relevant for this instruction.
    PcAndEpoch pce <- branch.getPc(nextId, True);
    // Construct a control token with the default values.
    ControlTokenT ct = defaultControlToken;
    // Assign the current epoch and the next instruction ID as normal.
    ct.epoch = pce.epoch;
    ct.id = nextId;
    // Set the PC to rubbish. We want to make sure this is never used and that
    // it is obvious if it is.
    ct.pc = 64'hfeedfeeddeadbeef;
    // Tag this instruction as from the debug unit.
    ct.fromDebug = True;
    // Make sure we do not write the PC by default from this instruction.
    ct.writePC = False;
    // Get the actual instruction from the debug unit and do some initial parsing.
    Bit#(32) instruction <- theDebug.client.request.get();
    // Categorize the instruction, poking it into a tagged type according to its
    // fields.
    ct.inst = classifyMIPSInstruction(instruction);
    // Enq the control token to the scheduler/register rename stage.
    toScheduler.enq(ct);
    // increment the instruction id.
    nextId <= nextId + 1;
    // Submit the (rubbish) instruction memory request to instruction memory.
    // This will likely cause a TLB miss.
    Address addr = 64'b0;
    theMem.instructionMemory.reqInstruction(addr, ct.id);
    debug($display("Debug fetching at time %t, Id=%d", $time(), nextId));
  endrule
  // This rule deqs from the toScheduler fifo and enqs to the scheduler, likely
  // because the instruction fetch has finished.
  rule fromFetchToScheduler;
    // Assign the name ct to the top element of the toScheduler fifo.
    ControlTokenT ct = toScheduler.first;
    // Enq ct to the scheduler module fifo interface. The logic for the
    // scheduler/register rename stage happens./simn the enq.
    scheduler.enq(ct);
    // Deq the toScheduler fifo.
    toScheduler.deq();
  endrule
  // This function checks if an instruction is a CP0 instruction. This is used
  // in the next rule to avoid instructions that may read CP0 state from
  // proceeding until all instructions that modify CP0 state have completed.
  function Bool isCP0(InstructionT x);
      // Return False (not a CP0 instruction) by default.
      Bool ret = False;
      // If the instruction is of the Register category...
      if (x matches tagged Register .ri) begin
        // And the opcode is COP0, indicate that this is a CP0 instruction.
        if (ri.op == COP0 || ri.op == SPECIAL3) ret = True;
      end
      if (x matches tagged Coprocessor .ci) begin
        ret = True;
      end
      return ret;
  endfunction
  // This rule takes a token from the scheduler/register rename stage and enqs
  // it to the decode stage. The conditions on this rule only allow it to fire
  // when a CP0 write is pending and we are about to decode (and fetch the
  // registers for) another CP0 instruction.
  rule fromSchedulerToDecode(!(isCP0(scheduler.first.inst) && theCP0.writePending));
    // Enq the top element in the scheduler output fifo to decode.
    // The enq interface of this module actually performs the decode pipeline stage.
    decode.enq(scheduler.first);
    // Deq the first element from the scheduler output fifo.
    scheduler.deq();
  endrule

  // The fromDecodeToExecute rule enqs the top element from the output fifo in
  // the decode stage to the execute stage of the pipeline.
  //(* descending_urgency = "fromDecodeToExecute, execute_doReadReport" *)
  rule fromDecodeToExecute;
    // Enq the top element of the output fifo of the decode stage to the execute
    // input fifo.
    execute.enq(decode.first);
    // Deq the decode stage output fifo.
    decode.deq();
  endrule
  // The fromExecteToMemAccess rule deqs the top element of the execute stage
  // output fifo and enqs it to memAccess.
  rule fromExecuteToMemAccess;
    // Enq the control token in the output fifo of the execute stage to the enq
    // method of memAccess which implements the memory access stage of the
    // pipeline.
    memAccess.enq(execute.first);
    // Remove the control token from the output fifo in the execute stage of the
    // pipeline.
    execute.deq();
  endrule

  // This rule simply demarcates cycles in a simulation trace with debug output
  // enabled.
  rule tick;
    debug($display("%t: Tick", $time()));
  endrule
  // This putResetOut rule passes a reset signal into the resetBuffer. If the
  // input signal goes low for any cycle,  the output of the reset buffer will
  // go low for many, many cycles, regardless of the general reset into the
  // system.
  rule putResetOut;
    resetBuffer.resetIn(theDebug.reset_n());
  endrule

  // Export the interrupts interface on theCP0 as the putIrqs interface of this
  // module.
  interface putIrqs = theCP0.interrupts;
  `ifndef MULTI
  // Export theMem.memory main memory interface as the memory interface of this
  // top level module.
  interface memory = theMem.memory;
  `else
  interface imemory = theMem.imemory;
  interface dmemory = theMem.dmemory;
  `endif
  // Export theDebug.strem interface as the debugStream interface of this top
  // level module.
  interface debugStream = theDebug.stream;

  `ifdef MULTI
    interface invalidateICache = theMem.invalidateICache;
    interface invalidateDCache = theMem.invalidateDCache;
  `endif
  // Assign the reset_n output of this module to the reset_n_out method of the
  // resetBuffer module.
  method reset_n() = resetBuffer.reset_n_out();
  // Delever a new pause state to the system.
  method getPause() = theDebug.getPause();
  // Get some state elements for the system.
  method Action putState(Bit#(48) count, Bool commonPause);
    theCP0.putCount(count[31:0]);
    writeback.putCycleCount(count);
    theDebug.pause(commonPause);
    pause <= commonPause;
  endmethod
endmodule
