/*-
 * Copyright (c) 2013 Jonathan Woodruff
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
 */

import MIPS::*;
import RegFile::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MEM::*;
import ConfigReg::*;
import Debug::*;

typedef Bit#(8) Key;

typedef struct {
  Address    target;
  BranchType branchType;
  Key        key;
} PredictionRecord deriving(Bits, Eq);

typedef struct {
  Bool    takeTarget;
  Address specTarget;
  Epoch   epoch;
  InstId  id;
} Prediction deriving(Bits, Eq);

typedef enum {Init, Run} State deriving(Bits, Eq);

`ifdef NOT_FLAT
  (*synthesize*)
`endif     
module mkBranchSimple(BranchIfc);
  // pc holds the current architectural program counter.
  // pc is updated in pcWriteback at the end of the pipeline.
  Reg#(Address)                        pc <- mkConfigReg(64'h9000000040000000);
  // specPc holds the current speculative program counter.
  // specPc is updated in getPc in instruction fetch.
  Reg#(Address)                    specPc <- mkConfigReg(64'h9000000040000000);
  // flushCount facilitates fixed delays before beginning to issue
  // new instructions after a flush.
  Reg#(UInt#(4))               flushCount <- mkConfigReg(0);
  // flushFifo signals that the pipeline needs to be flushed.
  // The pipeline is clear to continue when it is dequed.
  FIFOF#(Bool)                  flushFifo <- mkUGFIFOF1;
  // epoch is the current epoch of the execution.
  // epoch is incremented whenever there is a branch miss.
  Reg#(Epoch)                       epoch <- mkConfigReg(0);
  // issueEpoch is the epoch of the instruction we last issued.
  // When issueEpoch is different from epoch, we know that
  // we have had a miss-prediction.
  Reg#(Epoch)                  issueEpoch <- mkConfigReg(0);
  // newEpoch is used to delay updating the epoch in pcWriteback
  // by one cycle to ensure that branch delay slots always finish
  // before the epoch changes.
  FIFOF#(Epoch)                  newEpoch <- mkUGFIFOF;
  // predictions holds branch prediction data passed from putTarget
  // to getPc.
  FIFOF#(Prediction)          predictions <- mkSizedFIFOF(3);
  // keys holds the lookup key used in getPc.  It is consumed in
  // putTarget but passed in predictionCheck to pcWriteback
  // where it is used to update branch history state.
  FIFO#(Key)                         keys <- mkSizedFIFO(2);
  // predictionCheck holds a record of the prediction sufficient
  // for pcWriteback to determine if we made a miss.
  FIFO#(PredictionRecord) predictionCheck <- mkSizedFIFO(10);
  // state determines whether we are in the initialize state
  Reg#(State)                       state <- mkConfigReg(Init);
  // targets is a BRAM which holds a history of branch targets
  MEM#(Key, Bit#(32))             targets <- mkMEM();
  
  // function: updateSpeculativePc
  // This function updates the speculativePc based on an epoch
  // change. It is important for correct operation but not critical
  // for performance. You won't need to modify this.
  function Action updateSpeculativePc(Bool fromDebug, Address nextPc);
    action
      // Feeding pc to the specPc register on a miss has the effect of delaying
      // the change in control flow by one instruction issue, ensuring that any
      // branch delay slot slides through in the current epoch.
      if (!fromDebug) begin
        if (issueEpoch == epoch) begin
          specPc <= nextPc + 4;
        end else begin
          specPc <= pc;
        end
      end
      issueEpoch <= epoch;
    endaction
  endfunction
  
  // function: epochUpdate
  // This function updates the epoch in response to branch misses or flushes.
  // This logic is important to correct operation but is not performance
  // critical, so you are not likely to need to modify it.
  function Action epochUpdate(Bool doWriteback, Bool flushNow, Bool miss, Bool fromDebug);
    action
      if (doWriteback && miss && !flushNow) begin
        newEpoch.enq(epoch + 1);
      end
      if (doWriteback && flushNow) begin
        if (!flushFifo.notEmpty) flushFifo.enq(True);
        if (newEpoch.notEmpty) begin
          newEpoch.deq();
          epoch <= epoch + 2;
        end else begin
          epoch <= epoch + 1;
        end
      end else if (newEpoch.notEmpty) begin
        epoch <= newEpoch.first;
        newEpoch.deq();
      end
    endaction
  endfunction

  // rule: flushDelay
  // Delays issuing new instructions for a few cycles after
  // a flush to give time for any TLB updates to complete.
  rule flushDelay(state != Init && flushFifo.notEmpty);
    debug($display("Branch flush count %d", flushCount));
    if (flushCount == 4) begin
      flushFifo.deq();
      flushCount <= 0;
    end else begin
      flushCount <= flushCount + 1;
    end
  endrule

  // rule: primeFifo
  // Issues 2 predictions for the initial 2 instructions at the reset vector.
  // Due to the branch delay feature of MIPS, in normal execution the instruction
  // after a branch is unconditional so we can safely have 2 predictions in flight
  // at all times, knowing that when we encounter a branch we don't have to change
  // the flow of control until the instruction after the next.  If we have an
  // exception or a branch miss, we can still flush all following instructions.
  rule primeFifo(state == Init);
    debug($display("Branch primed fifo with prediction %d:%x at time:%t", flushCount, ((flushCount == 0) ? pc : pc+4), $time));
    predictions.enq(Prediction{
      takeTarget: False,
      specTarget: ?,
      epoch: epoch,
      id: ?
    });
    flushCount <= flushCount + 1;
    if (flushCount == 1) begin
      state <= Run;
    end
  endrule

  // method: getPc
  // Delivers a PC to instruction fetch and begins a lookup in branch history
  // structures for this instruction.
  method ActionValue#(PcAndEpoch) getPc(InstId id, Bool fromDebug) if (!flushFifo.notEmpty);
    Prediction pred = predictions.first;
    if (!fromDebug) begin
      predictions.deq();
    end
    Address nextPc = specPc;
    if (issueEpoch == pred.epoch && pred.takeTarget) begin
      nextPc = pred.specTarget;
    end
    updateSpeculativePc(fromDebug, nextPc);
    // **************************************************
    // This code is very safe to modify!
    // Here you can begin lookup on prediction history structures that depend
    // on the PC of a potential branch. These can be consumed in the putTarget
    // method and taken into account when it feeds back the next speculative PC.
    targets.read.put(nextPc[9:2]);
    // *************************************************
    keys.enq(nextPc[9:2]);
    debug($display("Branch delivering spec PC = %x in epoch %x at time:%t", nextPc, issueEpoch, $time));
    return PcAndEpoch{ pc: nextPc, epoch: issueEpoch };
  endmethod
  
  // method: putTarget
  // Receives a slightly decoded instruction and makes a branch prediction,
  // delivering it back to the getPc method for speculation and forward to
  // the pcWriteback method for confirmation.
  method Action putTarget(
    BranchType branchType,
    Bool branchLikely,
    Address instPc,
    InstructionT instruction,
    Epoch instEpoch,
    InstId id,
    Bool fromDebug,
    Bool link
  ) if (state == Run);
    Bit#(32) targetTail <- targets.read.get();
    // **************************************************
    // This code is very safe to modify!
    // What should the target be? Use any of the information available
    // here, including the branch type (if any), the instruction, the current PC,
    // or whether the branch is likely.
    Address target = {instPc[63:32],targetTail};
    // *************************************************
    `ifndef NOBRANCHPREDICTION
      if (!fromDebug) begin
        predictions.enq(Prediction{
          takeTarget: branchType != None,
          specTarget: target,
          epoch: instEpoch,
          id: id
        });
      end
    `endif
    predictionCheck.enq(PredictionRecord{
      target: target,
      branchType: branchType,
      key: keys.first
    });
    keys.deq();
  endmethod
  
  // method: pcWriteback
  // Receives the actual PC writeback and updates branch history structures.
  method Action pcWriteback(
    Bool dead,
    Address truePc,
    Bool doWriteback,
    Bool flushNow,
    Bool fromDebug,
    Bool taken
  ) if (state == Run);
    PredictionRecord check = predictionCheck.first;
    predictionCheck.deq();
    Bool miss = False;
    `ifdef NOBRANCHPREDICTION
      if (!fromDebug) begin
        predictions.enq(Prediction{
          takeTarget: (doWriteback && check.branchType != None),
          specTarget: truePc,
          epoch: epoch,
          id: ?
        });
      end
    `endif
    if (doWriteback) begin
      pc <= truePc;
      if (!fromDebug && !miss && check.branchType != None) begin
        if (check.target != truePc) begin
          miss = True;
        end
        // **************************************************
        // This code is very safe to modify!
        // Here you know whether it was a miss, what you predicted last time,
        // and what type of branch/jump it was. Here you can update some state
        // to help you make a better prediction next time.
        targets.write(check.key, truePc[31:0]);
        // *************************************************
      end
      case (check.branchType)
        Branch:  cycReport($display("[>B%s]", (miss)?"M":"H"));
        Jump:    cycReport($display("[>J%s]", (miss)?"M":"H"));
        JumpReg: cycReport($display("[>R%s]", (miss)?"M":"H"));
      endcase
    end
    epochUpdate(doWriteback, flushNow, miss, fromDebug);
  endmethod

  /*method Action pause(Bool pauseNow);
    pauseReg <= pauseNow;
  endmethod*/

  method Epoch getEpoch;
    return epoch;
  endmethod
endmodule
