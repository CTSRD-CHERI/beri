/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert N. M. Watson
 * Copyright (c) 2013 Simon W. Moore
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

import GetPut::*;
import MIPS::*;
import MemTypes::*;
import ClientServer::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import CP0::*;

`ifdef COP1
  import CoProFPTypes::*;
  import CoProFPInst::*;
`endif

// This is the file for the mkDecode unit, though much of its logic is in functions
// here at the top.  This module fills in the flags in the control token (ControlTokenT
// type) given the instruction from the Scheduler stage to setup for a very simple
// operation in the Execute stage.

// The unknownInstruction function returns a control token appropriate for an 
// unrecognized instruction format.
function ActionValue#(ControlTokenT) unknownInstruction(ControlTokenT i);
  actionvalue
    ControlTokenT di = i;
    di.writeDest = None;
    di.mem       = None;
    // Unrecognized instruction format exception.
    di.exception = RI;
    return di;
  endactionvalue
endfunction

// The aluFuncFromMIPSFunc does what it says on the tin.
// It takes a MIPS function field from instructions with the SPECIAL opcode type
// and returns an internal ALU operation that should be performed for this instruction.
function AluOp aluFuncFromMIPSFunc(Func f);
  case(f)
    SLL,SLLV,DSLLV,DSLL,DSLL32: return SLL; // Shift left logical
    SRL,SRLV,DSRLV,DSRL,DSRL32: return SRL; // Shift right logical
    SRA,SRAV,DSRAV,DSRA,DSRA32: return SRA; // Shirt right arithmetic (preserve the sign)
    JR,JALR:                    return Nop; // Do nothing, just pass the parameters through
    MOVZ:                       return MOVZ;// Set the destination to OpB if OpA is zero.
    MOVN:                       return MOVN;// Set the destination to OpB if OpA is non-zero.
    ADD,ADDU,DADD,DADDU:        return Add; // Add
    SUB,SUBU,DSUB,DSUBU:        return Sub; // Subtract
    AND:                        return And; // And
    OR:                         return Or;  // Or
    XOR:                        return Xor; // Exclusive Or
    NOR:                        return Nor; // Inverted Or
    SLT:                        return SLT; // Set the destination register to 0x1 if OpA is less than OpB.
    SLTU:                       return SLTU;// Set the destination register to 0x1 if OpA is less than OpB, unsigned.
    MULT,DMULT,MULTU,DMULTU:    return Mul; // Multiply the operands, result in hi & lo
    DIV,DDIV,DIVU,DDIVU:        return Div; // Divide the operands, result in hi & lo
    MFHI:                       return FHi; // Put hi register into destination
    MFLO:                       return FLo; // Put lo register into destination
    MTHI:                       return THi; // Move operand to hi register
    MTLO:                       return TLo; // Move operand to lo register
    SYNC:                       return Nop; // Do nothing. (SYNC is a nop in this simple pipeline)
    default:                    return Add; // Add by default!
  endcase
endfunction

// The decodeSpecial2 function is for decoding the instructions with the SPECIAL2 opcode.
// These are more complex multiply operations.
function ActionValue#(ControlTokenT) decodeSpecial2(Rtype ri, ControlTokenT i, MIPSReg pc);
  actionvalue
    ControlTokenT di = i;
    di.mem = None;
    di.alu = ?;

    di.signedOp = True;
    di.sixtyFourBitOp = False;

    // This field is the more common Func type by default, but this case needs the Func2
    // interpretation of this field.
    Func2 func = unpack(pack(ri.f));
    case(func)
      // Multiply two numbers with the 64-bit result going directly into the destination register.
      // This is a special and more complex path in Execute, but isn't more complicated here.
      MUL: begin
        // Special multiply operation to put result directly into destination register.
        di.alu = MulI;
        return di;
      end
      // Multiply add, signed and unsigned variants.
      MADD, MADDU: begin
        if (func == MADDU) begin
          di.signedOp = False;
        end
        di.alu = Madd;
        return di;
      end
      // Multiply subtract, signed and unsigned variants.
      MSUB, MSUBU: begin
        if (func == MSUBU) begin
          di.signedOp = False;
        end
        di.alu = Msub;
        return di;
      end
      default: begin
        let rv <- unknownInstruction(i);
        return rv;
      end
    endcase
  endactionvalue
endfunction

// The decodeSpecial function is for decoding the instructions with the SPECIAL opcode.
// These include most common arithmetic instructions.
function ActionValue#(ControlTokenT) decodeSpecial(Rtype ri, ControlTokenT i, MIPSReg pc);
  actionvalue
    ControlTokenT di = i;
    di.mem = None;
    di.alu = aluFuncFromMIPSFunc(ri.f);

    // Just assign "signedOp" here instead of in the main case statement.
    case(ri.f)
      ADD, SUB, MULT, DIV, DADD, DSUB, DMULT, DDIV, TGE, TLT, SLT: begin
        di.signedOp = True;
      end
      default: begin
        di.signedOp = False;
      end
    endcase

    case(ri.f)
      SLL, SRL, SRA, SLLV, SRLV, SRAV, ADD, ADDU, SUB, SUBU, MULT, MULTU, DIV, DIVU, MFHI, MTHI, MFLO, MTLO:
      begin
        di.sixtyFourBitOp = False;

        case(ri.f)
          SLL, SRA, SRL: di.opB = zeroExtend(ri.sa);
          MFHI, MFLO: di.sixtyFourBitOp = True;
          MTHI, MTLO: di.sixtyFourBitOp = True;
        endcase
      end
      AND, OR, NOR, XOR, DSLLV, DSRLV, DSRAV, DADD, DADDU, SLT, SLTU, DSUB, DSUBU, DSLL, DSRL, DSRA, DSLL32, DSRL32, DSRA32, DMULT, DMULTU, DDIV, DDIVU:
      begin
        di.sixtyFourBitOp = True;

        case(ri.f)
          DSLL,   DSRL,   DSRA:   di.opB = zeroExtend(ri.sa);
          DSLL32, DSRL32, DSRA32: di.opB = zeroExtend(ri.sa) + 32;
        endcase
      end
      MOVZ, MOVN: begin
       di.sixtyFourBitOp = True;
      end
      JR: begin
        //di.newPcSource = OpB;
        //di.branch = Always;
      end
      JALR: begin
        di.opA = pc + 8;
        //di.newPcSource = OpB;
        //di.branch = Always;
      end
      // These test operations can throw an exception if their conditions are not met.
      TGE, TGEU, TLT, TLTU, TEQ, TNE: begin
        di.alu = Sub; // rs - rt
        di.sixtyFourBitOp = True;
        // "signedOp" is assigned above
        case(ri.f)
          TGE, TGEU: begin // is rs >= rt?
            di.test = GE;
          end
          TLT, TLTU: begin // is rs < rt?
            di.test = LT;
          end
          TEQ: begin
            di.test = EQ;
          end
          TNE: begin
            di.test = NE;
          end
        endcase
      end
      SYSCALL: begin
        di.exception = Syscall;
      end
      BREAK: begin
        di.exception = Bp;
      end
      SYNC: begin
        //di.writeDest = None;
        //di.flushPipe = True;
      end
      default: begin
        di <- unknownInstruction(i);
      end
    endcase
    return di;
  endactionvalue
endfunction


// The mkDecode module implements the Decode stage of the MIPS pipeline.
// mkDecode exports a FIFO interface of the pipeline ControlTokenT type
// but needs to import interfaces to many other entities in the pipeline.
module mkDecode#(CP0Ifc cp0)(PipeStageIfc);

  // This is the fifo of control tokens
  FIFO#(ControlTokenT) outQ <- mkFIFO;

  function ActionValue#(ControlTokenT) decodeInstruction(ControlTokenT i, MIPSReg rc,MIPSReg pc);
    actionvalue
      ControlTokenT di = i;
      
      MIPSReg rs = 0;
      MIPSReg rt = 0;
      
      CoProEn cpEn = cp0.getCoprocessorEnables();

      case(i.inst) matches
        tagged Immediate .ii: begin
          case(ii.op)
            REGIMM: begin
              di = i;
            end
            BEQ, BNE, BLEZ, BGTZ, BEQL, BNEL, BLEZL, BGTZL: begin
              //di.newPcSource = PCUpdate;
              //case(ii.op)
              //  BEQ, BEQL: di.branch=EQ;
              //  BNE, BNEL: di.branch=NE;
              //  BLEZ, BLEZL: di.branch=LEZ;
              //  BGTZ, BGTZL: di.branch=GTZ;
              //endcase
              //di.pcUpdate = 8; // The branch delay will not write it's PC, so we add 8 by default.
            end
            DADDI, DADDIU, ADDI, ADDIU, SLTI, SLTIU, ANDI, ORI, XORI, LUI: begin
              case(ii.op)
                DADDI, DADDIU, ORI, ANDI, XORI, SLTI, SLTIU: begin
                  di.sixtyFourBitOp = True;
                end
                default: begin
                  di.sixtyFourBitOp = False;
                end
              endcase

              case(ii.op)
                ADDI, DADDI: begin
                  di.signedOp = True;
                  di.alu = Add;
                end
                ADDIU, DADDIU:
                  di.alu = Add;
                SLTI: begin
                  di.signedOp = True;
                  di.alu = SLT;
                end
                SLTIU: begin
                  di.alu = SLTU;
                end
                ANDI: begin
                  di.alu = And;
                end
                ORI: begin
                  di.alu = Or;
                end
                XORI: begin
                  di.alu = Xor;
                end
                LUI: begin
                  di.alu = Add;
                end
              endcase

              case(ii.op)
                ANDI, ORI, XORI: begin
                  di.opB = zeroExtend(ii.imm);
                end
                LUI: begin
                  di.opB = zeroExtend({ii.imm, 16'b0});
                end
                default: begin
                  di.opB = signExtend(ii.imm);
                end
              endcase
            end
            LB, LH, LW, LWL, LWR, LL, SB, SH, SW, SWL, SWR, LD, LDL, LDR, LLD, SD, SDL, SDR, LBU, LHU, LWU: begin
              di.alu = Add;
              di.opB = signExtend(ii.imm);
              di.sixtyFourBitOp = True;
              di.signExtendMem = True;

              case(ii.op)
                LBU, LHU, LWU:
                  di.signExtendMem = False;
                LL, LLD:
                  di.test = LL;
              endcase
            end
            SC, SCD: begin
              di.alu = Add;
              di.opB = signExtend(ii.imm);
              di.sixtyFourBitOp = True;
              di.test = SC;
            end
            CACHE: begin
              Bool privileged = cpEn.cu0 || i.fromDebug;
              if (privileged) begin
                di.alu = Add;
                di.opB = signExtend(ii.imm);
                di.sixtyFourBitOp = True;
                di.cop.inst = (case (ii.rt[4:2]) // Which cache operation?
                        0: return CacheInvalidateWriteback; // Invalidate index in the cache.
                        1: return CacheNop;        // Load tag is unsupported
                        2: return CacheNop;        // Store tag is unsupported
                        3: return CacheNop;        // Not defined.
                        4: return CacheInvalidate; // Invalidate on a match.  We just invalidate anyway.
                        5: return CacheInvalidateWriteback; // Writeback and invalidate.
                        6: return CacheWriteback;        // Just writeback.
                        7: return CacheNop;        // Fetch and Lock.  Not implemented.
                    endcase);
                di.cop.indexed = (case (ii.rt[4:2]) // Is address index or virtual address?
                        0: return True;        // Invalidate index in the cache.
                        1: return True;        // Load tag is unsupported
                        2: return True;        // Store tag is unsupported
                        3: return True;        // Not defined.
                        4: return False;       // Invalidate on a match.  We just invalidate anyway.
                        5: return False;       // Writeback and invalidate.
                        6: return False;       // Just writeback.
                        7: return False;       // Fetch and Lock.  Not implemented.
                    endcase);
                case (ii.rt[1:0]) // Which cache?
                  0: begin
                    di.cop.cache = ICache;
                    di.mem = ICacheOp;
                  end
                  1: begin
                    di.cop.cache = DCache;
                    di.mem = DCacheOp;
                  end
                  2: begin
                    di.cop.cache = None; // Instruction L2 if there is one.  There isn't.
                  end
                  3: begin
                    di.cop.cache = L2;
                    di.mem = DCacheOp;
                  end
                endcase
              end else begin
                if (di.exception == None) di.exception = CP0;
              end
            end
            default:
              di <- unknownInstruction(i);
          endcase
        end
        tagged Jump .ji: begin
          case(ji.op)
            J, JAL: begin
              //di.branch = DoneTaken;
              //di.newPcSource = Immediate;
            end
          endcase
        end
        tagged Register .ri: begin
          Bool privileged = cpEn.cu0 || i.fromDebug;
          HWREna hwrena = cp0.getHardwareRegisterEnables();
          case(ri.op)
            SPECIAL:
              di <- decodeSpecial(ri, i, pc);
            SPECIAL2:
              di <- decodeSpecial2(ri, i, pc);
            SPECIAL3: begin
              Func3 func3 = unpack(pack(ri.f));
              case (func3)
                RDHWR: begin
                  di.mem = None;
                  case (ri.rd)
                    0: begin
                      if (!hwrena.cpunum && !privileged) di.exception = RI;
                      di.opA = rc & 64'hFFFF;
                      di.alu = Nop;
                    end
                    //1: synci_step not implemented yet.
                    2: begin
                      if (!hwrena.cc && !privileged) di.exception = RI;
                      di.sixtyFourBitOp = True;
                      di.opA = rc;
                      di.alu = Nop;
                    end
                    3: begin
                      if (!hwrena.ccres && !privileged) di.exception = RI;
                      di.opA = 1;
                      di.alu = Nop;
                    end
                    29: begin
                      if (!hwrena.tls && !privileged) di.exception = RI;
                      di.sixtyFourBitOp = True;
                      di.opA = rc;
                      di.alu = Nop;
                    end
                    30: begin
                      if (!hwrena.cpunum && !privileged) di.exception = RI;
                      di.opA = (rc>>16) & 64'hFFFF;
                      di.alu = Nop;
                    end
                    default: if (di.exception == None) di.exception = RI;
                  endcase
                end
              endcase
            end
            COP0: begin // Move from or to coprocessor.  Just pass on the value read from the coprocessor.
              CoProOp mf = unpack(ri.rs);
              di.mem = None;
              di.opB = zeroExtend(pack(ri.f)[2:0]);
              if (cpEn.cu0 || i.fromDebug) begin
                case (mf)
                  DMFC, DMTC:
                    di.sixtyFourBitOp = True;
                  MFC, MTC:
                    di.sixtyFourBitOp = False;
                endcase

                case (mf)
                  MFC, DMFC: begin
                    di.opA = rc;
                    di.alu = Nop;
                  end
                  MTC, DMTC: begin
                    di.alu = Nop;
                  end
                  INST: begin
                    di.opA = {58'b0,pack(ri.f)};
                    di.alu = Nop;
                    CP0Inst tlbInst = unpack(pack(ri.f)[5:0]);
                    case (tlbInst)
                      ERET: begin // request the PC for an exception return.
                        di.opB = rc; // Write the value pulled from copro0 (the victim pc) to the PC.
                      end
                    endcase
                  end
                  default: begin
                    if (di.exception == None) di.exception = RI;
                  end
                endcase
                debug($display("In the COP0 %b, opA=%x", mf, di.opA));
              end else begin
                if (di.exception == None) di.exception = CP0;
              end
            end
          endcase
        end
        tagged Coprocessor .ci: begin
          case(ci.op)
             `ifdef COP1
               // SPECIAL means a MOVCI instruction
               COP1, COP3, LWC1, LDC1, SWC1, SDC1, SPECIAL: begin
                 if (!cpEn.cu1 && di.exception==None) di.exception = CP1;
               end
            `else
              COP3: begin // Move from or to coprocessor.  Just pass on the value read from the coprocessor.
                Bool coProAvailable = (cpEn.cu1 && ci.op==COP1) || (cpEn.cu3 && ci.op==COP3);
                if (!coProAvailable && di.exception==None) di.exception = CP3;
              end
            `endif
            `ifdef CAP
              COP2,LWC2,LDC2,SWC2,SDC2: begin
                if (!cpEn.cu2 && !i.fromDebug && di.exception==None) di.exception = CP2;
                // The capability unit will return 1 or 0, depending on whether
                // we should take the branch, so we tell the execute and
                // writeback stages just to branch on that result.
                // We're going to treat this as a branch instruction in the
                // execute stage, so set the tags to indicate that it has an
                // immediate field that we can use.
                if (ci.op == COP2 && (ci.cOp == CBTS || ci.cOp == CBTU))
                  di.inst = tagged Immediate unpack(pack(ci));
              end
            `endif
          endcase  
        end
      endcase
      return di;
    endactionvalue
  endfunction

  method Action enq(ControlTokenT ct);
    // zero the operands to ensure the optimiser knows they are not used.
    //ct.opA = 0;
    //ct.opB = 0;
    ct.storeData = tagged DoubleWord 0;
    MIPSReg pc = ct.pc;
    MIPSReg rc <- cp0.readGet(ct.writeDest==CoPro0); // Coprocessor Register Read
    if (ct.opAsrc == CoPro0) ct.opA = rc;
    if (ct.opBsrc == CoPro0) ct.opB = rc;
    debug($display("======   PRE-DECODE INSTRUCTION   ======"));
    debug(displayControlToken(ct));

    let di <- decodeInstruction(ct, rc, pc);

    if (ct.branchDelay) di.writePC = False;
    outQ.enq(di);
  endmethod

  method first = outQ.first;
  method deq   = outQ.deq;
  method clear = outQ.clear;

endmodule
