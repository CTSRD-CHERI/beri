/*
 * Copyright (c) 2011-2012 SRI International
 * Copyright (c) 2012 Robert M. Norton
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
 *
 * Description: Searchable FIFO
 *
 ******************************************************************************/

import EHR::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;

import ConfigReg::*;

interface SFIFO#(type t, type st, type val);
  interface FIFOF#(t) fifo;
  interface Forwarder#(st,val) search;
endinterface

interface Forwarder#(type st, type val);
  method Maybe#(Maybe#(val)) searchA(st x);
  method Maybe#(Maybe#(val)) searchB(st x);
  method Bool isFlushed();
endinterface

module mkNullForwarder(Forwarder#(st, val));
  method searchA(x) = Invalid;
  method searchB(x) = Invalid;
  method isFlushed()= True;
endmodule

function Maybe#(Maybe#(a)) foldValues(Vector#(n, Maybe#(Maybe#(a))) xs)
     provisos(Add#(1, a__, n));
  function foldFn(mx,my) = (isValid(mx)) ? mx : my;
  return Vector::fold(foldFn, xs);
endfunction

function Vector#(n, Maybe#(Maybe#(v))) getValuesA(Vector#(n, Forwarder#(a, v)) fwds, a r);
  function f(fwd) = fwd.searchA(r);
  return Vector::map(f, fwds);
endfunction

function Vector#(n, Maybe#(Maybe#(v))) getValuesB(Vector#(n, Forwarder#(a, v)) fwds, a r);
  function f(fwd) = fwd.searchB(r);
  return Vector::map(f, fwds);
endfunction

module mkSFIFO1V#(function Maybe#(Maybe#(val)) searchF(t x, st r))
     (SFIFO#(t,st,val))
         provisos(Bits#(t,t__));

   Reg#(Maybe#(t))    mvalue <- mkRegU();
   Bool full = isValid(mvalue);

   interface FIFOF fifo;
      method Action enq(x) if (!full);
	 mvalue <= tagged Valid x;
      endmethod

      method t first() if (mvalue matches tagged Valid .x);
	 return x;
      endmethod

      method Action deq() if (full);
	 mvalue <= Invalid;
      endmethod

      method Action clear();
	 mvalue <= Invalid;
      endmethod

      method Bool notEmpty();
	 return full;
      endmethod

      method Bool notFull();
	 return !full;
      endmethod

  endinterface

  interface Forwarder search;
    method Maybe#(Maybe#(val)) searchA(st r);
       return (mvalue matches tagged Valid .x ? searchF(x, r) : Invalid);
    endmethod
    method Maybe#(Maybe#(val)) searchB(st r);
       return (mvalue matches tagged Valid .x ? searchF(x, r) : Invalid);
    endmethod
    method isFlushed = !full;
  endinterface

endmodule

module mkSFIFO1#(parameter Integer dn, // position of deq (and notEmpty) in sequence
		 parameter Integer en, // position of enq (and notFull) in sequence
		 parameter Integer sn, // position of search in sequence
		 parameter Integer fn, // position of isFlushed in sequence
		 function Maybe#(Maybe#(val)) searchF(t x, st r))
   (SFIFO#(t,st,val))
   provisos(Bits#(t,t__));

   EHR#(3, Maybe#(t))  mvalue <- mkEHR(Invalid);
   function full(n) = isValid(mvalue[n]);

   interface FIFOF fifo;
      method Bool notEmpty();
	 return full(dn);
      endmethod

      method t first() if (mvalue[0] matches tagged Valid .x);
	 return x;
      endmethod

      method Action deq() if (full(dn));
	 mvalue[dn] <= Invalid;
      endmethod

      // -----

      method Bool notFull();
	 return !full(en);
      endmethod

      method Action enq(x) if (!full(en));
	 mvalue[en] <= tagged Valid x;
      endmethod

      // -----

      method Action clear();
	 mvalue[2] <= Invalid;
      endmethod

   endinterface

   interface Forwarder search;
      method Maybe#(Maybe#(val)) searchA(st r);
	 return (mvalue[sn] matches tagged Valid .x ? searchF(x, r) : Invalid);
      endmethod
      method Maybe#(Maybe#(val)) searchB(st r);
	 return (mvalue[sn] matches tagged Valid .x ? searchF(x, r) : Invalid);
      endmethod
      method isFlushed = !full(fn);
   endinterface

endmodule