/*-
 * Copyright (c) 2014 Bluespec
 * Copyright (c) 2015 Hongyan Xia
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

import Real          ::*;
import Vector        ::*;
import BUtils        ::*;
import DefaultValue    ::*;
import FShow         ::*;
import GetPut        ::*;
import ClientServer    ::*;
import FIFO          ::*;
import Divide        ::*;
import SquareRoot      ::*;
import FixedPoint      ::*;
import FloatingPoint    ::*;

function Integer minexp(FloatingPoint#(e,m) f) = (1-bias(f));
function Integer maxexp(FloatingPoint#(e,m) f) = bias(f);
function Bool  isNormal(FloatingPoint#(e,m) f) = !isSubNormal(f) && !isNaNOrInfinity(f);
function Bool isNaNOrInfinity(FloatingPoint#(e,m) f) = (f.exp == '1);
function Bit#(1) getHiddenBit(FloatingPoint#(e,m) f) = (isSubNormal(f)) ? 0 : 1;
function Integer bias(FloatingPoint#(e,m) f) = (2 ** (valueof(e)-1) - 1);
function Bit#(e) unbias(FloatingPoint#(e,m) f) = (f.exp - fromInteger(bias(f)));

function Tuple2#(Bit#(n),Bool) jround( Bit#(n) din, Bit#(x) sfdin)
   provisos(
    // per request of bsc
     Add#(n, a__, x)
    );
    
	
	let zeros = countZerosMSB(sfdin);
  Bit#(2) guard = sfdin[valueOf(x)-valueOf(n)-1:valueOf(x)-valueOf(n)-2];
  Bit#(2) guard2 = sfdin[valueOf(x)-valueOf(n)-2:valueOf(x)-valueOf(n)-3];
	Bit#(n) carrymantissa = truncateLSB(sfdin);
	Bit#(n) mantissa = truncateLSB(sfdin<<1);
	Bit#(n) result = ?;
	Bool carry = ?;
	
	if( zeros == 0 ) begin
		carry = True;
		case (guard)
			'b00: result = carrymantissa;
			'b01: result = carrymantissa;
			'b10: result = (lsb(carrymantissa)== 1)? carrymantissa+1 : carrymantissa;
			'b11: result = carrymantissa + 1;
		endcase
	end
	else begin
		carry = False;
		case (guard2)
			'b00: result = mantissa;
			'b01: result = mantissa;
			'b10: begin
				result = (lsb(mantissa)== 1)? mantissa+1 : mantissa ;
				if(result==0) carry=True;
			end
			'b11: begin
				result = mantissa + 1;
				if(result==0) carry=True;
			end
		endcase
	end
	return tuple2(result,carry);
endfunction




////////////////////////////////////////////////////////////////////////////////
/// Pipelined Floating Point Multiplier
////////////////////////////////////////////////////////////////////////////////
module mkFloatingPointMultiplierSimple(Server#(Tuple3#(FloatingPoint#(e,m), FloatingPoint#(e,m), RoundMode), Tuple2#(FloatingPoint#(e,m),Exception)))
  provisos(
  // per request of bsc
  Add#(a__, TLog#(TAdd#(1, TAdd#(TAdd#(m, 1), TAdd#(m, 1)))), TAdd#(e, 1))
  );

  ////////////////////////////////////////////////////////////////////////////////
  /// S0
  ////////////////////////////////////////////////////////////////////////////////
  FIFO#(Tuple3#(FloatingPoint#(e,m),
		 FloatingPoint#(e,m),
		 RoundMode))      fOperands_S0   <- mkLFIFO;

  ////////////////////////////////////////////////////////////////////////////////
  /// S1 - calculate the new exponent/sign
  ////////////////////////////////////////////////////////////////////////////////
  FIFO#(Tuple5#(Maybe#(FloatingPoint#(e,m)),
	   Bit#(TAdd#(m,1)),
		 Bit#(TAdd#(m,1)),
		 Int#(TAdd#(e,2)),
		 Bool)) fState_S1 <- mkLFIFO;

  rule s1_stage;
    match { .opA, .opB, .rmode } <- toGet(fOperands_S0).get;
    Bool sign = (opA.sign != opB.sign);
    Maybe#(FloatingPoint#(e,m)) s = ?;    

    Int#(TAdd#(e,2)) expA = isSubNormal(opA) ? fromInteger(minexp(opA)) : signExtend(unpack(unbias(opA)));
    Int#(TAdd#(e,2)) expB = isSubNormal(opB) ? fromInteger(minexp(opB)) : signExtend(unpack(unbias(opB)));
    Int#(TAdd#(e,2)) newexp = expA + expB;

    Bit#(TAdd#(m,1)) opAsfd = { getHiddenBit(opA), opA.sfd };
    Bit#(TAdd#(m,1)) opBsfd = { getHiddenBit(opB), opB.sfd };
    
    if( isNormal(opA) && isNormal(opB) ) 
       s = tagged Invalid;
    else if ( isNaN(opA) || isNaN(opB) ) 
       s = tagged Valid snan();
    else if ( isInfinity(opA) || isInfinity(opB) ) begin
      if ( (isInfinity(opA) && isInfinity(opB)) || (isNormal(opA) && isInfinity(opB)) || (isInfinity(opA) && isNormal(opB)) )
        s = tagged Valid infinity(opA.sign != opB.sign);
      else 
        s = tagged Valid snan();
    end
    else s = tagged Valid zero(opA.sign != opB.sign);

    fState_S1.enq(tuple5(s,
			  opAsfd,
			  opBsfd,
			  newexp,
			  sign));
  endrule

  ////////////////////////////////////////////////////////////////////////////////
  /// S2
  ////////////////////////////////////////////////////////////////////////////////
  FIFO#(Tuple4#(Maybe#(FloatingPoint#(e,m)),
		 Bit#(TAdd#(TAdd#(m,1),TAdd#(m,1))),
		 Int#(TAdd#(e,2)),
		 Bool)) fState_S2 <- mkLFIFO;

  rule s2_stage;
    match {.s, .opAsfd, .opBsfd, .exp, .sign} <- toGet(fState_S1).get;
    Bit#(TAdd#(TAdd#(m,1),TAdd#(m,1))) sfdres = primMul(opAsfd, opBsfd);
    fState_S2.enq(tuple4(s,
			  sfdres,
			  exp,
			  sign));
  endrule

  ////////////////////////////////////////////////////////////////////////////////
  /// S3
  ////////////////////////////////////////////////////////////////////////////////
  FIFO#(Tuple2#(FloatingPoint#(e,m),Exception)) fResult_S3       <- mkLFIFO;

  rule s3_stage;
    match {.s, .sfdres, .exp, .sign} <- toGet(fState_S2).get;

    FloatingPoint#(e,m) result = defaultValue;
    Exception etemp = defaultValue;
    etemp.invalid_op = False;
    etemp.divide_0 = False;
    etemp.overflow = False;
    etemp.underflow = True;
    etemp.inexact = True;
	  
	  Bit#(TAdd#(m,1)) temp = { 'b1, result.sfd };
	  Bit#(m) roundedMts = truncate( tpl_1( jround(temp,sfdres) ) );
	  let roundCarry = tpl_2( jround(temp,sfdres) );
    if (s matches tagged Invalid) begin
		  exp = exp + zeroExtend(unpack(pack(roundCarry)));
	    if (exp > fromInteger(maxexp(result)))
			  result = infinity(sign);
		  else begin
		    let shift = fromInteger(minexp(result)) - exp;
			
		    if (shift > 0) begin
			    // subnormal
			    roundedMts = roundedMts >> shift;
			    result.exp = 0;
		    end else
			    result.exp = cExtend(exp + fromInteger(bias(result)));

        // $display("shift = %d", shift);
        // $display("sfdres = 'h%x", sfdres);
        // $display("result = ", fshow(result));
        // $display("exc = 'b%b", pack(exc));
        // $display("zeros = %d", countZerosMSB(sfdres));
  
        result.sign = sign;
        result.sfd = roundedMts;
  
        // $display("result = ", fshow(result));
        // $display("exc = 'b%b", pack(exc));
		  end
	  end else result = fromMaybe(defaultValue,s);
	  
    fResult_S3.enq(tuple2(result,etemp));
  endrule

  ////////////////////////////////////////////////////////////////////////////////
  /// Interface Connections / Methods
  ////////////////////////////////////////////////////////////////////////////////
  interface request = toPut(fOperands_S0);
  interface response = toGet(fResult_S3);

endmodule: mkFloatingPointMultiplierSimple
