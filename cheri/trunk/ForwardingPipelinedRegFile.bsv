/*-
 * Copyright (c) 2010 Gregory A. Chadwick
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
import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;

//`define ReRegs 4

typedef Bit#(4) RenameReg; // A renamed destination register address, one of 4 in the current design

interface ForwardingPipelinedRegFileIfc#(type regType, numeric type renameRegs);
  method Action reqRegs(ReadReq req);
  // These two methods, getRegs and writeRegSpeculative should be called in the
  // same rule, Execute.
  method ActionValue#(ReadRegs#(regType)) readRegs();
  method Action writeRegSpeculative(regType data, Bool write);
  method Action writeReg(RegNum regW, regType data, Bool write, Bool committing);
  method Action writeRaw(RegNum regW, regType data);
  method ActionValue#(ReadRegs#(regType)) readRaw(RegNum regA, RegNum regB);
  method Action putDebugRegs(regType a, regType b);
endinterface

// Register file interface determines the number of rename registers.
typedef ForwardingPipelinedRegFileIfc#(MIPSReg, 4) MIPSRegFileIfc;

typedef struct {
  Bool    valid;
  regType register;
} SpecReg#(type regType) deriving (Bits, Eq);

typedef struct {
  Epoch  epoch;
  Bool   valid;
  RegNum regNum;
  Bool   pending;
} SpecRegTag deriving (Bits, Eq);

typedef struct {
  Epoch   epoch;
  RegNum  a;
  RegNum  b;
  Bool    write;
  Bool    pendingWrite;
  RegNum  dest;
  Bool    fromDebug;
  Bool    conditionalUpdate;
} ReadReq deriving (Bits, Eq);

typedef struct {
  Bool valid;
  Bool pending;
  RenameReg regNum;
} RenameReport deriving (Bits, Eq);

typedef struct {
  RenameReport a;
  RenameReport b;
  RenameReport old;
  ReadRegs#(regType) regFileVals;
  WriteReport write;
} RegReadReport#(type regType) deriving (Bits, Eq);

typedef struct {
  SpecReg#(regType)   specReg;
  RenameReg           regNum;
} RenameRegWrite#(type regType) deriving (Bits, Eq);

typedef struct {
  Bool    write;
  Bool    couldWrite;
  regType data;
  RegNum  regNum;
} RegWrite#(type regType) deriving (Bits, Eq);

typedef struct {
  regType regA;
  regType regB;
} ReadRegs#(type regType) deriving (Bits, Eq);

typedef struct {
  Bool      write;
  Bool      conditional;
  Bool      pending;
  RenameReg regNum;
} WriteReport deriving (Bits, Eq);

typedef enum {Init, Serving} RegFileState deriving (Bits, Eq);
//(* synthesize *)
module mkForwardingPipelinedRegFile(ForwardingPipelinedRegFileIfc#(regType,renameRegs))
  provisos(Bits#(regType, regType_sz));
  SpecRegTag initialTag = SpecRegTag{valid:False, epoch:?, regNum:?, pending:?};
  Reg#(Vector#(renameRegs,SpecRegTag)) rnTags         <- mkReg(replicate(initialTag));
  Reg#(Vector#(renameRegs,SpecReg#(regType))) rnRegs  <- mkReg(?);
  //RegFile#(RegNum,regType)          regFile        <- mkRegFile(0, 31); // BRAM
  RegFile3Port#(regType)   regFile                 <- mkRegFile3Port;

  FIFOF#(void)             limiter                 <- mkUGSizedFIFOF(valueOf(renameRegs));
  FIFOF#(ReadReq)          readReq                 <- mkFIFOF;
  FIFOF#(RegReadReport#(regType))    readReport    <- mkFIFOF;
  FIFOF#(WriteReport)      wbReRegWrite            <- mkSizedFIFOF(4);
  FIFO#(RegWrite#(regType)) writeback              <- mkLFIFO;

  FIFOF#(RenameRegWrite#(regType))   pendVal       <- mkUGFIFOF;
  Reg#(RenameReg)          nextReReg               <- mkReg(0);

  Reg#(regType)            debugOpA                <- mkRegU;
  Reg#(regType)            debugOpB                <- mkRegU;
  
  // speculativeWriteUsed forces a priority between the writePending rule and
  // the writeSpeculative method.
  Wire#(Bool)              speculativeWriteUsed    <- mkDWire(False);
  // These two wires force a priority of the pipelined read and write
  // methods over the raw versions to prevent extra ports being created
  // for the raw interfaces.
  Wire#(Bool)              writeRegUsed            <- mkDWire(False);
  Wire#(Bool)              readRegsUsed            <- mkDWire(False);

  rule readRegFiles(limiter.notFull);
    ReadReq rq = readReq.first;
    readReq.deq();

    ReadRegs#(regType) ret = ?;
    ret.regA <- regFile.readA(rq.a);
    ret.regB <- regFile.readB(rq.b);
    // signal that readRaw should not fire.
    readRegsUsed <= True;

    if (rq.fromDebug) begin
      if (rq.a==0) ret.regA = debugOpA;
      if (rq.b==0) ret.regB = debugOpB;
    end 

    // Detect any dependencies on renamed registers and setup for forwarding in
    // the readRegs method.
    RegReadReport#(regType) report = RegReadReport{
      a:   RenameReport{ valid: False, regNum: ?, pending: False },
      b:   RenameReport{ valid: False, regNum: ?, pending: False },
      old: RenameReport{ valid: False, regNum: ?, pending: False },
      regFileVals: ret,
      write: WriteReport{
        write: rq.write,
        conditional: rq.conditionalUpdate,
        regNum: nextReReg,
        pending: rq.pendingWrite
      }
    };

    Vector#(renameRegs, SpecRegTag) newReTags = rnTags;
    for (Integer i=0; i<valueOf(renameRegs); i=i+1) begin
      SpecRegTag srt = rnTags[i];
      RenameReport renameReport = RenameReport{
        valid: True,
        regNum: fromInteger(i),
        pending: srt.pending
      };
      if (srt.valid) begin
        if (srt.epoch == rq.epoch) begin
          if (srt.regNum == rq.a) begin
            report.a = renameReport;
            debug($display("Reading A from rereg %d", i));
          end
          if (srt.regNum == rq.b) begin
            report.b = renameReport;
            debug($display("Reading B from rereg %d", i));
          end
        end else begin
          // If the epoch is old, invalidate the record.
          newReTags[i].valid = False;
        end
        //Do we need to check r0? We didn't before
        if (rq.write && srt.regNum == rq.dest) begin
          if (srt.epoch == rq.epoch) begin
            report.old = renameReport;
            debug($display("Old Register is %d", i));
          end
          newReTags[i].valid = False;
        end
      end
    end
    if (rq.write) begin
      newReTags[nextReReg] = SpecRegTag{
        valid: True,
        regNum: rq.dest,
        epoch: rq.epoch,
        pending: rq.pendingWrite
      };
    end else begin
      newReTags[nextReReg].valid = False;
    end
    if (rq.write) begin
      nextReReg <= (nextReReg + 1 == fromInteger(valueOf(renameRegs))) ? 0:nextReReg + 1;
      limiter.enq(?);
      //$display("rereg enqueued");
    end 
    rnTags <= newReTags;
    readReport.enq(report);
  endrule

  // Some booleans to help with composing the conditions for the readRegs method.
  // ReadRegs needs to wait until any pending operands that it needs are ready.
  RegReadReport#(regType) topRpt = readReport.first;
  Bool a_is_pending = topRpt.a.valid &&
                      topRpt.a.pending &&
                      !rnRegs[topRpt.a.regNum].valid;
  Bool b_is_pending = topRpt.b.valid &&
                      topRpt.b.pending &&
                      !rnRegs[topRpt.b.regNum].valid;
  Bool old_is_pending = topRpt.write.conditional &&
                        topRpt.old.pending &&
                        !rnRegs[topRpt.old.regNum].valid;
  Bool a_is_ready = pendVal.notEmpty &&
                    pendVal.first.regNum == topRpt.a.regNum;
  Bool b_is_ready = pendVal.notEmpty &&
                    pendVal.first.regNum == topRpt.b.regNum;
  Bool old_is_ready = pendVal.notEmpty &&
                      pendVal.first.regNum == topRpt.old.regNum;
  Bool pipeEmpty = !wbReRegWrite.notEmpty && !pendVal.notEmpty;
  Bool read_is_ready = ((!a_is_pending || a_is_ready) &&
                        (!b_is_pending || b_is_ready) &&
                        (!old_is_pending || old_is_ready)) ||
                        pipeEmpty;

  rule writePending(pendVal.notEmpty && !speculativeWriteUsed);
    Vector#(renameRegs, SpecReg#(regType)) newRnRegs = rnRegs;
    newRnRegs[pendVal.first.regNum] = pendVal.first.specReg;
    pendVal.deq();
    rnRegs <= newRnRegs;
    debug($display("wrote pending in dedicated rule"));
  endrule

/*
  rule doRegisterWrite;
    RegWrite rw = writeback.first;
    writeback.deq();
    if (rw.write) begin
      regFile.write(rw.regNum,rw.data);
      debug($display("Wrote register %d", writeback.first.regNum));
    end
    if (rw.couldWrite) limiter.deq();
  endrule
*/

  method Action reqRegs(ReadReq req);
    readReq.enq(req);
  endmethod

  method ActionValue#(ReadRegs#(regType)) readRegs() if (read_is_ready);
    RegReadReport#(regType) report = readReport.first(); //Dequeued by writeRegSpeculative
    ReadRegs#(regType) ret = report.regFileVals;
    // Return renamed register values if necessary
    if (report.a.valid) begin
      if (rnRegs[report.a.regNum].valid) ret.regA = rnRegs[report.a.regNum].register;
      else if (a_is_ready) ret.regA = pendVal.first.specReg.register;
    end
    if (report.b.valid) begin
      if (rnRegs[report.b.regNum].valid) ret.regB = rnRegs[report.b.regNum].register;
      else if (b_is_ready) ret.regB = pendVal.first.specReg.register;
    end
    return ret;
  endmethod

  method Action writeRegSpeculative(regType data, Bool write);
    Vector#(renameRegs, SpecReg#(regType)) newRnRegs = rnRegs;
    WriteReport  req = readReport.first.write;
    RenameReport old = readReport.first.old;
    readReport.deq();
    // Roll in pending write
    if (pendVal.notEmpty) begin
      newRnRegs[pendVal.first.regNum] = pendVal.first.specReg;
      debug($display("wrote pending in write speculative"));
      pendVal.deq();
    end
    // Update rename registers with this write value.
    SpecReg#(regType) regWrite = SpecReg{ register: ?, valid: False };
    if (write) begin
      regWrite = SpecReg{ register: data, valid: !req.pending };
    end else if (req.write && old.valid) begin
      regWrite = newRnRegs[old.regNum];
      debug($display("Copying old register value %x", regWrite.register));
    end
    newRnRegs[req.regNum] = regWrite;
    rnRegs <= newRnRegs;
    wbReRegWrite.enq(req);
    speculativeWriteUsed <= True;
  endmethod

  method Action writeReg(RegNum regW, regType data, Bool write, Bool committing) if (pendVal.notFull);
    Bool doWrite = (write && committing);
    //Bool couldWrite = wbReRegWrite.first.write;
    // Do the BRAM write in the next cycle for frequency.
    //writeback.enq(RegWrite{ write: doWrite, couldWrite: couldWrite, data: data, regNum: regW});
    if (doWrite) begin
      regFile.write(regW,data);
      debug($display("Wrote register %d", regW));
    end
    if (wbReRegWrite.first.write) limiter.deq();
    if (wbReRegWrite.first.pending && doWrite) begin
      pendVal.enq(RenameRegWrite{
        specReg: SpecReg{ valid: True, register: data },
        regNum: wbReRegWrite.first.regNum
      });
    end
    wbReRegWrite.deq();
    writeRegUsed <= True;
  endmethod
  
  method Action writeRaw(RegNum regW, regType data) if (!writeRegUsed);
    regFile.write(regW,data);
  endmethod
  
  method ActionValue#(ReadRegs#(regType)) readRaw(RegNum regA, RegNum regB) if (!readRegsUsed);
    ReadRegs#(regType) ret = ?;
    ret.regA <- regFile.readA(regA);
    ret.regB <- regFile.readB(regB);
    return ret;
  endmethod

  method Action putDebugRegs(regType a, regType b);
    debugOpA <= a;
    debugOpB <= b;
  endmethod

endmodule


interface RegFile3Port#(type regType);
  method Action  write(RegNum regW, regType data);
  method ActionValue#(regType) readA(RegNum regNum);
  method ActionValue#(regType) readB(RegNum regNum);
endinterface

module mkRegFile3Port(RegFile3Port#(regType))
  provisos(Bits#(regType, regType_sz));
  RegFile#(RegNum,regType) regFile <- mkRegFile(0, 31); // BRAM
  Reg#(Bool) dummyA <- mkReg(False);
  Reg#(Bool) dummyB <- mkReg(False);
  
  method Action write(RegNum regW, regType data);
    regFile.upd(regW,data);
  endmethod
  method ActionValue#(regType) readA(RegNum regNum);
    dummyA <= !dummyA;
    return regFile.sub(regNum);
  endmethod
  method ActionValue#(regType) readB(RegNum regNum);
    dummyB <= !dummyB;
    return regFile.sub(regNum);
  endmethod
endmodule

