/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Alex Horsman
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

import MIPS::*;
import RegFile::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import MEM::*;
import ConfigReg::*;
import Debug::*;

typedef Bit#(5) Seg;
typedef Bit#(38) Target;

typedef Bit#(11) Key;

typedef struct {
  Bool       tookTarget;
  Address    target;
  History    history;
  BranchType branchType;
  Key        key;
  Bool       branchLikely;
} PredictionRecord deriving(Bits, Eq);

typedef struct {
  Bool    takeTarget;
  Address specTarget;
  Epoch   epoch;
  InstId  id;
} Prediction deriving(Bits, Eq);

typedef struct {
  Int#(2) history;
  Seg     seg;
  Target  target;
} History deriving(Bits, Eq);

typedef enum {Init, Run} State deriving(Bits, Eq);
`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkBranch(BranchIfc);
  Reg#(Address)                        pc <- mkConfigReg(64'h9000000040000000);
  Reg#(Address)                    specPc <- mkReg(64'h9000000040000000);
  Reg#(UInt#(4))               flushCount <- mkReg(0);
  //FIFOF#(Bool)                  flushFifo <- mkUGFIFOF1;
  Reg#(Epoch)                       epoch <- mkConfigReg(0);
  Reg#(Epoch)                  issueEpoch <- mkReg(0);
  FIFOF#(Epoch)                  newEpoch <- mkUGFIFOF;
  FIFOF#(Prediction)          predictions <- mkUGSizedFIFOF(2);
  FIFO#(Key)                         keys <- mkSizedFIFO(2);
  FIFO#(PredictionRecord) predictionCheck <- mkSizedFIFO(10);
  FIFO#(PredictionRecord)   historyUpdate <- mkFIFO;
  Reg#(State)                       state <- mkReg(Init);

  MEM#(Bit#(11), History)       histories <- mkMEM();
  // Circular buffer of return addresses.  We push the return address when we
  // do any kind of jump and link and pop when we jump-register with $ra as the
  // destination.  We assume that call stacks are rarely more than 16 elements
  // deep (when they are, they are usually spending a lot of time in the deep
  // part, so optimising for the other end is not useful) and that the compiler
  // will do a jr $ra to return from any jal / jalr.
  MEM#(UInt#(5), Address)     callHistory <- mkMEM();
  // Index of the currently used value for the return buffer.  This will
  // overflow and wrap around if the stack is too deep, overwriting the oldest
  // result (i.e. the one likely to be needed the furthest in the future).
  Reg#(UInt#(5))                callDepth <- mkReg(0);
  Reg#(Address)                   callTop <- mkRegU;
  Reg#(Bit#(4))                  globHist <- mkConfigReg(0);

  rule callHistoryReq;
    callHistory.read.put(callDepth - 1);
  endrule
  rule callHistoryResp;
    Address newCallTop <- callHistory.read.get();
    callTop <= newCallTop;
  endrule

  rule primeFifoRule(state == Init);
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

  // This is broken out into a separate rule to improve timing.
  rule updateHistory;
    PredictionRecord check = historyUpdate.first;
    historyUpdate.deq;
    histories.write(check.key, check.history);
  endrule

  method ActionValue#(PcAndEpoch) getPc(InstId id, Bool fromDebug);
    Prediction pred = predictions.first;
    if (!fromDebug) begin
      predictions.deq;
    end
    Address nextPc = specPc;
    if (issueEpoch == pred.epoch && pred.takeTarget) begin
      nextPc = pred.specTarget;
    end
    // Feeding pc to the specPc register on a miss has the effect of delaying
    // the change in control flow by one instruction issue, ensuring that any
    // branch delay slot slides through in the current epoch.
    if (!fromDebug) begin
      if (issueEpoch == epoch) begin
        specPc <= nextPc + 4;
      end else specPc <= pc;
      issueEpoch <= epoch;
    end
    Key key = {globHist,7'b0} ^ nextPc[12:2];
    histories.read.put(key);
    keys.enq(key);
    debug($display("Branch delivering spec PC = %x in epoch %x at time:%t", nextPc, issueEpoch, $time));
    //trace($display("(->%x e%x)", nextPc[11:0], issueEpoch));
    return PcAndEpoch{pc: nextPc, epoch: issueEpoch};
  endmethod

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
    History hist <- histories.read.get();
    // If this is a branch-and-link, push the current return address
    // Actually, always write the address in the next location, but
    // only increment the counter when it is certainly a link.
    callHistory.write(callDepth, instPc + 8);
    Bool popLink = False;
    // Only increment the counter, thus keeping the current link address,
    // if this is a link and if this instruction is not in an old epoch.
    if (link && instEpoch == epoch) begin
      callDepth <= callDepth + 1;
      debug($display("Branch pushing return target %x to the call stack for instruction %x at time %t", instPc+8, instPc, $time));
    end
    // Register 31 is the return address, so a jump to it indicates a return.
    else if(branchType == JumpReg &&& instruction matches tagged Register (tagged Rtype{ rs: 31 })) begin
      if (hist.history >= 0) begin
        // Use history here as a tournament to determine whether to use the call
        // stack or not. If this is a jump to the return address, pop the last
        // return address
        popLink = True;
        callDepth <= callDepth - 1;
      end
    end

    Address target = (case (branchType)
      Branch:  return {hist.seg,signExtend(hist.target),2'b0};
      Jump:    return (hist.history >= 0) ?
        {instPc[63:28], pack(instruction)[25:0], 2'b0}
        :{hist.seg,signExtend(hist.target),2'b0};
      JumpReg: return popLink ?
        callTop
        :{hist.seg,signExtend(hist.target),2'b0};
      default: return ?;
    endcase);
    Bool takeTarget = (case (branchType)
      Branch:  return (hist.history >= 0 || branchLikely);
      Jump:    return True;
      JumpReg: return True;
      default: return False;
    endcase);

    `ifndef NOBRANCHPREDICTION
      if (!fromDebug) begin
        predictions.enq(Prediction{
          takeTarget: takeTarget,
          specTarget: target,
          epoch: instEpoch,
          id: id
        });
      end
    `endif
    predictionCheck.enq(PredictionRecord{
      tookTarget:   takeTarget,
      target:       target,
      history:      hist,
      branchType:   branchType,
      key:          keys.first,
      branchLikely: branchLikely
    });
    keys.deq;
  endmethod

  method Action pcWriteback(
    Bool dead,
    Address truePc,
    Bool doWriteback,
    Bool flushNow,
    Bool fromDebug,
    Bool taken
  ) if (state == Run);

    PredictionRecord check = predictionCheck.first;
    predictionCheck.deq;

    Bool miss = False;
    `ifdef NOBRANCHPREDICTION
      //if (check.branchType != None)
      if (!fromDebug) begin
        predictions.enq(Prediction{
          takeTarget: (doWriteback && check.branchType != None),
          specTarget: truePc,
          epoch: epoch,
          id: ?
        });
      end
    `endif
    //if (fromDebug) doWriteback = False;
    if (doWriteback) begin
      pc <= truePc;
      case (check.branchType)
        Branch: begin
          globHist <= {globHist[2:0],pack(taken)};
          if (check.tookTarget) begin
            miss = (!taken) || (check.target != truePc);
          end else begin
            miss = (taken);
          end
          if (taken) begin
            check.history.target = truePc[39:2];
            check.history.seg = truePc[63:59];
          end
          check.history.history = boundedPlus(check.history.history,(taken)?1:-1);
        end
        JumpReg: begin
          if (check.target != truePc) begin
            miss = True;
          end
          check.history.target = truePc[39:2];
          check.history.seg = truePc[63:59];
          // For a jump reg, use the history to indicate whether to use the call
          // stack or not. We just want to go the opposite direction we went
          // last time if we missed.
          Int#(2) histSign = (check.history.history >= 0) ? 1:-1;
          check.history.history = boundedPlus(check.history.history,(miss)?-histSign:histSign);
        end
        Jump: begin
          if (check.target != truePc) begin
            miss = True;
            check.history.target = truePc[39:2];
            check.history.seg = truePc[63:59];
          end
          // For a jump, use the history to indicate whether we used the simple
          // calculation or not. This would help if C0 is not 0.
          Int#(2) histSign = (check.history.history >= 0) ? 1:-1;
          check.history.history = boundedPlus(check.history.history,(miss)?-histSign:histSign);
        end
      endcase
      case (check.branchType)
        Branch, JumpReg, Jump: historyUpdate.enq(check);
      endcase
      if (miss && !flushNow) begin
        debug($display("Branch prediction miss! PC writeback %x != speculative PC %x at time:%t", truePc, check.target, $time));
        newEpoch.enq(epoch + 1);
        //trace($display("<C!%x e%x->e%x>", truePc[11:0], epoch, epoch+1));
      end else if (!flushNow) begin
        debug($display("Branch was correct for truePC %x, target %x, history %x at time:%t",
          truePc, check.target, check.history, $time));
        //trace($display("<C.%x e%x>", truePc[11:0], epoch));
      end else begin
        debug($display("Branch flushing to truePC %x at time:%t",
          truePc, $time));
        //trace($display("<CFlush%x e%x->e%x>", truePc[11:0], epoch, epoch+1));
      end
    end
    debug($display("Branch Writeback"));
    // Only update the epoch if this instruction is not dead..
    if (!dead) begin
      case (check.branchType)
        Branch:  cycReport($display("[>B%s]", (miss)?"M":"H"));
        Jump:    cycReport($display("[>J%s]", (miss)?"M":"H"));
        JumpReg: cycReport($display("[>R%s]", (miss)?"M":"H"));
      endcase
      if (flushNow) begin
        if (newEpoch.notEmpty) begin
          newEpoch.deq;
          epoch <= epoch + 2;
        end else begin
          epoch <= epoch + 1;
        end
      // This is the normal branch delay slot case. Only update the epoch if
      // there is something to update and if it is not from the debug unit.
      end else if (newEpoch.notEmpty && !fromDebug) begin
        epoch <= newEpoch.first;
        newEpoch.deq;
      end
    end
  endmethod

  method Epoch getEpoch;
    return epoch;
  endmethod

endmodule
