/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Alan A. Mujumdar
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

import GetPut :: *;
import ClientServer :: *;
import Execute :: *;
import MIPS :: *;
import Memory :: *;
import ForwardingPipelinedRegFile :: *;
import CP0 :: *;
`ifdef CAP
  import CapCop :: *;
`endif
import FIFO :: *;
import FIFOF :: *;
import LevelFIFO :: *;
import SpecialFIFOs::*;
import Vector::*;
import DebugUnit::*;
import Debug::*;
import ConfigReg::*;
import TraceTypes::*;

typedef struct {
  ControlTokenT ct;
  MIPSReg       result;
  Bit#(16)      count;
} InstructionReport deriving (Bits); // total=256

module mkWriteback#(
  MIPSMemory m,
  ForwardingPipelinedRegFileIfc#(MIPSReg) rf,
  CP0Ifc cp0,
  BranchIfc branch,
  DebugIfc debugUnit,
  CoProIfc cop1,
  `ifdef CAP
    CapCopIfc capCop,
  `endif
  CoProIfc cop3,
  FIFO#(ControlTokenT) inQ
)(WritebackIfc);

  FIFOF#(Bool)                   hiLoCommit <- mkFIFOF();
  Reg#(InstructionReport) instructionReport <- mkRegU;
  Reg#(Bit#(16))               lastReportId <- mkReg(0);
  Reg#(InstId)           lastCommitReportId <- mkConfigReg(1);
  Reg#(Exception)        preMemExceptionReg <- mkConfigReg(?);

  Reg#(UInt#(48)) instCount <- mkReg(0);
  Reg#(UInt#(48)) cyclCount <- mkReg(0);
  Reg#(UInt#(48)) lsInCycCt <- mkReg(0);
  Reg#(Bool)  doCycleReport <- mkReg(True);
  
  ControlTokenT nexT = inQ.first;
  Bool nextDead = False;
  if (nexT.dead) nextDead = True;
  if (nexT.epoch != branch.getEpoch) nextDead = True;
  
  Exception preMemException = nexT.exception;
  Cp0ExceptionReport cp0ExpRpt = cp0.getException();
  if (cp0ExpRpt.exception!=None && !nexT.fromDebug) 
          preMemException = cp0ExpRpt.exception;
  // Handling ALU exceptions
  Bool needTrap = (case(nexT.test)
        EQ: return (!nexT.signedOp) ? (nexT.opA == 0)     : False;
        GE: return (!nexT.signedOp) ? (nexT.carryout == 0): (nexT.opA[63] == 0);
        LT: return (!nexT.signedOp) ? (nexT.carryout == 1): (nexT.opA[63] == 1);
        NE: return (!nexT.signedOp) ? (nexT.opA != 0)     : False;
        default: return False;
      endcase);
  if (needTrap && preMemException==None) preMemException=TRAP;
  if (nextDead) preMemException = None;

  `ifdef BLUESIM
    Vector#(32, Reg#(Bit#(64))) debugRegFile <- replicateM(mkRegU);
  `endif

  function Address getExceptionEntryROM(Exception exc);
    case (exc)
      NMI:                return 64'h9000000040000000;
      ITLB, DTLBL, DTLBS: return 64'hFFFFFFFFBFC00280; //TLB exception.
      CAPCALL:            return 64'hFFFFFFFFBFC00480;
      default:            return 64'hFFFFFFFFBFC00380; //General purpose exception.
    endcase
  endfunction

  function Address getExceptionEntryRAM(Exception exc);
    case (exc)
      NMI:                return 64'h9000000040000000;
      ITLB, DTLBL, DTLBS: return 64'hFFFFFFFF80000080; //TLB exception.
      CAPCALL:            return 64'hFFFFFFFF80000280;
      default:            return 64'hFFFFFFFF80000180; //General purpose exception.
    endcase
  endfunction

  function Action doRegisterWriteback(
    RegNum dest,
    Bit#(3) sel,
    MIPSReg result,
    CacheResponseDataT memResponse,
    WriteBack writeDest,
    Bool fromDebug,
    Exception exp,
    Bool dead,
    InstId id
  );
    action
      Bool instructionIsCommitting = (!dead && exp == None);
      rf.writeReg(dest, result, writeDest==RegFile, instructionIsCommitting);
      if (instructionIsCommitting) begin // If we had an exception, flush the pipe with no effect on register file.
        if (writeDest == RegFile) begin
          `ifdef BLUESIM
            debugRegFile[dest] <= result;
          `endif
        end
        if (cyclCount - lsInCycCt > 1) begin
          cycReport($display("%3d dead cycles", cyclCount - lsInCycCt - 1));
        end
        lsInCycCt <= cyclCount;
        instCount <= instCount + 1;
      end
      if (writeDest == HiLo) begin
        hiLoCommit.enq(instructionIsCommitting);
      end
      if (writeDest == CoPro0) begin
        cp0.writeReg(dest, sel, result, fromDebug, instructionIsCommitting);
      end
      if (fromDebug) begin
        if (dest==0) begin
          debugUnit.client.response.put(DebugReport{
            writeback: tagged Valid result,
            expType: getExceptionCode(exp)
          });
        end else begin
          debugUnit.client.response.put(DebugReport{
            writeback: tagged Invalid,
            expType: getExceptionCode(exp)
          });
        end
      end
      `ifdef CAP
        Capability capMemResponse = ?;
        if (memResponse.data matches tagged Line .l) begin
          capMemResponse = unpack({pack(memResponse.capability),l});
        end
        capCop.commitWriteback(CapWritebackRequest{
          mipsExp: exp,
          dead: dead,
          memResponse: capMemResponse,
          instId: id
        });
      `endif
      cop1.commitWriteback(CoProWritebackRequest{
          dead: dead,
          commit: instructionIsCommitting,
          instId: id,
          data: result
        });
      cop3.commitWriteback(CoProWritebackRequest{
          dead: dead,
          commit: instructionIsCommitting,
          instId: id,
          data: result
        });
    endaction
  endfunction

  function Action doPCUpdate(
    InstructionT inst,
    Address pc,
    Address archPc,
    Int#(20)  pcUpdate,
    MIPSReg opA, 
    MIPSReg opB,
    MIPSReg result,
    Epoch epoch,
    Bool fromDebug,
    ExceptionWriteback exp,
    Branch branchState,
    Bool dead,
    Bool writePC,
    Bool flushPipe,
    Bool branchDelay,
    `ifdef MULTI
      Bit#(16) coreID,
    `endif
    PCSource  newPcSource
  );
    action
      // Do full target calculation.  I don't know which of these is used for a flush!
      Address jumpTarget = 64'b0;
      if (inst matches tagged Jump .ji) begin
        jumpTarget = {archPc[63:28], ji.imm, 2'b0} + (pc - archPc);
      end
      Address target = ?;
      case (newPcSource)
        PCUpdate:   target = pack(unpack(pc) + signExtend(pcUpdate));
        OpB:        target = opB;
        Immediate:  target = jumpTarget;
      endcase
      if (exp.exception != None) begin
        target = exp.entry;
      end
      Bool doWritePc = (!dead && ((writePC && exp.exception == None)||(exp.exception != None)));
      if (exp.exception != None && (dead || fromDebug)) begin
        exp.exception = None;
      end
      // Flush immediatly without a branch delay...
      Bool flush = ((exp.exception != None) ||    // If there was an exception
                   flushPipe) && !dead;           // Or an exception return or a missed branch likely
      branch.pcWriteback(dead, target, doWritePc, flush, fromDebug, branchState==DoneTaken || branchState==Always);
      if (exp.exception==None && !dead && !fromDebug) begin
        debugUnit.putPC(archPc);
      end
      
      debug($display("Exception check: exception %x, dead %x, fromDebug %x", exp.exception, dead, fromDebug));
      if (exp.exception != None && !dead && !fromDebug) begin
        exp.victim = archPc;
        exp.branchDelay = branchDelay;
        if (exp.branchDelay) begin
          exp.victim = exp.victim - 4;
        end
        debug($display("Exception in MemAccess"));
        `ifndef MULTI
          trace($display("     Exception!  Code=0x%x in MA", getExceptionCode(exp.exception)));
          trace($display("     Victim = %x, Instruction = %x", exp.victim, exp.instruction));
        `else
          trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception!  Code=0x%x in MA", $time, coreID, getExceptionCode(exp.exception)));
          trace($display("Time:%0d, Core:%0d, Thread:0 :: Victim = %x, Instruction = %x", $time, coreID, exp.victim, exp.instruction));
        `endif
      end else if (writePC && !dead) begin // Write the new PC
        exp.victim = zeroExtend(pack(instCount));
      end
      cp0.putException(exp, pc, opA); // Write the appropriate CP0 registers.
    endaction
  endfunction

  rule doInstructionReport;
    InstructionReport reportInput = instructionReport;
    ControlTokenT c = reportInput.ct;
    MIPSReg result = reportInput.result;
    Bit#(4) version = 0;
    MIPSReg val1 = 64'h000000000000DEAD;
    MIPSReg val2 = 64'h000000000000DEAD;
    
    Word storeData = pack(c.storeData)[63:0];
    Bool newDoCycleReport = doCycleReport;
    
    // If the counter has wrapped around
    if (reportInput.count[9] == 1'b0 && lastReportId[9] == 1'b1)
      newDoCycleReport = True;
      
    case (c.writeDest)
      RegFile, CoPro0, HiLo: begin
        val2 = result;
        version = 1;
      end
    endcase
    case (c.mem)
      Read: begin
        val1 = c.opA;
        version = 2;
      end
      Write: begin
        val1 = c.opA;
        val2 = storeData;
        version = 3;
      end
    endcase

    if (reportInput.count != lastReportId) begin
      TraceEntry nextTraceEntry = TraceEntry {
         version: version,
         pc: c.archPc,
         inst: pack(c.inst)[31:0],
         regVal1: val1,
         regVal2: val2,
         ex: pack(getExceptionCode(c.exception)),
         count: reportInput.count[9:0],
         asid: cp0.getAsid,
         reserved: ?,
         valid: !c.fromDebug && !c.dead
      };
      debugUnit.putTraceEntry(nextTraceEntry);
      lastReportId <= reportInput.count;
    end else if (newDoCycleReport) begin
      TraceEntry nextTraceEntry = TraceEntry {
         version: 4,
         pc: ?,
         inst: ?,
         regVal1: zeroExtend(pack(cyclCount)),
         regVal2: zeroExtend(pack(instCount)),
         ex: 31,
         count: ?,
         asid: ?,
         reserved: ?,
         valid: True
      };
      debugUnit.putTraceEntry(nextTraceEntry);
      newDoCycleReport = False;
    end

    doCycleReport <= newDoCycleReport;
  endrule

  rule doWriteBack;
    ControlTokenT er = inQ.first();
    inQ.deq();
    
    Bit#(64) virtualAddress = er.opA;
    if (er.test == SC) begin
      er.opA = er.opB;
    end
    MIPSReg result = er.opA;
    
    er.dead = nextDead;
    er.exception = (lastCommitReportId == nexT.id) ? preMemExceptionReg:preMemException;
        
    debug($display("======   EXECUTE RESULT   ======"));
    debug($display("Writeback"));
    debug(displayControlToken(er));

    `ifdef BLUESIM
      if (er.writeDest == CoPro0 && er.dest == 26) begin
        debugInst($display("======   RegFile   ======"));
        debugInst($display("DEBUG MIPS PC 0x%x", er.pc));
        debugInst($display("DEBUG MIPS REG %2d 0x%x", 0, 64'h0));
        for (Integer i = 1; i<32; i=i+1) begin
          debugInst($display("DEBUG MIPS REG %2d 0x%x", i, debugRegFile[i]));
        end
      end
      if (er.writeDest == CoPro0 && er.dest == 26 && er.coProSelect == 1) begin
        debugInst($display("======   ICache Tags   ======"));
        m.instructionMemory.debugDump();
      end
    `endif

    Word oldWord = ?;
    if (er.storeData matches tagged DoubleWord .d) oldWord = d;

    `ifndef MULTI
      CacheResponseDataT memResult <- m.dataMemory.getResponse(oldWord, er.signExtendMem, er.opA[7:0], er.memSize, (er.exception!=None) || er.dead);
    `else 
      CacheResponseDataT memResult <- m.dataMemory.getResponse(oldWord, er.signExtendMem, er.opA[7:0], er.memSize, (er.exception!=None) || er.dead, (er.test == SC && er.opB[0] == 1)?True:False); 
      if (er.test == SC && er.opB[0] == 1 && pack(memResult.data)[0] == 1) begin
        debug($display("Writeback: Store Conditional Success"));
      end  
      if (er.test == SC && (er.opB[0] != 1 || pack(memResult.data)[0] != 1)) begin
        er.opA = 0;
        result = er.opA;
      end 
    `endif
    
    // If this one had a valid memory operation, look at the exception.
    if (er.mem != None && er.mem != ICacheOp && 
        memResult.exception != None && er.exception == None) begin
      er.exception = memResult.exception;
    end
    // The memory response in a word type, which is th common case.
    if (memResult.data matches tagged DoubleWord .d &&& er.mem == Read) result = d;
    else if (er.mem == Write) result = er.opA;
    
    // Prepare to exception report for CP0
    Address entry = (cp0ExpRpt.bev) ? getExceptionEntryROM(er.exception)
                                     :getExceptionEntryRAM(er.exception);
    ExceptionWriteback exp = ExceptionWriteback{ 
      exception: er.exception,
      victim: er.pc,
      entry: entry,
      branchDelay: er.branchDelay,
      instId: er.id,
      instruction: pack(er.inst)[31:0],
      dead: er.dead
    };

    doPCUpdate(
      er.inst, er.pc, er.archPc, er.pcUpdate, virtualAddress, er.opB, result, er.epoch, er.fromDebug, exp,
      er.branch, er.dead, er.writePC, er.flushPipe,
      er.branchDelay, 
      `ifdef MULTI
        er.coreID,
      `endif
      er.newPcSource
    );
    Bit#(3) sel = 0;
    if (er.inst matches tagged Coprocessor .cp) begin
      sel = cp.select;
    end
    if (er.inst matches tagged Register .ri) begin
      sel = zeroExtend(pack(ri.f)[2:0]);
    end
    doRegisterWriteback(er.dest, sel, result, memResult, er.writeDest, 
                        er.fromDebug, er.exception, er.dead, er.id);

    if (!er.dead && exp.exception == None) begin // If we had an exception, flush the pipe with no effect on register file.
      `ifndef MULTI
        trace(displayTrace(er, result, instCount));
      `else
        trace(displayTrace(er, result, instCount, inQ.first.coreID));
      `endif
    end
    instructionReport <= InstructionReport{ct:er, result:result, count:pack(cyclCount)[15:0]};
  endrule

  interface getHiLoCommit = hiLoCommit;
  
  method ActionValue#(Bool) nextWillCommit() if (lastCommitReportId != nexT.id);
    lastCommitReportId <= nexT.id;
    preMemExceptionReg <= preMemException;
    return !nextDead && (preMemException==None);
  endmethod
  
  method Action putCycleCount(Bit#(48) count);
    cyclCount <= unpack(count);
  endmethod
endmodule
