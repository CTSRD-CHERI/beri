/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
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
 * Description: Multiplier / Divider Units
 * 
 ******************************************************************************/


import FIFO::*;
import FShow::*;

import MIPS::*;
import CHERITypes::*;
import Library::*;
import Debug::*;

interface Multiply;
 method Action req(MulOperation req, Value vA, Value vB, Value hi, Value lo);
 method ActionValue#(Tuple2#(Value, Value)) resp();
endinterface

//----------------------------------------------------------------------------
//| Multiplier Unit - 3 Stages
//----------------------------------------------------------------------------


(* synthesize, options="-aggressive-conditions" *)
module mkMultiply(Multiply);
  
  `ifndef VERIFY
  FIFO#(Tuple6#(MulOperation, Bool, Value, Value, Value, Value)) inQ <- mkFIFO(); //in: op, neg?, vA, vB, hi, lo
  FIFO#(Tuple5#(MulOperation, Bool, Bit#(128), Value, Value))   mulQ <- mkFIFO(); //post mult: op, neg?, val, hi, lo
  FIFO#(Tuple2#(MulOperation, Bit#(128)))                       outQ <- mkFIFO(); //after possible addition
  `else 
  FIFO#(Tuple6#(MulOperation, Bool, Value, Value, Value, Value)) inQ <- mkSizedFIFO(1); //in: op, neg?, vA, vB, hi, lo
  FIFO#(Tuple5#(MulOperation, Bool, Bit#(128), Value, Value))   mulQ <- mkSizedFIFO(1); //post mult: op, neg?, val, hi, lo
  FIFO#(Tuple2#(MulOperation, Bit#(128)))                       outQ <- mkSizedFIFO(1); //after possible addition
  `endif
 
  rule doMul;
    match {.req, .negateResult, .vA, .vB, .hi, .lo} = inQ.first();
    inQ.deq();
    
    //The following code attempts to break the multiply into 32-bit
    //pieces for efficient synthesis using 32-bit multiply DSP
    //blocks. However, at least in Quartus 12.1, it triggers a bug
    //which crashes the synthesis tools. In any case the 64x64
    //multiply appears to be inferred fine and hopefully will result
    //in something sensible.
    //
    //let uA = unpack(vA[63:32]); let lA = unpack(vA[31: 0]);
    //let uB = unpack(vB[63:32]); let lB = unpack(vB[31: 0]);
    //
    //Value uu = pack(unsignedMul(uA,uB)); Value ul = pack(unsignedMul(uA,lB));
    //Value lu = pack(unsignedMul(lA,uB)); Value ll = pack(unsignedMul(lA,lB));
    //
    //Value uu = pack(unsignedMul(uA,uB)); Value ul = pack(unsignedMul(uA,lB));
    //Value lu = pack(unsignedMul(lA,uB)); Value ll = pack(unsignedMul(lA,lB));
    //
    //    
    //zeroExtend({uu,64'd0}) + zeroExtend({ul,32'd0}) 
    //                    + zeroExtend({lu,32'd0}) + zeroExtend({ll});    
    //debug($display("DEBUG: ", fshow(req.mul_op) ," (", fshow(negateResult), 
    //  ", 0x%h, 0x%h) = \n  (0x%h, 0x%h, 0x%h, 0x%h, 0x%h)", vA, vB,uu,ul,lu,ll, mulResult));  
    

    `ifdef VERIFY
    //pad out to make input and output sizes match
    UInt#(128) uvA = unpack({64'b0,vA});
    UInt#(128) uvB = unpack({64'b0,vB});								
    Bit#(128) mulResult = pack(uvA * uvB);
    `else
    Bit#(128) mulResult = pack(unsignedMul(unpack(vA), unpack(vB)));
    `endif

   
    mulQ.enq(tuple5(req, negateResult, mulResult, hi, lo));
  endrule
 
  rule doAddSub;
    match {.req, .negateResult, .mulResultBase, .hi, .lo} = mulQ.first();
    mulQ.deq();

    let mulResult = toSigned(negateResult, mulResultBase);
    
    // Extract the appropriate part of hi and lo to use as the accumulator.
    // No need to sign extend in 32-bit case because those bits will be discarded.
    let hilo   = req.mul_size32 ? zeroExtend({hi[31:0],lo[31:0]}) : {hi,lo};
    
    let result = case (req.mul_op) matches
                   MUL:  return mulResult;
                   MADD: return hilo + mulResult;
                   MSUB: return hilo - mulResult;
                 endcase;

    debug($display("DEBUG: MUL2 (0x%h <= %h/%h/%h)", result, hi, lo, mulResult));  

    outQ.enq(tuple2(req, result));
  endrule
 
  method Action req(MulOperation r, Value valA, Value valB, Value hi, Value lo);
    function extend(x) = (r.mul_signed) ? signExtend(x):zeroExtend(x);
    Value valAc   = (r.mul_size32) ? extend(valA[31:0]): valA;
    Value valBc   = (r.mul_size32) ? extend(valB[31:0]): valB;

    match {.signA, .vA} = fromSigned(r.mul_signed, valAc);
    match {.signB, .vB} = fromSigned(r.mul_signed, valBc);

    inQ.enq(tuple6(r, signA != signB, vA, vB, hi, lo));  
  endmethod

  method ActionValue#(Tuple2#(Value, Value)) resp();
    match {.req, .result} = outQ.first();
    outQ.deq();
  
    if (req.mul_size32) 
      return(tuple2(signExtend(result[63:32]), signExtend(result[31: 0])));
    else
      return(tuple2(result[127:64], result[ 63: 0]));  
  endmethod 
 
endmodule 

//----------------------------------------------------------------------------
//| Divider Unit
//----------------------------------------------------------------------------

interface Divider;
 method Action req(DivOperation req, Value vA, Value vB);
 method ActionValue#(Tuple2#(Value, Value)) resp();
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkDivider(Divider);

  //count, dividend, quotient update each cycle

  Reg#(Bit#(8))      count <- mkReg(0);
  
  Reg#(Bit#(128)) dividend <- mkRegU;
  Reg#(Value)     quotient <- mkRegU;
  
  `ifndef VERIFY
  FIFO#(Tuple5#(DivOperation, Bool, Value, Bool, Value)) inQ <- mkFIFO(); //operation, negate result, dividend, divisor
  FIFO#(Tuple2#(Value, Value))                          outQ <- mkFIFO(); //rem, quot
  `else
  FIFO#(Tuple5#(DivOperation, Bool, Value, Bool, Value)) inQ <- mkSizedFIFO(1); //operation, negate result, dividend, divisor
  FIFO#(Tuple2#(Value, Value))                          outQ <- mkSizedFIFO(1); //rem, quot
  `endif

  
  match {.divOp, .negateA, .initDividend, .negateB, .theDivisor} = inQ.first();
    
  rule doDivide; //use of values from inQ will prevent this from firing prematurely
    
    //start with quot as 0, div as {64'0, div} divisor as divisor
    // if (div >divisor) quot ++ and div -= divisor
    // div << 1, quot << 1;

    // getInput
    let theDividend = (count == 0) ? zeroExtend(initDividend) : dividend;
    let theQuotient = (count == 0) ? 0                        : quotient;
    let theCount    = (count == 0) ? 64                       : count - 1;
    
    // do compute  
        
    let    zeroDividend = theDividend << 1;
    let     oneDividend = zeroDividend - {theDivisor,64'b0};
    Bool         setBit = zeroDividend  >= {theDivisor,64'b0};  
    Value   newQuotient = truncate({theQuotient, (setBit) ? 1'b1: 1'b0});
    let     newDividend = (setBit) ? oneDividend : zeroDividend;

    debug($display("DEBUG: DIV %d (%h,%h,%h) => (%h, %h %h) set: %b", count, dividend, quotient, theDivisor, 
                                                                          newDividend, newQuotient, theDivisor, setBit));
      
    // Finish Division and send result to outQ   
    count <= theCount;
    
    if(theCount == 0) // final computation
      begin
        //Bool negateB = msb(theDivisor) == 1;
        Value quot64 = toSigned(divOp.div_signed && (negateA!=negateB), quotient);
        // if divisor is negative, so is remainder
        Value  rem64 = toSigned(divOp.div_signed && negateA, dividend[127:64]); 
        outQ.enq((divOp.div_size32) ? tuple2(signExtend(rem64[31:0]), signExtend(quot64[31:0]))
                                    : tuple2(rem64, quot64));
        inQ.deq(); 
        debug($display("DEBUG: DIV complete "));        
      end
    else
      begin
        quotient <= newQuotient;
        dividend <= newDividend;
      end
        
  endrule    
    
  method Action req(DivOperation r, Value valA, Value valB);

    function extend(x) = (r.div_signed) ? signExtend(x):zeroExtend(x);
    Value valAc   = (r.div_size32) ? extend(valA[31:0]): valA;
    Value valBc   = (r.div_size32) ? extend(valB[31:0]): valB;
    
    match {.signA, .vA} = fromSigned(r.div_signed, valAc);
    match {.signB, .vB} = fromSigned(r.div_signed, valBc);
    inQ.enq(tuple5(r, signA, vA, signB, vB));  
    debug($display("DEBUG: DIV new Request: ", fshow(r), ",", fshow(signA), ",", fshow(vA), ",", fshow(signA), ",", fshow(vB)));
  endmethod
  
  method ActionValue#(Tuple2#(Value, Value)) resp();
    match {.vr, .vq} = outQ.first();        
    outQ.deq();
    debug($display("DEBUG: DIV new Response %h %h", vq, vr));  
    return(tuple2(vr, vq));
  endmethod 
  
endmodule
