/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
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

import MIPS::*;
import GetPut::*;
import Decode::*;
import MemAccess::*;
import ForwardingPipelinedRegFile::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import ClientServer::*;
import CP0::*;
import RegFile::*;
import ConfigReg::*;

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
`endif


//Need to allow shift amounts greater than 1 - bit width of the thing we're shifting
//However if remove the proviso off arithmeticShift2 to allow this the Bluespec compiler
//enters an infinite loop, so we have arithmeticShift to check if the shiftAmount is
//great than 1 - bit width, if so it just fills the result with 1 or 0 as appropriate
//otherwise it hands it to arithmeticShift2 with an appropriately truncated shiftAmount.
function Bit#(a) arithmeticShift(Bit#(a) toShift, Bit#(b) shiftAmount)
  provisos(Log#(a, c));

  Bit#(a) result;

  if(shiftAmount >= fromInteger(valueOf(a))) begin
    Integer i;
    for(i = 0;i < valueOf(a);i = i + 1)
      result[i] = toShift[valueOf(a) - 1];
  end else begin
    result = arithmeticShift2(toShift, shiftAmount[valueOf(c) - 1 : 0]);
  end

  return result;
endfunction

function Bit#(a) arithmeticShift2(Bit#(a) toShift, Bit#(b) shiftAmount)
  provisos(Log#(a, b));

  Bit#(a) result = toShift >> shiftAmount;

  Integer i;
  for(i = 0;fromInteger(i) < shiftAmount;i = i + 1)
    result[valueOf(a) - 1 - i] = toShift[valueOf(a) - 1];

  return result;
endfunction

typedef enum {Init, Run} ExecuteState deriving (Bits, Eq);

module mkExecute#(
  MIPSRegFileIfc rf,
  WritebackIfc writeback,
  CP0Ifc cp0,
  CoProIfc cop1,
  `ifdef USECAP
    CapCopIfc capCop,
  `endif
  FIFO#(ControlTokenT) inQ
)(PipeStageIfc);
  FIFO#(ControlTokenT)        outQ <- mkLFIFO;
  MulDivIfc                    mul <- mkMulDiv;
  Reg#(MIPSReg)                 hi <- mkReg(64'b0);
  Reg#(MIPSReg)                 lo <- mkReg(64'b0);
  FIFOF#(Bool)         hiLoPending <- mkFIFOF1;
  FIFOF#(ControlTokenT) pendingOps <- mkFIFOF1;
  Reg#(Bit#(16))            coreid <- mkConfigReg(0);

  Maybe#(MIPSReg) stub = tagged Invalid;

  Bool hiOrLoIsBlocking =
    (case(inQ.first.alu)
      FHi,FLo,Madd,Msub: return True;
      default: return False;
    endcase) && hiLoPending.notEmpty;

  //(* descending_urgency = "finishMultiplyOrDivide, doExecute" *)
  (* mutually_exclusive = "finishMultiplyOrDivide, deliverPendingOp" *)
  rule finishMultiplyOrDivide;
    Tuple2#(Maybe#(Word),Maybe#(Word)) tpl <- mul.muldiv.response.get();
    Bool commit = writeback.getHiLoCommit.first();
    writeback.getHiLoCommit.deq();
    if (commit) begin
      if (isValid(tpl_1(tpl))) begin
        hi <= fromMaybe(?,tpl_1(tpl));
        `ifdef MULTI
          trace($display("Time:%0d, Core:%0d, Thread:0 :: Hi <- %x", $time, coreid, fromMaybe(?,tpl_1(tpl))));
        `else
          trace($display("Hi <- %x", fromMaybe(?,tpl_1(tpl))));
        `endif
      end
      if (isValid(tpl_2(tpl))) begin
        lo <= fromMaybe(?,tpl_2(tpl));
        `ifdef MULTI
          trace($display("Time:%0d, Core:%0d, Thread:0 :: Lo <- %x", $time, coreid, fromMaybe(?,tpl_2(tpl))));
        `else
          trace($display("Lo <- %x", fromMaybe(?,tpl_2(tpl))));
        `endif
      end
    end
    hiLoPending.deq();
  endrule
  rule deliverPendingOp;
    ControlTokenT di = pendingOps.first;
    pendingOps.deq();
    ControlTokenT er = di;
    Tuple2#(Maybe#(Word),Maybe#(Word)) tpl <- mul.muldiv.response.get();
    hiLoPending.deq();
    if (er.alu == MulI) begin
      er.opA = fromMaybe(?,tpl_2(tpl));
      rf.writeRegSpeculative(er.opA, True);
    end
    debug($display("Pending Operation Out... (probably a 3 operand Multiply)"));
    outQ.enq(er);
  endrule

  method Action enq(ControlTokenT di) if (!hiOrLoIsBlocking && !pendingOps.notEmpty);
    ControlTokenT er = di;

    `ifdef MULTI
      coreid <= er.coreID;
    `endif

    ReadRegs#(MIPSReg) regFileRead <- rf.readRegs();
    Bit#(65) opA = zeroExtend(di.opA);
    if (di.opAsrc == RegFile) opA[63:0] = zeroExtend(regFileRead.regA);
    // sign extend the operand if it's a signed operation.
    opA[64] = (di.signedOp) ? opA[63]:1'b0;
    Bit#(65) opB = zeroExtend(di.opB);
    if (di.opBsrc == RegFile) opB[63:0] = zeroExtend(regFileRead.regB);
    // sign extend the operand if it's a signed operation.
    opB[64] = (di.signedOp) ? opB[63]:1'b0;

    if (di.storeDatasrc == RegFile) er.storeData = tagged DoubleWord regFileRead.regB;

    // ======================================

    er.opA = opA[63:0];
    er.opB = opB[63:0];
    Bit#(65) calcResult = ?;

    debug($display("======   PRE-EXECUTE INSTRUCTION   ======"));
    debug(displayControlToken(er));

    Bool cap = False;
    `ifdef USECAP
      CapReq capReq = CapReq{
        offset: unpack(er.opA),
        pc: di.pc,
        size: di.memSize,
        memOp: di.mem
      };
      if (di.inst matches tagged Coprocessor .ci) begin
        if (ci.op == COP2) cap = True;
      end
      CoProResponse capVal = CoProResponse{
                                    valid: True, 
                                    data: ?, 
                                    storeData: ?, 
                                    exception: None
                                  };
    `endif
    CoProResponse cr1 <- cop1.getCoProResponse(CoProVals{opA: er.opA, opB: er.opB});
    `ifdef COP1
    if (cr1.valid && er.exception == None)
        er.exception = cr1.exception;
    `endif

    // Calculate the architectural PC from the absolute virtual address
    // PC that we generally use. We will need this if we link or
    // write the PC into any architecturally visible register.
    er.archPc = er.pc;
    `ifdef USECAP
      er.archPc = capCop.getArchPc(er.pc, er.epoch);
    `endif
    if (di.mem != None) begin
      case(di.alu)
        Add: begin
          calcResult = opA + opB;
          `ifdef USECAP
            capReq.offset = unpack(calcResult[63:0]);
            capVal <- capCop.getCapResponse(capReq);
          `endif
        end
        `ifdef USECAP
          Cap: begin
            capReq.offset = unpack(er.opB);
            capVal <- capCop.getCapResponse(capReq);
            calcResult = signExtend(capVal.data);
          end
        `endif
        default: begin
          `ifdef USECAP
            capReq.offset = unpack(er.opB);
            capVal <- capCop.getCapResponse(capReq);
          `endif
          calcResult = opA;
        end
      endcase

      `ifdef USECAP
        er.opA = capVal.data;
        if (capVal.valid) begin
          if (er.exception == None || capVal.exception == ICAP) begin
            er.exception = capVal.exception;
          end
        end
      `else
        er.opA = calcResult[63:0];
      `endif
      Bool scResult = True;
      if (di.exception == None) begin
        scResult <- cp0.setLlScReg(er.opA[63:0], er.test == LL, di.mem == Write);
      end
      if (di.mem == Write) begin
        if (di.storeDatasrc == CoPro1 && cr1.valid) begin
          er.storeData = tagged DoubleWord cr1.data;
        end
        `ifdef USECAP
          else if (di.storeDatasrc == CoPro2) begin
            er.storeData = capVal.storeData;
          end
        `endif
        if (er.test == SC) begin
          er.opB = zeroExtend(pack(scResult));
          debug($display("Store Conditional! Result = %x, id=%d", scResult, er.id));
        end
      end
      rf.writeRegSpeculative(er.opB, er.writeDest == RegFile);
      outQ.enq(er);
    end else if (di.branch != Never) begin
      Bit#(65) signedA = signExtend(opA[63:0]);
      Bit#(65) signedB = signExtend(opB[63:0]);
      Int#(65) intA = unpack(signedA);
      Int#(65) intB = unpack(signedB);

      `ifdef USECAP
        capReq.offset = unpack(er.opB);
        capVal <- capCop.getCapResponse(capReq);
        if (capVal.valid) begin
          if (er.exception == None 
              || (er.exception == CAPCALL &&  capVal.exception != None)
              || capVal.exception == ICAP) begin
            er.exception = capVal.exception;
          end
        end
        er.opB = capVal.data;
      `endif

      //Address jumpTarget = 64'b0;
      case (di.inst) matches
        tagged Immediate .ii: begin
          //debug($display("signedA in branch test: %x, di.branch:%x", intA, di.branch));
          if(case(er.branch)
              EQ: return (opA == opB);
              NE: return (opA != opB);
              LEZ: return (intA <= 0);
              LTZ: return (intA < 0);
              GTZ: return (intA > 0);
              GEZ: return (intA >= 0);
              `ifdef USECAP
                CapTag: return (capVal.data == 1);
              `endif
            endcase) begin
            er.pcUpdate = signExtend(unpack({ii.imm, 2'b0})) + 4;
            er.branch = DoneTaken;
          end else begin
            er.pcUpdate = 8; // The next instruction is already in the pipe...
            er.branch = DoneNotTaken;
            if (di.branchLikely) begin
              er.flushPipe = True;
            end
          end
        end
        tagged Jump .ji: begin
          // This value is computed in writeback.
          //jumpTarget = {er.archPc[63:28], ji.imm, 2'b0} + (er.pc - er.archPc);
          //trace($display("Jumped to %x? %x, pc:%x, archPc:%x", jumpTarget, 
          //  {er.archPc[63:28], ji.imm, 2'b0}, er.pc, er.archPc));
        end
        `ifdef COP1
          tagged Coprocessor .ci:
            if((ci.op == COP1) && (unpack(pack(ci.cOp)) == BC1)) begin
              FPBType tmp = convert(CoProInst{
                  op: unpack(pack(ci.cOp)),
                  regNumA: ci.r2,
                  regNumB: ci.r3,
                  regNumDest: ci.r1,
                  imm: {ci.spacer,ci.select},
                  instId: di.id
              });
              if (cr1.valid) begin
                debug($display("Coprocessor says to branch."));
                er.pcUpdate = signExtend(unpack({tmp.offset, 2'b0})) + 4;
                er.branch = DoneTaken;
              end else begin
                debug($display("Coprocessor says to not branch."));
                er.pcUpdate = 8;
                er.branch = DoneNotTaken;
                if (di.branchLikely) begin
                  er.flushPipe = tmp.nd;
                end
              end
            end
        `endif
        `ifdef USECAP
          tagged Coprocessor .ci: begin
            //if (ci.cOp == CCall)
            er.opB = capVal.data;
          end
        `endif
      endcase

      if (er.link || er.writeDest == RegFile) begin
        er.opA = er.archPc + 8;
      end
      rf.writeRegSpeculative(er.opA, er.writeDest == RegFile);
      outQ.enq(er);
    end else begin // Not a memory op or a branch.
      Bit#(65) signedA = signExtend(opA[63:0]);
      Bit#(65) signedB = signExtend(opB[63:0]);
      Int#(65) intA = unpack(signedA);
      Int#(65) intB = unpack(signedB);
      `ifdef USECAP
        capVal <- capCop.getCapResponse(capReq);
        if (capVal.valid) begin
          if (er.exception == None 
              || (er.exception == CAPCALL &&  capVal.exception != None)
              || capVal.exception == ICAP) begin
            er.exception = capVal.exception;
          end
        end
      `endif
      case(di.alu)
        Add, Sub :begin
          if (di.alu == Sub) opB = ~opB + 1; // 2s complement
          calcResult = opA + opB;
          // Test overflow as defined by MIPS spec, that the MSB and the carry out are different.
          if (er.signedOp) begin
            if (di.sixtyFourBitOp) begin
              if (calcResult[64] != calcResult[63] && er.exception == None) er.exception=Ov;
            end else begin
              if (calcResult[32] != calcResult[31] && er.exception == None) er.exception=Ov;
              // Preserve the carry-out bit since the 32-bit result will be sign extended.
              calcResult[64] = calcResult[32];
            end
          end
        end
        Or, Nor: begin
          calcResult = opA | opB;
          if (di.alu == Nor) begin
            calcResult = ~calcResult;
          end
        end
        Xor: begin
          calcResult = opA ^ opB;
        end
        And: begin
          calcResult = opA & opB;
        end
        SLT: begin
          calcResult = (intA < intB) ? 1 : 0;
        end
        SLTU:
          calcResult = (opA < opB) ? 1 : 0;
        SLL: begin
          calcResult = signExtend(opA[63:0] << opB[4:0]);
          // If it's a 64bit operation, shift by the last bit. If not, sign extend the top bits.
          if(di.sixtyFourBitOp) begin
            if (opB[5]==1'b1) calcResult = calcResult << 32;
          end else begin
            calcResult = signExtend(calcResult[31:0]);
          end
        end
        SRL: begin
          if(!di.sixtyFourBitOp) opA=zeroExtend(opA[31:0]);
          calcResult = zeroExtend(opA[63:0] >> opB[4:0]);
          if(di.sixtyFourBitOp) begin
            if (opB[5]==1'b1) calcResult = calcResult >> 32;
          end
        end
        SRA: begin
          if(di.sixtyFourBitOp) calcResult = signExtend(arithmeticShift2(opA[63:0], opB[5:0]));
          else begin
            calcResult[31:0] = arithmeticShift2(opA[31:0], opB[4:0]);
          end
        end
        Cop1: begin
          if (di.inst matches tagged Coprocessor .ci &&& ci.op == SPECIAL) begin
            if (cr1.valid) begin //Do move
              calcResult = opA;
            end else begin
              //calcResult = opB;
              er.writeDest = None;
            end
          end else begin
            if (cr1.valid) begin
              calcResult = signExtend(cr1.data);
            end else begin
              er.writeDest = None;
            end
            if (er.exception == None) begin
              er.exception = cr1.exception;
            end
          end
        end
        FHi: begin
          calcResult = signExtend(hi);
        end
        FLo: begin
          calcResult = signExtend(lo);
        end
        Mul, Div, MulI, Madd, Msub, THi, TLo: begin
          MulDivRequestT mdr = ?;
          er.opA = opA[63:0];
          er.opB = opB[63:0];
          mul.muldiv.request.put(
            MulDivRequestT{
              alu: er.alu,
              signedOp: er.signedOp,
              sixtyFourBitOp: er.sixtyFourBitOp,
              opA: er.opA,
              opB: er.opB,
              hi: hi,
              lo: lo
            });
          hiLoPending.enq(True);
          calcResult = opA;
          er.signedOp = False;
        end
        MOVZ, MOVN: begin
          Bool test = (opB == 0);
          if (di.alu == MOVN) test = !test;
          if (test) begin
            calcResult = opA;
          end else begin
            er.writeDest = None;
          end
        end
        `ifdef USECAP
          Cap: begin
            calcResult = signExtend(capVal.data);
          end
        `endif
        Nop:
          calcResult = opA;
        default:
          if (er.link) begin
            calcResult = zeroExtend(er.pc + 8);
          end
      endcase

      if(!er.sixtyFourBitOp) begin
        calcResult[63:0] = signExtend(calcResult[31:0]);
      end

      er.opA = calcResult[63:0];
      er.carryout = calcResult[64];

      if (er.alu == MulI) begin
        pendingOps.enq(er);
      end else begin
        outQ.enq(er);
        rf.writeRegSpeculative(er.opA, er.writeDest == RegFile);
      end
    end // Not a memory op.
  endmethod
  method ControlTokenT first = outQ.first;
  method Action deq = outQ.deq;
endmodule

/*
  Multiply & Divide Pipeline ==============================================================
*/

typedef struct {
  Bool     sixtyFourBitOp;
  Bool     signedOp;
  AluOp    alu;
  Bit#(64) opA;
  Bit#(64) opB;
  MIPSReg  lo;
  MIPSReg  hi;
} MulDivRequestT deriving (Bits);

typedef enum { Idle, Mul1, Mul2, Div1, Div2 } MulDivState deriving (Bits, Eq);

typedef struct {
  Vector#(2, Vector#(2, Bit#(64))) vals;
  Bool aNeg;
  Bool bNeg;
} MultiplyIntermediatT deriving (Bits);

typedef struct {
  Word      divisor;
  Bit#(128) dividend;
  Word      quotient;
  Bit#(8)   count;
  Bool      aNeg;
  Bool      bNeg;
} DivideIntermediateT deriving (Bits, Eq, Bounded);

interface MulDivIfc;
   interface Server#(MulDivRequestT,Tuple2#(Maybe#(Word),Maybe#(Word))) muldiv;
endinterface

(* synthesize *)
module mkMulDiv(MulDivIfc);
  Reg#(MulDivState)              state <- mkReg(Idle);
  Reg#(MultiplyIntermediatT) mulIntReg <- mkRegU;
  FIFO#(MulDivRequestT)   request_fifo <- mkFIFO1;

  FIFO#(Maybe#(Word))          lo_fifo <- mkFIFO;
  FIFO#(Maybe#(Word))          hi_fifo <- mkFIFO;
  // Divisor
  Reg#(DivideIntermediateT)     divint <- mkReg(unpack(266'b0));

  rule mulPipe1(state == Mul1);
    // Pre multiply in preparation for execute stage.
    MultiplyIntermediatT mulInt = mulIntReg;

    for (Integer i = 0; i < 2; i=i+1) begin
      mulInt.vals[i][0] = zeroExtend(mulIntReg.vals[1][i][31:0]) * zeroExtend(mulIntReg.vals[0][0][31:0]);
      mulInt.vals[i][1] = zeroExtend(mulIntReg.vals[1][i][31:0]) * zeroExtend(mulIntReg.vals[0][1][31:0]);
    end

    for (Integer i = 0; i < 2; i=i+1)
      debug($write("\n Multiply Debug 1: aNeg: %d, bNeg: %d,",
                   "b%d  %x %x %x %x ---------------------\n",
                   mulInt.aNeg, mulInt.bNeg, i, mulInt.vals[i][1],
                   mulInt.vals[i][0]));

    state <= Mul2;
    mulIntReg <= mulInt;
  endrule

  rule mulPipe2(state == Mul2);
    MultiplyIntermediatT mulInt = mulIntReg;
    MulDivRequestT  mdr = request_fifo.first;
    MIPSReg oldLo = mdr.lo;
    MIPSReg oldHi = mdr.hi;
    request_fifo.deq;

    Bit#(128) addends [3];
    Bit#(128) product;

    addends[0] = {mulInt.vals[1][1],mulInt.vals[0][0]};
    addends[1] = (zeroExtend(mulInt.vals[0][1]) +
                  zeroExtend(mulInt.vals[1][0])) << 32;
    product = addends[0] + addends[1];
    if ((mulInt.aNeg != mulInt.bNeg) && mdr.signedOp) product = ~product + 1;

    if (!mdr.sixtyFourBitOp) begin
      if (mdr.alu == Madd) begin
        product = signExtend({oldHi[31:0],oldLo[31:0]}+product[63:0]);
      end else if (mdr.alu == Msub) begin
        product = signExtend({oldHi[31:0],oldLo[31:0]}-product[63:0]);
      end
      Bit#(64) newLo = signExtend(product[31:0]);
      Bit#(64) newHi = signExtend(product[63:32]);
      product = {newHi,newLo};
    end

    debug($write("\n Multiply Debug 4: aNeg= %d bNeg= %d addend 1=%x",
                 "addend 2=%x  product=%x ---------------------\n",
                 mulInt.aNeg, mulInt.bNeg, addends[0], addends[1], product));
    state <= Idle;
    lo_fifo.enq(tagged Valid unpack(product[63:0]));
    hi_fifo.enq(tagged Valid unpack(product[127:64]));
  endrule

  rule doDivide(state == Div1);
    DivideIntermediateT mydiv = divint;
    mydiv.count = mydiv.count - 1;
    mydiv.dividend = mydiv.dividend << 1;
    mydiv.quotient = mydiv.quotient << 1;

    // If the next 8 bits of the dividend are 0, skip ahead by 8.
    if (mydiv.dividend[127:56] == 72'h0 && mydiv.count > 9) begin
      mydiv.count = mydiv.count - 8;
      mydiv.dividend = mydiv.dividend << 8;
      mydiv.quotient = mydiv.quotient << 8;
    end

    if (request_fifo.first.signedOp) begin
      Word difference = mydiv.dividend[127:64]-mydiv.divisor;
      if (difference[63] == 0) begin
        mydiv.quotient[0] = 1;
        mydiv.dividend[127:64] = difference;
      end
    end else begin
      UInt#(64) uDividend = unpack(mydiv.dividend[127:64]);
      UInt#(64) uDivisor = unpack(mydiv.divisor);
      if (uDividend >= uDivisor) begin
        mydiv.quotient[0] = 1;
        mydiv.dividend[127:64] = pack(uDividend-uDivisor);
      end
    end

    debug($write("\n Divide Debug loop: count:%d quotient:%x dividend=%x divisor=%x ---------------------\n", mydiv.count, mydiv.quotient, mydiv.dividend, mydiv.divisor));

    divint <= mydiv;
    if (mydiv.count == 0) state <= Div2;
  endrule

  rule finishDivide(state == Div2);
    MulDivRequestT mdr = request_fifo.first;
    request_fifo.deq;
    DivideIntermediateT mydiv = divint;
    Word remainder = unpack(mydiv.dividend[127:64]);
    if ((mydiv.aNeg != mydiv.bNeg) && mdr.signedOp) begin
      mydiv.quotient = ~mydiv.quotient + 1;
    end
    if (mydiv.bNeg && mdr.signedOp) begin
      remainder = ~remainder + 1;
    end
    if (!mdr.sixtyFourBitOp) begin
      mydiv.quotient[63:0] = signExtend(mydiv.quotient[31:0]);
      remainder[63:0] = signExtend(remainder[31:0]);
    end
    lo_fifo.enq(tagged Valid unpack(mydiv.quotient));
    hi_fifo.enq(tagged Valid remainder); // This is the remainder.
    state <= Idle;
    debug($write("\n Divide Done: quotient(lo):%x remainder(hi):%x ---------------------\n", mydiv.quotient, remainder));
  endrule

  interface Server muldiv;
    interface Put request;
      method Action put(mdr) if (state == Idle); // input decoded instruction
        Bit#(64) a = pack(mdr.opA);
        Bit#(64) b = pack(mdr.opB);

        debug($write("\n A:%x B:%x Coming in.\n", a, b));

        if (!mdr.sixtyFourBitOp) begin
          if (mdr.signedOp) begin
            a = signExtend(a[31:0]);
            b = signExtend(b[31:0]);
          end else begin
            a = zeroExtend(a[31:0]);
            b = zeroExtend(b[31:0]);
          end
        end
        debug($write("\n A:%x  B:%x After fixing width.\n", a, b));

        Bool aNeg = False;
        Bool bNeg = False;
        // If it is a signed multiply, get the magnitude of the operands.
        if (mdr.signedOp) begin
          aNeg = a[63]==1'b1;
          bNeg = b[63]==1'b1;
          // Store signs of operands to determine the sign of the result.
          if (a[63] == 1) a = ~(a - 1);
          if (b[63] == 1) b = ~(b - 1);
        end
        debug($write("\n A:%x  B:%x After fixing sign.\n", a, b));

        case (mdr.alu)
          Mul, MulI, Madd, Msub: begin // If this is a Multiply...
                    // Pre multiply in preparation for execute stage.
            MultiplyIntermediatT mulInt = ?;
            mulInt.aNeg = aNeg;
            mulInt.bNeg = bNeg;

            mulInt.vals[0][0] = zeroExtend(a[31:0]);
            mulInt.vals[0][1] = zeroExtend(a[63:32]);
            mulInt.vals[1][0] = zeroExtend(b[31:0]);
            mulInt.vals[1][1] = zeroExtend(b[63:32]);

            mulIntReg <= mulInt;
            state <= Mul1;
            request_fifo.enq(mdr);
          end
          Div: begin      // If this is a divide...
            Bit#(64) divisor = pack(a);
            Bit#(64) dividend = pack(b);
            if (divisor==0) begin
              dividend=0;
              aNeg = False;
              bNeg = False;
            end

            DivideIntermediateT divJob = ?;
            divJob.count = 64;

            debug($write("\n Divide Debug 1: %x/%x ---------------------\n", dividend, divisor));
            divJob.divisor = divisor;
            divJob.dividend = {64'h0000000000000000,dividend};
            divJob.quotient = 0;
            divJob.aNeg = aNeg;
            divJob.bNeg = bNeg;

            divint <= divJob;
            request_fifo.enq(mdr);
            state <= Div1;
          end
          THi: begin
            lo_fifo.enq(tagged Invalid);
            hi_fifo.enq(tagged Valid a);
          end
          TLo: begin
            lo_fifo.enq(tagged Valid a);
            hi_fifo.enq(tagged Invalid);
          end
        endcase
      endmethod
    endinterface

    interface Get response; // return Hi & Lo registers.
      method ActionValue#(Tuple2#(Maybe#(Word),Maybe#(Word))) get();
        debug($write("\n MulDiv Out! ---------------------\n"));
        let lo = lo_fifo.first; lo_fifo.deq;
        let hi = hi_fifo.first; hi_fifo.deq;
        return(tuple2(hi, lo));
      endmethod
    endinterface
  endinterface
endmodule
