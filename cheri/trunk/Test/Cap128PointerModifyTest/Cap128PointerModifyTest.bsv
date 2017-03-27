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
import Clocks    :: *;
import Debug::*;

typedef struct {
  Bit#(64) base;
  Bit#(64) length;
  Bit#(64) offset;
  Bit#(6)  sigBits;
} Bounds deriving(Bits, Eq, FShow); // 40-bits

module [Specification] modifyPointerSpec#(Reset r) ();
  // 1st stage
  FIFO#(CapFat) cs <- mkFIFO1();
  FIFO#(Bit#(64)) offsets <- mkFIFO1();
  FIFO#(Bounds)   stds <- mkFIFO1();
  FIFO#(Bit#(64)) tops <- mkFIFO1();
  
  // 2nd stage
  FIFO#(CapFat) results <- mkFIFO1();
  
  TestIfc dut <- mkTest();
  
  function Action boundsPut(Bounds bi) =
    action
      Bounds b = Bounds{
       base: bi.base>>bi.sigBits,
       length: bi.length>>bi.sigBits,
       offset: bi.offset>>bi.sigBits,
       sigBits: ?
      };
      $display("Input: ", fshow(b));
      CapFat c = defaultCapFat;
      c.pointer = zeroExtend(b.base);
      c <- setBounds(c, b.length);
      ManHiBits hb = getHiBits(c);
      b.sigBits = c.exp;
      cs.enq(c);
      offsets.enq(b.offset);
      
      // Standard
      tops.enq(truncate(getTopFat(c,hb)));
      stds.enq(b);
    endaction;
    
  rule doTheTest;
    CapFat result <- dut.doTest(cs.first, offsets.first);
    results.enq(result);
    cs.deq();
    offsets.deq();
  endrule
    
  function ActionValue#(Bool) verifyFunc(Bounds bi) =
    actionvalue
      Bounds b <- toGet(stds).get();
      CapFat c <- toGet(results).get();
      Bit#(64) oldTop <- toGet(tops).get();
      ManHiBits hb = getHiBits(c);

      Bool representable = c.isCapability;
      Bool topStillTop = truncate(getTopFat(c, hb))==oldTop;
      Bool pointerIsRight = truncate(c.pointer) == b.base+b.offset;
      Int#(65) offset = unpack(signExtend(b.offset));
      Exp exp = b.sigBits; // Exponent stashed here.
      Int#(65) maxOffset = unpack(zeroExtend(b.length)) + ('h1000<<exp);
      Int#(65) minOffset = ('h1000<<exp);
      trace($display("OldTop: %x, newTop: %x, goodPointer: %x, pointer: %x, \n%d offset \n%d max offset \n%d min offset", 
               oldTop, getTopFat(c, hb), b.base+b.offset, c.pointer, offset, maxOffset, minOffset));
      
      Bool shouldBeRepresentable = True;
      // If offset is greater than zero, we should be able to reach past the length.
      if (offset >= 0) shouldBeRepresentable = (offset <= maxOffset);
      // If offset is less than 0, we should be able to reach just past the bottom.
      else begin
        // Because signed comparison in Bluespec doesn't work!?
        shouldBeRepresentable = (-offset <= minOffset);
        trace($display("offset >= minOffset: %x", shouldBeRepresentable));
      end
      
      // It's ok if it became unrepresentable, unless it should have been.
      Bool allGood = (topStillTop && pointerIsRight) || (!representable);
      if (shouldBeRepresentable && !representable) allGood = False;
      
      trace($display("Inbounds - stillCap: %d, capTop==oldTop: %d, capPointer==goodPointer: %d, shouldBeRepresentable: %d, allGood: %d", 
               representable, topStillTop, pointerIsRight, shouldBeRepresentable, allGood));
      return allGood;
    endactionvalue;
  

  prop("putBounds", boundsPut);
  prop("check", verifyFunc);
endmodule

//module boundsCheckVerify();
//  BlueCheck_Params params = bcParams;
//  params.numIterations = 100000;
//  Stmt s <- mkModelChecker(modifyPointerSpec, params);
//  mkAutoFSM(s);
//endmodule

module boundsCheckVerify();
  Clock clk <- exposeCurrentClock;
  MakeResetIfc r <- mkReset(0, True, clk);
  BlueCheck_Params params = bcParamsID(r);
  params.numIterations = 1000000;
  params.id.testsPerDepth = 1;
  params.id.initialDepth = 20;
  params.id.incDepth = id;
  Stmt s <- mkModelChecker(modifyPointerSpec(r.new_rst), params);
  mkAutoFSM(s);
endmodule

interface TestIfc;
  method ActionValue#(CapFat) doTest(CapFat c, Bit#(64) offset);
endinterface
(* synthesize *)
module mkTest(TestIfc);
  method ActionValue#(CapFat) doTest(CapFat c, Bit#(64) offset);
    LAddress addr = zeroExtend(c.pointer) + zeroExtend(offset);
    CapFat ret <- incOffset(c, addr, unpack(zeroExtend(offset)), getHiBits(c), False);
    return ret;
  endmethod
endmodule