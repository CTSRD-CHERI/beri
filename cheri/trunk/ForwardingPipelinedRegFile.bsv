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
import Debug::*;
import RegFile::*;
import FIFOF::*;
import FIFO::*;
import FF::*;
import SpecialFIFOs::*;
import Vector::*;

//`define ReRegs 4

typedef Bit#(4) RenameReg; // A renamed destination register address, one of 4 in the current design

typedef struct {
  Bool    valid;
  regType register;
} SpecReg#(type regType) deriving (Bits, Eq);

typedef struct {
  Epoch  epoch;
  Bool   valid;
  RegNum regNum;
  Bool   pending;
} SpecRegTag deriving (Bits, Eq, FShow);

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
  WriteReport#(regType) write;
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
  WriteType wtype;
  Bool      doWrite; // Should the write happen (taking into account conditional write and whether the instruction committed.)
  RenameReg regNum;
  RegNum    archRegNum;
  regType   data;
} WriteReport#(type regType) deriving (Bits, Eq);

WriteReport#(regType) defaultWrite = WriteReport{
                                        wtype: None,
                                        doWrite: False,
                                        regNum: ?,
                                        archRegNum: ?,
                                        data: ?
                                      };

typedef enum {Init, Serving} RegFileState deriving (Bits, Eq);
//(* synthesize *)
module mkForwardingPipelinedRegFile(ForwardingPipelinedRegFileIfc#(regType,renameRegs))
  provisos(Bits#(regType, regType_sz));
  SpecRegTag initialTag = SpecRegTag{valid:False, epoch:?, regNum:?, pending:?};
  Reg#(Vector#(renameRegs,SpecRegTag)) rnTags         <- mkReg(replicate(initialTag));
  Vector#(renameRegs,Array#(Reg#(SpecReg#(regType)))) rnRegs  <- replicateM(mkCReg(2,?));
  //RegFile#(RegNum,regType)          regFile      <- mkRegFile(0, 31); // BRAM
  RegFile3Port#(regType)   regFile                 <- mkRegFile3Port;
  Reg#(Bit#(32))           regMask                 <- mkReg(0);
  FIFOF#(Bit#(32))         regMaskUpdate           <- mkUGSizedFIFOF(4);


  FIFOF#(void)             limiter                 <- mkUGSizedFIFOF(valueOf(renameRegs));
  FIFO#(ReadReq)           readReq                 <- mkSizedFIFO(3);
  FIFOF#(RegReadReport#(regType))    readReport    <- mkLFIFOF;
  FF#(WriteReport#(regType),1)       wbReRegWriteA  <- mkUGFF1;
  FIFOF#(WriteReport#(regType))      wbReRegWriteB  <- mkSizedFIFOF(valueOf(renameRegs));
  Reg#(WriteReport#(regType))    wbReRegWriteWire  <- mkDWire(defaultWrite);
  FIFO#(RegWrite#(regType)) writeback              <- mkLFIFO;
  
  Reg#(RenameReg)          nextReReg               <- mkReg(0);

  Reg#(regType)            debugOpA                <- mkRegU;
  Reg#(regType)            debugOpB                <- mkRegU;
  
  FIFOF#(RegNum)           readRawReg              <- mkFIFOF1;

  // These two wires force a priority of the pipelined read and write
  // methods over the raw versions to prevent extra ports being created
  // for the raw interfaces.
  Reg#(Bool)              writeRegUsed            <- mkDWire(False);

  rule readRegFilesRaw(readRawReg.notEmpty);
    trace($display("Did Read Raw on reg %x", readRawReg.first));
    ReadReq req = ?;
    req.a = readRawReg.first;
    readRawReg.deq;
    req.rawReq = True;
    readReq.enq(req);
  endrule
  
  ReadReq rq = readReq.first;
  rule readRegFiles(!rq.rawReq && (limiter.notFull || rq.write==None));
    readReq.deq();

    ReadRegs#(regType) ret = ?;
    ret.regA <- regFile.readA(rq.a);
    ret.regB <- regFile.readB(rq.b);
    if (regMask[rq.a]==1'b0) ret.regA = unpack(0);
    if (regMask[rq.b]==1'b0) ret.regB = unpack(0);

    if (rq.fromDebug) begin
      if (rq.a==0) ret.regA = debugOpA;
      if (rq.b==0) ret.regB = debugOpB;
    end 
    
    debug2("regfile", $display("Read values from register file BRAM: A:%x B:%x, regMask: %x", ret.regA, ret.regB, regMask));

    // Detect any dependencies on renamed registers and setup for forwarding in
    // the readRegs method.
    RegReadReport#(regType) report = RegReadReport{
      a:   RenameReport{ valid: False, regNum: ?, pending: False },
      b:   RenameReport{ valid: False, regNum: ?, pending: False },
      old: RenameReport{ valid: False, regNum: ?, pending: False },
      regFileVals: ret,
      write: WriteReport{
        wtype: rq.write,
        doWrite: ?,
        regNum: nextReReg,
        archRegNum: rq.dest,
        data: ?
      }
    };

    function SpecRegTag cleanOld(SpecRegTag st) =
      (st.epoch == rq.epoch) ? st:SpecRegTag{valid:False, epoch:st.epoch, regNum:st.regNum, pending:st.pending};
    Vector#(renameRegs, SpecRegTag) newReTags = map(cleanOld,rnTags);
    
    for (Integer i=0; i<valueOf(renameRegs); i=i+1) begin
      SpecRegTag srt = newReTags[i];
      RenameReport renameReport = RenameReport{
        valid: True,
        regNum: fromInteger(i),
        pending: srt.pending
      };
      if (srt.valid) begin
        if (srt.regNum == rq.a) begin
          report.a = renameReport;
          debug2("regfile", $display("Reading A from rereg %d", i));
        end
        if (srt.regNum == rq.b) begin
          report.b = renameReport;
          debug2("regfile", $display("Reading B from rereg %d", i));
        end
        // Remember and invalidate an old mapping of our destination register.
        if (srt.regNum == rq.dest) begin
          report.old = renameReport;
          debug2("regfile", $display("Old Register is %d", i));
          // Also invalidate a mapping if we will get a new one.
          if (rq.write != None) srt.valid = False;
        end
      end
      newReTags[i] = srt;
    end
    if (rq.write != None) begin
      newReTags[nextReReg] = SpecRegTag{
        valid: True,
        regNum: rq.dest,
        epoch: rq.epoch,
        pending: rq.write==Pending
      };
      debug2("regfile", $display("Rename register %d allocated for next write", nextReReg, fshow(newReTags[nextReReg])));
      nextReReg <= (nextReReg + 1 == fromInteger(valueOf(renameRegs))) ? 0:nextReReg + 1;
      limiter.enq(?);
    end 
    rnTags <= newReTags;
    readReport.enq(report);
  endrule

  // Some booleans to help with composing the conditions for the readRegs method.
  // ReadRegs needs to wait until any pending operands that it needs are ready.
  RegReadReport#(regType) topRpt = readReport.first;
  Bool a_is_pending = topRpt.a.valid &&
                      topRpt.a.pending &&
                      !rnRegs[topRpt.a.regNum][0].valid;
  Bool b_is_pending = topRpt.b.valid &&
                      topRpt.b.pending &&
                      !rnRegs[topRpt.b.regNum][0].valid;
  Bool old_is_pending = topRpt.write.wtype == Conditional &&
                        topRpt.old.pending &&
                        !rnRegs[topRpt.old.regNum][0].valid;
  Bool pipeEmpty = !wbReRegWriteA.notEmpty && !wbReRegWriteB.notEmpty;
  Bool read_is_ready = (!a_is_pending && !b_is_pending && !old_is_pending)
                        || pipeEmpty;
                       
  rule doWriteReg;
    WriteReport#(regType) wr = wbReRegWriteWire;
    if (wr.doWrite) begin
      regFile.write(wr.archRegNum,wr.data);
      debug2("regfile", $display("Wrote register %d", wr.archRegNum));
    end
    
    if (wr.wtype==Pending) begin
      rnRegs[wr.regNum][1] <= SpecReg{valid: wr.doWrite, register: wr.data };
    end
  endrule
  
  rule moveWbReRegWrite(wbReRegWriteA.notEmpty());
    wbReRegWriteB.enq(wbReRegWriteA.first());
    wbReRegWriteA.deq();
  endrule

  method Action reqRegs(ReadReq req) if (!readRawReg.notEmpty);
    readReq.enq(req);
  endmethod

  method ActionValue#(ReadRegs#(regType)) readRegs() if (read_is_ready);
    RegReadReport#(regType) report = readReport.first(); //Dequeued by writeRegSpeculative
    ReadRegs#(regType) ret = report.regFileVals;
    // Return renamed register values if necessary
    if (report.a.valid && rnRegs[report.a.regNum][0].valid)
      ret.regA = rnRegs[report.a.regNum][0].register;
    if (report.b.valid && rnRegs[report.b.regNum][0].valid)
      ret.regB = rnRegs[report.b.regNum][0].register;
    return ret;
  endmethod

  method Action writeRegSpeculative(regType data, Bool write);
    WriteReport#(regType)  req = readReport.first.write;
    RenameReport old = readReport.first.old;
    readReport.deq();
    req.data = data;
    // If we were told that this was going to be an unconditional write, write anyway.
    req.doWrite = (case(req.wtype)
                      None: return False;
                      Simple: return True;
                      Conditional: return write;
                      Pending: return True;
                   endcase);

    // Update rename registers with this write value.
    SpecReg#(regType) invReg = SpecReg{ register: ?, valid: False};
    rnRegs[req.regNum][0] <= (case(req.wtype)
                              None:        return rnRegs[req.regNum][0];
                              Simple:      return SpecReg{ register: data, valid: True};
                              Conditional: begin
                                             if (write) return SpecReg{ register: data, valid: True};
                                             else return (old.valid) ? rnRegs[old.regNum][0]:invReg;
                                           end
                              Pending:     return invReg;
                           endcase);
    
    wbReRegWriteA.enq(req);
  endmethod

  method Action writeReg(regType data, Bool committing) 
                            if (wbReRegWriteB.first.wtype==None||limiter.notEmpty);
    WriteReport#(regType) wr = wbReRegWriteB.first;
    wbReRegWriteB.deq();
    wr.doWrite = (wr.doWrite && committing);
    wr.data = (wr.wtype==Pending) ? data:wr.data;
    wbReRegWriteWire <= wr;
    // Do the BRAM write in the next cycle for frequency.
    //writeback.enq(RegWrite{ write: wr.doWrite, couldWrite: wr.wtype!=None, data: data, regNum: regW});
    Bit#(32) newRegMask = regMask;
    if (regMaskUpdate.notEmpty) begin
      newRegMask = (regMaskUpdate.first & newRegMask);
      debug2("regfile", $display("Applied register mask %x", newRegMask));
      regMaskUpdate.deq;
    end
    if (wr.doWrite) newRegMask[wr.archRegNum] = 1'b1;
    
    //rnRegs[wr.regNum][1] <= SpecReg{ valid: True, register: writeData };
    if (wr.wtype!=None) limiter.deq();
    regMask <= newRegMask;
    writeRegUsed <= True;
  endmethod
  
  method Action writeRaw(RegNum regW, regType data) if (!writeRegUsed);
    regMask[regW] <= 1'b1;
    wbReRegWriteWire <= WriteReport{
        wtype: Simple,
        doWrite: True,
        regNum: ?,
        archRegNum: regW,
        data: data
      };
  endmethod
  
  method Action readRawPut(RegNum regA);
    readRawReg.enq(regA);
  endmethod
  
  method ActionValue#(regType) readRawGet() if (rq.rawReq);
    regType ret <- regFile.readA(rq.a);
    debug2("regfile", $display("readRawGot %x", ret));
    readReq.deq();
    return ret;
  endmethod

  method Action putDebugRegs(regType a, regType b);
    debugOpA <= a;
    debugOpB <= b;
  endmethod
  
  method Action clearRegs(Bit#(32) mask);
    debug2("regfile", $display("Enqued register mask %x", mask));
    regMaskUpdate.enq(mask);
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
  
  method Action write(RegNum regW, regType data);
    regFile.upd(regW,data);
  endmethod
  method ActionValue#(regType) readA(RegNum regNum);
    return regFile.sub(regNum);
  endmethod
  method ActionValue#(regType) readB(RegNum regNum);
    return regFile.sub(regNum);
  endmethod
endmodule

