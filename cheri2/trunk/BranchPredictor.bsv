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
// This is all a bit confusing. Here's how it works: 
//
// Fetch calls getPrediction to get the address of the next
// instruction to fetch along with the next two predicted instructions
// and an epoch used for handling mispredictions.
//
// Execute checks the instruction epoch against the 'current' epoch
// and drops it if they don't match, unless the instruction is a
// branch delay slot (see Proc.bsv).
//
// Execute checks the result of branch instructions against the
// predicted nextNextPC and calls resolveBranchMiss if they do not
// match. This sets nextNextPC to the branch dest. and increments
// nextEpoch so that execution will begin from the new PC after nextPC
// is fetched (this may be the branch delay so we can't set nextPC
// directly). resolveBranchMiss is not called in branch delay slots as
// we do not want to overwrite nextNextPC which may still contain the
// destination of the branch. There should be no branch miss anyway as
// delay slots cannot contain branches (behaviour undefined).
//
// On exception writeback calls takeException to reset PC and epochs,
// then flushes the pipeline. Similarly for setPC from the debug unit
// except that the pipeline should be flushed already.
// 
module mkBranchPredictor#(Reg#(Address) pc)(BranchPredictor);
   // PC of next instruction to execute ('current' PC)
   EHR#(2, Address) nextPC     <- mkEHR(64'h9000000040000000);
   // Epoch of nextPC
   EHR#(2, Epoch)   epoch      <- mkEHR(0); // doesn't matter how it's initialized
   // PC of instruction to execute after nextPC
   EHR#(3, Address) nextNextPC <- mkEHR(64'h9000000040000004);
   // Epoch of nextNextPC, also 'current epoch'.
   EHR#(3, Epoch)   nextEpoch  <- mkEHR(0);
   // Signal to suppress resolveBranchMiss on exception.
   EHR#(2, Bool)    exception  <- mkEHR(False);

   // epoch, pc, pred next PC, pred next next PC
   method ActionValue#(Tuple4#(Epoch,Address,Address,Address)) getPrediction();
      // The "prediction".
      nextNextPC[2] <= nextNextPC[2] + 4;

      nextPC[1] <= nextNextPC[2];
      epoch[1]  <= nextEpoch[2];
      exception[1] <= False;
      // This implementation does no actual prediction.
      return tuple4(epoch[1], nextPC[1], nextPC[1] + 4, nextPC[1] + 8);
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

      // We avoid writing nextPC and epoch here which eliminates a
      // nasty forwarding path from writeback to fetch. However it
      // means one more dropped instruction leading to a potential
      // problem with capability jumps because we will fetch an
      // instruction from the old PC via the new PCC which could
      // generate a bad address which hangs the AXI bus. The TLB
      // should detect and suppress the bad address but this is not
      // guaranteed...

      //nextPC[0]     <= epc;
      //epoch[0]      <= nextEpoch[0] + 1;
      nextNextPC[0] <= epc;
      nextEpoch[0]  <= nextEpoch[0] + 1;
   endmethod

   method Action debug_setPC(Address newPC);
     nextPC[1]     <= newPC;
     epoch[1]      <= epoch[1] + 1;
     nextNextPC[2] <= newPC + 4;
     nextEpoch[2]  <= epoch[1] + 1;
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
