/*-
 * Copyright (c) 2013 Ben Thorner
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Ben Thorner as part of his summer internship
 * and Colin Rothwell as part of his final year undergraduate project.
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
import CoProFPTypes::*;
import CoProFPInst::*;
import CoProFPRegState::*;
import MIPS::*;

import Vector::*;
import FloatingPoint::*;

typedef Vector#(32, RegState) RegStates;

function CoProFPInst getCoProFPInst(CoProInst coProInst);
    // We know that if the whole instruction is 0, then it's a NOP: essentially
    // we just re-interpret the main pipeline's NOP. This is a hack, but seems
    // to be the best way of working with the current interface.
    // A large amount of the actual decoding happens in the conversions in
    // CoProFPInst.bsv.
    // Pretty much all of this logic is a total mess, because the token we get
    // is essentially a half decoded capability coprocessor instruction.
    // From the original MIPS instruction:
    // [31:26] = mipsOp
    // [25:21] = op
    // [20:16] = regNumDest
    // [15:11] = regNumA 
    // [10:6]  = regNumB
    // [5:0]   = imm
    CoProFPInst inst;
    // fmt is the name of the field in the MIPS manual
    UInt#(5) fmt = unpack(pack(coProInst.op));
    case (coProInst.mipsOp)
        COP1: 
            // Movement instruction of some sort.
            // 3 and 7 are move to/from high, which we don't support.
            if (fmt <= 7 && fmt != 3 && fmt != 7)
                inst = tagged RI convert(coProInst);
            else if (fmt == 8) // Branch
                inst = tagged B convert(coProInst);
            else if (fmt == 16 || fmt == 17 || fmt == 20 || fmt == 21 || fmt == 22)
                inst = tagged R convert(coProInst);
            else //if ((fmt >= 9 && fmt <= 15) || fmt == 18 || fmt == 19 || fmt >= 23)
                inst = tagged InvalidInstruction;
        COP3: begin
            CoProFPXOp func = unpack(coProInst.imm);
            case (func)
                LWXC1, SWXC1, LDXC1, SDXC1:
                    inst = tagged MEM convert(coProInst);
                default:
                    inst = tagged InvalidInstruction;
            endcase
        end
        LWC1, LDC1, SWC1, SDC1:
            inst = tagged MEM convert(coProInst);
        SPECIAL:
            if (coProInst.op == None && coProInst.regNumDest == 0 &&
                    coProInst.regNumA == 0 && coProInst.regNumB == 0 &&
                    coProInst.imm == 0)
                inst = tagged Nop;
            else if (coProInst.imm == 1) // MOVCI func code
                inst = tagged B convert(coProInst);
            else
                inst = tagged InvalidInstruction;
        default:
            inst = tagged InvalidInstruction;
    endcase
    return inst;
endfunction

function FCC updateFCC(FCC fcc, Bit#(3) cc, Format fmt, MIPSReg res);
    fcc[cc] = res[0] > 0;
    if (fmt == PS)
        fcc[cc + 1] = res[1] > 0;
    return fcc;
endfunction

function Bit#(3) extractCC(FPRType r);
    return r.fd[4:2];
endfunction

function Action debugROperands(FPRType r, RegStates regStates);
    $display("First reg is %d = %b, Second reg is %d = %b.", r.fs,
    regStates[r.fs].isFree(), r.ft, regStates[r.ft].isFree());
endfunction

function Bool rOperandsAvailable(FPRType r, RegStates regStates, Bool fcsrFree);
    let accessAllowed = regStates[r.fs].isFree();
    case (getOperator(r.func, r.fmt)) matches
        tagged Valid .op:
            case (op)
                Compare, Add, Div, Mul, Sub:
                    accessAllowed = accessAllowed && regStates[r.ft].isFree();
            endcase
        tagged Invalid:
            case (r.func)
                CVTPS, PLL, PLU, PUL, PUU:
                    accessAllowed = accessAllowed && regStates[r.ft].isFree();
                MOVC, MOVZ, MOVN: begin
                    accessAllowed = accessAllowed && regStates[r.fd].isFree();
                    if (r.func == MOVC)
                        accessAllowed = accessAllowed && fcsrFree;
                end
            endcase
    endcase
    return accessAllowed;
endfunction

function Action debugRiOperands(FPRIType ri, RegStates rs, Bool fcsr);
    case (ri.sub)
        MFC, DMFC: $display("[D]MFC: %d = %b", ri.fs, rs[ri.fs].isFree());
        CFC: $display("CFC %d. FCSR: %b", ri.fs, fcsr);
    endcase
endfunction

function Bool riOperandsAvailable(FPRIType ri, RegStates regStates,
                                  Bool fcsrFree);
    case (ri.sub)
        MFC, DMFC: return regStates[ri.fs].isFree();
        CFC: return ri.fs == 0 || fcsrFree; 
        //fs 0 is the FIR, everthing else is FCSR
        default: return True;
    endcase
endfunction

function Bool memOperandsAvailable(FPMemInstruction mem, 
                                   RegStates regStates);
    case (mem.op)
        Store: return regStates[mem.storeReg].isFree();
        default: return True;
    endcase
endfunction

function Bool operandsAvailable(CoProFPInst inst, 
                                RegStates regStates, Bool fcsrFree);
    case (inst) matches
        tagged R .r: return rOperandsAvailable(r, regStates, fcsrFree);
        tagged RI .ri: return riOperandsAvailable(ri, regStates, fcsrFree);
        tagged MEM .mem: return memOperandsAvailable(mem, regStates);
        tagged B .b: return fcsrFree;
        default: return True; // Invalid Instructions etc. need no operands.
    endcase
endfunction

function Bool isCompareFunc(FPFunc func);
    return pack(func)[5:4] == 'b11;
endfunction

function Maybe#(Operator) getOperator(FPFunc func, Format fmt);
    Bool valid = True;
    Operator op = Add; // Defined default
    if (isCompareFunc(func))
        op = Compare;
    else
        case (func)
            ABS: op = Abs;
            ADD: op = Add;
            DIV: op = Div;
            MUL: op = Mul;
            NEG: op = Neg;
            SQRT: op = Sqrt;
            SUB: op = Sub;
            RECIP: op = Recip;
            RSQRT: op = RecipSqrt;
            CVTD: op = ToDouble;
            CVTS: 
                if (fmt == PS) // This is cvt.s.pu, which we don't want
                    valid = False; // execute unit to handle.
                else
                    op = ToFloat;
            CVTW, CEILW, FLOORW, ROUNDW, TRUNCW: op = ToWord;
            CVTL, CEILL, FLOORL, ROUNDL, TRUNCL: op = ToLong;
            default: valid = False;
        endcase

    if (valid)
        return tagged Valid op;
    else
        return tagged Invalid;
endfunction

function RoundMode getRoundMode(FPFunc func, RoundMode default_mode);
    return case (func)
        CEILW, CEILL: Rnd_Plus_Inf;
        FLOORW, FLOORL: Rnd_Minus_Inf;
        ROUNDW, ROUNDL: Rnd_Nearest_Even;
        TRUNCW, TRUNCL: Rnd_Zero;
        default: default_mode;
    endcase;
endfunction

typedef enum { Monadic, Diadic, Comparison } OperatorType deriving (Eq);

function OperatorType getOperatorType(Operator op);
    case (op)
        Abs, Neg, Sqrt, Recip, RecipSqrt, ToDouble, ToFloat, ToWord, ToLong:
            return Monadic;
        Add, Div, Mul, Sub:
            return Diadic;
        Compare:
            return Comparison;
    endcase
endfunction

function ExecuteArgs comparisonArgs(Format fmt, FPFunc func, MIPSReg left, MIPSReg right);
    let args = ComparisonArgs { fmt: fmt, left: left, right: right, cond: pack(func)[3:0] };
    return tagged Compare args;
endfunction

function ExecuteArgs executeRequestArgs(FPRType r, Operator op, Format fmt,
        RoundMode rnd, MIPSReg fs, MIPSReg ft);

    case (getOperatorType(op)) 
        Monadic: case (fmt)
            S: return tagged MonadFloat tuple2(unpack(truncate(fs)), rnd);
            D: return tagged MonadDouble tuple2(unpack(fs), rnd);
            PS: return tagged MonadPairedSingle tuple2(toPairedSingle(fs), rnd);
            W: return tagged MonadWord unpack(truncate(fs));
            L: return tagged MonadLong unpack(fs);
        endcase
        Diadic: case(fmt) 
            S: begin
                let left = unpack(truncate(fs));
                let right = unpack(truncate(ft));
                return tagged DiadFloat tuple3(left, right, rnd);
            end
            D: return tagged DiadDouble tuple3(unpack(fs), unpack(ft), rnd);
            PS: begin
                let left = toPairedSingle(fs);
                let right = toPairedSingle(ft);
                return tagged DiadPairedSingle tuple3(left, right, rnd);
            end
        endcase
        Comparison: return comparisonArgs(fmt, r.func, fs, ft);
    endcase
endfunction

function PairedSingle toPairedSingle(MIPSReg raw);
    return tuple2(unpack(raw[63:32]), unpack(raw[31:0]));
endfunction

function Maybe#(ExecuteRequest) getExecuteRequest(FPRType r, MIPSReg fs, MIPSReg
                                                  ft, Bool flushToZero);
    case (getOperator(r.func, r.fmt)) matches
        tagged Valid .op: begin
            let rm = getRoundMode(r.func, Rnd_Nearest_Even);
            return tagged Valid ExecuteRequest { 
                op: op, 
                args: executeRequestArgs(r, op, r.fmt, rm, fs, ft),
                flushToZero: flushToZero
            };
        end
        tagged Invalid: return Invalid;
    endcase
endfunction

function Maybe#(ExecuteRequest) fpuExecuteRequest(CoProFPInst inst, MIPSReg opS,
                                                  MIPSReg opT, Bool flushToZero);
    case (inst) matches
        tagged R .r: return getExecuteRequest(r, opS, opT, flushToZero);
        default: return tagged Invalid;
    endcase
endfunction

function Maybe#(RegNum) blockedRegister(CoProFPToken tok);
    case (tok.resultAction)
        ExecuteFromMain, ExecuteMOVZ, ExecuteMOVN, GetFromExecuteUnit,
        WritebackFromMain, SimpleWriteback:
            return tagged Valid tok.targetReg;
        default:
            return tagged Invalid;
    endcase
endfunction

function Bool blockedFCSR(CoProFPToken tok);
    case (tok.resultAction)
        ControlFromMain, GetExecuteCompare, GetExecuteComparePS:
            return True;
        default:
            return False;
    endcase
endfunction

function CoProFPToken tokenForExecutedRType(FPRType r, Operator op);
    let tok = unpack(0);
    tok.targetReg = r.fd;
    if (op == Compare) begin
        if (r.fmt == PS)
            tok.resultAction = GetExecuteComparePS;
        else
            tok.resultAction = GetExecuteCompare;
        tok.targetReg = 25;
        tok.result = zeroExtend(extractCC(r));
    end
    else begin
        tok.resultAction = GetFromExecuteUnit;
    end
    return tok;
endfunction

function FPRMCType fprmcFromR(FPRType r);
    // I know this is ugly, but the whole decode stage needs going over.
    return FPRMCType {
        fmt: r.fmt,
        cc: r.ft[4:2],
        tf: unpack(r.ft[0]),
        fs: r.fs,
        fd: r.fd,
        func: r.func
    };
endfunction

function MIPSReg executeConditionalMove(CoProFPToken tok, FPRMCType inst,
                                        FCSR fcsr, MIPSReg opS, MIPSReg opD);
    MIPSReg answer;
    Bool cc = fcsr.fcc[inst.cc];
    Bool ccp1 = fcsr.fcc[inst.cc+1];
    answer = (cc == inst.tf) ? opS : opD;
    if (inst.fmt == PS)
        answer[63:32] = (ccp1 == inst.tf) ? opS[63:32] : opD[63:32];
    return answer;
endfunction

// This is pretty ugly, because the inherited decoder pretended a bunch of
// formats were R types when they actually weren't, and it just about works.
function CoProFPToken tokenForSimpleRType(FPRType r, FCSR fcsr, MIPSReg opS, 
                                          MIPSReg opT, MIPSReg opD);
    let tok = unpack(0);
    tok.targetReg = r.fd;
    tok.resultAction = case (r.func)
                          MOVZ: ExecuteMOVZ;
                          MOVN: ExecuteMOVN;
                          default: SimpleWriteback;
                      endcase;
    case (r.func)
        CVTPS: tok.result = {opS[31:0], opT[31:0]};
        CVTPL: tok.result = {32'b0, opS[31:0]};
        CVTS: tok.result = {32'b0, opS[63:32]}; //cvts is opcode for cvt.s.pu.
        // We don't need to check format, because other formats are handled by
        // execution unit.
        MOV: tok.result = opS;
        PLL: tok.result = {opS[31:0], opT[31:0]};
        PLU: tok.result = {opS[31:0], opT[63:32]};
        PUL: tok.result = {opS[63:32], opT[31:0]};
        PUU: tok.result = {opS[63:32], opT[63:32]};                            
        MOVC: begin
            let inst = fprmcFromR(r);
            tok.result = executeConditionalMove(tok, inst, fcsr, opS, opD);
        end
        MOVZ, MOVN: begin
            tok.result = opS;
            tok.otherOp = opD;
        end
    endcase
    return tok;
endfunction

function CoProFPToken tokenForRIType(FPRIType ri, MIPSReg opS, MIPSReg controlS);
    let tok = unpack(0);
    tok.targetReg = ri.fs;
    case (ri.sub) 
        // Move control register uses the control reg file.
        MTC, DMTC: tok.resultAction = ExecuteFromMain;
        CTC: tok.resultAction = ControlFromMain;
        MFC, DMFC: begin
            tok.resultAction = RespondToGet;
            tok.result = opS;
        end
        CFC: begin
            tok.resultAction = RespondToGet;
            tok.result = controlS;
        end
    endcase
    return tok;
endfunction

function CoProFPToken tokenForMemInstruction(FPMemInstruction mem, MIPSReg opS,
                                             MIPSReg opT);
    let tok = unpack(0);
    case (mem.op)
        Load: begin
            tok.resultAction = WritebackFromMain;
            tok.targetReg = mem.loadTarget;
        end
        Store: begin
            tok.resultAction = RespondToGet;
            case (mem.storeSource)
                FS: tok.result = opS;
                FT: tok.result = opT;
            endcase
        end
    endcase
    return tok;
endfunction

function CoProFPToken tokenForBType(FPBType b, FCSR fcsr);
    let tok = unpack(0);
    if (fcsr.fcc[b.cc] == b.tf)
        tok.resultAction = RespondToGet;
    else
        tok.resultAction = None;
    return tok;
endfunction

function CoProFPToken tokenForInvalidInstruction(FCSR fcsr);
    CoProFPToken tok = ?;
    tok.fcsr = fcsr;
    tok.resultAction = InvalidInstruction;
    return tok;
endfunction

function CoProFPToken tokenForNop(FCSR fcsr);
    CoProFPToken tok = ?;
    tok.fcsr = fcsr;
    tok.resultAction = None;
    return tok;
endfunction

function CoProFPToken getFPUToken(CoProFPInst inst, FCSR fcsr, MIPSReg opS, 
                                  MIPSReg opT, MIPSReg opD, MIPSReg controlS);
    case (inst) matches
        tagged R .r: begin
            case (getOperator(r.func, r.fmt)) matches
                tagged Valid .op: return tokenForExecutedRType(r, op);
                tagged Invalid: return tokenForSimpleRType(r, fcsr, opS, opT, opD);
            endcase
        end
        tagged RI .ri: return tokenForRIType(ri, opS, controlS);
        tagged MEM .mem: return tokenForMemInstruction(mem, opS, opT);
        tagged B .b: return tokenForBType(b, fcsr);
        tagged InvalidInstruction: return tokenForInvalidInstruction(fcsr);
        tagged Nop: return tokenForNop(fcsr);
    endcase
endfunction
