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

typedef Bit#(TLog#(renameRegs)) RenameReg#(numeric type renameRegs); // A renamed destination register address, one of 4 in the current design
typedef Bit#(TLog#(renameRegs)) RenameTag#(numeric type renameRegs);

// Register file interface determines the number of rename registers.
typedef ForwardingPipelinedRegFileIfc#(MIPSReg, 8) MIPSRegFileIfc;

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

typedef struct {
  Bool    valid;
  Bool    pending;
  regType register;
} SpecReg#(type regType) deriving (Bits, Eq);

typedef struct {
  Epoch  epoch;
  Bool   valid;
  RegNum regNum;
  RenameReg#(renameRegs) renameReg;
  Bool   pending;
  RenameReg#(renameRegs) age;
} SpecRegTag#(numeric type renameRegs) deriving (Bits, Eq);

typedef struct {
  Bool    valid;
  RegNum  regNum;
  regType register;
} CachedReg#(type regType) deriving (Bits, Eq);

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
  RenameReg#(renameRegs) regNum;
} RenameReport#(numeric type renameRegs) deriving (Bits, Eq);

typedef struct {
  RenameReport#(renameRegs) a;
  RenameReport#(renameRegs) b;
  RenameReport#(renameRegs) old;
  ReadRegs#(regType) regFileVals;
  ReadReq     rq;
  WriteReport#(renameRegs) write;
} RegReadReport#(type regType, numeric type renameRegs) deriving (Bits, Eq);

typedef struct {
  SpecReg#(regType)       specReg;
  RenameReg#(renameRegs)  renameReg;
} RenameRegWrite#(type regType, numeric type renameRegs) deriving (Bits, Eq);

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
  Bool                    write;
  Bool                    conditional;
  Bool                    pending;
  Bool                    usedNewReReg;
  RenameTag#(renameRegs)  tagReg;
  RenameReg#(renameRegs)  renameReg;
} WriteReport#(numeric type renameRegs) deriving (Bits, Eq);

typedef enum {Init, Serving} RegFileState deriving (Bits, Eq);
module mkForwardingPipelinedRegFileHighFrequency(ForwardingPipelinedRegFileIfc#(regType,renameRegs))
  provisos(Bits#(regType, regType_sz),IsModule#(_m__, _c__),
           Add#(a__, TLog#(renameRegs), 5));
  
  Vector#(renameRegs,SpecRegTag#(renameRegs)) initRnTags = ?;
  for (Integer i=0; i<valueOf(renameRegs); i=i+1)
    initRnTags[i] = SpecRegTag{valid:False, epoch:?, regNum:?, pending:?, renameReg: fromInteger(i), age: 0};
  Reg#(Vector#(renameRegs,SpecRegTag#(renameRegs))) rnTags  <- mkReg(initRnTags);
  Reg#(Vector#(renameRegs,SpecReg#(regType)))       rnRegs  <- mkReg(?);
  
  CachedReg#(regType) initialChReg = CachedReg{valid:False, regNum:?, register: ?};
  Reg#(Vector#(renameRegs,CachedReg#(regType))) chRegs  <- mkReg(replicate(initialChReg));
  //RegFile#(RegNum,regType)          regFile        <- mkRegFile(0, 31); // BRAM
  RegFile3Port#(regType)                        regFile       <- mkRegFile3Port;

  FIFOF#(void)                                  limiter       <- mkUGSizedFIFOF(valueOf(renameRegs));
  FIFO#(ReadReq)                                readReq       <- mkFIFO;
  FIFO#(RegReadReport#(regType, renameRegs))    skipReadReq   <- mkBypassFIFO;
  FIFO#(RegReadReport#(regType, renameRegs))    bramReadReq   <- mkFIFO;
  FIFO#(RegReadReport#(regType, renameRegs))    readReport    <- mkFIFO;
  FIFOF#(WriteReport#(renameRegs))              wbReRegWrite  <- mkSizedFIFOF(4);
  FIFO#(RegWrite#(regType))                     writeback     <- mkLFIFO;

  FIFOF#(RenameRegWrite#(regType,renameRegs))   pendVal       <- mkUGFIFOF;

  Reg#(regType)                                 debugOpA      <- mkRegU;
  Reg#(regType)                                 debugOpB      <- mkRegU;
  
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

    // Detect any dependencies on renamed registers and setup for forwarding in
    // the readRegs method.
    RegReadReport#(regType, renameRegs) report = RegReadReport{
      a:   RenameReport{ valid: False, regNum: ?, pending: False },
      b:   RenameReport{ valid: False, regNum: ?, pending: False },
      old: RenameReport{ valid: False, regNum: ?, pending: False },
      rq: rq,
      regFileVals: ReadRegs{regA: unpack(0), regB: unpack(0)},
      write: WriteReport{
        write: rq.write,
        conditional: rq.conditionalUpdate,
        tagReg: ?,
        renameReg: ?,
        usedNewReReg: rq.write,
        pending: rq.pendingWrite
      }
    };
    RenameReg#(renameRegs) idx;
    Vector#(renameRegs, SpecRegTag#(renameRegs)) newReTags = rnTags;
    Bool destSet = (rq.write) ? False:True;
    for (Integer i=0; i<valueOf(renameRegs); i=i+1) begin
      SpecRegTag#(renameRegs) srt = newReTags[i];
      idx = srt.renameReg;
      RenameReport#(renameRegs) renameReport = RenameReport{
        valid: True,
        regNum: idx,
        pending: srt.pending
      };
      if (srt.valid) begin
        if (srt.epoch == rq.epoch) begin
          if (srt.regNum == rq.a) begin
            report.a = renameReport;
            debug($display("%t Reading A from specreg %d", $time, idx));
          end
          if (srt.regNum == rq.b) begin
            report.b = renameReport;
            debug($display("%t Reading B from specreg %d", $time, idx));
          end
        end else begin
          // If the epoch is old, invalidate the record.
          newReTags[i].valid = False;
        end
        if (rq.write && srt.regNum == rq.dest) begin
          if (srt.epoch == rq.epoch) begin
            report.old = renameReport;
            debug($display("%t Old Register is %d", $time, idx));
          end
          report.write.tagReg = fromInteger(i);
          report.write.renameReg = srt.renameReg;
          debug($display("%t Reusing Rename Register %d for destination", $time, idx));
          if (srt.age!=0) report.write.usedNewReReg = False;
          destSet = True;
        end
      end
    end
    if (rq.write && destSet == False) begin
      for (Integer i=0; i<valueOf(renameRegs); i=i+1) begin
        if (newReTags[i].age==0 || !newReTags[i].valid) begin
          report.write.tagReg = fromInteger(i);
          report.write.renameReg = newReTags[i].renameReg;
          destSet = True;
        end
      end
    end
    for (Integer i=0; i<valueOf(renameRegs); i=i+1)
      if (newReTags[i].age!=0) newReTags[i].age = newReTags[i].age-1;
    if (!report.a.valid) debug($display("%t Fetching %d from Register File", $time, rq.a));
    if (!report.b.valid) debug($display("%t Fetching %d from Register File", $time, rq.b));
    if (!destSet) $display(" Panic!  No destination! ");
    if (rq.write) begin
      newReTags[report.write.tagReg] = SpecRegTag{
        valid: True,
        regNum: rq.dest,
        epoch: rq.epoch,
        pending: rq.pendingWrite,
        renameReg: newReTags[report.write.tagReg].renameReg,
        age: fromInteger(valueOf(renameRegs)-1)
      };
    end
    if (report.write.usedNewReReg) begin
      limiter.enq(?);
      //$display("%t specreg enqueued");
    end 
    rnTags <= rotate(newReTags);
    
    // Furthermore, check if the registers that do need to be fetched are in
    // the cache of registers that have recently been read.
    Bool usedCachedA = False;
    idx = truncate(rq.a);
    if (chRegs[idx].valid && chRegs[idx].regNum == rq.a) begin
      report.regFileVals.regA = chRegs[idx].register;
      usedCachedA = True;
    end else if (rq.fromDebug && rq.a==0) begin
      report.regFileVals.regA = debugOpA;
      usedCachedA = True;
    end
    Bool usedCachedB = False;
    idx = truncate(rq.b);
    if (chRegs[idx].valid && chRegs[idx].regNum == rq.b) begin
      report.regFileVals.regB = chRegs[idx].register;
      usedCachedB = True;
    end else if (rq.fromDebug && rq.b==0) begin
      report.regFileVals.regB = debugOpB;
      usedCachedB = True;
    end
    
    // Skip the BRAM lookup if the operands are in rename registers.
    Bool skipBRAMLookup = (report.a.valid || usedCachedA) && 
                          (report.b.valid || usedCachedB) &&
                          !rq.conditionalUpdate;
    if (skipBRAMLookup) skipReadReq.enq(report);
    else                bramReadReq.enq(report);
  endrule
  
  (* descending_urgency = "doBRAMRead,skipBRAMRead" *)
  // Skip architectural lookup, we have the operands in rename registers.
  rule skipBRAMRead;
    debug($display("%t Skipped BRAM Read in RegFile", $time));
    RegReadReport#(regType, renameRegs) report = skipReadReq.first;
    skipReadReq.deq;
    RenameReg#(renameRegs) idx = truncate(report.rq.dest);
    Vector#(renameRegs,CachedReg#(regType)) newChRegs = chRegs;
    if (report.write.write && report.rq.dest == newChRegs[idx].regNum)
      chRegs[idx] <= initialChReg;
    readReport.enq(report);
  endrule
  // Actually do regitser lookup
  rule doBRAMRead;
    debug($display("%t Did Full BRAM Read in RegFile", $time));
    RegReadReport#(regType, renameRegs) report = bramReadReq.first;
    bramReadReq.deq;
    report.regFileVals.regA <- regFile.readA(report.rq.a);
    report.regFileVals.regB <- regFile.readB(report.rq.b);
    Vector#(renameRegs,CachedReg#(regType)) newChRegs = chRegs;
    RenameReg#(renameRegs) idx = truncate(report.rq.a);
    if (!report.a.valid) newChRegs[idx] = CachedReg{
            valid: True, 
            regNum: report.rq.a, 
            register: report.regFileVals.regA
          };
    idx = truncate(report.rq.b);
    if (!report.b.valid) newChRegs[idx] = CachedReg{
            valid: True, 
            regNum: report.rq.b, 
            register: report.regFileVals.regB
          };
    idx = truncate(report.rq.dest);
    if (report.write.write && report.rq.dest == newChRegs[idx].regNum)
      newChRegs[idx] = initialChReg;
    chRegs <= newChRegs;
    // signal that readRaw should not fire.
    readRegsUsed <= True;
    readReport.enq(report);
  endrule

  // Some booleans to help with composing the conditions for the readRegs method.
  // ReadRegs needs to wait until any pending operands that it needs are ready.
  RegReadReport#(regType, renameRegs) topRpt = readReport.first;
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
                    pendVal.first.renameReg == topRpt.a.regNum;
  Bool b_is_ready = pendVal.notEmpty &&
                    pendVal.first.renameReg == topRpt.b.regNum;
  Bool old_is_ready = pendVal.notEmpty &&
                      pendVal.first.renameReg == topRpt.old.regNum;
  Bool pipeEmpty = !wbReRegWrite.notEmpty && !pendVal.notEmpty;
  Bool read_is_ready = ((!a_is_pending || a_is_ready) &&
                        (!b_is_pending || b_is_ready) &&
                        (!old_is_pending || old_is_ready)) ||
                        pipeEmpty;

  rule writePending(pendVal.notEmpty && !speculativeWriteUsed);
    Vector#(renameRegs, SpecReg#(regType)) newRnRegs = rnRegs;
    if (newRnRegs[pendVal.first.renameReg].pending)
        newRnRegs[pendVal.first.renameReg] = pendVal.first.specReg;
    pendVal.deq();
    rnRegs <= newRnRegs;
    debug($display("%t wrote pending in dedicated rule"));
  endrule


  rule doRegisterWrite;
    RegWrite#(regType) rw = writeback.first;
    writeback.deq();
    if (rw.write) begin
      regFile.write(rw.regNum,rw.data);
      debug($display("%t Wrote register %d", $time, writeback.first.regNum));
    end
    if (rw.couldWrite) limiter.deq();
  endrule


  method Action reqRegs(ReadReq req);
    readReq.enq(req);
  endmethod

  method ActionValue#(ReadRegs#(regType)) readRegs() if (read_is_ready);
    RegReadReport#(regType, renameRegs) report = readReport.first(); //Dequeued by writeRegSpeculative
    ReadRegs#(regType) ret = report.regFileVals;
    
    // Return renamed register values if necessary
    if (report.a.valid) begin
      if (rnRegs[report.a.regNum].valid) begin
        ret.regA = rnRegs[report.a.regNum].register;
        debug($display("%t read A specreg %d : %x", $time, report.a.regNum, ret.regA));
      end else if (a_is_ready) begin
        ret.regA = pendVal.first.specReg.register;
      end
    end
    if (report.b.valid) begin
      if (rnRegs[report.b.regNum].valid) begin
        ret.regB = rnRegs[report.b.regNum].register;
        debug($display("%t read B specreg %d : %x", $time, report.b.regNum, ret.regB));
      end else if (b_is_ready) begin
        ret.regB = pendVal.first.specReg.register;
      end
    end
    return ret;
  endmethod

  method Action writeRegSpeculative(regType data, Bool write);
    Vector#(renameRegs, SpecReg#(regType)) newRnRegs = rnRegs;
    WriteReport#(renameRegs)  req = readReport.first.write;
    RenameReport#(renameRegs) old = readReport.first.old;
    readReport.deq();
    // Roll in pending write
    if (pendVal.notEmpty) begin
      if (newRnRegs[pendVal.first.renameReg].pending)
        newRnRegs[pendVal.first.renameReg] = pendVal.first.specReg;
      debug($display("%t wrote pending to specreg %d in write speculative %x", $time, pendVal.first.renameReg, pendVal.first.specReg));
      pendVal.deq();
    end
    if (write) begin
      newRnRegs[req.renameReg] = SpecReg{ register: data, valid: !req.pending, pending: req.pending };
      debug($display("%t wrote specreg %d with %x", $time, req.renameReg, data));
    end /*else if (req.write && old.valid) begin
      regWrite = newRnRegs[old.regNum];
      debug($display("%t Copying old register value %x", $time, regWrite.register));
    end*/ else if (req.write && !old.valid) begin
      newRnRegs[req.renameReg].valid = False;
    end
    //newRnRegs[req.regNum] = regWrite;
    rnRegs <= newRnRegs;
    wbReRegWrite.enq(req);
    speculativeWriteUsed <= True;
  endmethod

  method Action writeReg(RegNum regW, regType data, Bool write, Bool committing) if (pendVal.notFull);
    Bool doWrite = (write && committing);
    Bool couldWrite = wbReRegWrite.first.usedNewReReg;
    // Do the BRAM write in the next cycle for frequency.
    writeback.enq(RegWrite{ write: doWrite, couldWrite: couldWrite, data: data, regNum: regW});
    /*if (doWrite) begin
      regFile.write(regW,data);
      debug($display("%t Wrote register %d", $time, regW));
    end
    if (wbReRegWrite.first.usedNewReReg) limiter.deq();*/
    if (wbReRegWrite.first.pending && doWrite) begin
      pendVal.enq(RenameRegWrite{
        specReg: SpecReg{ valid: True, register: data, pending: True },
        renameReg: wbReRegWrite.first.renameReg
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

