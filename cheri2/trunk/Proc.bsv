/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2011-2013 Jonathan Woodruff
 * Copyright (c) 2012-2013 Robert M. Norton
 * Copyright (c) 2013 Alex Horsman
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
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
 *
 ******************************************************************************
 *
 * Author: Nirav Dave <ndave@csl.sri.com>
 *         Robert M. Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Top-Level Cheri Processor
 *
 ******************************************************************************/

import MIPS::*;
import CHERITypes::*;
import Debug::*;

import EHR::*;
import CP0::*;
`ifdef CP1X
import CP1X::*;
`endif
import RegisterFile::*;
import Memory::*;
import BranchPredictor::*;
import ThreadScheduler::*;
import PIC::*;

import CapabilityRegisterFile::*;
`ifdef CAP
import CapCop::*;
import CapabilityMicroTypes::*;
`endif


import DebugUnit :: *;
import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import SearchFIFO::*;
import Vector::*;
import FShow::*;
import ClientServer::*;
import ConfigReg::*;
import List::*;

import CheriAxi::*;
import Peripheral::*;
import DecodeTypes::*;
import Decode::*;
import Execute::*;
import MulDiv::*;

import Processor::*;
import Library::*;

(*synthesize, options="-aggressive-conditions"*)
module mkCheri(Processor);
  //Vector#(NumThreads, EHR#(2,Bool))          flushingPipelineP <- replicateM(mkEHR(False)); // Are we flushing each thread currently?
  // Currently using a ConfigReg here to avoid a backwards SB constraint from fetch/execute to writeback. This is not ideal but doesn't
  // really matter -- it just means one more instruction might go past execute before flushing starts.
  Vector#(NumThreads, EHR#(3,Bool))       flushingPipelineP <- replicateM(mkEHR(False));

  Vector#(NumThreads,Reg#(Maybe#(Address))) branchDelayNextPC <- replicateM(mkReg(Invalid)); // what's the real next PC for branch delay

  //Pipeline "Registers"

   let      fet2decQ_debug <- mkFIFOF_Debug(mkPipeFIFOF,1);
   FIFOF#(FetInst) fet2decQ = fet2decQ_debug.inf;

   //let      dec2exeQ_debug <- mkFIFOF_Debug(mkPipeFIFOF,1);
   function nullSearch(x,y) = Invalid;
   let sdec2exeQ <- mkSFIFO1(0,1,99,2, nullSearch);
   module mkD2EQ(FIFOF#(DecInst)); return sdec2exeQ.fifo; endmodule
   let      dec2exeQ_debug <- mkFIFOF_Debug(mkD2EQ,1);
  FIFOF#(DecInst) dec2exeQ = dec2exeQ_debug.inf;

  // YYY ndave: If these SFIFOs searched an extended type we could forward HI/LO as well

//  SFIFO#(ExeInst, ThreadRegName, Value)  sexe2memQ <- mkSFIFO1_ne_nf_deq_search_enq_EHR(searchExe);
//  SFIFO#(MemInst, ThreadRegName, Value)  smem2memQ <- mkSFIFO1_ne_nf_deq_enq_search_EHR(searchMem);
//  SFIFO#(MemInst, ThreadRegName, Value)   smem2wbQ <- mkSFIFO1_ne_nf_deq_enq_search_EHR(searchMem);

  SFIFO#(ExeInst, ThreadRegName, Value)  sexe2memQ <- mkSFIFO1(0,1,1,2, searchExe);
  SFIFO#(MemInst, ThreadRegName, Value)  smem2memQ <- mkSFIFO1(0,1,2,2, searchMem);
  SFIFO#(MemInst, ThreadRegName, Value)   smem2wbQ <- mkSFIFO1(0,1,2,2, searchMem);

  FIFOF#(ExeInst) exe2memQ = sexe2memQ.fifo;
  FIFOF#(MemInst) mem2memQ = smem2memQ.fifo;
  FIFOF#(MemInst) mem2wbQ  = smem2wbQ.fifo;

  // list of searching interfaces from FIFOs (head is later instructions)
  Vector#(3, Forwarder#(ThreadRegName, Value)) forwarders =
        Vector::cons(sexe2memQ.search, Vector::cons(smem2memQ.search, Vector::cons(smem2wbQ.search, Vector::nil)));

  `ifndef VERIFY2
  Debug#(RegisterFile, Display#(Tuple2#(ThreadID, Address))) debug_rf <- mkRegisterFile_Debug(mkRegisterFile);
  RegisterFile      rf         = debug_rf.inf;
  Display#(Tuple2#(ThreadID, Address)) rf_display = debug_rf.debugging;
  `else
  RegisterFile      rf <- mkRegisterFile();
  `endif
  RegisterFile forwardrf  <- mkForwardingRegisterFile(rf, forwarders);

  Vector#(NumThreads, BranchPredictor) bpreds <- mapM(mkBranchPredictor, rf.pc); // XXX we should unify this

  MemoryHierarchy mem <- mkMemoryHierarchy();
  `ifndef VERIFY2 // for verification we do not consider the PIC
  let          thePIC <- mkPIC();
  Vector#(1, Peripheral#(0)) picVector = newVector();
  picVector[0] = thePIC.regs;
  `endif

  let imem = mem.imem;
  let dmem = mem.dmem;
  let cp0  = mem.cp0;
  `ifndef VERIFY2
  let extMem <- mkInternalMemoryToInterconnect(mem.extMemory);
  `endif

  Bool isFlushedP = fet2decQ.notFull()   && sdec2exeQ.search.isFlushed() &&
                    sexe2memQ.search.isFlushed()   && smem2memQ.search.isFlushed() && smem2wbQ.search.isFlushed() &&
                    mem.isFlushed();

  `ifdef CAP
  CapabilityRegisterFile caprf <- mkCapabilityRegisterFile();
  `else
  CapabilityRegisterFile caprf = ?;
  `endif

  `ifdef DEBUG
  let debugUnit <- mkDebugUnit(isFlushedP, rf, cp0, caprf, bpreds, mem.dmem);
  rf    = debugUnit.rf;
  cp0   = debugUnit.cp0rf;
  caprf = debugUnit.caprf;
  `endif

  `ifdef CAP
  CapabilityCoprocessor     capCop <- mkCapabilityCoprocessor(mem.imem, mem.dmem, mem.capMem, caprf);
  isFlushedP = isFlushedP && capCop.isFlushed();
  imem = capCop.capIMem;
  dmem = capCop.capDMem;
  `endif

  ThreadScheduler                       threadSched <- mkThreadScheduler();

  `ifdef CP1X
  CP1X cp1X <- mkCP1X;
  `endif

  //======================================================================
  //Stage Logic
  //======================================================================

  //Decode
  Decode decoder <- mkDecode();

  //Execute
  Execute  exec <- mkExecute();
  Multiply mult <- mkMultiply();
  Divider   div <- mkDivider();

  // ndave: Nullify the next instruction?
  //        (from failed likely branch)
  Vector#(NumThreads, Reg#(Bool)) execShouldNullify <- replicateM(mkReg(False));

  Reg#(Maybe#(Bit#(64))) lastCommitTime <- mkReg(Invalid);
  Reg#(Bit#(64))          commitedInsts <- mkReg(0);
  Reg#(Bit#(64))           decodedInsts <- mkReg(0);

  function Bool isEHRTrue(Integer n, EHR#(3, Bool) r) = r[n];
  function flushing(n) = any(isEHRTrue(n), flushingPipelineP);
  //Bool flushing = any(readReg, flushingPipelineP);

  `ifdef UNPIPELINE
  let unpipelineFetchEnableP = isFlushedP;
  `else
  let unpipelineFetchEnableP = True;
  `endif

  // Do not fetch new instructions until we're done flushing
  rule fetch((!flushing(2) || isFlushedP) && unpipelineFetchEnableP);
    debug($display("*** FET ***"));
    `ifdef DEBUG
	  debugUnit.canFetchInst();
    `endif

    let thread <- threadSched.getDecision();
    let ts = cp0.threadStates[thread];
    //This stage issues requests from memory and checks if we can read
    match {.epoch, .specPC, .predictedNextPC, .predictedNextNextPC} <- bpreds[thread].getPrediction();

    debug2("fetch", $display("DEBUG: FET 0x%h <= %d", specPC, epoch));

    let exception <- imem.req(thread, ts, specPC);
    let inst = FetInst{
                 thread: thread,
                 ts    : ts,
                 epoch : epoch,
                 pc    : specPC,
                 nextPC: predictedNextPC,
                 nextNextPC: predictedNextNextPC,
                 exception: exception
	  };
    fet2decQ.enq(inst);
  endrule

  rule decode;
    debug($display("*** DEC ***"));
    // This stage gets memory results and decodes instruction
    let fi = fet2decQ.first();
    fet2decQ.deq();

    match {.ex, .inst} <- (fi.exception == Ex_None) ? imem.resp() : toAV(tuple2(Ex_None, 0));

    DecodedResult decResult <- decoder.decode(inst,fi.pc);
    debug($display(fshow(fi.exception), fshow(ex), fshow(decResult.decException)));
    let exception = joinException(fi.exception, joinException(ex, decResult.decException));

    //--------------------------------------------------------------------------------------------
    //Register File

    //ndave: We always make rf requests, but if we do not need it, we'll request
    //       Reg 0 (which is constant 0 and doesn't delay)

    function getRegName(x) = case (x) matches
                               tagged Op_RegName .r: return r;
                               default             : return 0; // R0 = const zero
                             endcase;

    debug_decode($display("DEC: RF accesses to Regs %d %d",
      getRegName(decResult.decOperandA), getRegName(decResult.decOperandB)));

    forwardrf.readReqA(fi.thread,getRegName(decResult.decOperandA));
    forwardrf.readReqB(fi.thread,getRegName(decResult.decOperandB));

    `ifdef CAP
      //Initialize Capability Request
      debug($display("CP2 DEC op", fshow(decResult.decCapOperation)));
      capCop.capReq(decResult.decCapOperation,
                    decResult.decOffset[15:0]);
    `endif

    let di = DecInst{
               thread     : fi.thread,
               ts         : fi.ts,
               epoch      : fi.epoch,
               pc         : fi.pc,
               nextPC     : fi.nextPC,
               nextNextPC : fi.nextNextPC,
               exception  : exception,
               aluOperation:    decResult.decALUOperation,
               branchOperation: decResult.decBranchOperation,
               mmemOperation:   decResult.decmMemOperation,
               cp0Operation:    decResult.decCP0Operation,
               `ifdef CP1X
               cp1XOperation:   decResult.decCP1XOperation,
               `endif
               mmulOperation:   decResult.decmMulOperation,
               mdivOperation:   decResult.decmDivOperation,
               `ifdef CAP
               getCapResp : decResult.decCapOperation.hasResult,
               `endif
               whenWritten: decResult.decWhenWritten,
               flushAfterCommit: decResult.decFlushAfterCommit,
               dest       : decResult.decDest,
               opA        : decResult.decOperandA,
               opB        : decResult.decOperandB,
               offset     : decResult.decOffset,
	       inst       : inst,
               debug      : decResult.decDebug
             };

    dec2exeQ.enq(di);

    debug_decode(action
            $write("DEBUG: DEC [0x%h] inst: %h dest: ", fi.pc, inst, fshow(decResult.decDest));
            $write(" optype: (", fshow(decResult.decALUOperation.op_alutype),
                            ",",  fshow(decResult.decBranchOperation.op_brtype),
                   ",",fshow(decResult.decBranchOperation.op_isLink),")");
            $write(" dest: ", fshow(decResult.decDest));
            $write(" opA: ",  fshow(decResult.decOperandA));
            $write(" opB: ",  fshow(decResult.decOperandB));
            $write(" imm: %h",  decResult.decOffset);
            $write(" exc: ",  fshow(di.exception));
            $write(" [%d/%d]", decResult.decDebug.printRegisterState,
                               decResult.decDebug.terminate);
            `ifdef CAP
            $display("CAP Op:", fshow(decResult.decCapOperation));
            `endif
            $display("");
       endaction);

    decodedInsts <= decodedInsts + 1;
    debug_cheri1_trace($display("inst %5d %x : %x", decodedInsts, fi.pc, inst));
  endrule

  // ndave: We identify wrong path instructions by examining the epoch
  // value with which the instruction is tagged and the current epoch
  // in the branch predictor. On PC mispeculations, we change the
  // epoch in the branch predictor, changing the tag for new right
  // path instructions. If we then get an instruction to execute with
  // an old tag we know it must have been fetched before we corrected
  // the PC and so should be dropped.

  ThreadID nextExeThread = dec2exeQ.first().thread;
  //Drop insts from flushing threads here and in writeback
  Bool execIsRightPath = !flushingPipelineP[nextExeThread][1] &&
                           (bpreds[nextExeThread].curEpoch() == dec2exeQ.first().epoch
                            || isValid(branchDelayNextPC[nextExeThread]));




  rule execute_drop(!execIsRightPath || execShouldNullify[nextExeThread]);
    debug($display("*** EXE/D ***"));
    let valA   <- forwardrf.readRespA(); // ndave: drop the response values
    let valB   <- forwardrf.readRespB();
    dec2exeQ.deq();
    branchDelayNextPC[nextExeThread] <= Invalid;
    execShouldNullify[nextExeThread] <= False;
	`ifdef VERIFY2
    $display(valA, valB);
	`endif

    `ifdef CAP
    let capResp <- capCop.capResp(True, ?, ?, ?, ?, ?); // kill op
    `endif

    if(execShouldNullify[nextExeThread])
      debug2("exec", $display("DEBUG: EXE NULLIFY T[%d] 0x%h", {1'b0, nextExeThread}, dec2exeQ.first().pc));
    else
      debug2("exec", $display("DEBUG: EXE WRONGPATH 0x%h %d not %d delaybranch: ", dec2exeQ.first().pc,
         dec2exeQ.first().epoch, bpreds[nextExeThread].curEpoch(), fshow(isValid(branchDelayNextPC[nextExeThread]))));
    debug_cheri1_trace($display("    dropped\n"));
  endrule

  // ndave: We can execute an instruction only when all hazards are
  // resolvable. In the context of values this means that we know
  // (possibly via forwarding) the correct value of an
  // instruction. Due to possible timing issues, the HI and LO
  // registers have _NO_ forwarding and we must make sure that all
  // previous instructions writing them are complete. Currently this
  // is done by waiting until the instruction is the oldest in the pipeline

  // ndave: For SYNC instructions, we must also make sure that all
  // instructions are globally complete, i.e., all previous
  // instructions are through the pipeline and no dirty values are in
  // the non-globally coherent memory.

  // ndave: Currently all instructions are single-cycle. If we need
  // multi-cycle instructions we can split out the operation as with
  // dmem, and pick up the result from the subunit in the MEM stage.

  Bool nextExecReadHILO = ((isOpHI(dec2exeQ.first().opA) || isOpLO(dec2exeQ.first().opA)) ||
               (isOpHI(dec2exeQ.first().opB) || isOpLO(dec2exeQ.first().opB)) ||
                           (isMAddSubOp(dec2exeQ.first().mmulOperation)));
   //Bool backendFlushed = sexe2memQ.search.isFlushed() && smem2memQ.search.isFlushed() && smem2wbQ.search.isFlushed() &&
  Bool backendFlushed = sexe2memQ.fifo.notFull() && smem2memQ.search.isFlushed() && smem2wbQ.search.isFlushed() &&
                        mem.isCommitted(); //XXX ndave: this may need to be changes for CP2
  Bool noHazard = (nextExecReadHILO) ? backendFlushed : True;

  rule execute(execIsRightPath && noHazard && !execShouldNullify[nextExeThread]);
    debug($display("*** EXE ***"));
    debug2("exec", $display("DEBUG: EXE STARTING"));
    let di = dec2exeQ.first();
    dec2exeQ.deq();

    // ndave: Get the response from the register file. Because the
    // forwarding register file may know of an instruction writing the
    // value for which we do not have a final value, the value may not
    // be valid. We solve this by making the response unready in the this case.

    let valA   <- forwardrf.readRespA();
    let valB   <- forwardrf.readRespB();

    function getVal(x, val) = case(x) matches
                                tagged Op_Value   .v: return v;
                                tagged Op_RegName .*: return val;
                                tagged Op_HI:         return forwardrf.hi[di.thread];
                                tagged Op_LO:         return forwardrf.lo[di.thread];
                                tagged Op_CoProc0 .*: return  ?;
                              endcase;

    let vA = getVal(di.opA, valA);
    let vB = getVal(di.opB, valB);

    //ndave: XXX for scheduling we may need to make calcResult is
    //       a pure function as we cannot look at the value of an
    //       actionvalue without the action happening, we will
    //       conservatively have to assume the branch resolution
    //       can happen in all executions for scheduling purposes.

    let imm = di.offset[15:0]; // ndave: sharing offset and abs as they're shared in ISA.

    let result <-  exec.calcResult(di.aluOperation, vA, vB, imm);

    let thePC = di.pc;
    let rv    = result.exeResult;
    let bCond = result.branchCond;
    let capEx = Ex_None;
    let fetchPC = thePC;

    `ifdef CAP
    // Pass the exe result through CapCop. For most instructions it is passed straight through,
    // for memory operations it is offset through the capability, and some ops discard it and
    // return their own result. Similarly for the branch condition.
    let capResp <- capCop.capResp(False, di.pc, vA, vB, rv, bCond);
    rv    = capResp.result;
    bCond = capResp.bCond;
    capEx = capResp.exception;
    fetchPC = capResp.fetchAddr;
    `endif

    // Pass the computed branch condition to pc calc to resolve any branch. rv is passed through
    // so that it can be overwritten with the link address where necessary.
    let pcCalc <- exec.calcPC(di.branchOperation, bCond, rv, vA, thePC, di.offset);
    rv = pcCalc.pcResult;

    // If there was a fetch exception pass the bad PC through instead of the return value so that
    // CP0 can use it.
    if (di.exception != Ex_None)
      rv = fetchPC;

    // resolve branch misprediction (is correct guess or we're in a branch Delay slot)
    if(pcCalc.pcIsBranch)
      branchDelayNextPC[di.thread] <= tagged Valid pcCalc.pcCalcNextNextPC;
    else // not a branch so forget delays
      branchDelayNextPC[di.thread] <= Invalid;

    Operand opA = Op_Value (rv);
    Operand opB = Op_Value (result.exeResult2);

    Bool predictionBad = !isValid(branchDelayNextPC[di.thread])
      && pcCalc.pcCalcNextNextPC != di.nextNextPC;

    if(predictionBad)
      begin
        debug2("exec", $display("EXE BRANCH MISPREDICT @[0x%h] %h. (inst epoch: %d) GOING TO ADDR %h",
                       di.pc, di.nextNextPC, dec2exeQ.first().epoch, pcCalc.pcCalcNextNextPC));
        bpreds[di.thread].resolveBranchMiss(di.pc, pcCalc.pcCalcNextNextPC);
        //ndave: It would be nice to be able to clear the fet2decQ
        //       and dec2exeQ here, but this requires we know the
        //       delay slot isn't there AND no instructions from
        //       another thread exist.
      end
    else
      begin
        debug2("exec", $display("EXE BRANCH CORRECT @[0x%h] GOING TO ADDR %h/%h (epoch: %d)",
                       di.pc, di.nextNextPC, pcCalc.pcCalcNextNextPC, dec2exeQ.first().epoch));
      end




    let exception = joinException(di.exception, joinException(result.exeException, capEx));

    case (di.mmulOperation) matches
      tagged Valid .op: mult.req(op, vA, vB, rf.hi[di.thread], rf.lo[di.thread]);
    endcase

    case (di.mdivOperation) matches
      tagged Valid .op: div.req(op, vA, vB);
    endcase

    //pass data to next stage
    let ei = ExeInst{ // we can now forget nextNextPC
               thread      : di.thread,
               ts          : di.ts,
               pc          : di.pc,
               nextPC      : fromMaybe(di.nextPC, branchDelayNextPC[di.thread]), //correct nextPC in case of branch delay
               exception   : exception,
               mmemOperation: di.mmemOperation,
               cp0Operation: di.cp0Operation,
               `ifdef CP1X
               cp1XOperation: di.cp1XOperation,
               `endif
               getMulResp  : isValid(di.mmulOperation),
               getDivResp  : isValid(di.mdivOperation),
               whenWritten : di.whenWritten,
               flushAfterCommit: di.flushAfterCommit,
               dest        : (result.exePreventWrite) ? Dest_None: di.dest,
               opA         : opA, // passed through pc calc to allow link
               opB         : opB,
               isDelay     : isValid(branchDelayNextPC[di.thread]),
               inst        : di.inst,
               debug       : di.debug
             };


    exe2memQ.enq(ei);
    //ndave: update if we should nullify execute next time
    execShouldNullify[di.thread] <= pcCalc.pcCalcNullifyNextInst;
    if(pcCalc.pcIsBranch)
      debug_cheri1_trace($display("     Branch dest=%x ", pcCalc.pcCalcNextNextPC));
    debug2("exec", action
            $display("DEBUG: EXE 0x%h dest:", di.pc, fshow(di.dest));
            $display("    (", fshow(di.opA), ") [0x%h=>%h] ", valA, vA);
            $display("    (", fshow(di.opB), ") [0x%h=>%h] ", valB, vB);
            $display("    imm: %h => ", imm, fshow(ei.opA), " " , fshow(ei.opB));
            $display("    exception: ", fshow(exception));
          endaction);
  endrule

  rule memory;
    debug($display("*** MEM ***"));

    let ei = exe2memQ.first();
    exe2memQ.deq();

    //ndave: Calculate memory operation. ei.opA holds the address, and
    //       the value is stored in ei.opB

    Value addr = getOpValue(ei.opA);

    //ndave: only issue a request when there's no exception
    let ex <- case (ei.mmemOperation) matches
                tagged Valid .o &&& (ei.exception == Ex_None): dmem.req(ei.thread, ei.ts, o, addr, getOpValue(ei.opB));
                tagged Invalid:  toAV(Ex_None);
              endcase;

    ei.exception = joinException(ei.exception, ex);
    `ifdef CAP
    let x <- capCop.memoryStage();
    ei.exception = joinException(ei.exception, x);
    `endif

    debug2("mem", $display("DEBUG: MEM @ %h: ", ei.pc, " => ", fshow(ei.opA)," ", fshow(ei.opB), " exception:", fshow(ex)));

    let exception = joinException(ei.exception, ex);
    `ifndef VERIFY2
    let irqs = thePIC.irqMapper.getMIPSIrqs(ei.thread);
    `else
	let irqs = 0;
	`endif
    //always issue to CP0, even on effective nops so we can safely get resps
    cp0.req(ei.thread, ei.ts, ei.cp0Operation, irqs);
    `ifdef CP1X
    cp1X.req(ei.cp1XOperation);
    `endif

    let mi = MemInst{
               thread     : ei.thread,
               ts         : ei.ts,
               pc         : ei.pc,
               nextPC     : ei.nextPC,
               exception  : exception,
               getMemResp : isValid(ei.mmemOperation) && (exception==Ex_None), // exceptional memory ops abort
               getMulResp : ei.getMulResp,
               getDivResp : ei.getDivResp,
               whenWritten: ei.whenWritten,
               flushAfterCommit: ei.flushAfterCommit,
               dest       : ei.dest,
               opA        : ei.opA,
               opB        : ei.opB,
               isDelay    : ei.isDelay,
               inst       : ei.inst,
               debug      : ei.debug
            };
    mem2memQ.enq(mi);
  endrule

  rule mem2;
    debug($display("*** MEM2 ***"));
    let mi    <- popFIFOF(mem2memQ);
    let cp0Ex <- cp0.checkException;
    let ex     = joinException(mi.exception, cp0Ex);
    let commit = ex == Ex_None && !flushingPipelineP[mi.thread][1];
    let memEx <- mi.getMemResp ? dmem.commit(commit) : toAV(Ex_None);
    mi.exception = joinException(ex, memEx);
    `ifdef CAP
    let capEx <- capCop.memoryStage2(commit && mi.exception == Ex_None);
    mi.exception = joinException(mi.exception, capEx);
    `endif
    mem2wbQ.enq(mi);
  endrule

  let nextWBThread = mem2wbQ.first().thread;
  let dropNextWB = flushingPipelineP[nextWBThread][0];
  rule writeback_drop(dropNextWB);
    debug($display("*** WB/D ***"));
    let mi = mem2wbQ.first();
    mem2wbQ.deq();
    if (mi.getMemResp)
      begin
        let resp <- dmem.resp();
	    `ifdef VERIFY2
        $display(resp);
        `endif
       end
    let          cp0result <- cp0.resp(False, mi.pc, mi.exception, mi.isDelay, getOpValue(mi.opA), mi.inst);
    `ifdef VERIFY2
    $display(cp0result);
    `endif


    `ifdef CP1X
    let         cp1Xresult <- cp1X.rsp(False, getOpValue(mi.opA));
    `endif
    match {.mulHi, .mulLo} <- (mi.getMulResp) ? mult.resp(): toAV(tuple2(?,?));
    match {.divHi, .divLo} <- (mi.getDivResp) ? div.resp() : toAV(tuple2(?,?));
	`ifdef VERIFY2
    $display(mulHi, mulLo, divHi, divLo);
	`endif

    `ifdef CAP
    Bool flush_after_commit <- capCop.commitWriteback(False, Invalid); // don't commit it's wrong path
    `endif
    debug2("wb", $display("DEBUG: WB DROP [0x%h]", mi.pc));
    debug_cheri1_trace($display("    dropped\n"));
  endrule

  rule writeback(!dropNextWB);
    debug($display("*** WB ***"));

    let mi = mem2wbQ.first();
    mem2wbQ.deq();
    //There is a correctness requirement that we don't do memory operations & CP0 / Mul ops rmn30 ??? at the same time?
    // ndave: note that CP0 cannot directly store MUL/DIV or MEM values currently. Small reorganization would be necessary.
    // Get cp0 response, this includes the final exception value for inst.
    let                exc =  mi.exception;
    let             memVal <- (mi.getMemResp) ? dmem.resp() : ?;
    let               isEx =  exc != Ex_None;
    match {.mulHi, .mulLo} <- (mi.getMulResp) ? mult.resp()     : toAV(tuple2(?,?));
    match {.divHi, .divLo} <- (mi.getDivResp) ? div.resp()      : toAV(tuple2(?,?));

    let          cp0result <- cp0.resp(True, mi.pc, exc, mi.isDelay, getOpValue(mi.opA), mi.inst);
    `ifdef CP1X
    let         cp1Xresult <- cp1X.rsp(True, getOpValue(mi.opA));
    `endif

    match {.destVal, .destVal2} <-
       actionvalue
          if(cp0result.cp0_mvalue matches tagged Valid .valA)
            begin //CP0 response had a value, so use it.
              debug2("wb", $display("CP0 RESP! ", fshow(cp0result)," ",mi.opA));
              return tuple2(valA, getOpValue(mi.opB));
            end
          `ifdef CP1X
          else if(cp1Xresult matches tagged Valid .valA)
            return tuple2(valA, ?);
          `endif
          else if (mi.getMemResp)
            begin
              debug2("wb", $display("Mem RESP!"));
              return tuple2(memVal, ?);
            end
          else if (mi.getMulResp)
            begin
              debug2("wb", $display("Mult RESP!"));
              return tuple2(mulLo , mulHi);
            end
          else if (mi.getDivResp)
            begin
              debug2("wb", $display("Div RESP!"));
              return tuple2(divLo , divHi);
            end
          else
            return tuple2(getOpValue(mi.opA), getOpValue(mi.opB));
        endactionvalue;

    `ifdef DEBUG
    //Log for debug unit
    //Conflicts with fetch and execute :-(
    let debugflush <- debugUnit.completeInst(mi.inst, mi.pc, mi.nextPC, destVal, destVal2, exc, cp0result.ts.asid);
    `else
    let debugflush = False;
    `endif

    Bool flush_after_commit = mi.flushAfterCommit || debugflush;
    `ifdef CAP
    let exceptionOrERET = isValid(cp0result.cp0_mexceptionPC)? Valid(isEx) : Invalid;
    let flush_due_to_cp2 <- capCop.commitWriteback(True, exceptionOrERET); // commit, isException?
    flush_after_commit = flush_after_commit || flush_due_to_cp2;
    `endif

    // Blocks fetch unless threadStates is configreg
    cp0.threadStates[mi.thread] <= cp0result.ts;

    let t <- $time;
    let deadCycles = (t - fromMaybe(t-10, lastCommitTime))/10 - 1;
    lastCommitTime <= tagged Valid t;
    commitedInsts  <= commitedInsts + 1;

    case (cp0result.cp0_mexceptionPC) matches
      tagged Valid .epc:
        begin // take exception
          bpreds[mi.thread].takeException(epc);
          //forwardrf.pc[mi.thread] <= epc; // ndave: jump to correct instruction (we use spec IFC for consistency)
          flushingPipelineP[mi.thread][0]   <= True; //blocks execute and fetch
          if (isEx)
            begin
              trace($display("%1d\tT%1d: [%h] TAKING EXCEPTION to 0x%h code:0x%x ", commitedInsts, {1'b0, mi.thread}, mi.pc, epc, exc, fshow(exc), mi.isDelay ? " (in delay slot)" : ""," (%1d dead cycles)\n", deadCycles));
            end
          else
            begin
              trace($display("%1d\tT%1d: [%h] EXCEPTION RETURN to 0x%h", commitedInsts, {1'b0, mi.thread}, mi.pc, epc, " (%1d dead cycles)\n", deadCycles));
              debug_cheri1_trace($display("     ERET to 0x%x", epc));
            end
        end
      default:
      begin
        case(mi.dest) matches
          tagged Dest_None:   noAction;
          tagged Dest_Reg .r: forwardrf.write(mi.thread, r, destVal);
          tagged Dest_HI:     forwardrf.hi[mi.thread] <= destVal;
          tagged Dest_LO:     forwardrf.lo[mi.thread] <= destVal;
          tagged Dest_HILO:
            begin
              forwardrf.hi[mi.thread] <= destVal2;
              forwardrf.lo[mi.thread] <= destVal;
            end
        endcase
        if (flush_after_commit)
          begin
            debug2("wb", $display("DEBUG: WB FLUSH T%d 0x%h", {1'b0, mi.thread}, mi.nextPC));
            flushingPipelineP[mi.thread][0] <= True;  //blocks execute and fetch
            bpreds[mi.thread].takeException(mi.nextPC); // not an exception but a flush
          end
        forwardrf.pc[mi.thread] <= mi.nextPC; // mark PC as the next PC. Only used by DebugUnit
        trace(
           action
             $write("%1d\tT%1d: [%h]", commitedInsts, mi.thread, mi.pc);
             case(mi.dest) matches
               tagged Dest_Reg .r: $write(" %s<-%x", regName(r), destVal);
               tagged Dest_HI:     $write(" HI<-%x", destVal);
               tagged Dest_LO:     $write(" LO<-%x", destVal);
               tagged Dest_HILO:   $write(" HI/LO <- %x/%x", destVal2, destVal);
               default:            begin
                                     if (mi.getMemResp)
                                       $write(" store               ");
                                     else
                                       $write(" branch/coproc       ");
                                   end
             endcase
           $write(" inst=%x (%1d dead cycles)\n", mi.inst, deadCycles);
           endaction
           );
        debug_cheri1_trace(
          action
            if(mi.isDelay)
              $display("     branch delay slot");
            case(mi.dest) matches
              tagged Dest_None:   noAction;
              tagged Dest_Reg .r: $display("     Reg %d <- %x", r, destVal);
              tagged Dest_HI:     $display("     HI     <- %x", destVal);
              tagged Dest_LO:     $display("     LO     <- %x", destVal);
              tagged Dest_HILO:   $display("     HI/LO  <- %x/%x", destVal2, destVal);
            endcase
            $display("");
           endaction
           );
      end
    endcase
    `ifndef VERIFY2
    if (mi.debug.printRegisterState)
      debugDisplay(rf_display, tuple2(mi.thread, mi.pc));
    `endif

`ifdef INSTR_LIMIT
    Bool instr_limit_reached=commitedInsts >= `INSTR_LIMIT)
`else
    Bool instr_limit_reached=False;
`endif
    if (mi.debug.terminate || instr_limit_reached)
      begin
        trace($display("Simulation terminated due to ", mi.debug.terminate?"halt instruction.":"instruction limit."));
        $finish();
      end
  endrule

  (* fire_when_enabled *)
  rule displayState(True);
    debug2("pipe", action
           $display("=====================================================");
           $write("  WB:   %x ", mem2wbQ.notEmpty   ? mem2wbQ.first.pc   : 0);
           displayFIFO1(mem2wbQ);
           $write("\nMEM2:   %x ", mem2memQ.notEmpty ? mem2memQ.first.pc : 0);
           displayFIFO1(mem2memQ);
           $write("\n MEM:   %x ", exe2memQ.notEmpty  ? exe2memQ.first.pc  : 0);
           displayFIFO1(exe2memQ);
           $write("\n EXE:   %x ", dec2exeQ.notEmpty  ? dec2exeQ.first.pc  : 0);
           dec2exeQ_debug.debugging.debug_display(?);
           $write("\n DEC:   %x ", fet2decQ.notEmpty  ? fet2decQ.first.pc  : 0);
           fet2decQ_debug.debugging.debug_display(?);
	       $display("");
           `ifdef CAP
           capCop.debugDisplay();
           `endif
	       $display("");
	   //mem.debug.debug_display(?);
           //function getEpoch(br) = br.curEpoch();
      	   //$display("Epoch: ", fshow(map(getEpoch, bpreds)));
          endaction);
    //$write(""); // prevents lint failure
  endrule

  //ndave: Make sure we don't order ME rules
  (* mutually_exclusive = "writeback, writeback_drop" *)
  (* mutually_exclusive = "execute,   execute_drop" *)
  `ifdef CAP
  (* execution_order =  "displayState, writeback     ,  mem2, memory, execute,      decode, fetch" *)
  (* execution_order =  "displayState, writeback_drop,  mem2, memory, execute_drop, decode, fetch" *)
  `else
  (* execution_order =  "displayState, writeback,      mem2, memory, execute,      decode, fetch" *)
  (* execution_order =  "displayState, writeback_drop, mem2, memory, execute_drop, decode, fetch" *)
  `endif
  `ifdef DEBUG
  (* preempts = "memory, debugUnit_startDebugCommand_notIsolated"*)
  (* preempts = "mem2, debugUnit_commitMem"*)
  (* preempts = "(writeback, writeback_drop), debugUnit_endCommand_notIsolated"*)
  `endif
  rule restart(isFlushedP && flushing(1));
    //clear the delay slots and flushing flags
    for(Integer i = 0; i < valueOf(NumThreads); i = i+1)
      begin
        flushingPipelineP[i][1] <= False;
        if (flushingPipelineP[i][1])
          branchDelayNextPC[i] <= Invalid;
      end
  endrule

  `ifndef VERIFY2
  interface extMemory = extMem;
  `endif

  method Action putIrqs(Bit#(32) i);
    `ifndef VERIFY2
    thePIC.irqMapper.putExtIrqs(zeroExtend(i));
    `endif
  endmethod

  `ifndef VERIFY2
  interface pic = picVector;
  `endif

  interface reset_n = True;

  `ifdef DEBUG
  interface Server debugStream = replicate(debugUnit.stream);
  `else
  interface Server debugStream = ?;
  `endif

  `ifdef CP1X
  method cp1xdIn = cp1X.dIn;
  method cp1xdOut = cp1X.dOut;
  `endif
endmodule
