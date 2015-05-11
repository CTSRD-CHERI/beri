/*-
 * Copyright (c) 2011-2012 SRI International
 * Copyright (c) 2013 Robert M. Norton
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
 * Authors: 
 *   Nirav Dave <ndave@csl.sri.com>
 * 
 ******************************************************************************
 *
 * Description: Execute Logic
 * 
 ******************************************************************************/

import Vector::*;
import FShow::*;

import Debug::*;
import MIPS::*;
import CHERITypes::*;

typedef struct{
  Bool      exePreventWrite; //MOVZ/MOVN may prevent writing to the registerFile
  Value     exeResult;
  Value     exeResult2;
  Exception exeException;
  Bool      branchCond;
} ExecutedResult deriving(Bits, Eq, FShow);

typedef struct{
  Bool      pcIsBranch;
  Bool      pcCalcNullifyNextInst; // likely branches may nullify delay slot
  Address   pcCalcNextNextPC;
  Value     pcResult;
} PCCalcResult deriving(Bits, Eq, FShow);


interface Execute;
  method ActionValue#(ExecutedResult) calcResult(ALUOperation op, Value vA, Value vB, Bit#(16) imm);
  method ActionValue#(PCCalcResult) calcPC(BranchOperation op, Bool branchCond, Value result, Value vA, Address pc, Bit#(26) offset);
endinterface	
		
(* synthesize, options="-aggressive-conditions" *)
module mkExecute(Execute);
  method calcResult = calcResultFN;
  method calcPC     = calcPCFN;
endmodule

function ActionValue#(ExecutedResult) calcResultFN(ALUOperation op, Value vA, Value vB, Bit#(16) imm);
  actionvalue
    Value result          = ?;
    Exception exception   = Ex_None;
    Bool  preventWrite    = False;

    // set up base values
    let extend = (op.op_signed) ? signExtend : zeroExtend;
    Bit#(128) eValA = (op.op_size32) ? extend(vA[31:0]): extend(vA);
    Bit#(128) eValB = (op.op_size32) ? extend(vB[31:0]): extend(vB);
    Value      valA = truncate(eValA);
    Value      valB = truncate(eValB);       
    
    //we use zeroExtended immediate if the operator is logical (AND/OR/XOR)

    function isLogicalOp(x) = (x == ALU_AND || x == ALU_OR || x== ALU_XOR || x == ALU_NOR);

    if (op.op_useImm)
       valB = isLogicalOp(op.op_alutype) ? zeroExtend(imm) : signExtend(imm);

    //ALU Computation ========================================================

    Bool isEQ = valA == valB;
    Bool isLT = (op.op_signed) ? signedLT(valA,valB) : (valA < valB);

    Bit#(6) shiftAmount = (op.op_size32) ? {1'b0, valA[4:0]} : valA[5:0];
    
    function Value size32(Value x) = (op.op_size32) ? signExtend(x[31:0]) : x;
      
    case (op.op_alutype)
      ALU_IdA: result = size32(valA);
      ALU_LT:  result = (isLT)         ? 1 : 0;
      ALU_EQ:  result = (isEQ)         ? 1 : 0;
      ALU_LE:  result = (isEQ || isLT) ? 1 : 0;
      // ndave: ShiftL and shiftR are split because barrel shiftings cheaper in FPGA. May be merged YYY
      ALU_ShiftL: result = size32(valB   << shiftAmount);
      ALU_ShiftR: result = size32((eValB >> shiftAmount)[63:0]); 
      ALU_MOVZ:
        begin
          preventWrite = (valB != 0);
          result = valA;
        end
      ALU_MOVN:
        begin
          preventWrite = (valB == 0);
          result = valA;
        end
      ALU_ADD: // overflow may happen if signed
        begin // ndave: may be shared with SUB, but dropped as arithmetic is fast on FPGA
          Bit#(65) resultAdd = {valA[63],valA} + {valB[63],valB};
          result = op.op_size32 ? signExtend(resultAdd[31:0]) : resultAdd[63:0];
          Bool overflow32 = (resultAdd[31] != resultAdd[32]);
          Bool overflow64 = (resultAdd[63] != resultAdd[64]);					
          Bool overflow   = (op.op_signed && ((op.op_size32) ? overflow32 : overflow64));
          if (overflow)
            begin
              debug($display("ADD: OVERFLOW! 0x%h + 0x%h = 0x%h", valA, valB, result));
              exception = Ex_Overflow;
            end
        end
      ALU_SUB: // overflow may happen if signed
        begin
          Bit#(65) resultSub =  {valA[63],valA} - {valB[63], valB};
          result = op.op_size32 ? signExtend(resultSub[31:0]) : resultSub[63:0];
          Bool overflow32 = (resultSub[31]) != (resultSub[32]);
          Bool overflow64 = resultSub[63] != resultSub[64];
          Bool overflow   = (op.op_signed && ((op.op_size32) ? overflow32 : overflow64));
          if (overflow)
            begin
              debug($display("SUB: OVERFLOW! 0x%h - 0x%h = 0x%h", valA, valB, result));
              exception = Ex_Overflow;
            end
        end
      ALU_AND: result = valA & valB;
      ALU_OR:  result = valA | valB;   
      ALU_XOR: result = valA ^ valB;
      ALU_NOR: result = ~(valA | valB);           
    endcase

    Bool hasTrap = (result[0] != 0) ? op.op_TrapOnNonZero: op.op_TrapOnZero;
    Exception trapException = (hasTrap) ? Ex_Trap : Ex_None;
    exception = joinException(exception, trapException);      
    
    // Separate calculation of bCond removes false critical path because it does not have to pass through shift
    let bCond = case (op.op_alutype) 
                  ALU_LT: return isLT;
                  ALU_LE: return isLT || isEQ;
                  ALU_EQ: return isEQ;
                  default: return ?;
                endcase;
    
    debug2("exec", action 
            $display("   ALU Inputs: %h %h (signed: %b) (op: ", valA, valB, op.op_signed, fshow(op.op_alutype),")");
            $display("   ALU Trap: [%b/%b/%b] = %b => ", result[0], op.op_TrapOnNonZero,  op.op_TrapOnZero, hasTrap, fshow(trapException));
            $display("   ALU Results (0x%h 0x%h", result, vB, fshow(exception) ,")");
          endaction);

    return ExecutedResult{
             exePreventWrite: preventWrite,
             exeResult:       result,
             exeResult2:      vB, //ndave: valB holds value for store ops
             exeException:    exception,
             branchCond:      bCond
      };

  endactionvalue
endfunction

function ActionValue#(PCCalcResult) calcPCFN(BranchOperation op, Bool branchCond, Value result, Value vA, Address pc, Bit#(26) offset);
  actionvalue
    //PC Computation ========================================================
    Address pc8 = pc + 8;

    Address pcCalc = case (op.op_brtype)
                       BR_PC8:    return pc8;
                       BR_OpA:    return vA; //no sizing needed
                       BR_Offset: return (pc + 4 + signExtend({offset[15:0], 2'b00}));
                       BR_Abs:    return ({truncateLSB(pc),offset,2'b00}); // drop bottom bits and replace with excess
                     endcase;

    Bool     branchTaken = (branchCond) ? op.op_BranchOnTrue : op.op_BranchOnFalse;
    Address   nextNextPC = (branchTaken) ? pcCalc : pc8;
    Bool nullifyNextInst = op.op_isLikely && !branchTaken;

    debug2("exec", action
            $display("PC CALC op:", fshow(op), " val: 0x%h pc: 0x%h, off: 0x%h", vA, pc, offset);
            $display("        (result/rest/bt/bf) = (%h/%d/%d/%d)", result, branchCond, op.op_BranchOnTrue, op.op_BranchOnFalse);
            $display("        pc8: %h pcCalc: %h (isLink %d)", pc8, pcCalc, op.op_isLink);
          endaction);

    return PCCalcResult{
      pcIsBranch:            op.op_brtype != BR_PC8,
      pcCalcNextNextPC:      nextNextPC,
      pcCalcNullifyNextInst: nullifyNextInst,
      pcResult:              op.op_isLink ? pc8 : result
    };

  endactionvalue
endfunction
