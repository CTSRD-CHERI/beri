/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2014, 2015 Alexandre Joannou
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

import MIPS::*;
import ForwardingPipelinedRegFile::*;
import CP0::*;
import GetPut::*;
import Memory::*;
import FIFO::*;
import SpecialFIFOs::*;
import LevelFIFO::*;
import ClientServer::*;
`ifdef COP1
  import CoProFPTypes::*;
  import CoProFPInst::*;
`endif
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
`ifdef STATCOUNTERS
import StatCounters::*;
import Debug::*;
`endif

// The unknownInstruction function returns a control token appropriate for an 
// unrecognized instruction format.
function ActionValue#(ControlTokenT) unknownInstruction(ControlTokenT cti);
  actionvalue
    ControlTokenT cto = cti;
    cto.alu = Nop;
    cto.writeDest = None;
    cto.mem       = None;
    // Unrecognized instruction format exception.
    cto.exception = RI;
    return cto;
  endactionvalue
endfunction

// The mkScheduler module does a "pre-decode" of the instruction to find which
// register numbers may be fetched and to classify the branch behaviour of the
// instruction for the branch predictor.
module mkScheduler#(
  // The scheduler needs the branch interface so that it can report the branch type
  // for the next prediction.  This saves the branch predictor from having to guess
  // if the next instruction is a branch or not.
  BranchIfc branch,
  // The scheduler needs the register file interface because it submits the
  // register fetches that are retrieved in the decode stage.
  MIPSRegFileIfc theRF,
  // The scheduler needs the CP0 interface because it also submits potential register
  // reads to the CP0 interface, which are also retrieved in the decode stage.
  CP0Ifc cp0,
  CoProIfc cop1,
  `ifdef USECAP
    CapCopIfc capCop,
  `endif
  // The scheduler needs the instruction memory interface because it pulls the next
  // instruction out of the instruction memory to begin pre-decode analysis.
  InstructionMemory m
  // The scheduler exports a PipeStageIfc interface, (a FIFO#(ControlTokenT) interface),
  // for integration with the pipeline.
  `ifdef STATCOUNTERS
  , StatCounters statCounters
  `endif
)(PipeStageIfc);

  // The lastWasBranch register records whether the last instruction was a
  // branch (and therefore whether this one will be a branch delay slot).
  Reg#(Bool) lastWasBranch <- mkReg(False);
  // The lastEpoch register records the branch epoch of the last fetch so that
  // we can know whether this and the previous instruction are part of an
  // unbroken stream of instructions, specifically so that we know whether this
  // is the branch delay of a previous branch, or if it is from a new stream of
  // instructions.
  Reg#(Epoch) lastEpoch <- mkReg(0);
  // The outQ is the output queue of control tokens.  After an instruction has
  // completed this stage, we place its control token into the outQ to be taken
  // for the next stage.
  FIFO#(ControlTokenT) outQ <- mkFIFO;

  // This pipeline stage, as with the others, presents a FIFO#(ControlTokenT)
  // interface, that is, a fifo of control tokens.  This is the enq method.
  method Action enq(ControlTokenT cti);
    ControlTokenT cto = cti;
    // zero the operands to ensure that operation is predictable if they are not used.
    cto.opA = 0;
    cto.opB = 0;
    cto.pcUpdate = 4;
    cto.storeData = tagged DoubleWord 0;
    cto.dest = 0;
    cto.writeDest = None;
    cto.mem = None;
    cto.memSize = Byte;
    // Get the instruction from the memory system.
    CacheResponseInstT instResp <- m.getInstruction();
    // If this instruction is not inserted by the debug unit...
    if (!cti.fromDebug) begin
      // And if there has not been an exception already, adopt the exception
      // from the instruction fetch. (Hopefully it is also None)
      if (cti.exception == None) begin
        cto.exception = instResp.exception;
      end
      // Also if this control token is not from debug, take the instruction from
      // the memory response.
      //cto.inst = instResp.inst;
    end
    // Take the instruction from the memory response.
    cto.inst = instResp.inst;
    // Create the branch type which must be decided in this module, default to
    // None (not a branch).
    BranchType branchType = None;
    // If the last instruction was a branch in the same epoch, and if this
    // instruction is not from debug, mark this instruction as in a branch delay
    // slot.
    if (lastWasBranch && (lastEpoch == cti.epoch) && !cti.fromDebug) begin
      cto.branchDelay = True;
    end
    // The branchCertain flag tells the branch predictor if this is a branch is
    // certain to be taken
    Bool branchCertain = False;
    // The link flag tells the branch predictor if this is a jump with a link,
    // enabling a call stack in the predictor.
    Bool link = False;
    // Flag to determine if the register write might not happen.
    Bool conditionalUpdate = False;
    // Initialize default register number requests to zero.
    RegNum reqA = 5'b0;
    RegNum reqB = 5'b0;
    RegNum reqC = 5'b0;
    Bit#(3) reqSel = 3'b0; // This "select" for CP0
    
    // Prepare nop coprocessor instructions for the general purpose coprocessors.
    CoProInst coProInst = unpack(0);
    coProInst.op = None;
    coProInst.instId = cti.id;
    CoProInst coProInst1 = coProInst;
    `ifdef USECAP
      /*CapInst capInst = CapInst{
        op: None,
        r0: ?,
        r1: ?,
        r2: ?,
        r3: ?,
        memSize: CapWord,
        instId: cti.id,
        epoch: cti.epoch
      };*/
      Bool couldBeCapLoadOrStore = False; // Use this bool to detect if this could be a capability load/store
      Ctype cinst = unpack(truncate(pack(cto.inst)));
      CapInst capInst = CapInst{
                op: None,
                r0: pack(cinst.cOp),
                r1: cinst.r1,
                r2: cinst.r2,
                r3: cinst.r3,
                fetchA: 0,
                doFetchA: False,
                fetchB: ?,
                doFetchB: False,
                dest: ?,
                doWriteDest: False,
                memSize: CapWord,
                instId: cti.id,
                epoch: cti.epoch
              };
    `endif
    `ifdef STATCOUNTERS
    // prepare default statcounters request
    StatCountersReq statcounters_req = tagged Nop;
    `endif

    debug($display("======   PRE-SCHEDULER INSTRUCTION   ======"));
    debug(displayControlToken(cto));
    debug($display("INSTRUCTION FORMAT: ", fshow(cto.inst)));
    // A case statement on the instruction type.
    case (cto.inst) matches
      // Case for the immediate instruction format, which has a 16 bit immediate operand.
      (tagged Immediate .ii): begin
        // The rt field represents a function field for some immediate
        // instructions, so do a cast here.
        RegImmFunc f = unpack(ii.rt);
        reqA = ii.rs;
        cto.opAsrc = RegFile;
        reqB = ii.rt;
        cto.opBsrc = RegFile;
        // This case statement assigns properties of various instruction classes
        // of immediate format instructions.
        case (ii.op)
          REGIMM: begin
            reqB = 0;
            cto.opBsrc = ControlToken;
            case (f)
              // Test instructions have no special properties that we need in this stage.
              TEQI, TGEI, TGEIU, TLTI, TLTIU, TNEI: begin
                reqB = 0;
                cto.opBsrc = ControlToken;
              end // Do nothing.
              // These branch link instructions must be recorded for the branch predictor.
              BLTZAL, BGEZAL, BLTZALL, BGEZALL: begin
                branchType = Branch;
                link = True;
                cto.writeDest = RegFile;
                cto.dest = 31;
                if (case (f) BLTZALL, BGEZALL: return True; default: return False; endcase)
                  cto.branchLikely = True;
                if (case (f) BLTZALL, BGEZALL: return True; default: return False; endcase)
                  cto.branchLikely = True;
              end
              // These are plain branch likelies without links.
              BLTZL, BGEZL: begin
                cto.branchLikely = True;
                branchType = Branch;
              end
              // All other instructions of this class are branches.
              default: begin
                branchType = Branch;
              end
            endcase
            // Do another pass through these to pick up the remaining flags.
            case(f)
              // These are branch and branch likely instructions.
              BLTZ, BGEZ, BLTZAL, BGEZAL, BLTZL, BLTZALL, BGEZL, BGEZALL: begin
                cto.mem = None;
                cto.opB = 0;
                cto.newPcSource = PCUpdate;
                case(f)
                  BLTZ, BLTZAL, BLTZL, BLTZALL: begin
                    cto.branch = LTZ;
                  end
                  BGEZ, BGEZAL, BGEZL, BGEZALL: begin
                    cto.branch = GEZ;
                  end
                endcase
                // The next instruction (in the branch delay slot) is compulsory, so the target in
                // question is the instruction after that one.  The default is 8.  We will update
                // this when the branch is evaluated in Execute.
                cto.pcUpdate = 8;
              end
              // Test operations will throw an exception if their condition is violated.
              // These ones test against immediate values.
              TEQI, TGEI, TGEIU, TLTI, TLTIU, TNEI: begin
                cto.opB = signExtend(ii.imm);
                cto.alu = Sub;
                cto.sixtyFourBitOp = True;
        
                cto.signedOp = (f == TGEI || f == TLTI);
        
                case(f)
                  TGEI, TGEIU:  cto.test = GE;
                  TLTI, TLTIU:  cto.test = LT;
                  TEQI:         cto.test = EQ;
                  TNEI:         cto.test = NE;
                endcase
              end
              default: begin
                cto <- unknownInstruction(cto);
              end
            endcase
          end
          // A set of branch instructions
          BEQ,BNE,BLEZ,BGTZ,BEQL,BNEL,BLEZL,BGTZL: begin
            branchType = Branch;
            // If the instruction tests equality of a register against itself,
            // the the branch is certain, so pass the hint down to the branch
            // predictor.
            if (ii.op == BEQ && ii.rs == ii.rt) begin
              branchCertain = True;
            end
            // These are the likely versions of branches.
            if (case (ii.op) BEQL,BNEL,BLEZL,BGTZL:return True; default: return False; endcase)
              cto.branchLikely = True;
            cto.newPcSource = PCUpdate;
            case(ii.op)
              BEQ, BEQL: cto.branch=EQ;
              BNE, BNEL: cto.branch=NE;
              BLEZ, BLEZL: cto.branch=LEZ;
              BGTZ, BGTZL: cto.branch=GTZ;
            endcase
            cto.pcUpdate = 8; // The branch delay will not write it's PC, so we add 8 by default.
          end
          LB, LH, LW, LL, LD, LLD, LBU, LHU, LWU, LWL, LWR, LDL, LDR: begin
            cto.dest = ii.rt;
            cto.writeDest = RegFile;
            cto.opBsrc = ControlToken;
            case (ii.op)
              LWL, LWR, LDL, LDR: cto.storeDatasrc = RegFile;
              default: reqB = 0;
            endcase
            cto.mem = Read;
            cto.observesCP0 = True; // Loads and stores observe the TLB
            case (ii.op)
              LB, LBU: cto.memSize = Byte;
              LH, LHU: cto.memSize = HalfWord;
              LW, LL, LWU: cto.memSize = Word;
              LD, LLD: cto.memSize = DoubleWord;
              LWL:     cto.memSize = WordLeft;
              LWR:     cto.memSize = WordRight;
              LDL:     cto.memSize = DoubleWordLeft;
              LDR:     cto.memSize = DoubleWordRight;
            endcase
          end
          SB, SH, SW, SWL, SWR, SD, SDL, SDR: begin
            cto.opBsrc = ControlToken;
            cto.storeDatasrc = RegFile;
            cto.mem = Write;
            cto.observesCP0 = True; // Loads and stores observe the TLB
            case (ii.op)
              SB:  cto.memSize = Byte;
              SH:  cto.memSize = HalfWord;
              SW:  cto.memSize = Word;
              SWL: cto.memSize = WordLeft;
              SWR: cto.memSize = WordRight;
              SD:  cto.memSize = DoubleWord;
              SDL: cto.memSize = DoubleWordLeft;
              SDR: cto.memSize = DoubleWordRight;
            endcase
          end
          SC, SCD: begin
            cto.writeDest = RegFile;
            cto.dest = ii.rt;
            cto.opBsrc = ControlToken;
            cto.storeDatasrc = RegFile;
            cto.mem = Write;
            cto.observesCP0 = True; // Loads and stores observe the TLB

            `ifdef MULTI
              // If its a store conditional we don't want Execute to write into the
              // RegFile as the success or failure depends in the state of the shared
              // L2Cache. This allows us to delay the Reg write until the Writeback
              // stage.
              cto.pendingWrite = True;
            `endif

            case (ii.op)
              SC: begin
                cto.memSize = Word;
              end
              SCD: begin
                cto.memSize = DoubleWord;
              end
            endcase
          end
          CACHE: begin
            cto.opBsrc = ControlToken;
            // If the instruction is a Cache Load Tag
            if (ii.rt[4:2] == 1) begin
              cto.writeDest = CoPro0;
              cto.dest = 28;
            end    
            debug($display("Scheduler: Cache Operation ii.rt=%x, writeDest=%x, cto.dest=%d", ii.rt[4:2], cto.writeDest, cto.dest));        
          end
          default: begin
            cto.writeDest = RegFile;
            cto.dest = ii.rt;
            cto.opBsrc = ControlToken;
          end
        endcase
      end
      // The "jump" type of instruction has a 24 bit immediate value and no
      // register operands.
      (tagged Jump .ji): begin
        case (ji.op)
          // A jump instruction sets flags for the branch predictor, but has no
          // operands or destination register.
          J: begin
              branchType = Jump;
              cto.branch = DoneTaken;
              cto.newPcSource = Immediate;
            end
          // Jump and link immediate instructions have a destination register,
          // as well as flags for the branch predictor.
          JAL,JALX: begin
              link = True;
              cto.writeDest = RegFile;
              cto.dest = 31;
              branchType = Jump;
              cto.branch = DoneTaken;
              cto.newPcSource = Immediate;
            end
        endcase
      end
      // Dependency and branch flags for the register immediate class of instructions
      (tagged Register .ri): begin
        // Do the dependency check for the three possible register operands for
        // register format instructions.
        cto.opAsrc = RegFile;
        cto.opBsrc = RegFile;
        cto.storeDatasrc = None;
        reqA = ri.rs;
        reqB = ri.rt;
        cto.writeDest = RegFile;
        cto.dest = ri.rd;
        // Fetch rd from CP0.
        reqC = ri.rd;
        case (ri.op)
          SPECIAL: begin
            cto.dest = ri.rd;
            // The "SPECIAL" class of instructions depends on the function field
            case (ri.f)
              MULTU, DIVU, MULT, DIV, DMULTU, DDIVU, DMULT, DDIV: begin
                cto.writeDest = HiLo;
                reqA = ri.rt;
                reqB = ri.rs;
              end
              SLLV, SRLV, SRAV, DSLLV, DSRLV, DSRAV: begin
                reqA = ri.rt;
                reqB = ri.rs;
              end
              SLL, SRA, SRL, DSLL, DSRL, DSRA, DSLL32, DSRL32, DSRA32: begin
                reqA = ri.rt;
                reqB = 0;
                cto.opBsrc = ControlToken;
              end
              MTHI, MTLO: begin
                reqB = 0;
                cto.opBsrc = None;
                cto.writeDest = HiLo;
              end
              // Jump Register sets flags for the branch predictor, but has no destination.
              JR: begin
                reqA = 0;
                cto.opAsrc = None;
                reqB = ri.rs;
                cto.writeDest = None;
                branchType = JumpReg;
                cto.newPcSource = OpB;
                cto.branch = Always;
              end
              // Jump and link register the branch type and link behaviour
              JALR: begin
                reqA = 0;
                cto.opAsrc = None;
                reqB = ri.rs;
                branchType = JumpReg;
                link = True;
                cto.newPcSource = OpB;
                cto.branch = Always;
              end
              MOVZ, MOVN: begin
                conditionalUpdate = True;
              end
              TGE, TGEU, TLT, TLTU, TEQ, TNE, SYSCALL, BREAK, SYNC: begin
                cto.writeDest = None;
              end
            endcase
          end
          SPECIAL2: begin
            // This field is the more common Func type by default, but this case
            // needs the Func2 interpretation of this field.
            Func2 func2 = unpack(pack(ri.f));
            case (func2)
              // Multiply add, signed and unsigned variants.
              MADD, MADDU: begin
                // Write destination is the hi/lo registers.
                cto.writeDest = HiLo;
                reqA = ri.rt;
                reqB = ri.rs;
              end
              // Multiply subtract, signed and unsigned variants.
              MSUB, MSUBU: begin
                cto.writeDest = HiLo;
                reqA = ri.rt;
                reqB = ri.rs;
              end
              /*
              CLZ,DCLZ: begin
                  reqA = ri.rs;
                  reqB = ri.rt;
                  cto.opAsrc = RegFile;
                  cto.opBsrc = RegFile;
                  cto.mem = None;
                  cto.writeDest = RegFile;
                  cto.dest = ri.rd;
              end
               */
            endcase
          end
          SPECIAL3: begin
            // This field is the more common Func type by default, but this case
            // needs the Func2 interpretation of this field.
            Func3 func3 = unpack(pack(ri.f));
            cto.observesCP0 = True;
            case (func3)
              RDHWR: begin
                case (ri.rd)
                  0,30: begin
                    cto.coProSelect = 0;
                    reqC = 15;
                    reqSel = 6;
                    cto.opAsrc = CoPro0;
                    cto.dest = ri.rt;
                  end
                  2: begin
                    cto.coProSelect = 0;
                    reqC = 9;
                    cto.opAsrc = CoPro0;
                    cto.dest = ri.rt;
                  end
                  3: begin
                    cto.opAsrc = None;
                    cto.opBsrc = ControlToken;
                    cto.dest = ri.rt;
                  end
                  4: begin
                    reqC = 9;
                    reqSel = 4;  // insts
                    cto.opAsrc = CoPro0;
                    cto.dest = ri.rt;
                  end
                  5: begin
                    reqC = 9;
                    reqSel = 5; // instTLBMiss
                    cto.opAsrc = CoPro0;
                    cto.dest = ri.rt;
                  end
                  6: begin
                    reqC = 9;
                    reqSel = 6; // dataTLBMiss
                    cto.opAsrc = CoPro0;
                    cto.dest = ri.rt;
                  end
                  `ifdef STATCOUNTERS
                  7: begin
                    debug2("StatCounters", $display("<time %0t, Scheduler> RDHWR %0d (reset stat counters)", $time, ri.rd));
                    statcounters_req = tagged ResetAll;
                    cto.opAsrc = None;
                    cto.opBsrc = None;
                    cto.dest   = ri.rt;
                  end
                  8,9,10,11,12,13,14: begin
                    debug2("StatCounters", $display("<time %0t, Scheduler> RDHWR %0d (read stat counters)", $time, ri.rd));
                    statcounters_req = tagged Read Selectors {
                      moduleSelector:   ri.rd-8,
                      counterSelector: ri.sa
                    };
                    cto.opAsrc = None;
                    cto.opBsrc = None;
                    cto.dest   = ri.rt;
                  end
                  `endif
                  29: begin
                    cto.coProSelect = 0;
                    reqC = 4;
                    reqSel = 2;
                    cto.opAsrc = CoPro0;
                    cto.dest = ri.rt;
                  end
                endcase
              end
            endcase
          end
          // Coprocessor 0 instructions
          COP0: begin
            cto.observesCP0 = True;
            CoProOp copro = unpack(ri.rs);
            //  This is the shadow register select for coprocessor 0.
            reqSel = pack(ri.f)[2:0];
            // Case switch on coprocessor operation
            case (copro)
              // Move from coprocessor variants use the select field and have a
              // destination register
              MFC,DMFC,CFC: begin
                cto.coProSelect = pack(ri.f)[2:0];
                reqC = ri.rd;
                cto.opAsrc = CoPro0;
                cto.dest = ri.rt;
              end
              // Move to coprocessor variants use the select field but write to
              // the coprocessor.
              CTC,MTC,DMTC: begin
                reqA = ri.rt;
                reqB = 0;
                cto.opBsrc = None;
                cto.dest = ri.rd;
                cto.writeDest = CoPro0;
                cto.coProSelect = pack(ri.f)[2:0];
              end
              // Coprocessor 0 instructions, mostly TLB related, have no general
              // purpose destination register.
              INST: begin
                cto.opAsrc = ControlToken;
                cto.opBsrc = None;
                reqA = 0;
                reqB = 0;
                cto.writeDest = CoPro0;
                cto.dest = 5'd31; // Secret unused location for passing an instruction!
                CP0Inst tlbInst = unpack(pack(ri.f)[5:0]);
                case (tlbInst)
                  // ERET needs to request register 14 from coprocessor 0
                  ERET: begin
                    cto.opBsrc = CoPro0;
                    reqC = 14; // request the PC for an exception return.
                    `ifdef USECAP
                      capInst.op = ERET;
                      `ifdef CAP128
                        // Not actually writing to regiter file, but indicating 
                        // that the branch target will come late.
                        cto.pendingWrite = True;
                      `elsif CAP64
                        cto.pendingWrite = True;
                      `endif
                      capInst.fetchA = 31;
                      capInst.doFetchA = True;
                    `endif
                    cto.flushPipe = True;
                    cto.newPcSource = OpB;
                    cto.branch = Always;
                  end
                endcase
              end
            endcase
          end
        endcase
      end
      (tagged Coprocessor .ci): begin
        case (ci.op)
          `ifdef COP1
            COP1: begin
              reqA = ci.r1;
              reqB = ci.r2;
              cto.opAsrc = RegFile;
              cto.opBsrc = RegFile;
              cto.mem = None;
              cto.writeDest = RegFile;
              CoProFPOp coProFPOp = unpack(pack(ci.cOp));
              case (coProFPOp)
                MFC, DMFC, CFC: begin
                  cto.writeDest = RegFile;
                  cto.dest = ci.r1;
                end
                MTC, DMTC, CTC: begin
                  cto.dest = ci.r1;
                end
                BC1: begin
                  cto.writeDest = None;
                  cto.branch = Always;
                  FPBType tmp = convert(CoProInst{
                    mipsOp: ?,
                    op: unpack(pack(ci.cOp)),
                    regNumA: ci.r2,
                    regNumB: ci.r3,
                    regNumDest: ci.r1,
                    imm: {ci.spacer,ci.select},
                    instId: cti.id
                  });
                  branchType = JumpReg;
                  cto.branchLikely = tmp.nd;
                end
              endcase
            end
            SPECIAL: begin
              Rtype ri = unpack(pack(ci));
              reqA = ri.rs;
              reqB = ri.rt;
              cto.opAsrc = RegFile;
              cto.opBsrc = RegFile;
              cto.mem = None;
              cto.writeDest = RegFile;
              cto.dest = ri.rd;
              cto.alu = Cop1;
              cto.sixtyFourBitOp = True;
            end
            LWC1,LDC1,SWC1,SDC1,COP3: begin
              Itype ii = unpack(pack(ci));
              let base = unpack(pack(ci.cOp));
              reqA = base;
              reqB = ii.rt;
              cto.opAsrc = RegFile;
              if (ci.op == COP3) begin
                reqB = ci.r1;
                cto.opBsrc = RegFile;
              end else begin
                cto.opBsrc = ControlToken;
              end
              cto.dest = ci.r3;
              CoProFPXOp fpxOp = unpack(pack(ci)[5:0]);
              case (ci.op)
                LWC1, SWC1: begin
                  cto.memSize = Word;
                end
                LDC1, SDC1: begin
                  cto.memSize = DoubleWord;
                end
                COP3: begin
                  case (fpxOp)
                    LWXC1, SWXC1: begin
                      cto.memSize = Word;
                    end
                    LDXC1, SDXC1: begin
                      cto.memSize = DoubleWord;
                    end
                    endcase
                  end
              endcase
              case (ci.op)
                LWC1, LDC1: begin
                  cto.mem = Read;
                end
                SWC1, SDC1: begin
                  cto.writeDest = None;
                  cto.mem = Write;
                  cto.storeDatasrc = CoPro1;
                end
                COP3: begin
                  case (fpxOp)
                    LWXC1, LDXC1: begin
                      cto.mem = Read;
                    end
                    SWXC1, SDXC1: begin
                      cto.writeDest = None;
                      cto.mem = Write;
                      cto.storeDatasrc = CoPro1;
                    end
                  endcase
                end
              endcase
            end
          `endif
          `ifdef USECAP
            COP2,LWC2,LDC2,SWC2,SDC2: begin
              couldBeCapLoadOrStore = True;
              reqA = ci.r3;
              reqB = ci.r2;
              cto.opAsrc = RegFile;
              cto.opBsrc = RegFile;
              reqC = 0;
              cto.writeDest = None;
              cto.alu = Cap;
              cto.signedOp = False;
              cto.sixtyFourBitOp = True;
              capInst.memSize = cto.memSize;
              CapReg fa = ?;
              Bool dfa = False;
              CapReg fb = ?;
              Bool dfb = False;
              CapReg wb = ?;
              Bool dwb = False;
              case (ci.op)
                COP2: begin
                  reqB = ci.r1;
                  cto.memSize = Byte;
                  case (ci.cOp) // This case statement checks dependencies
                    // Offset manipulation instructions 
                    COffset: begin
                      OffsetOpCode op = unpack(ci.select);
                      case(op)
                        CIncOffset: begin
                          cto.coProSelect = ci.select;
                          cto.capOp = IncOffset;
                          fa = capInst.r2; dfa = True;
                          wb = capInst.r1; dwb = True;
                        end
                        CSetOffset: begin
                          cto.capOp = SetOffset;
                          fa = capInst.r2; dfa = True;
                          wb = capInst.r1; dwb = True;
                        end
                        CGetOffset: begin
                          cto.writeDest = RegFile;
                          cto.dest = ci.r1;
                          cto.capOp = GetOffset;
                          fa = capInst.r2; dfa = True;
                          //`ifdef CAP128
                          //  cto.pendingWrite = True;
                          //`endif
                        end
                        default: begin
                          cto <- unknownInstruction(cto);
                        end
                      endcase
                    end
                    CCompare: begin
                      cto.writeDest = RegFile;
                      cto.dest = ci.r1;
                      case (ci.select)
                        0: cto.capOp = CmpEQ;
                        1: cto.capOp = CmpNE;
                        2: cto.capOp = CmpLT;
                        3: cto.capOp = CmpLE;
                        4: cto.capOp = CmpLTU;
                        5: cto.capOp = CmpLEU;
                        6: cto.capOp = CmpEQX;
                        default: cto <- unknownInstruction(cto);
                      endcase
                      fa = capInst.r2; dfa = True;
                      fb = capInst.r3; dfb = True;
                    end
                    MFC: begin
                      cto.writeDest = RegFile;
                      cto.dest = ci.r1;
                      CapFuncThreeOpCode capFuncThreeOp = unpack({ci.spacer,ci.select});
                      fa = capInst.r2; dfa = True;
                      case(capFuncThreeOp)
                        CapFuncGetPermOld: cto.capOp = GetPerm;
                        CapFuncGetTypeOld: cto.capOp = GetType;
                        CapFuncGetBaseOld: begin
                          cto.capOp = GetBase;
                        end
                        CapFuncGetLenOld: begin
                          cto.capOp = GetLen;
                        end
                        CapFuncGetCauseOld:  begin
                          cto.capOp = GetConfig;
                          dfa = False;
                        end
                        CapFuncGetTagOld:    cto.capOp = GetTag;
                        CapFuncGetSealedOld: cto.capOp = GetSealed;
                        CapFuncGetPCCOld: begin
                          cto.writeDest = None;
                          cto.alu = Nop;
                          cto.capOp = GetPCC;
                          dfa = False;
                          wb = capInst.r1; dwb = True;
                        end
                        /*CapFuncSetBounds: begin
                          cto.writeDest = None;
                          cto.capOp = SetBounds;
                          wb = capInst.r1; dwb = True;
                        end*/
                        CapFuncSetBoundsExact: begin
                          cto.writeDest = None;
                          cto.capOp = SetBoundsExact;
                          wb = capInst.r1; dwb = True;
                        end
                        CapFuncSub: begin
                          cto.dest = ci.r1;
                          cto.capOp = Subtract;
                          fa = capInst.r2; dfa = True;
                          fb = capInst.r3; dfb = True;
                        end
                        /*CapFuncSeal: begin
                          cto.capOp = Seal;
                          reqA = 0; // Make sure offset is 0 in cap unit.
                          reqB = 0;
                          fa = capInst.r3; dfa = True;
                          fb = capInst.r2; dfb = True;
                          wb = capInst.r1; dwb = True;
                        end
                        CapFuncUnseal: begin
                          cto.capOp = Unseal;
                          reqA = 0; // Make sure offset is 0 in cap unit.
                          reqB = 0;
                          fa = capInst.r3; dfa = True;
                          fb = capInst.r2; dfb = True;
                          wb = capInst.r1; dwb = True;
                        end
                        CapFuncAndPerm: begin
                          cto.coProSelect = ci.select;
                          cto.capOp = AndPerm;
                          wb = capInst.r1; dwb = True;
                        end
                        CapFuncSetOffset: begin
                          cto.writeDest = None;
                          cto.capOp = SetOffset;
                          wb = capInst.r1; dwb = True;
                        end
                        CapFuncIncOffset: begin
                          cto.writeDest = None;
                          cto.coProSelect = ci.select;
                          cto.capOp = IncOffset;
                          wb = capInst.r1; dwb = True;
                        end
                        CapFuncCToPtr: begin
                          cto.dest = ci.r1;
                          cto.capOp = GetRelBase;
                          fa = capInst.r3; dfa = True;
                          fb = capInst.r2; dfb = True;
                          `ifdef CAP128
                            cto.pendingWrite = True;
                          `elsif CAP64
                            cto.pendingWrite = True;
                          `endif
                        end
                        CapFuncCFromPtr: begin
                          cto.writeDest = None;
                          cto.coProSelect = ci.select;
                          cto.capOp = IncBaseNull;
                          wb = capInst.r1; dwb = True;
                        end
                        CapFuncEQ: begin
                          cto.dest = ci.r1;
                          cto.capOp = CmpEQ;
                          fb = capInst.r3; dfb = True;
                        end
                        CapFuncNE: begin
                          cto.dest = ci.r1;
                          cto.capOp = CmpNE;
                          fb = capInst.r3; dfb = True;
                        end
                        CapFuncLT: begin
                          cto.dest = ci.r1;
                          cto.capOp = CmpLT;
                          fb = capInst.r3; dfb = True;
                        end
                        CapFuncLE: begin
                          cto.dest = ci.r1;
                          cto.capOp = CmpLE;
                          fb = capInst.r3; dfb = True;
                        end
                        CapFuncLTU: begin
                          cto.dest = ci.r1;
                          cto.capOp = CmpLTU;
                          fb = capInst.r3; dfb = True;
                        end
                        CapFuncLEU: begin
                          cto.dest = ci.r1;
                          cto.capOp = CmpLEU;
                          fb = capInst.r3; dfb = True;
                        end
                        CapFuncEXEQ: begin
                          cto.dest = ci.r1;
                          cto.capOp = CmpEQX;
                          fb = capInst.r3; dfb = True;
                        end*/
                        CapFuncTwoOp: begin
                          CapFuncTwoOpCode capFuncTwoOp = unpack(ci.r3);
                          case (capFuncTwoOp)
                            /*CapFuncGetPerm: begin
                              cto.capOp = GetPerm;
                            end
                            CapFuncGetType: begin
                              cto.capOp = GetType;
                            end
                            CapFuncGetBase: begin
                              cto.capOp = GetBase;
                            end
                            CapFuncGetLen: begin
                              cto.capOp = GetLen;
                            end
                            CapFuncGetTag: begin
                              cto.capOp = GetTag;
                            end
                            CapFuncGetSealed: begin
                              cto.capOp = GetSealed;
                            end
                            CapFuncGetOffset: begin
                              cto.writeDest = RegFile;
                              cto.dest = ci.r1;
                              cto.capOp = GetOffset;
                            end*/
                            CapFuncGetPCCSetOffset: begin
                              cto.writeDest = None;
                              cto.alu = Nop;
                              reqA = ci.r2;
                              cto.capOp = SetPCCOffset;
                              dfa = False;
                              wb = capInst.r1; dwb = True;
                            end
                            /*CapFuncCheckPerm: begin
                              cto.capOp = CheckPerms;
                              fa = capInst.r1; dfa = True;
                            end
                            CapFuncCheckType: begin
                              cto.capOp = CheckType;
                              fa = capInst.r1; dfa = True;
                              fb = capInst.r2; dfb = True;
                            end
                            CapFuncMove: begin
                              cto.capOp = Move;
                              wb = capInst.r1; dwb = True;
                            end
                            CapFuncClearTag: begin
                              cto.capOp = ClearTag;
                              wb = capInst.r1; dwb = True;
                            end*/
                            CapFuncOneOp: begin
                              CapFuncOneOpCode capFuncOneOp = unpack(ci.r2);
                              dfa = False;
                              case(capFuncOneOp) 
                                CapFuncGetPCC: begin
                                  cto.writeDest = None;
                                  cto.alu = Nop;
                                  cto.capOp = GetPCC;
                                  wb = capInst.r1; dwb = True;
                                end
                                CapFuncGetCause: begin
                                  cto.capOp = GetConfig;
                                end
                                CapFuncSetCause: begin
                                  cto.writeDest = None;
                                  cto.capOp = SetConfig;
                                  reqA = ci.r1;
                                end
                                CapFuncCJR: begin
                                  cto.writeDest = None;
                                  branchType = JumpReg;
                                  cto.branch = Always;
                                  cto.capOp = JR;
                                  cto.newPcSource = OpB;
                                  fa = capInst.r2; dfa = True;
                                end
                                default: cto <- unknownInstruction(cto);
                              endcase
                            end
                            default: cto <- unknownInstruction(cto);
                          endcase
                        end
                        default: cto <- unknownInstruction(cto);
                      endcase
                    end
                    MTC: begin
                      cto.coProSelect = ci.select;
                      fa = capInst.r2; dfa = True;
                      wb = capInst.r1; dwb = True;
                      case(ci.select)
                        0: cto.capOp = AndPerm;
                        4: begin
                          cto.capOp = SetConfig;
                          dfa = False;
                          dwb = False;
                        end
                        5: cto.capOp = ClearTag;
                        6: begin
                          cto.capOp = ReportRegs;
                          dfa = False;
                          dwb = False;
                        end
                        7: cto.capOp = IncBaseNull;
                        default: cto <- unknownInstruction(cto);
                      endcase
                    end
                    CSetBounds: begin
                      cto.capOp = SetBounds;
                      fa = capInst.r2; dfa = True;
                      wb = capInst.r1; dwb = True;
                    end
                    CRelBase: begin
                      cto.writeDest = RegFile;
                      cto.dest = ci.r1;
                      cto.capOp = GetRelBase;
                      fa = capInst.r3; dfa = True;
                      fb = capInst.r2; dfb = True;
                      `ifdef CAP128
                        cto.pendingWrite = True;
                      `elsif CAP64
                        cto.pendingWrite = True;
                      `endif
                    end
                    CJR: begin
                      branchType = JumpReg;
                      cto.branch = Always;
                      cto.capOp = JR;
                      cto.newPcSource = OpB;
                      fa = capInst.r2; dfa = True;
                    end
                    CJALR: begin
                      branchType = JumpReg;
                      cto.branch = Always;
                      cto.capOp = JALR;
                      // We will manually feed PC + 8 into operand B
                      cto.opBsrc = ControlToken;
                      cto.newPcSource = OpB;
                      fa = capInst.r2; dfa = True;
                      wb = capInst.r1; dwb = True;
                    end
                    CBTS,CBTU,CBEZ,CBNZ: begin
                      // The capability unit will return 1 or 0, depending on whether
                      // we should take the branch, so we tell the execute and
                      // writeback stages just to branch on that result.
                      cto.branch=CapTag;
                      cto.writeDest = None;
                      branchType = Branch;
                      // We implement the capability branch instructions as normal conditional branches (BEQ / BNE)
                      cto.mem = None;
                      cto.newPcSource = PCUpdate;
                      cto.pcUpdate = 8; // The branch delay will not write it's PC, so we add 8 by default.
                      case(ci.cOp)
                        CBTS: cto.capOp = BranchTagSet;
                        CBTU: cto.capOp = BranchTagUnset;
                        CBEZ: cto.capOp = BranchEqZero;
                        CBNZ: cto.capOp = BranchNEqZero;
                      endcase
                      fa = capInst.r1; dfa = True;
                    end
                    CSeal: begin
                      cto.capOp = Seal;
                      reqA = 0; // Make sure offset is 0 in cap unit.
                      reqB = 0;
                      fa = capInst.r3; dfa = True;
                      fb = capInst.r2; dfb = True;
                      wb = capInst.r1; dwb = True;
                    end
                    CUnseal: begin
                      cto.capOp = Unseal;
                      reqA = 0; // Make sure offset is 0 in cap unit.
                      reqB = 0;
                      fa = capInst.r3; dfa = True;
                      fb = capInst.r2; dfb = True;
                      wb = capInst.r1; dwb = True;
                    end
                    Check: begin
                      case(ci.select)
                        0: cto.capOp = CheckPerms;
                        1: begin
                          cto.capOp = CheckType;
                          fa = capInst.r2; dfa = True;
                        end
                        default: cto <- unknownInstruction(cto);
                      endcase
                      fb = capInst.r1; dfb = True;
                    end
                    CCall: begin
                      // Select field is the bottom 11 bits of the instruction.
                      Bit#(11) select = {ci.r3,ci.spacer,ci.select};
                      case (select)
                        0:  begin
                          cto.exception = CAPCALL;
                          cto.capOp = Call;
                        end
                        42: begin
                          branchType = JumpReg;
                          cto.branch = Always;
                          cto.opBsrc = ControlToken;
                          cto.newPcSource = OpB;
                          cto.capOp = CallFast;
                          wb = 5'd26; dwb = True;
                        end
                        default: cto <- unknownInstruction(cto);
                      endcase
                      reqA = 0; // Make sure offset is 0 in cap unit.
                      reqB = 0;
                      cto.writeDest = None;
                      fa = capInst.r1; dfa = True;
                      fb = capInst.r2; dfb = True;
                    end
                    CReturn: begin
                      cto.capOp = Return;
                      cto.exception = CAPCALL;
                    end
                    CClear: begin
                      cto.alu = Nop;
                      cto.opAsrc = ControlToken;
                      case(ci.r1)
                        0,1: cto.writeRegMask = True;
                        2,3: cto.capOp = Clear;
                        default: cto <- unknownInstruction(cto);
                      endcase
                    end
                    CLLSC: begin
                      Bool load = (ci.spacer[0]==1'b1);
                      reqA = 0;
                      reqB = 0;
                      cto.writeDest = RegFile;
                      capInst.r0 = ci.r1;
                      capInst.r1 = ci.r2;
                      cto.alu = Cap;
                      cto.observesCP0 = True; // Loads and stores observe the TLB
                      case (ci.select[1:0])
                        0: cto.memSize = Byte;
                        1: cto.memSize = HalfWord;
                        2: cto.memSize = Word;
                        3: cto.memSize = (ci.select[2]==1'b1) ? CapWord:DoubleWord;
                      endcase
                      if (load) begin // Load Linked
                        cto.mem = Read;
                        cto.signExtendMem = (ci.select[2] == 1); // "signed" bit.
                        cto.test = LL;
                      end else begin // Store Conditional
                        cto.dest = pack(ci.r3);
                        cto.mem = Write;
                        cto.test = SC;
                        `ifdef MULTI
                          cto.pendingWrite = True;
                        `endif
                      end
                      if (cto.memSize != CapWord) begin
                        if (load) begin // Load Linked
                          cto.dest = pack(ci.r1);
                          cto.capOp = L;
                        end else begin
                          cto.capOp = S;
                          cto.opBsrc = ControlToken;
                          cto.storeDatasrc = RegFile;
                          reqB = ci.r1;
                        end
                      end else begin // Load Linked or Store Conditional of a capability!
                        if (load) begin // Load Linked
                          cto.writeDest = CoPro2;
                          cto.capOp = LC;
                          cto.test = LL;
                          wb = capInst.r0; dwb = True;
                        end else begin // Store Conditional
                          cto.capOp = SC;
                          cto.storeDatasrc = CoPro2;
                          `ifdef MULTI
                            cto.pendingWrite = True;
                          `endif
                          fb = capInst.r0; dfb = True;
                        end
                      end
                      fa = capInst.r1; dfa = True;
                    end
                    default: begin
                      cto <- unknownInstruction(cto);
                    end
                  endcase
                end
                LWC2: begin
                  reqA = ci.r2;
                  cto.opBsrc = ControlToken;
                  cto.opB = signExtend({ci.r3, ci.spacer});
                  cto.dest = pack(ci.cOp);
                  cto.writeDest = RegFile;
                  cto.mem = Read;
                  cto.observesCP0 = True; // Loads and stores observe the TLB
                  case (ci.select[1:0])
                    0: cto.memSize = Byte;
                    1: begin
                      cto.memSize = HalfWord;
                      cto.opB = cto.opB << 1;
                    end
                    2: begin
                      cto.memSize = Word;
                      cto.opB = cto.opB << 2;
                    end
                    3: begin
                      cto.memSize = DoubleWord;
                      cto.opB = cto.opB << 3;
                    end
                  endcase
                  cto.capOp = L;
                  cto.signExtendMem = (ci.select[2] == 1);
                  if (ci.select == 3'b111) begin // Linked operation
                    cto.test = LL;
                  end
                  cto.alu = Add;
                  fa = capInst.r1; dfa = True;
                end
                SWC2: begin
                  reqA = ci.r2;
                  reqB = pack(ci.cOp);
                  cto.opBsrc = ControlToken;
                  cto.storeDatasrc = RegFile;
                  cto.dest = pack(ci.cOp);
                  cto.mem = Write;
                  cto.observesCP0 = True; // Loads and stores observe the TLB
                  cto.opB = signExtend({ci.r3, ci.spacer});
                  if (ci.select == 3'b111) begin // Linked operation
                    cto.writeDest = RegFile;
                    cto.dest = pack(ci.cOp);
                  end else begin
                    cto.writeDest = None;
                  end
                  case (ci.select[1:0])
                    0: cto.memSize = Byte;
                    1: begin
                      cto.memSize = HalfWord;
                      cto.opB = cto.opB << 1;
                    end
                    2: begin
                      cto.memSize = Word;
                      cto.opB = cto.opB << 2;
                    end
                    3: begin
                      cto.memSize = DoubleWord;
                      cto.opB = cto.opB << 3;
                    end
                  endcase
                  cto.capOp = S;
                  if (ci.select[2] == 1'b1) cto.test = SC;
                  cto.alu = Add;
                  fa = capInst.r1; dfa = True;
                end
                LDC2: begin
                  reqA = ci.r2;
                  cto.opBsrc = ControlToken;
                  cto.writeDest = CoPro2;
                  cto.mem = Read;
                  cto.observesCP0 = True; // Loads and stores observe the TLB
                  cto.memSize = CapWord;
                  cto.capOp = LC;
                  cto.alu = Add;
                  cto.opB = signExtend({ci.r3, ci.spacer, ci.select, 4'b0});
                  fa = capInst.r1; dfa = True;
                  wb = capInst.r0; dwb = True;
                end
                SDC2: begin
                  reqA = ci.r2;
                  cto.opBsrc = ControlToken;
                  cto.storeDatasrc = CoPro2;
                  cto.writeDest = None;
                  cto.mem = Write;
                  cto.observesCP0 = True; // Loads and stores observe the TLB
                  cto.memSize = CapWord;
                  cto.capOp = SC;
                  cto.alu = Add;
                  cto.opB = signExtend({ci.r3, ci.spacer, ci.select, 4'b0});
                  fa = capInst.r1; dfa = True;
                  fb = capInst.r0; dfb = True;
                end
                default: begin
                  cto <- unknownInstruction(cto);
                end
              endcase
              capInst.op = cto.capOp;
              capInst.memSize = cto.memSize;
              capInst.fetchA = fa;
              capInst.doFetchA = dfa;
              capInst.fetchB = fb;
              capInst.doFetchB = dfb;
              capInst.dest = wb;
              capInst.doWriteDest = dwb;
            end
          `endif
          default:
            cto <- unknownInstruction(cto);
        endcase
        `ifdef COP1
          // Additional processing for floating point instructions.
          case(ci.op)
            // SPECIAL means a MOVCI instruction
            COP1, COP3, LWC1, LDC1, SWC1, SDC1, SPECIAL: begin
              CoProXOp  coProOp   = unpack(pack(ci.cOp));
              CoProFPOp coProFPOp = unpack(pack(ci.cOp));
              coProInst = CoProInst{
                op: coProOp,
                regNumA: ci.r2,
                regNumB: ci.r3,
                regNumDest: ci.r1,
                imm: {ci.spacer,ci.select},
                instId: cti.id,
                mipsOp: ci.op
              };
              debug($display("CoProInst: op:%x, regNumA:%x, regNumB:%x, regNumDest:%x, imm:%x, instId:%x",
              coProInst.op, coProInst.regNumA, coProInst.regNumB, coProInst.regNumDest, coProInst.imm, coProInst.instId));
              coProInst1 = coProInst;
              if (ci.op == COP1) begin
                case (coProFPOp)
                  DMFC, DMTC:
                    cto.sixtyFourBitOp = True;
                  MFC, MTC:
                    cto.sixtyFourBitOp = False;
                  CFC, CTC:
                    cto.sixtyFourBitOp = False;
                endcase

                case (coProFPOp)
                  MFC, DMFC, CFC: begin
                    cto.alu = Cop1;
                  end
                  MTC, DMTC, CTC: begin
                    cto.alu = Nop;
                  end
                  BC1: begin
                    let tmp = convert(coProInst);
                    cto.newPcSource = PCUpdate;
                    cto.pcUpdate = 8;
                  end
                endcase
                debug($display("In the COP1 %b, opA=%x", coProOp, cto.opA));
              end else if (ci.op == SPECIAL) begin // MOVCI
                Rtype ri = unpack(pack(ci));
                cto.alu = Cop1;
                cto.sixtyFourBitOp = True;
              end else begin // memory instruction
                Itype ii = unpack(pack(ci));
                CoProFPXOp fpxOp = unpack(pack(ci)[5:0]);
                cto.alu = Add;
                if (ci.op != COP3) begin
                  cto.opB = signExtend(ii.imm);
                end
                cto.sixtyFourBitOp = True;
                cto.signExtendMem = False;
              end
            end
          endcase
        `endif
      end
    endcase

    // Prepare for Branch Predictor Report ************************************
    // If this is a branch delay, make sure it does not branch.
    if (cto.branchDelay) begin
      // If this is a branch (in a branch delay slot), turn it into a nop!
      if (branchType!=None) begin
        cto.inst = tagged Register unpack(0);
      end
      branchType = None;
    end
    // Copy the branch type to the control token.
    cto.branchType = branchType;
    cto.link = link;

    //  If the control token is not from debug, set up for making the next
    //  instruction a branch delay.
    if (!cti.fromDebug) begin
      // Record branch status so we can make the next instruction a branch delay.
      lastWasBranch <= (branchType != None);
      // Remember the last epoch we saw so we will know if it changes.
      // This allows us to ignore branch delay behaviour at the seam between epochs.
      lastEpoch <= cti.epoch;
    end
    // Put a "pre-decode" report into the branch predictor so that it can
    // predict the next fetch.
    branch.putTarget(branchType, branchCertain, cti.pc, 
                     cto.inst, cti.epoch, cti.id, cti.fromDebug, link);
    // If this is a branch from the debug unit, just flush, no branch delay.
    if (branchType!=None && cto.fromDebug) begin
      cto.flushPipe = True;
    end
    // Make sure we write the PC if we are doing a branch. This is the default
    // for the common case but this is needed for instructions from the debug
    // unit.
    if (branchType != None) begin
      cto.writePC = True;
    end

    if (cto.mem == Read && cto.memSize != CapWord) cto.pendingWrite = True;
    
    // Cancel writes if they are to register 0.
    if (cto.writeDest == RegFile && cto.dest==0) cto.writeDest = None;

    WriteType wtype = None;
    if (cto.writeDest==RegFile) begin
      if (cto.pendingWrite) wtype = Pending;
      else if (conditionalUpdate) wtype = Conditional;
      else wtype = Simple;
    end
    debug($display("Requesting registers %d (A) and %d (B) in Scheduler for id %d", reqA, reqB, cto.id));
    theRF.reqRegs(ReadReq{
      a: reqA,
      b: reqB,
      write: wtype,
      dest: cto.dest,
      epoch: cti.epoch,
      fromDebug: cti.fromDebug,
      rawReq: False
    });
    // Submit a register fetch address (register number and shadow register
    // select) to coprocessor 0, the system control coprocessor. The result of
    // this fetch will be discarded for most instructions.
    cp0.readReq(reqC, reqSel);
    `ifdef STATCOUNTERS
    // enqueue the request to the statcounters module (default is Invalid)
    debug2("StatCounters", $display("<time %0t, Scheduler> put statcounters request: ", $time, fshow(statcounters_req)));
    statCounters.request.put(statcounters_req);
    `endif
    // Submit read requests to other coprocessors.
    cop1.putCoProInst(coProInst1);
    `ifdef USECAP
      if (!couldBeCapLoadOrStore) begin
        // Default value of capInst.fetchA is 0, and is relied upon here.
        // Choosing 0 in only this case is slow for decoding.
        if (cto.mem!=None)  capInst.memSize = cto.memSize;
        if (cto.mem==Read)  begin
          capInst.op = LegacyL;
          capInst.doFetchA = True;
        end
        if (cto.mem==Write) begin
          capInst.op = LegacyS;
          capInst.doFetchA = True;
        end
        if (cto.branch==Always && !cto.flushPipe) capInst.op = JumpRegister;
      end
      capCop.putCapInst(capInst);
    `endif
    debug($display("Instruction %X into Decode at time %t", cto.inst, $time()));
    // by the next stage in the pipeline.
    outQ.enq(cto);
  endmethod
  method ControlTokenT first = outQ.first;
  method deq = outQ.deq;
  method clear = noAction; // XXX This method should never be called.
endmodule
