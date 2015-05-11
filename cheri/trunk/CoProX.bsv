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

import ClientServer::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import RegFile::*;
import ConfigReg::*;

typedef struct {
  CoProInst coProInst; // Instruction passed in
  RegNum    regNumA;      // Coprocessor operand A
  RegNum    regNumB;      // Coprocessor operand B
} CoProInstToken deriving(Bits, Eq);

typedef struct {
  CoProXOp  op;            // Operation, should be either Load or Store
  CoProReg  storeCoProReg; // Coprocessor register to store
  Exception exception;     //
  Address   address;       // Virtual Address to Load or Store
  RegNum    loadReg;       // Register to load value into.
  InstId    instId;        // instruction ID
} CoProMemInst deriving(Bits, Eq);

typedef struct {
  Bool     valid;  // A valid pending writeback
  CoProReg value;  // Coprocessor register to be written
  RegNum   regNum; // Coprocessor register to be written
  InstId   instId; // Instruction ID that requests the update
} CoProWriteback deriving(Bits, Eq);

typedef struct {
  CoProXOp op;     // Operation causing the writeback
  InstId   instId; // Instruction ID that requests the update
  Bool     valid;  // Whether we should actually write back
} CoProWritebackTag deriving(Bits, Eq);

typedef enum {MemorySend, MemoryResponse, Ready} CoProState deriving (Bits, Eq);

module mkCoPro(CoProIfc);
  Vector#(4, RegFile#(RegNum, Bit#(64))) regFile <- replicateM(mkRegFile(0, 31));
  FIFOF#(CoProInstToken) coProInsts <- mkSizedFIFOF(4);
  FIFO#(RegNum)          fetchFifoA <- mkSizedFIFO(4);
  FIFO#(RegNum)          fetchFifoB <- mkSizedFIFO(4);
  // Writeback is controlled by 2 FIFOs. Every instruction enqs to
  // coProWritebackTags, which deqs in writeback.
  // Instructions that actually write a coprocessor register enq to coProWriteback.
  // Once a second writeback value is enqed, the pipeline stalls until the first
  // is written back.
  FIFOF#(Bool)             nextWillWriteback    <- mkFIFOF;
  Reg#(CoProWriteback)     coProWriteback       <- mkConfigReg(?);
  FIFO#(CoProWritebackTag) coProWritebackTags   <- mkFIFO;
  FIFOF#(CoProMemInst)     coProMemInsts        <- mkFIFOF1;
  FIFO#(Bool)              commitStore          <- mkFIFO;
  FIFO#(Bool)              commitWritebackFifo  <- mkBypassFIFO;
  FIFO#(CoProMemAccess)    memAccesses          <- mkFIFO1;
  FIFOF#(CoProReg)         memResponse          <- mkUGFIFOF;
  Reg#(CoProState)         coProState           <- mkConfigReg(Ready);
  FIFOF#(CoProState)       nextCoProState       <- mkUGFIFOF();
  Reg#(UInt#(5))           count                <- mkReg(0);
  Reg#(UInt#(5))           regUpdatesIn         <- mkConfigReg(0);
  Reg#(UInt#(5))           regUpdatesCalculated <- mkConfigReg(0);
  Reg#(UInt#(5))           regUpdatesDone       <- mkConfigReg(0);

  rule coProMemoryLoad(coProState == MemorySend && coProMemInsts.first.op == Load);
    CoProMemInst coProMemInst = coProMemInsts.first();
    Address addr = coProMemInst.address;
    case (coProMemInst.op)
      Load: begin // Load Coprocessor Register
        memAccesses.enq(CoProMemAccess{
          memOp: Read,
          address: addr,
          coProReg: ?
        });
        trace($display("CoProcessor Load from %x", addr));
      end
    endcase
    coProState <= MemoryResponse;
  endrule
  // CoProMemoryStore will wait until commitStore is enqued by commitWriteback
  rule coProMemoryStore((coProState == Ready || coProState == MemorySend) && coProMemInsts.first.op == Store);
    CoProMemInst coProMemInst = coProMemInsts.first();
    Address addr = coProMemInst.address;

    if (commitStore.first()) begin
      case (coProMemInst.op)
        Store: begin // Store Coprocessor Register
          memAccesses.enq(CoProMemAccess{
            memOp: Write,
            address: addr,
            coProReg: coProMemInst.storeCoProReg
          });
          CoProReg dc = coProMemInst.storeCoProReg;
          trace($display("Address %x <- CoProReg %d, 0x%x",
            addr, coProMemInst.loadReg, dc));
        end
      endcase
    end
    coProMemInsts.deq();
    commitStore.deq();
  endrule

  rule writeCoProState(coProState == Ready);
    if (nextCoProState.notEmpty) begin
      coProState <= nextCoProState.first;
      nextCoProState.deq;
    end
  endrule

  rule writeBack;
    commitWritebackFifo.deq;
    CoProReg writeback = coProWriteback.value;
    RegNum regNum = coProWriteback.regNum;
    for(Integer i = 0; i < 4; i =i+1) regFile[i].upd(pack(regNum), writeback[63+64*i:64*i]);
    trace($display("%t - CoProReg %d <- 0x%x",
      $time(), regNum, writeback));
  endrule

  method Action putCoProInst(coProInst) if (coProState == Ready && (regUpdatesIn - regUpdatesDone <= 2));
    Maybe#(RegNum) fetchA = tagged Invalid;
    Maybe#(RegNum) fetchB = tagged Invalid;
    CoProState newCoProState = Ready;
    Bool writeback = False;
    case (coProInst.op)
      MFC, DMFC: begin // Move From Coprocessor Register Field
        fetchA = tagged Valid coProInst.regNumA;
      end
      MTC, DMTC: begin // Move to Coprocessor Register Field
        fetchA = tagged Valid coProInst.regNumA;
        writeback = True;
      end
      Store: begin // Store Coprocessor Register
        fetchB = tagged Valid coProInst.regNumB;
      end
      Load: begin // Load Coprocessor Register
        newCoProState = MemorySend;
        writeback = True;
      end
      None: begin
        fetchA = tagged Valid 0;
      end
    endcase
    // Throw exceptions if improper registers are read, but always fetch to avoid stalls.
    CoProInstToken token = CoProInstToken{coProInst: coProInst, regNumA: fromMaybe(0,fetchA), regNumB: fromMaybe(0,fetchB)};
    coProInsts.enq(token);
    // These are seperated from the previous values becuase they are used as
    // addresses for the RegFile constructs.  Using dedicated fifos for
    // addresses may improve the ability to infer them as BRAMs.
    fetchFifoA.enq(token.regNumA);
    fetchFifoB.enq(token.regNumB);
    debug($display("%t Selecting to fetch CoProRegA=%d and CoProRegB=%d for instId=%d", $time(), fromMaybe(0,fetchA), fromMaybe(0,fetchB), coProInst.instId));
    nextCoProState.enq(newCoProState);
    if (writeback) begin
      regUpdatesIn <= regUpdatesIn + 1;
    end
    nextWillWriteback.enq(writeback);

    if (coProInst.op != None) begin
      debug($display("Use CoPro Request. op=%x, regA=%x regB=%x immediate=%x At time %d", coProInst.op, coProInst.regNumA, coProInst.regNumB, coProInst.imm, $time));
    end
  endmethod

  method ActionValue#(CoProResponse) getCoProResponse(CoProVals coProVals) if ((coProState == Ready || coProState == MemorySend) && (!nextWillWriteback.first || regUpdatesCalculated == regUpdatesDone));
    actionvalue
      CoProInst coProInst = coProInsts.first.coProInst;
      coProInsts.deq();
      MIPSReg opA = coProVals.opA;
      MIPSReg opB = coProVals.opB;
      // Prepare an address in case we do a Load or Store
      // Cast immediate and opA to do a signed offset.
      Int#(11) offset = unpack({coProInst.imm,5'b0});
      Int#(65) base = unpack({1'b0,opA});
      Address addr = (pack(base+signExtend(offset)))[63:0];
      // Prepare the coprocessor register operands
      RegNum regNumA = coProInsts.first.regNumA;
      RegNum regNumB = coProInsts.first.regNumB;
      // regNumA either takes the forwarded value or the value from the register file.
      CoProReg regA = {
        regFile[3].sub(fetchFifoA.first),
        regFile[2].sub(fetchFifoA.first),
        regFile[1].sub(fetchFifoA.first),
        regFile[0].sub(fetchFifoA.first)
      };
      fetchFifoA.deq();
      CoProReg regB = {
        regFile[3].sub(fetchFifoB.first),
        regFile[2].sub(fetchFifoB.first),
        regFile[1].sub(fetchFifoB.first),
        regFile[0].sub(fetchFifoB.first)
      };
      fetchFifoB.deq();
      nextWillWriteback.deq;
      debug($display("%t - regNumA(%d)==writeReg(%d)?", $time(), regNumA, coProWriteback.regNum));
      if (regNumA == coProWriteback.regNum && coProWriteback.valid) begin
        regA = coProWriteback.value;
        debug($display("regA is forwarded! regNumA: 0x%x", regNumA, regA));
      end
      // regB either takes the forwarded value or the value from the register file.
      debug($display("%t - regNumB(%d)==writeReg(%d)?", $time(), regNumB, coProWriteback.regNum));
      if (regNumB == coProWriteback.regNum && coProWriteback.valid) begin
        regB = coProWriteback.value;
        debug($display("regB is forwarded! regNumB: 0x%x", regNumB, regB));
      end
      Maybe#(RegNum) wbReg = tagged Invalid;
      CoProReg writeback = regA;
      CoProResponse retVal = CoProResponse{valid: False, data: ?, exception: None};
      case (coProInst.op)
        MTC: begin // Move Word to Coprocessor Register Field
          case(coProInst.imm[2:0])
            0: writeback[31:0] = opA[31:0];
            1: writeback[63:32] = opA[31:0];
            2: writeback[95:64] = opA[31:0];
            3: writeback[127:96] = opA[31:0];
            4: writeback[159:128] = opA[31:0];
            5: writeback[191:160] = opA[31:0];
            6: writeback[223:192] = opA[31:0];
            7: writeback[255:224] = opA[31:0];
          endcase
          wbReg = tagged Valid coProInst.regNumA;
        end
        DMTC: begin // Move Double to Coprocessor Register Field
          case(coProInst.imm[2:0])
            0,1: writeback[63:0] = opA;
            2,3: writeback[127:64] = opA;
            4,5: writeback[191:128] = opA;
            6,7: writeback[255:192] = opA;
          endcase
          wbReg = tagged Valid coProInst.regNumA;
        end
        MFC: begin // Move Word From Coprocessor Register Field
          case(coProInst.imm[2:0])
            0: retVal.data = signExtend(regB[31:0]);
            1: retVal.data = signExtend(regB[63:32]);
            2: retVal.data = signExtend(regB[95:64]);
            3: retVal.data = signExtend(regB[127:96]);
            4: retVal.data = signExtend(regB[159:128]);
            5: retVal.data = signExtend(regB[191:160]);
            6: retVal.data = signExtend(regB[223:192]);
            7: retVal.data = signExtend(regB[255:224]);
          endcase
          retVal.valid = True;
        end
        DMFC: begin // Move Double From Coprocessor Register Field
          case(coProInst.imm[2:0])
            0,1: retVal.data = signExtend(regB[63:0]);
            2,3: retVal.data = signExtend(regB[127:64]);
            4,5: retVal.data = signExtend(regB[191:128]);
            6,7: retVal.data = signExtend(regB[255:192]);
          endcase
          retVal.valid = True;
        end
        Load: begin // Load Coprocessor Register
          coProMemInsts.enq(CoProMemInst{
            op: Load,
            storeCoProReg: ?,
            address: addr,
            loadReg: coProInst.regNumDest,
            exception: None,
            instId: coProInst.instId
          });
          debug($display("Doing a Coprocessor Load"));
        end
        Store: begin // Store Coprocessor Register
          coProMemInsts.enq(CoProMemInst{
            op: Store,
            storeCoProReg: regB,
            address: addr,
            loadReg: regNumB,  // default value, not used
            exception: None,
            instId: coProInst.instId
          });
          debug($display("Doing a Coprocessor Store"));
        end
      endcase

      if (coProInst.op != None) begin
        debug($display("Use CoPro Response. op=%x, regA=%x regB=%x immediate=%x retVal.isValid=%d retVal=%x At time %d", coProInst.op, coProInst.regNumA, coProInst.regNumB, coProInst.imm, retVal.valid, retVal.data, $time));
      end
      // Prepare a null writeback value in case we need a null writeback.
      CoProWritebackTag coProWritebackTagVal = CoProWritebackTag{
        op: coProInst.op,
        instId: coProInst.instId,
        valid: False
      };
      if (wbReg matches tagged Valid .regNum) begin
        coProWriteback <= CoProWriteback{
          valid: True,
          value: writeback,
          regNum: regNum,
          instId: coProInst.instId
        };
        coProWritebackTagVal.valid = True;
        debug($display("%t - Put in CoProWriteback. Reg=%d, instID=%d, CAP 0x%x",
          $time(), regNum, coProInst.instId, writeback));
        regUpdatesCalculated <= regUpdatesCalculated + 1;
      end
      debug($display("Use CoPro Update. op=%x, regA=%x regB=%x immediate=%x At time %d",
        coProInst.op, coProInst.regNumA, coProInst.regNumB, coProInst.imm, $time));

      // In the Load case, the writeback is committed later.
      if (coProInst.op != Load) begin
        coProWritebackTags.enq(coProWritebackTagVal);
      end
      return retVal;
    endactionvalue
  endmethod

  interface Client coProMem;
    interface Get request;
      method ActionValue#(CoProMemAccess) get();
        debug($display("Delivering Memory Request from CoProCop."));
        memAccesses.deq;
        return memAccesses.first();
      endmethod
    endinterface
    interface Put response;
      method Action put(CoProReg coProReg) if (memResponse.notFull && coProMemInsts.notEmpty && coProState == MemoryResponse);
        CoProReg writeback = coProReg;
        CoProMemInst coProMemInst = coProMemInsts.first;
        RegNum regNum = coProMemInst.loadReg;
        CoProWritebackTag coProWritebackTagVal = CoProWritebackTag{
          op: coProMemInst.op,
          instId: coProMemInst.instId,
          valid: False
        };
        CoProWriteback writebackReg = CoProWriteback{
          valid: False,
          value: writeback,
          regNum: regNum,
          instId: coProMemInst.instId
        };
        writebackReg.valid = True;
        coProWritebackTagVal.valid = True;
        debug($display("Recieving Memory Response in Coprocessor."));
        coProWritebackTags.enq(coProWritebackTagVal);
        coProWriteback <= writebackReg;
        coProMemInsts.deq();
        coProState <= Ready;
        regUpdatesCalculated <= regUpdatesCalculated + 1;
      endmethod
    endinterface
  endinterface

  method Action commitWriteback(CoProWritebackRequest wbReq);
    if (wbReq.instId == coProWritebackTags.first.instId) begin
      if (coProWritebackTags.first.valid && coProWritebackTags.first.instId == coProWriteback.instId) begin
        regUpdatesDone <= regUpdatesDone + 1;
        if (wbReq.commit) begin
          commitWritebackFifo.enq(True);
        end else begin
          CoProReg writeback = coProWriteback.value;
          RegNum regNum = coProWriteback.regNum;
          trace($display("%t -  CANCELED CoProReg %d <- 0x%x", $time(), regNum, writeback));
        end
      end
      // If the operation was a coprocessor store, commit the store.
      if (coProWritebackTags.first.op == Store) begin
        debug($display("Committing to a Coprocessor Store"));
        commitStore.enq(wbReq.commit);
      end
      coProWritebackTags.deq();
    end
    debug($display("CoProCop Writeback, instID:%d==coProWBTags.id:%d, coProWBTags.valid:%d, coProWB.first.instID:%d", wbReq.instId, coProWritebackTags.first.instId, coProWritebackTags.first.valid, coProWriteback.instId));
  endmethod
endmodule
