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
 * Authors:
 *   Nirav Dave <ndave@csl.sri.com>
 *   Robert M. Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Branch Predictor
 *
 ******************************************************************************/

import MIPS::*;
import CHERITypes::*;

import EHR::*;
import Debug::*;


interface BranchPredictor;
                           // epoch, pc, pred next PC, pred next next PC
  method ActionValue#(Tuple4#(Epoch,Address,Address,Address)) getPrediction();

  method Epoch           curEpoch();
  method Action resolveBranchMiss(Address pc, Address nextPC);
  method Action     takeException(Address epc);
  method Action       debug_setPC(Address pc);
endinterface


// ndave: Simple prediction + 8 always
// ndave: YYY We should do at least 2-bit prediction + BTB

`ifndef VERIFY2
// Simplified branch "predictor" with almost identical behaviour to
// the original.  Much easier to understand and takes one extra cycle
// on branch miss/exception but avoids critical path from exe/wb to
// fetch.
module mkBranchPredictor#(Reg#(Address) pc)(BranchPredictor);
   Reg#(Address) nextPC     <- mkReg(64'h9000000040000000);
   Reg#(Epoch)   epoch      <- mkReg(0); // doesn't matter how it's initialized

   EHR#(3, Address) nextNextPC <- mkEHR(64'h9000000040000004);
   EHR#(3, Epoch)   nextEpoch  <- mkEHR(0); // epoch of next inst
   EHR#(2, Bool)    exception  <- mkEHR(False);

   // epoch, pc, pred next PC, pred next next PC
   method ActionValue#(Tuple4#(Epoch,Address,Address,Address)) getPrediction();
      // The "prediction".
      nextNextPC[2] <= nextNextPC[2] + 4;

      nextPC <= nextNextPC[2];
      epoch  <= nextEpoch[2];
      exception[1] <= False;
      return tuple4(epoch, nextPC, nextPC + 4, nextPC + 8);
   endmethod

   method Epoch           curEpoch();
      return nextEpoch[1];
   endmethod

   method Action resolveBranchMiss(Address pc, Address realNextPC);
      if (!exception[1])
	 begin
            nextNextPC[1] <= realNextPC;
            nextEpoch[1]  <= nextEpoch[1] + 1;
	 end
   endmethod

   method Action     takeException(Address epc);
      exception[0]  <= True;
      nextPC        <= epc;
      nextNextPC[0] <= epc + 4;
      nextEpoch[0]  <= nextEpoch[0] + 1;
      epoch         <= nextEpoch[0] + 1;
   endmethod

   method Action debug_setPC(Address newPC);
     nextPC <= newPC;
     epoch  <= epoch + 1;
     nextNextPC[2] <= newPC + 4;
     nextEpoch[2]  <= epoch + 1;
   endmethod
endmodule

`else // VERIFIABLE Version

module mkBranchPredictor#(Reg#(Address) pc)(BranchPredictor);
  Reg#(Maybe#(Address))     specPC <- mkReg(Nothing);
  Reg#(Maybe#(Address)) specNextPC <- mkReg(Nothing);

  Reg#(Epoch)                epoch     <- mkReg(0); // doesn't matter how it's initialized
  Reg#(Epoch)                nextEpoch <- mkReg(0); // epoch of next inst

  let currPC     = fromMaybe(pc,specPC);
  let currNextPC = fromMaybe(currPC + 4,specNextPC);

  method ActionValue#(Tuple4#(Epoch,Address,Address,Address)) getPrediction();
    let predNextNextPC = currNextPC + 4; // Our prediction
    specPC     <= tagged Valid currNextPC;
    specNextPC <= tagged Valid predNextNextPC;
    epoch      <= nextEpoch;
    debug($display("getPrediction %d (%d, %h %h, %h)", $time, epoch,  currPC, currNextPC, predNextNextPC));
    return tuple4(epoch, currPC, currNextPC, predNextNextPC);
  endmethod

  method Epoch curEpoch();
    return nextEpoch;
  endmethod

  method Action resolveBranchMiss(Address pc, Address realNextPC);
    debug($display("RESOLVE %d Branch Miss [%d]  %h %h", $time, epoch, pc, realNextPC));

    // The initial value of specNextPC relies on the lack of back to back
    //        instructions. We should check this

    specNextPC <= tagged Valid (realNextPC);

    nextEpoch  <= nextEpoch + 1; // ndave: change epoch to prevent false-path
                                 //        instructions form being executed.
  endmethod

  method Action takeException(Address epc);
    specNextPC <= Valid (epc);
    nextEpoch  <= nextEpoch + 1; // ndave: increment to clear pipeline
  endmethod

   method Action debug_setPC(Address newPC);
      specPC <= tagged Valid newPC;
      epoch  <= epoch + 1;
   endmethod
endmodule
`endif
