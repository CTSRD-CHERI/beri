/*-
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Philip Withnall
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
 *         Robert M. Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 * Description
 *
 * Provides Base Debugging Primitives for CHERI Processor
 *
 ******************************************************************************/

import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Counter::*;

function String regName(Bit#(5) regNo);
  return case (regNo)
            5'h00: " 0";
            5'h01: "at";
            5'h02: "v0";
            5'h03: "v1";
            5'h04: "a0";
            5'h05: "a1";
            5'h06: "a2";
            5'h07: "a3";
            5'h08: "a4";
            5'h09: "a5";
            5'h0a: "a6";
            5'h0b: "a7";
            5'h0c: "t0";
            5'h0d: "t1";
            5'h0e: "t2";
            5'h0f: "t3";
            5'h10: "s0";
            5'h11: "s1";
            5'h12: "s2";
            5'h13: "s3";
            5'h14: "s4";
            5'h15: "s5";
            5'h16: "s6";
            5'h17: "s7";
            5'h18: "t8";
            5'h19: "t9";
            5'h1a: "k0";
            5'h1b: "k1";
            5'h1c: "gp";
            5'h1d: "sp";
            5'h1e: "fp";
            5'h1f: "ra";
            default:"xx";
         endcase;
endfunction

`ifndef VERIFY2
function Action trace(Action a);
  action
    Bool debugP<-$test$plusargs("debug");
    Bool traceP<-$test$plusargs("trace");
    if(traceP||debugP)
      a;
  endaction
endfunction

function Action debug(Action a);
  action
    Bool debugP<-$test$plusargs("debug");
    if(debugP)
      a;
  endaction
endfunction

function Action cachedump(Action a);
  action 
      Bool cachedumpB <- $test$plusargs("cachedump");
      if (cachedumpB)
        a;
  endaction 
endfunction 

function Action debug2(String component, Action a);
  action
    Bool debugP<-$test$plusargs("debug");
    Bool debugC<-$test$plusargs(component);
    if (debugP||debugC)
      a;
  endaction
endfunction
function Action debug_decode(Action a);
  action
    debug2("decode", a);
  endaction
endfunction

function Action debug_dmem(Action a);
  action
    Bool debug <- $test$plusargs("debug");
    Bool dmem  <- $test$plusargs("dmem");
    Bool c1t   <- $test$plusargs("cheri1_trace");
    if (debug||dmem||c1t)
      a;
  endaction
endfunction

function Action debug_cp0(Action a);
  action
    Bool debug <- $test$plusargs("debug");
    Bool cp0   <- $test$plusargs("cp0");
    Bool c1t   <- $test$plusargs("cheri1_trace");
    if (debug||cp0||c1t)
      a;
  endaction
endfunction

function Action debug_cheri1_trace(Action a);
  action
    Bool c1t   <- $test$plusargs("cheri1_trace");
    if (c1t)
      a;
  endaction
endfunction

function Action debug_tlb(Action a);
  action
    debug2("tlb", a);
  endaction
endfunction

function Action cycReport(Action a);
  action
    `ifdef BLUESIM
      Bool traceB <- $test$plusargs("cTrace");
      if (traceB)
        a;
    `endif
  endaction
endfunction

`else
function Action trace(Action a) = noAction;
function Action debug(Action a) = noAction;
function Action debug2(String component, Action a) = noAction;
function Action debug_decode(Action a) = noAction;
function Action debug_cp0(Action a) = noAction;
function Action debug_dmem(Action a) = noAction;
function Action debug_cheri1_trace(Action a) = noAction;  
function Action debug_tlb(Action a) = noAction;	  
function Action cycReport(Action a) = noAction;	  
`endif

interface Debug#(type a, type b);
  interface a inf;
  interface b debugging;
endinterface

function Action debugDisplay(Display#(a) m, a v);
  action m.debug_display(v); endaction
endfunction

interface Display#(type a);
  method Action debug_display(a v);
endinterface

//=====================================================================================
// PipelineFIFOF with beginning of cycle access to empty/full signals

`ifndef VERIFY
module [m] mkFIFOF_Debug#(m#(FIFOF#(a)) mkF, Integer sz)(Debug#(FIFOF#(a), Display#(void)))
  provisos(IsModule#(m, m__));

  FIFOF#(a)      f <- mkF();
  Counter#(32) cnt <- mkCounter(0);

  interface FIFOF inf;
    method Action     enq(x) = action f.enq(x);  cnt.up();    endaction;
    method Action      deq() = action f.deq();   cnt.down();  endaction;
    method Action    clear() = action f.clear(); cnt.clear(); endaction;
    method Bool   notEmpty() = f.notEmpty();
    method Bool    notFull() = f.notFull();
    method a         first() = f.first();
  endinterface

  interface Display debugging;
    method Action debug_display(void v);
      let x = cnt.value();
      if(x == 0)
        $write("EMPTY");
      else if(x == fromInteger(sz))
        $write("FULL ");
      else
        $write("", x, "/", sz);
    endmethod
  endinterface
endmodule
`else
module [m] mkFIFOF_Debug#(m#(FIFOF#(a)) mkF, Integer sz)(Debug#(FIFOF#(a), Display#(void)))
     provisos(IsModule#(m, m__));
	let f <- mkF;
	interface FIFOF inf = f;
  interface Display debugging;
    method Action debug_display(void v) = noAction;
  endinterface
endmodule
`endif



function Action displayFIFO(FIFOF#(a) f);
  action
    case ({pack(f.notEmpty), pack(f.notFull)}) matches
      2'b00: $write("Impossible State");
      2'b01: $write("EMPTY");
      2'b10: $write("FULL");
      2'b11: $write("PARTIALLY FULL");
    endcase
  endaction
endfunction

function Action displayFIFO1(FIFOF#(a) f); // only for FIFOs of size 1
   action
      // Since for most of these FIFOs notFull and notEmpty are SBR, we use
      // only notEmpty:
      case ({pack(f.notEmpty), pack(!f.notEmpty)}) matches
	 2'b00: $write("Impossible State");
	 2'b01: $write("EMPTY");
	 2'b10: $write("FULL");
	 2'b11: $write("PARTIALLY FULL");
      endcase
   endaction
endfunction
