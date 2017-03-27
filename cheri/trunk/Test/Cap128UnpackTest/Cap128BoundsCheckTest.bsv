/*
 * Copyright 2015 Matthew Naylor
 * Copyright 2016 Jonathan Woodruff
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
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream
 * Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
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

import Capability128c3Libs :: *;
import StmtFSM   :: *;
import BlueCheck :: *;
import GetPut    :: *;
import FIFO      :: *;
import FIFOF     :: *;

typedef struct {
  Bit#(64) base;
  Bit#(64) length;
  Bit#(64) offset;
  Bit#(6)  sigBits;
} Bounds deriving(Bits, Eq, FShow); // 40-bits

module [Specification] boundsCheckSpec ();
  FIFO#(CapFat) results <- mkFIFO1();
  FIFO#(Capability) thins <- mkFIFO1();
  FIFO#(Bit#(64)) tops <- mkFIFO1();
  
  TestIfc dut <- mkTest();
  
  function Action boundsPut(Bounds biin) =
    action
      Bounds bi = biin;
      // Ensure that the offset is small enough to not overflow
      // the address space.
      if (bi.sigBits==0) bi.sigBits = 1;
      Bounds b = Bounds{
       base: bi.base>>bi.sigBits,
       length: bi.length>>bi.sigBits,
       offset: bi.offset>>bi.sigBits,
       sigBits: bi.sigBits
      };
      $display("Input: ", fshow(b));
      CapFat c = defaultCapFat;
      c.pointer = zeroExtend(b.base);
      c <- setBounds(c, b.length);
      ManHiBits hb = getHiBits(c);
      thins.enq(packCap(c));
      
      // Standard top
      tops.enq(b.base+b.length);
    endaction;
    
  rule doTheTest;
    CapFat result <- dut.doTest(thins.first, ?);
    results.enq(result);
    thins.deq();
  endrule
    
  function ActionValue#(Bool) boundsCheckVerifyFunc(Bounds bi) =
    actionvalue
      Bit#(64) top <- toGet(tops).get();
      CapFat c <- toGet(results).get();
      $display("Inbounds - standard %x, bench says %x ", top, getTopFat(c, getHiBits(c)));
      return top == truncate(getTopFat(c, getHiBits(c)));
    endactionvalue;
  

  prop("putBounds", boundsPut);
  prop("check", boundsCheckVerifyFunc);
endmodule

module boundsCheckVerify();
  BlueCheck_Params params = bcParams;
  params.numIterations = 100000;
  Stmt s <- mkModelChecker(boundsCheckSpec, params);
  mkAutoFSM(s);
endmodule

module [Module] boundsCheckVerifySynth(JtagUart);
  FIFOF#(Bit#(8)) out <- mkUGFIFOF;
  let params           = bcParams;
  params.numIterations = 100000;
  params.interactive   = False;
  params.outputFIFO    = tagged Valid out;
  JtagUart uart       <- mkJtagUart(out);
  Stmt s              <- mkModelChecker(boundsCheckSpec, params);
  mkAutoFSM(s);
  return uart;
endmodule

interface TestIfc;
  method ActionValue#(CapFat) doTest(Capability c, Bit#(64) offset);
endinterface
(* synthesize *)
module mkTest(TestIfc);
  method ActionValue#(CapFat) doTest(Capability c, Bit#(64) offset);
    return unpackCap(c);
  endmethod
endmodule
