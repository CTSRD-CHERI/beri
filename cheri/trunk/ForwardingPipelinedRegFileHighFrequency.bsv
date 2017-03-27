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
import ConfigReg::*;
import FIFOF::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;

//`define ReRegs 4

typedef Bit#(TLog#(renameRegs)) RenameReg#(numeric type renameRegs); // A renamed destination register address, one of 4 in the current design
typedef Bit#(TLog#(renameRegs)) RenameTag#(numeric type renameRegs);

typedef struct {
  Bool    valid;
  regType register;
} SpecReg#(type regType) deriving (Bits, Eq, FShow);

typedef struct {
  Epoch  epoch;
  Bool   valid;
  RegNum regNum;
  Bool   pending;
  Bool   conditional;
} SpecRegTag deriving (Bits, Eq, FShow);

typedef struct {
  Bool    valid;
  RegNum  regNum;
  regType register;
} CachedReg#(type regType) deriving (Bits, Eq);

typedef struct {
  Bool valid;
  Bool pending;
  RenameReg#(renameRegs) regNum;
  Bool conditional;
} RenameReport#(numeric type renameRegs) deriving (Bits, Eq);

typedef struct {
  RenameReport#(renameRegs) a;
  RenameReport#(renameRegs) b;
  RenameReport#(renameRegs) old;
  ReadRegs#(regType) regFileVals;
  ReadReq     rq;
  WriteReport#(regType, renameRegs) write;
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
  WriteType               wtype;
  Bool                    doWrite;
  RenameReg#(renameRegs)  renameReg;
  RegNum                  archRegNum;
  regType                 data;
} WriteReport#(type regType, numeric type renameRegs) deriving (Bits, Eq);

typedef enum {Init, Serving} RegFileState deriving (Bits, Eq);
module mkForwardingPipelinedRegFileHighFrequency(ForwardingPipelinedRegFileIfc#(regType,renameRegs))
  provisos(Bits#(regType, regType_sz),IsModule#(_m__, _c__),
           Add#(a__, TLog#(renameRegs), 5),
           FShow#(ForwardingPipelinedRegFileHighFrequency::SpecReg#(regType))
          );
  
  SpecRegTag initRnTag = SpecRegTag{valid:False, epoch:?, regNum:?, pending:?, conditional:?};
  Reg#(Vector#(renameRegs,SpecRegTag)) rnTags  <- mkReg(replicate(initRnTag));
  Vector#(renameRegs,Array#(Reg#(SpecReg#(regType)))) rnRegs  <- replicateM(mkCReg(2,SpecReg{ register: ?, valid: False }));
  Vector#(renameRegs,FIFOF#(void))                  rnUpdt  <- replicateM(mkUGSizedFIFOF(4)); // Arbitrary size.  ~4 updates outstanding for each register.
  CachedReg#(regType) initialChReg = CachedReg{valid:False, regNum:?, register: ?};
  Reg#(Vector#(renameRegs,CachedReg#(regType))) chRegs        <- mkReg(replicate(initialChReg));
  RegFile3Port#(regType)                        regFile       <- mkRegFile3Port;
  Reg#(Bit#(32))                                regMask       <- mkReg(0);
  FIFOF#(Bit#(32))                              regMaskUpdate <- mkUGSizedFIFOF(4);
  
  FIFO#(ReadReq)                                readReq       <- mkFIFO;
  //FIFO#(RegReadReport#(regType, renameRegs))    skipReadReq   <- mkBypassFIFO;
  FIFOF#(RegReadReport#(regType, renameRegs))   bramReadReq   <- mkFIFOF1;
  FIFO#(RegReadReport#(regType, renameRegs))    readReport    <- mkFIFO;
  // Break this into two fifos to improve timing.  (capacity without big mux)
  FIFOF#(WriteReport#(regType, renameRegs))     wbReRegWriteA <- mkFIFOF;
  FIFOF#(WriteReport#(regType, renameRegs))     wbReRegWriteB <- mkFIFOF;
  FIFOF#(RegWrite#(regType))                    writeback     <- mkLFIFOF;

  Reg#(regType)                                 debugOpA      <- mkRegU;
  Reg#(regType)                                 debugOpB      <- mkRegU;
  
  FIFOF#(RegNum)                                readRawReg    <- mkFIFOF;
  
  Reg#(RenameReg#(renameRegs))                  count         <- mkRegU;
  
  // These two wires force a priority of the pipelined read and write
  // methods over the raw versions to prevent extra ports being created
  // for the raw interfaces.
  Wire#(Bool)              writeRegUsed            <- mkDWire(False);
  
  rule moveWbReRegWriteAlong;
    wbReRegWriteB.enq(wbReRegWriteA.first);
    wbReRegWriteA.deq;
  endrule
  
  // Only fire when there are no oustanding reads from the normal interface.
  rule readRegFilesRaw(readRawReg.notEmpty && !bramReadReq.notEmpty && !writeback.notEmpty);
    trace($display("Did Read Raw on reg %x", readRawReg.first));
    RegReadReport#(regType, renameRegs) req = ?;
    req.rq.a = readRawReg.first;
    readRawReg.deq;
    req.rq.rawReq = True;
    bramReadReq.enq(req);
  endrule
  
  ReadReq fr = readReq.first;
  Bool dontNeedNewDestination = fr.write==None;
  for (Integer i=0; i<valueOf(renameRegs); i=i+1) begin
    SpecRegTag rt = rnTags[i];
    if ((rt.regNum==fr.dest||!rt.valid) && !rt.pending) dontNeedNewDestination = True;
  end
  
  function Bool isEmpty(FIFOF#(void) f) = !f.notEmpty;
  function Bool  isFull(FIFOF#(void) f) = !f.notFull;
  Bool haveRoomForDestination = any(isEmpty,rnUpdt);
  Bool oneUpdtFifoFull = any(isFull,rnUpdt);

  rule readRegFiles(!readRawReg.notEmpty && !bramReadReq.notEmpty && !oneUpdtFifoFull && (dontNeedNewDestination||haveRoomForDestination));
    ReadReq rq = readReq.first;
    readReq.deq();

    // Detect any dependencies on renamed registers and setup for forwarding in
    // the readRegs method.
    RegReadReport#(regType, renameRegs) report = RegReadReport{
      a:   RenameReport{ valid: False, regNum: ?, conditional: ?, pending: False },
      b:   RenameReport{ valid: False, regNum: ?, conditional: ?, pending: False },
      old: RenameReport{ valid: False, regNum: ?, conditional: ?, pending: False },
      rq: rq,
      regFileVals: ReadRegs{regA: unpack(0), regB: unpack(0)},
      write: WriteReport{
        wtype: rq.write,
        doWrite: ?,
        renameReg: ?,
        archRegNum: rq.dest,
        data: ?
      }
    };
    
    // Read in tags while cleaning out old epochs.
    function SpecRegTag cleanOld(SpecRegTag st) =
      (st.epoch == rq.epoch) ? st:SpecRegTag{valid:False, epoch:st.epoch, regNum:st.regNum, pending:st.pending, conditional:st.conditional};
    Vector#(renameRegs, SpecRegTag) newReTags = map(cleanOld,rnTags);

    Bool needDest = (rq.write==None) ? False:True;
    for (Integer i=0; i<valueOf(renameRegs); i=i+1) begin
      SpecRegTag srt = newReTags[i];
      RenameReport#(renameRegs) renameReport = RenameReport{
        valid: True,
        regNum: fromInteger(i),
        pending: srt.pending,
        conditional: srt.conditional
      };
      if (srt.valid) begin
        // Note if either of our operands are in rename registers.
        if (srt.regNum == rq.a) begin
          report.a = renameReport;
          debug2("hfregfile", $display("%t Reading A (%d) from Rename Register %d", $time, rq.a, fromInteger(i)));
        end
        if (srt.regNum == rq.b) begin
          report.b = renameReport;
          debug2("hfregfile", $display("%t Reading B (%d) from Rename Register %d", $time, rq.b, fromInteger(i)));
        end
        // Remember any old rename register that held this architectural register.
        if (srt.regNum == rq.dest) begin
          report.old = renameReport;
          debug2("hfregfile", $display("%t Old Register is %d", $time, fromInteger(i)));
          // Also invalidate a mapping if we will get a new one.
          if (rq.write != None) srt.valid = False;
        end
      end
      // Potentially reuse a rename register if we can.
      if (needDest && !srt.valid && !srt.pending) begin
        report.write.renameReg = fromInteger(i);
        debug2("hfregfile", $display("%t Reusing Rename Register %d for destination", $time, fromInteger(i)));
        needDest = False;
      end
      newReTags[i] = srt;
    end
    
    if (needDest) count <= count + 1; // Cycle through first choice of rename register.
    // find destination register
    for (Integer i=0; i<valueOf(renameRegs); i=i+1) begin
      RenameReg#(renameRegs) choice = count + fromInteger(i);
      // If there are no updates to this register that have not been written into the register file....
      if (needDest && !rnUpdt[choice].notEmpty) begin
        report.write.renameReg = choice;
        needDest = False;
        debug2("hfregfile", $display("%t Using Rename Register %d for destination", $time, choice));
      end
    end
    
    if (needDest) $display(" Panic!  No destination! ");

    if (rq.write!=None) begin
      RenameReg#(renameRegs) renameReg = report.write.renameReg;
      rnUpdt[renameReg].enq(?); // Log an outstanding update to this register.
      newReTags[renameReg] = SpecRegTag{
        valid: True,
        regNum: rq.dest,
        epoch: rq.epoch,
        pending: rq.write==Pending,
        conditional: rq.write==Conditional
      };
    end
    debug2("hfregfile", $display("%t Rename Register Tags", $time));
    for (Integer i=0; i<valueOf(renameRegs); i=i+1)
      debug2("hfregfile", $display("%d : ", i, fshow(newReTags[i])));
    rnTags <= newReTags;
    
    Bool usedCachedA = False;
    Bool usedCachedB = False;
    // Furthermore, check if the registers that do need to be fetched are in
    // the cache of registers that have recently been read.
    RenameReg#(renameRegs) idx = truncate(rq.a);
    if (!report.a.valid && (chRegs[idx].valid && chRegs[idx].regNum == rq.a)) begin
      debug2("hfregfile", $display("%t Reading A (%d) from Cached Register %d", $time, rq.a, idx));
      report.regFileVals.regA = chRegs[idx].register;
      usedCachedA = True;
    end else if (!report.a.valid && regMask[rq.a]==1'b0) begin
      debug2("hfregfile", $display("%t Reading A (%d) as zero", $time, rq.a));
      report.regFileVals.regA = unpack(0);
      usedCachedA = True;
    end else if (rq.fromDebug && rq.a==0) begin
      report.regFileVals.regA = debugOpA;
      usedCachedA = True;
    end
    idx = truncate(rq.b);
    if (!report.b.valid && (chRegs[idx].valid && chRegs[idx].regNum == rq.b)) begin
      debug2("hfregfile", $display("%t Reading B (%d) from Cached Register %d", $time, rq.b, idx));
      report.regFileVals.regB = chRegs[idx].register;
      usedCachedB = True;
    end else if (!report.b.valid && regMask[rq.b]==1'b0) begin
      debug2("hfregfile", $display("%t Reading B (%d) as zero", $time, rq.b));
      report.regFileVals.regB = unpack(0);
      usedCachedB = True;
    end else if (rq.fromDebug && rq.b==0) begin
      report.regFileVals.regB = debugOpB;
      usedCachedB = True;
    end
    
    idx = truncate(rq.dest);
    if (report.write.wtype!=None && rq.dest == chRegs[idx].regNum)
        chRegs[idx] <= initialChReg;
    
    if (!report.a.valid && !usedCachedA) debug2("hfregfile", $display("%t Fetching %d from Register File", $time, rq.a));
    if (!report.b.valid && !usedCachedB) debug2("hfregfile", $display("%t Fetching %d from Register File", $time, rq.b));
    
    // Skip the BRAM lookup if the operands are in rename registers.
    Bool aCanSkip = (report.a.valid && !report.a.conditional) || usedCachedA;
    Bool bCanSkip = (report.b.valid && !report.b.conditional) || usedCachedB;
    Bool skipBRAMLookup = aCanSkip && bCanSkip; 
                          //(report.b.valid || usedCachedB) &&
                          //rq.write != Conditional;
    if (skipBRAMLookup) begin//skipReadReq.enq(report);
      debug2("hfregfile", $display("%t Skipped BRAM Read in RegFile", $time));
      readReport.enq(report);
    end else bramReadReq.enq(report);
  endrule
  
  //(* descending_urgency = "doBRAMRead,skipBRAMRead" *)
  // Skip architectural lookup, we have the operands in rename registers.
  /*
  rule skipBRAMRead;
    debug2("hfregfile", $display("%t Skipped BRAM Read in RegFile", $time));
    RegReadReport#(regType, renameRegs) report = skipReadReq.first;
    skipReadReq.deq;
    RenameReg#(renameRegs) idx = truncate(report.rq.dest);
    Vector#(renameRegs,CachedReg#(regType)) newChRegs = chRegs;
    if (report.write.wtype!=None && report.rq.dest == newChRegs[idx].regNum)
      chRegs[idx] <= initialChReg;
    readReport.enq(report);
  endrule*/
  // Actually do regitser lookup
  rule doBRAMRead(bramReadReq.notEmpty && !bramReadReq.first.rq.rawReq);
    debug2("hfregfile", $display("%t Did Full BRAM Read in RegFile", $time));
    RegReadReport#(regType, renameRegs) report = bramReadReq.first;
    bramReadReq.deq;
    report.regFileVals.regA <- regFile.readA(report.rq.a);
    report.regFileVals.regB <- regFile.readB(report.rq.b);
    if (regMask[report.rq.a]==1'b0) report.regFileVals.regA = unpack(0);
    if (regMask[report.rq.b]==1'b0) report.regFileVals.regB = unpack(0);
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
    // Make sure our write destination is cleared in the cache if it is there,
    // even if we've just read in the old value.
    idx = truncate(report.rq.dest);
    if (report.write.wtype!=None && report.rq.dest == newChRegs[idx].regNum)
        newChRegs[idx] = initialChReg;
    chRegs <= newChRegs;
    readReport.enq(report);
  endrule

  // Some booleans to help with composing the conditions for the readRegs method.
  // ReadRegs needs to wait until any pending operands that it needs are ready.
  RegReadReport#(regType, renameRegs) topRpt = readReport.first;
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
                        
  rule doRegisterWrite;
    RegWrite#(regType) rw = writeback.first;
    if (rw.write) begin
      regFile.write(rw.regNum,rw.data);
      debug2("hfregfile", $display("%t Wrote register %d <= %x", $time, rw.regNum, rw.data));
      Bit#(32) newRegMask = regMask;
      if (regMaskUpdate.notEmpty) begin
        newRegMask = (regMaskUpdate.first & newRegMask);
        regMaskUpdate.deq;
      end
      newRegMask[rw.regNum] = 1'b1;
      if (newRegMask!=regMask) trace($display("%t Wrote register mask <= %x", $time, newRegMask));
      regMask <= newRegMask;
    end
    writeRegUsed <= True;
    writeback.deq();
  endrule

  method Action reqRegs(ReadReq req);
    readReq.enq(req);
  endmethod

  method ActionValue#(ReadRegs#(regType)) readRegs() if (read_is_ready);
    RegReadReport#(regType, renameRegs) report = readReport.first(); //Dequeued by writeRegSpeculative
    ReadRegs#(regType) ret = report.regFileVals;
    
    for (Integer i=0; i<valueOf(renameRegs); i=i+1)
      debug2("hfregfile", $display("%t SpecReg %d: ", $time, i, fshow(rnRegs[i][0])));
    
    // Return renamed register values if necessary
    if (report.a.valid) begin
      if (rnRegs[report.a.regNum][0].valid) begin
        ret.regA = rnRegs[report.a.regNum][0].register;
        debug2("hfregfile", $display("%t read A specreg %d : %x", $time, report.a.regNum, ret.regA));
      end
    end
    if (report.b.valid) begin
      if (rnRegs[report.b.regNum][0].valid) begin
        ret.regB = rnRegs[report.b.regNum][0].register;
        debug2("hfregfile", $display("%t read B specreg %d : %x", $time, report.b.regNum, ret.regB));
      end
    end
    debug2("hfregfile", $display("%t returning read in RegFile", $time, fshow(ret)));
    return ret;
  endmethod

  method Action writeRegSpeculative(regType data, Bool write);
    WriteReport#(regType, renameRegs)  req = readReport.first.write;
    RenameReport#(renameRegs) old = readReport.first.old;
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
    rnRegs[req.renameReg][0] <= (case(req.wtype)
                              None:        return rnRegs[req.renameReg][0];
                              Simple:      return SpecReg{ register: data, valid: True};
                              Conditional: begin
                                             if (write) return SpecReg{ register: data, valid: True};
                                             else return (old.valid) ? rnRegs[old.regNum][0]:invReg;
                                           end
                              Pending:     return invReg;
                           endcase);
    
    wbReRegWriteA.enq(req);
  endmethod

  method Action writeReg(regType data, Bool committing);
    WriteReport#(regType, renameRegs) wr = wbReRegWriteB.first;
    wbReRegWriteB.deq();
    wr.doWrite = (wr.doWrite && committing);
    regType writedata = (wr.wtype==Pending) ? data:wr.data;
    // Do the BRAM write in the next cycle for frequency.
    writeback.enq(RegWrite{ write: wr.doWrite, couldWrite: wr.wtype!=None, data: writedata, regNum: wr.archRegNum});
    /*if (doWrite) begin
      regFile.write(regW,data);
      debug2("hfregfile", $display("%t Wrote register %d", $time, regW));
    end
    
    Bit#(32) newRegMask = regMask;
    if (regMaskUpdate.notEmpty) begin
      newRegMask = regMaskUpdate.first;
      regMaskUpdate.deq;
    end
    if (wr.doWrite) newRegMask[wr.archRegNum] = 1'b1;
    if (newRegMask!=regMask) trace($display("%t Wrote register mask <= %x", $time, newRegMask));
    regMask <= newRegMask;
    writeRegUsed <= True;
    */
    if (wr.wtype!=None) rnUpdt[wr.renameReg].deq;
    // If the writeback is pending and we're supposed to do a write and the current value is invalid...
    if (wr.wtype==Pending) begin
      rnRegs[wr.renameReg][1] <= SpecReg{ valid: True, register: data };
      debug2("hfregfile", $display("%t wrote specreg %d with %x in writeback", $time, wr.renameReg, data));
    end
  endmethod
  
  method Action writeRaw(RegNum regW, regType data) if (!writeRegUsed);
    regFile.write(regW,data);
    regMask[regW] <= 1'b1;
    chRegs  <= replicate(initialChReg);
  endmethod
  
  method Action readRawPut(RegNum regA);
    readRawReg.enq(regA);
  endmethod
  
  method ActionValue#(regType) readRawGet() if (bramReadReq.first.rq.rawReq);
    regType ret <- regFile.readA(bramReadReq.first.rq.a);
    bramReadReq.deq();
    return ret;
  endmethod

  method Action putDebugRegs(regType a, regType b);
    debugOpA <= a;
    debugOpB <= b;
  endmethod
  
  method Action clearRegs(Bit#(32) mask);
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

