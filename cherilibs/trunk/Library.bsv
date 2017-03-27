/*-
 * Copyright (c) 2011-2012 SRI International
 * Copyright (c) 2013 Jonathan Woodruff
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
 * Author: Nirav Dave <ndave@csl.sri.com>
 *
 ******************************************************************************
 * Description:
 *
 * Provides Useful Utility Functions
 *
 ******************************************************************************/

import Vector::*;
import RegFile::*;
import ConfigReg::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import BRAM::*;
import EHR::*;

function Bool andBools(Bool a, Bool b) = a && b;
function Bool orBools(Bool a, Bool b) = a || b;
function Bool andNotBools(Bool a, Bool b) = a && !b;

function Bit#(k) rtruncate(Bit#(n) x) provisos (Add#(k,xxx,n));
  match {.rv,.*} = split(x);
  return rv;
endfunction

function Maybe#(a) joinMaybe(Maybe#(Maybe#(a)) mma);
  return fromMaybe(Invalid, mma);
endfunction

function ActionValue#(a) fromMaybeAV(ActionValue#(a) act, Maybe#(a) m);
  if (isValid(m))
    return toAV(validValue(m));
  else
    return act;
endfunction

//function m#(a) joinM(m#(m#(a)) mma) provisos(Monad#(m)) = Monad::bind(mma, id);

function Bit#(8) toByte(a x) provisos(Bits#(a,asz), Add#(asz,xxx,8));
  return zeroExtend(pack(x));
endfunction

function Tuple2#(c, b) applyFst(function c f(a x), Tuple2#(a,b) t);
  match{.a,.b} = t;
  return tuple2(f(a), b);
endfunction

function a fst(Tuple2#(a,b) x);
  match {.a,.*} = x;
  return a;
endfunction


function ActionValue#(a) popFIFO(FIFO#(a) f);
  actionvalue
  	let x = f.first();
    f.deq();
  	return x;
  endactionvalue
endfunction

function ActionValue#(a) popFIFOF(FIFOF#(a) f);
  actionvalue
  	let x = f.first();
    f.deq();
  	return x;
  endactionvalue
endfunction

function ActionValue#(a) toAV(a x);
  actionvalue
    return x;
  endactionvalue
endfunction

  module toModule#(a ifc)(a);
	return ifc;
  endmodule

function Bit#(n) selectBytes(Bit#(k) selector, Bit#(n) as, Bit#(n) bs) provisos(Mul#(k,8,n));
  Vector#(k, Bool) selectors = unpack(selector);
  Vector#(k, Bit#(8)) aBytes = unpack(as);
  Vector#(k, Bit#(8)) bBytes = unpack(bs);
  function Bit#(8) selectByte(Tuple3#(Bool, Bit#(8), Bit#(8)) arg);
    match {.s, .a, .b } = arg;
    return s ? a : b;
  endfunction
  return pack(map(selectByte, zip3(selectors, aBytes, bBytes)));
endfunction

function Bit#(n) reverseBytes(Bit#(n) x) provisos(Mul#(k,8,n));
  Vector#(k, Bit#(8)) v = unpack(x);
  return pack(reverse(v));
endfunction

//function Bit#(n) reverseBits(Bit#(n) x);
//  Vector#(n, Bit#(1)) v = unpack(x);
//  return pack(reverse(v));
//endfunction

// Reverse the order of the bytes within each 64-bit word of a bit vector.
function Bit#(n) reverseBytesInWords(Bit#(n) line) provisos(Mul#(w,64,n));
  Vector#(w, Bit#(64)) words = unpack(line);
  let reversed = map(reverseBytes, words);
  return pack(reversed);
endfunction

// Reverse the order of the bits within each byte of a bit vector.
function Bit#(n) reverseBitsInBytes(Bit#(n) v) provisos(Mul#(b,8,n));
  Vector#(b, Bit#(8)) bytes = unpack(v);
  let reversed = map(reverseBits, bytes);
  return pack(reversed);
endfunction

function Tuple2#(Bool, Bit#(n)) fromSigned(Bool isSigned, Bit#(n) x) provisos(Add#(1,k,n));
  Bool sign = (msb(x)== 1) && isSigned;
  return tuple2(sign, (sign) ? (-x) : x);
endfunction

function Bit#(n) toSigned(Bool sign, Bit#(n) x);
  return (sign) ? (-x) : x;
endfunction

function Bool isAddOverflow(Bit#(n) x, Bit#(n) y, Bit#(n) sum) provisos (Add#(1,k,n));
  return (msb(x) != msb(sum)) && (msb(y) != msb(sum));
endfunction

function Maybe#(Bit#(sz)) findFirstMatchingIndex(function Bool p(a x), Vector#(n, a) xs)
             provisos (Log#(n, sz), Add#(1, x__, n));

  function Maybe#(Bit#(sz)) number(a x, Integer i)= (p(x)) ? tagged Valid (fromInteger(i)) : tagged Invalid;
  Vector#(n, Maybe#(Bit#(sz))) numbered = Vector::zipWith(number,xs,genVector);
  function Maybe#(x) pickLeft(Maybe#(x) mx, Maybe#(x) my) = (isValid(mx)) ? mx: my;
  return Vector::fold(pickLeft, numbered);
endfunction

function Maybe#(a) firstValid(Vector#(n, Maybe#(a)) xs)
             provisos (Add#(1, x__, n));
  function Maybe#(x) pickLeft(Maybe#(x) mx, Maybe#(x) my) = (isValid(mx)) ? mx: my;
  return Vector::fold(pickLeft, xs);
endfunction

`ifndef VERIFY
function m#(FIFO#(a))  mkPipeFIFO provisos (Bits#(a,asz), IsModule#(m,m__))  = mkPipelineFIFO();
function m#(FIFOF#(a)) mkPipeFIFOF provisos (Bits#(a,asz), IsModule#(m,m__)) = mkPipelineFIFOF();
`else
function m#(FIFO#(a))  mkPipeFIFO  provisos (Bits#(a,asz), IsModule#(m,m__)) = mkSizedFIFO(1);
function m#(FIFOF#(a)) mkPipeFIFOF provisos (Bits#(a,asz), IsModule#(m,m__)) = mkSizedFIFOF(1);
`endif

`ifndef VERIFY2
module mkReg_WriteFirst#(Maybe#(a) mv)(Reg#(a)) provisos(Bits#(a,a__));
   EHR#(2, a) r  <- case (mv) matches
                      tagged Valid .v: mkEHR(v);
                      tagged Invalid : mkEHRU();
		   endcase;

   method a _read() = r[1];
    method Action _write(a x); r[0] <= x; endmethod

  endmodule
 `else
 module mkReg_WriteFirst#(Maybe#(a) mv)(Reg#(a)) provisos(Bits#(a,a__));
   Reg#(a) r <- case (mv) matches
		  tagged Valid .v: mkReg(v);
		  tagged Invalid : mkRegU();
		endcase;
   return r;
 endmodule
 `endif


 interface Write#(type a);
   method Bool   canRead();
   method Action _write(a x);
 endinterface

 module mkRegFile_initial#(a min, a max, v x)(RegFile#(a,v))
   provisos(Bits#(a,a__), Bounded#(a), Eq#(a), Arith#(a),
	    Bits#(v,v__));

   Reg#(Maybe#(a))        init <- mkReg(Valid(minBound));
   RegFile#(a,v)            rf <- mkRegFile(min, max);

   rule initRF(init matches tagged Valid .i);
     rf.upd(i, x);
	 init <= (i == maxBound) ? Invalid : tagged Valid (i+1);
   endrule


   method Action upd(a addr, v value) if (init == Invalid);
     rf.upd(addr,value);
   endmethod

   method v sub(a addr) if (init == Invalid);
     return rf.sub(addr);
   endmethod
 endmodule
