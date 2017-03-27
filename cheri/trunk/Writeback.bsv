/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014-2017 Alexandre Joannou
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
  import CapCop::*;
  `define USECAP 1
`elsif CAP128
  import CapCop128::*;
  `define USECAP 1
`elsif CAP64
  import CapCop64::*;
  `define USECAP 1
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
import MemTypes::*;
`ifdef STATCOUNTERS
import StatCounters::*;
`endif

typedef struct {
  ControlTokenT ct;
  MIPSReg       result;
  Address       nextPc;
  Bit#(10)      count;
} InstructionReport deriving (Bits); // total=256

typedef struct {
  Exception   exp;
  Address     nextPc;
} ExpPc deriving (Bits); // total=256

module mkWriteback#(
  MIPSMemory m,
  MIPSRegFileIfc rf,
  CP0Ifc cp0,
  BranchIfc branch,
  DebugIfc debugUnit,
  CoProIfc cop1,
  `ifdef USECAP
    CapCopIfc capCop,
  `endif
  `ifdef STATCOUNTERS
    StatCounters statCnt,
  `endif
  FIFO#(ControlTokenT) inQ
)(WritebackIfc);

  FIFOF#(Bool)                   hiLoCommit <- mkFIFOF();
  Reg#(InstructionReport) instructionReport <- mkRegU;
  `ifdef USECAP
    Reg#(CapFat)                 writtenCap <- mkRegU; 
  `endif
  // These two registers are used for tracing.
  Reg#(Bit#(10))             lastReportTime <- mkReg(0);
  Reg#(InstId)                 lastReportId <- mkConfigReg(1);
  // These are different.
  Reg#(InstId)           lastCommitReportId <- mkConfigReg(1);
  Reg#(Exception)        preMemExceptionReg <- mkConfigReg(?);

  Reg#(Bit#(48)) instCount <- mkReg(0);
  Reg#(Bit#(48)) cyclCount <- mkReg(0);
  Reg#(Bit#(48)) lsInCycCt <- mkReg(0);
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
        GE: return (!nexT.signedOp) ? (nexT.carryout == 0): (nexT.opA[63] == ((preMemException==Ov) ? 1:0));
        LT: return (!nexT.signedOp) ? (nexT.carryout == 1): (nexT.opA[63] == ((preMemException==Ov) ? 0:1));
        NE: return (!nexT.signedOp) ? (nexT.opA != 0)     : False;
        default: return False;
      endcase);
  if (needTrap && (preMemException==None || preMemException==Ov)) preMemException=TRAP;
  if (nexT.test!=Nop && preMemException==Ov) preMemException=None;
  if (nextDead) preMemException = None;

  `ifdef BLUESIM
    Vector#(32, Reg#(Bit#(64))) debugRegFile <- replicateM(mkRegU);
  `endif
  
  // A single element buffer for debug reports to help with timing.
  FIFO#(DebugReport)           debugReports <- mkFIFO1;
  rule passDebugReport;
    debugUnit.client.response.put(debugReports.first);
    debugReports.deq;
  endrule

  function Address getExceptionEntryROM(Exception exc);
    case (exc)
      `ifndef CAP64
          NMI:                return 64'h9000000040000000;
      `else
          NMI:                return 64'hFFFFFFFFE0000000;
      `endif
          ITLB, DTLBL, DTLBS: return 64'hFFFFFFFFBFC00280; //TLB exception.
          CAPCALL:            return 64'hFFFFFFFFBFC00480;
          default:            return 64'hFFFFFFFFBFC00380; //General purpose exception.
    endcase
  endfunction

  function Address getExceptionEntryRAM(Exception exc);
    case (exc)
      `ifndef CAP64
          NMI:                return 64'h9000000040000000;
      `else
          NMI:                return 64'hFFFFFFFFE0000000;
      `endif
          ITLB, DTLBL, DTLBS: return 64'hFFFFFFFF80000080; //TLB exception.
          CAPCALL:            return 64'hFFFFFFFF80000280;
          default:            return 64'hFFFFFFFF80000180; //General purpose exception.
    endcase
  endfunction

  function Action doRegisterWriteback(
    RegNum dest,
    Address pc,
    Bit#(3) sel,
    MIPSReg result,
    MemResponseDataT memResponse,
    SizedWord storeData,
    WriteBack writeDest,
    MemOp mem,
    Bool writeRegMask,
    Bool fromDebug,
    Exception exp,
    Bool dead,
    `ifdef MULTI
      Bit#(16) coreID,
    `endif
    InstId id
  );
    action
      MIPSReg regResult = (mem==Read) ? memResponse.data:result;
      Bool instructionIsCommitting = (!dead && exp == None);
      rf.writeReg(regResult, instructionIsCommitting);
      if (instructionIsCommitting) begin // If we had an exception, flush the pipe with no effect on register file.
        if (writeDest == RegFile) begin
          `ifdef BLUESIM
            debugRegFile[dest] <= regResult;
          `endif
        end
        if (cyclCount - lsInCycCt > 1) begin
          `ifdef MULTI
            cycReport($display("c%d: %3d dead cycles", coreID, cyclCount - lsInCycCt - 1));
          `else
            cycReport($display("%3d dead cycles", cyclCount - lsInCycCt - 1));
          `endif
        end
        if (writeRegMask) rf.clearRegs(truncate(result));
        lsInCycCt <= cyclCount;
        instCount <= instCount + 1;
      end
      if (writeDest == HiLo) begin
        hiLoCommit.enq(instructionIsCommitting);
      end
      if (writeDest == CoPro0) begin
        cp0.writeReg(dest, sel, result, fromDebug, instructionIsCommitting);
        debug($display("Writeback: CoPro0 dest=%d, sel=%d, result=%x, fromDebug=%x, instructionIsCommitting=%b", dest, sel, result, fromDebug, instructionIsCommitting));
      end
      if (fromDebug) begin
        debugReports.enq(DebugReport{
          valid: (dest==0),
          writeback: regResult,
          expType: getExceptionCode(exp)
        });
      end
      `ifdef USECAP
        Capability capMemResponse = unpack({pack(memResponse.isCap),memResponse.loadedCap});
        CapFat newWC <- capCop.commitWriteback(CapWritebackRequest{
          mipsExp: exp,
          dead: dead,
          memResponse: capMemResponse,
          instId: id,
          `ifndef CAP64
              pc: pc
          `else
              pc: pc[31:0]
          `endif
        });
        // This case should be subsumed by the next case.
        writtenCap <= newWC;
      `endif
      cop1.commitWriteback(CoProWritebackRequest{
          dead: dead,
          commit: instructionIsCommitting,
          instId: id,
          data: regResult
        });
      `ifdef STATCOUNTERS
        statCnt.commitReset(instructionIsCommitting);
      `endif
    endaction
  endfunction

  function ActionValue#(ExpPc) doPCUpdate(
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
    `ifdef USECAP
      CapOp capOp,
    `endif
    PCSource  newPcSource
  );
    actionvalue
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
      /*`ifdef USECAP
        Bool targetInBounds <- capCop.targetInBounds(target);
        Bool capJump = capOp==JR || capOp==JALR;
        if (!capJump
            && !branchDelay
            && exp.exception == None 
            && !targetInBounds
           ) exp.exception = ICAP;
      `endif*/
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
        debug($display("Exception in Writeback"));
        `ifndef MULTI
          trace($display("     Exception!  Code=0x%x (", getExceptionCode(exp.exception), fshow(exp.exception), ")"));
          trace($display("     Victim = %x, Instruction = %x", exp.victim, exp.instruction));
        `else
          trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception!  Code=0x%x", $time, coreID, getExceptionCode(exp.exception)));
          trace($display("Time:%0d, Core:%0d, Thread:0 :: Victim = %x, Instruction = %x", $time, coreID, exp.victim, exp.instruction));
        `endif
      end else if (writePC && !dead) begin // Write the new PC
        exp.victim = zeroExtend(instCount);
      end
      cp0.putException(exp, pc, opA); // Write the appropriate CP0 registers.
      return ExpPc{nextPc: (doWritePc ? target:0), exp: exp.exception};
    endactionvalue
  endfunction

  rule doInstructionReport;
    InstructionReport reportInput = instructionReport;
    ControlTokenT c = reportInput.ct;
    MIPSReg result = reportInput.result;
    TraceType version = TraceType_Invalid;
    MIPSReg val1 = 64'h000000000000DEAD;
    MIPSReg val2 = 64'h000000000000DEAD;
    
    Word storeData = pack(c.storeData)[63:0];
    Bool newDoCycleReport = doCycleReport;
    
    // If the counter has wrapped around
    if (msb(reportInput.count) == 1'b0 && msb(lastReportTime) == 1'b1)
      newDoCycleReport = True;
      
    case (c.writeDest)
      RegFile, CoPro0, HiLo: begin
        val2 = result;
        version = TraceType_ALU;
      end
    endcase
    case (c.mem)
      Read: begin
        val1 = c.opA;
        version = TraceType_Load;
      end
      Write: begin
        val1 = c.opA;
        val2 = storeData;
        version = TraceType_Store;
      end
      default: begin
        // Only needed for branch case, but the field isn't used otherwise.
        // Subtract PCC base from nextPC to the the architectural target. 
        val1 = reportInput.nextPc - (c.pc - c.archPc);
      end
    endcase
    
    `ifdef USECAP
      ShortCap sc = cap2short(writtenCap);
      if (c.inst matches tagged Coprocessor .ci) begin
        case (ci.op)
          COP2: begin // Capability operation
            if (c.writeDest != RegFile) begin
              val1 = pack(sc)[63:0];
              val2 = pack(sc)[127:64];
              version = TraceType_CapOp;
            end
          end
          LDC2: begin // Load capability
            val1 = c.opA;
            c.archPc = pack(sc)[63:0];
            val2 = pack(sc)[127:64];
            version = TraceType_CapLoad;
          end
          SDC2: begin // Store capability
            val1 = c.opA;
            c.archPc = pack(sc)[63:0];
            val2 = pack(sc)[127:64];
            version = TraceType_CapStore;
          end
        endcase
      end
    `endif
      
    if (c.id != lastReportId) begin
      TraceEntry nextTraceEntry = TraceEntry {
         entry_type: version,
         pc: c.archPc,
         inst: pack(c.inst)[31:0],
         regVal1: val1,
         regVal2: val2,
         ex: pack(getExceptionCode(c.exception)),
         count: reportInput.count,
         asid: cp0.getAsid,
         branch: c.branch != Never,
         reserved: ?,
         valid: !c.fromDebug && !c.dead
      };
      debugUnit.putTraceEntry(nextTraceEntry);
      lastReportTime <= reportInput.count;
      lastReportId <= c.id;
    end else if (newDoCycleReport) begin
      TraceEntry nextTraceEntry = TraceEntry {
         entry_type: TraceType_Timestamp,
         pc: ?,
         inst: ?,
         regVal1: zeroExtend(cyclCount),
         regVal2: zeroExtend(instCount),
         ex: 31,
         branch: ?,
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
    MIPSReg result = er.opA;
    if (er.test == SC) begin
      result = er.opB;
    end
    
    er.dead = nextDead;
    er.exception = (lastCommitReportId == nexT.id) ? preMemExceptionReg:preMemException;
        
    debug($display("======   EXECUTE RESULT   ======"));
    debug($display("Writeback"));
    debug(displayControlToken(er));

    `ifdef BLUESIM
      if (er.writeDest == CoPro0 && er.dest == 26) begin
        debugInst($display("======   RegFile   ======"));
        `ifdef MULTI
          debugInst($display("DEBUG MIPS COREID %d", er.coreID));
        `endif
        debugInst($display("DEBUG MIPS PC 0x%x", er.pc));
        debugInst($display("DEBUG MIPS REG %2d 0x%x", 0, 64'h0));
        for (Integer i = 1; i<32; i=i+1) begin
          debugInst($display("DEBUG MIPS REG %2d 0x%x", i, debugRegFile[i]));
        end
      end
    `endif

    Word oldWord = ?;
    if (er.storeData matches tagged DoubleWord .d) oldWord = d;

    
    MemResponseDataT memResult <- m.dataMemory.getResponse(oldWord, er.signExtendMem, er.opA[7:0], er.memSize, (er.exception!=None) || er.dead, (er.dest == 28 && er.writeDest == CoPro0 && er.cop.cache != ICache)?True:False);
    `ifdef MULTI
      `ifndef MICRO
        if (er.test == SC && er.opB[0] == 1 && memResult.scResult) begin
          debug($display("Writeback: Store Conditional Success"));
        end  
        if (er.test == SC && (er.opB[0] != 1 || !memResult.scResult)) begin
          debug($display("Writeback: Store Conditional Fail"));
          er.opA = 0;
          result = 0;
          er.mem = None;
        end
      `endif
    `endif
    
    // If this one had a valid memory operation, look at the exception.
    if (er.mem != None && er.mem != ICacheOp && 
        memResult.exception != None && er.exception == None) begin
      er.exception = memResult.exception;
    end
    
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

    ExpPc expPc <- doPCUpdate(
      er.inst, er.pc, er.archPc, er.pcUpdate, virtualAddress, er.opB, result, er.epoch, er.fromDebug, exp,
      er.branch, er.dead, er.writePC, er.flushPipe,
      er.branchDelay, 
      `ifdef MULTI
        er.coreID,
      `endif
      `ifdef USECAP
        er.capOp,
      `endif
      er.newPcSource
    );
    er.exception = expPc.exp;

    Bit#(3) sel = 0;
    if (er.inst matches tagged Coprocessor .cp) begin
      sel = cp.select;
    end

    if (er.inst matches tagged Register .ri) begin
      sel = zeroExtend(pack(ri.f)[2:0]);
    end

    doRegisterWriteback(er.dest, er.pc, sel, result, 
                        memResult, er.storeData, er.writeDest, er.mem,
                        er.writeRegMask, er.fromDebug, er.exception, er.dead, 
                        `ifdef MULTI
                          er.coreID,
                        `endif
                        er.id);
    
    // The memory response in a word type, which is the common case.  This is also handled in doRegisterWriteback.
    if (er.mem == Read) result = memResult.data;

    if (!er.dead && er.exception == None) begin // If we had an exception, flush the pipe with no effect on register file.
      `ifndef MULTI
        trace(displayTrace(er, result, instCount));
      `else
        trace(displayTrace(er, result, instCount, inQ.first.coreID));
      `endif
    end
    instructionReport <= InstructionReport{ct:er, result:result,
                         nextPc: expPc.nextPc, count:truncate(cyclCount)};
  endrule

  interface getHiLoCommit = hiLoCommit;
  
  method ActionValue#(Bool) nextWillCommit() if (lastCommitReportId != nexT.id);
    lastCommitReportId <= nexT.id;
    preMemExceptionReg <= preMemException;
    return !nextDead && (preMemException==None);
  endmethod
  
  method Action putCycleCount(Bit#(48) count);
    cyclCount <= count;
  endmethod
endmodule
