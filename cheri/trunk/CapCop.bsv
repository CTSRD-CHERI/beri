/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2012 Robert N. M. Watson
 * Copyright (c) 2011 SRI International
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
import ForwardingPipelinedRegFile::*;
import ConfigReg::*;

typedef Bit#(3) Select;

typedef struct {
  UInt#(64) offset; // The offset into the capability register
  Address   pc;     // PC to be validated.
  MemSize   size;
  MemOp     memOp;
} CapReq deriving(Bits, Eq);

typedef struct {
  Bool      isCapability;
  Bit#(32)  reserved;
  Perms     perms;
  Bool      unsealed;
  Word      oType_eaddr;
  Address   base;
  UInt#(64) length;
} Capability deriving(Bits, Eq);

typedef Bit#(5) CapReg;

typedef struct {
  CapOp     op;      // Operation
  CapReg    r0;      // Potential register name from bits 25-21
  CapReg    r1;      // bits 20-16
  CapReg    r2;      // bits 15-11
  CapReg    r3;      // bits 10-6
  MemSize   memSize;
  InstId    instId;
  Epoch     epoch;
} CapInst deriving(Bits, Eq);

typedef struct {
  Capability memResponse;
  Exception  mipsExp;
  Bool       dead;
  InstId     instId;    // Instruction ID that requests the update
} CapWritebackRequest deriving(Bits, Eq);

typedef struct {
  Bool   a;
  Bool   b;
} ExpectTags deriving(Bits, Eq);

typedef struct {
  CapInst    capInst; // Instruction passed in
  CapCause   cause;   //
  ExpectTags expectTags; // Whether to expect the fetched registers to be valid capabilities.
  CapReg     regA;
  CapReg     regB;
  Bool       readA;
  Bool       readB;
  Capability writeCap;      // Capability to be written
  CapReg     writeReg; // Capability register to be written
  Bool       doWrite; // Write the destination register.
  Bool       jump;
  InstId     instId; // Instruction ID that requests the update
  Epoch      epoch;
} CapControlToken deriving(Bits, Eq);

typedef struct {
  Bool      valid;
  UInt#(64) length;
  UInt#(64) offset;
  MemSize   memSize; // Instruction ID that requests the update
  CapReg    capReg;
} LenCheck deriving(Bits, Eq);

typedef struct {
  Bit#(16) soft;
  Bool access_CR28; // KR2C
  Bool access_CR27; // KR1C
  Bool access_CR29; // KCC
  Bool access_CR30; // KDC
  Bool access_CR31; // EPCC
  Bool reserved;
  Bool permit_set_type;
  Bool permit_seal;
  Bool permit_store_ephemeral_cap;
  Bool permit_store_cap;
  Bool permit_load_cap;
  Bool permit_store;
  Bool permit_load;
  Bool permit_execute;
  Bool non_ephemeral;
} Perms deriving(Bits, Eq); // 31 bits

typedef struct {
  CapReg     capReg;
  
  Bool       pcc;
  CapExpCode exp;
} CapCause deriving(Bits, Eq);

typedef struct {
  Address    addr;
  CapExpCode exp;
} AddrExp deriving(Bits, Eq);

typedef struct {
  Capability pcc;
  Epoch      epoch;
} BufferedPCC deriving(Bits, Eq);

Capability defaultCap = CapCop::Capability{
  length: 64'hFFFFFFFFFFFFFFFF,
  base: 64'b0,
  oType_eaddr: 64'b0,
  unsealed: True,
  perms: unpack(31'h7FFFFFFF),
  reserved: 32'b0,
  isCapability: True
};

typedef struct {
  MemOp       memOp;
  Address     address;
  Bool        isCapability;
  Capability  capability;
  InstId      instId;
} CapMemAccess deriving(Bits, Eq);

function CapExpCode checkRegAccess(Perms pp, CapReg cr);
  CapExpCode ret = None;
  if      (!pp.access_CR27 && cr==27) ret = CR27;
  else if (!pp.access_CR28 && cr==28) ret = CR28;
  else if (!pp.access_CR29 && cr==29) ret = CR29;
  else if (!pp.access_CR30 && cr==30) ret = CR30;
  else if (!pp.access_CR31 && cr==31) ret = CR31;
  return ret;
endfunction

typedef enum {Init, Ready, Except} CapState
  deriving (Bits, Eq);
typedef enum {Except, Return, None} ExceptionEvent
  deriving (Bits, Eq);

interface CapCopIfc;
  method Action                      putCapInst(CapInst capInst);
  method Address                     getArchPc(Address pc, Epoch epoch); // Translate absolute virtual address to arch PC
  method ActionValue#(CoProResponse) getCapResponse(CapReq capReq);
  method ActionValue#(CoProResponse) getAddress();
  method Action                      commitWriteback(CapWritebackRequest wbReq);
endinterface

`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkCapCop#(Bit#(16) coreId)(CapCopIfc);
  Reg#(Capability)            pcc                 <- mkConfigReg(defaultCap);
  FIFOF#((BufferedPCC))       pccUpdate           <- mkUGFIFOF();
  ForwardingPipelinedRegFileIfc#(Capability) regFile <- mkForwardingPipelinedRegFile();
  `ifdef BLUESIM
    Reg#(Capability) debugCaps[32];
    for (Integer i=0; i<32; i=i+1) debugCaps[i]   <- mkReg(defaultCap);
    FIFOF#(Bool) reportCapRegs <- mkUGFIFOF;
  `endif
  FIFO#(CapControlToken)      inQ                 <- mkLFIFO;
  FIFO#(CapControlToken)      dec2exeQ            <- mkSizedFIFO(2);
  FIFO#(CapControlToken)      exe2wbQ             <- mkSizedFIFO(4);
  FIFO#(ExceptionEvent)       exception           <- mkFIFO;
  FIFO#(CapReg)               expFetch            <- mkFIFO;
  Reg#(CapCause)              causeReg            <- mkRegU;
  FIFOF#(CapCause)            causeUpdate         <- mkUGFIFOF;
  FIFO#(LenCheck)             lenChecks           <- mkFIFO;
  FIFO#(CapCause)             lenCause            <- mkFIFO;
  Reg#(Bool)                  capBranchDelay      <- mkReg(False);
  Reg#(CapState)              capState            <- mkConfigReg(Init);
  Reg#(UInt#(5))              count               <- mkReg(0);

  function ActionValue#(AddrExp) checkAndOffset(CapReq capReq, Capability cap);
    actionvalue
      UInt#(6) size = case (capReq.size)
        Line: return 32;
        DoubleWord, DoubleWordLeft, DoubleWordRight: return 8;
        Word, WordLeft, WordRight: return 4;
        HalfWord: return 2;
        Byte: return 1;
        default: return 32; // Worst case default, just in case.
      endcase;
      //Maybe#(Address) vAddr = tagged Valid unpack({(pack(cap.base)[63:40]+pack(capReq.offset)[63:40]),(pack(cap.base)[39:0] + pack(capReq.offset)[39:0])});
      //if ((pack(capReq.offset)[39:0] + zeroExtend(pack(size))) > pack(cap.length)[39:0]) vAddr = tagged Invalid;
      AddrExp retVal = AddrExp{
        addr: pack(unpack(cap.base) + capReq.offset),
        exp: None
      };
      //Maybe#(Address) vAddr = tagged Valid pack(unpack(cap.base) + capReq.offset);
      UInt#(65) offsetSize = zeroExtend(capReq.offset) + zeroExtend(size);
      if (offsetSize > zeroExtend(cap.length)) begin
        retVal.exp = Len;
      end
      //$display("offset: %x, size: %x, offset+size: %x, cap.length: %x", capReq.offset, size, capReq.offset+zeroExtend(size), cap.length);
      return retVal;
    endactionvalue
  endfunction

  rule initialize(capState == Init);
    Capability cap = defaultCap;
    regFile.writeRaw(pack(count),defaultCap);
    count <= count + 1;
    if (count == 31) begin
      capState <= Ready;
    end
  endrule

  rule doException(capState == Except);
    if (exception.first==Except) begin
      Capability dc = pcc;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception in Capability Unit! PCC->EPCC u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", $time, coreId, dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `else
        trace($display("Exception in Capability Unit! PCC->EPCC u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `endif
      regFile.writeRaw(31,pcc);
      `ifdef BLUESIM
        debugCaps[31] <= pcc;
      `endif
      Capability kcc = regFile.readRaw(expFetch.first, 0).regA;
      pcc <= kcc;
      dc = kcc;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: KCC->PCC u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", $time, coreId, dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `else
        trace($display("KCC->PCC u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `endif
    end else begin
      Capability epcc = regFile.readRaw(expFetch.first, 0).regA;
      pcc <= epcc;
      Capability dc = epcc;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception Return in Capability Unit! EPCC->PCC u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", $time, coreId, dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `else
        trace($display("Exception Return in Capability Unit! EPCC->PCC u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `endif
    end
    expFetch.deq();
    exception.deq();
    capState <= Ready;
  endrule
  
  // This rule moves from the input queue to a larger queue.
  // These are seperated for timing.
  rule inQtoBuffer;
    dec2exeQ.enq(inQ.first);
    inQ.deq;
  endrule

  method Address getArchPc(Address pc, Epoch epoch);
    Capability forwardedPCC = (pccUpdate.notEmpty() && 
                               pccUpdate.first.epoch==epoch) ? 
                               pccUpdate.first.pcc:pcc;
    if (capBranchDelay) forwardedPCC = pcc;
    return (pc - forwardedPCC.base);
  endmethod

  method Action putCapInst(capInst) if (capState == Ready);
    Maybe#(CapReg) fetchA = tagged Invalid;
    Maybe#(CapReg) fetchB = tagged Invalid;
    Maybe#(CapReg) wbReg  = tagged Invalid;
    ExpectTags expectTags = ExpectTags{a:False, b:False};
    CapCause cause = CapCause{exp: None, pcc: False, capReg: ?};
    Bool jump = False;
    case (capInst.op)
      GetBase, GetLen, GetType, GetPerm, GetUnsealed, GetTag: begin // Move From Capability Register Field
        fetchA = tagged Valid capInst.r2;
      end
      // For one of the capability-branch-if-tag-set/unset instructions, we
      // need to fetch the tag, which we'll then use to decide whether we branch
      BranchTagSet, BranchTagUnset: begin
        fetchA = tagged Valid capInst.r1;
      end
      IncBase, IncBaseNull, SetLen, AndPerm: begin // Move to Capability Register Field
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        wbReg = tagged Valid capInst.r1;
      end
      GetPCC: begin
        wbReg = tagged Valid capInst.r2;
      end
      ClearTag: begin
        fetchA = tagged Valid capInst.r2;
        wbReg = tagged Valid capInst.r1;
      end
      SetType: begin
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        wbReg = tagged Valid capInst.r1;
      end
      L: begin // Load Byte, Double and Word via Capability Register
        fetchA = tagged Valid capInst.r1;
        expectTags.a = True;
      end
      S: begin // Store Byte, Word and Double via Capability Register
        fetchA = tagged Valid capInst.r1;
        expectTags.a = True;
      end
      JALR: begin // Jump and link Capability Register
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        wbReg = tagged Valid 24;          // Link register.
        jump = True;
      end
      JR: begin // Jump to Capability Register
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        jump = True;
      end
      SealCode: begin // Seal an executable capability
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        wbReg = tagged Valid capInst.r1;
      end
      SealData: begin // Seal a data capability
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        fetchB = tagged Valid capInst.r3;
        expectTags.b = True;
        wbReg = tagged Valid capInst.r1;
      end
      Unseal: begin
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        fetchB = tagged Valid capInst.r3;
        expectTags.b = True;
        wbReg = tagged Valid capInst.r1;
      end
      GetRelBase: begin
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        fetchB = tagged Valid capInst.r3;
        expectTags.b = True;
      end
      CheckPerms: begin
        fetchA = tagged Valid capInst.r1;
        expectTags.a = True;
      end
      CheckType: begin
        fetchA = tagged Valid capInst.r1;
        expectTags.a = True;
        fetchB = tagged Valid capInst.r2;
        expectTags.b = True;
      end
      SC: begin // Store Capability Register
        fetchA = tagged Valid capInst.r1;
        expectTags.a = True;
        fetchB = tagged Valid capInst.r0;
      end
      LC: begin // Load Capability Register
        fetchA = tagged Valid capInst.r1;
        expectTags.a = True;
        wbReg = tagged Valid capInst.r0;
      end
      Call: begin
        fetchA = tagged Valid capInst.r1;
        fetchB = tagged Valid capInst.r2;
        `ifdef HARDCALL
          jump = True;
          wbReg = tagged Valid 5'd26;
        `endif
      end
      Return: begin
        //fetchA = tagged Valid capInst.r1;
        //fetchB = tagged Valid capInst.r2;
      end
      ERET: begin
        fetchA = tagged Valid 31;
      end
      None: begin
        fetchA = tagged Valid 0;
        expectTags.a = True;
      end
    endcase
    // Throw exceptions if improper registers are read, but always fetch to avoid stalls.
    CapControlToken ctOut = CapControlToken{
                                  capInst: capInst, 
                                  cause: cause, 
                                  expectTags: expectTags,
                                  regA: 0,
                                  regB: 0,
                                  readA: ?,
                                  readB: ?,
                                  writeCap: ?,
                                  writeReg: ?,
                                  doWrite: False,
                                  jump: jump,
                                  instId: capInst.instId,
                                  epoch: capInst.epoch
                                };
                                
    if (fetchA matches tagged Valid .regA) begin
      ctOut.regA = regA;
      ctOut.readA = True;
      ctOut.cause.capReg = regA;
    end
    if (fetchB matches tagged Valid .regB &&& cause.exp == None) begin
      ctOut.regB = regB;
      ctOut.readB = True;
    end
    if (wbReg matches tagged Valid .writeReg &&& cause.exp == None) begin
      ctOut.writeReg = writeReg;
      ctOut.doWrite = True;
    end
    
    ReadReq regReq = ReadReq{
                    epoch: capInst.epoch,
                    a: ctOut.regA,
                    b: ctOut.regB,
                    write: ctOut.doWrite,
                    pendingWrite: capInst.op==LC,
                    dest: ctOut.writeReg,
                    fromDebug: False,
                    conditionalUpdate: False
                  };
    regFile.reqRegs(regReq);
    debug($display("%t Selecting to fetch CapRegA=%d and CapRegB=%d for instId=%d", $time(), fromMaybe(?,fetchA), fromMaybe(?,fetchB), capInst.instId));
    inQ.enq(ctOut);

    if (capInst.op != None) begin
      debug($display("Use Cap Request. op=%x, r1=%x r2=%x At time %d", capInst.op, capInst.r1, capInst.r2, $time));
    end
  endmethod

  method ActionValue#(CoProResponse) getCapResponse(CapReq capReq) if (capState == Ready && pccUpdate.notFull && causeUpdate.notFull);
    CapControlToken ct <- toGet(dec2exeQ).get();
    CapInst capInst = ct.capInst;
    CapCause cause = ct.cause;
    ExpectTags expectTags = ct.expectTags;

    ReadRegs#(Capability) capRegs <- regFile.readRegs();
    Capability capA = capRegs.regA;
    Capability capB = capRegs.regB;
    CapReg regA = ct.regA;
    CapReg regB = ct.regB;
    // Use forwarded PCC
    Capability forwardedPCC = (pccUpdate.notEmpty() && 
                               pccUpdate.first.epoch==ct.epoch) ? 
                               pccUpdate.first.pcc:pcc;
    
    Perms pp = forwardedPCC.perms;
    if (ct.readA && cause.exp == None) begin
      CapExpCode tmp = checkRegAccess(pp,regA);
      if (tmp != None) cause = CapCause{exp:tmp, pcc: False, capReg: regA};
    end
    if (ct.readB && cause.exp == None) begin
      CapExpCode tmp = checkRegAccess(pp,regB);
      if (tmp != None) cause = CapCause{exp:tmp, pcc: False, capReg: regB};
    end
    if (ct.doWrite && cause.exp == None) begin
      CapExpCode tmp = checkRegAccess(pp,ct.writeReg);
      if (tmp != None) cause = CapCause{exp:tmp, pcc: False, capReg: ct.writeReg};
    end
    if (expectTags.a && !capA.isCapability && cause.exp == None) begin
      cause.exp = Tag;
    end
    if (expectTags.b && !capB.isCapability && cause.exp == None) begin
      cause = CapCause{exp:Tag, pcc: False, capReg: regB};
    end
    
    Capability writeback = capA;
    Capability newPcc = capA;
    
    CapReq aCapReq = CapReq{
      pc: capReq.pc,
      offset: capReq.offset,
      size: capReq.size,
      memOp: Read
    };
    debug($display("gotCapResponse! op=%d", capInst.op));
    CoProResponse response = CoProResponse{valid: True, 
                                           data: ?,  
                                           storeData:?, 
                                           exception: None
                                       };
    AddrExp addrExpA <- checkAndOffset(aCapReq, capA);
    LenCheck lenCheck = LenCheck{valid: False, length: capA.length, offset: aCapReq.offset, memSize: aCapReq.size, capReg: regA};
    Maybe#(CapCause) causeWrite = tagged Invalid;
    case (capInst.op)
      IncBase, IncBaseNull: begin
        lenCheck = LenCheck{valid: True, length: capA.length, offset: aCapReq.offset, memSize: None, capReg: regA};
        if (cause.exp == Tag && aCapReq.offset==0) begin
          cause.exp = None;
        //end else if (addrExpA.exp==Len && capA.length!=aCapReq.offset && cause.exp == None) begin
        //  cause.exp = Len;
        //end else if (capA.length < aCapReq.offset && cause.exp == None) begin
        //  cause.exp = Len;
        end else if (!capA.unsealed && aCapReq.offset!=0 && cause.exp == None) begin
          cause.exp = Seal;
        end
        if (capInst.op == IncBaseNull && aCapReq.offset==0) begin
          writeback = unpack(0);
          writeback.isCapability = True;
        end else if (cause.exp == None) begin
          UInt#(64) newBase = unpack(capA.base) + aCapReq.offset;
          writeback.base = pack(newBase);
          writeback.length = capA.length - aCapReq.offset;
        end
      end
      SetLen: begin
        lenCheck = LenCheck{valid: True, length: capA.length, offset: aCapReq.offset, memSize: None, capReg: regA};
        //if (addrExpA.exp==Len && capA.length!=aCapReq.offset && cause.exp == None) cause.exp = Len;
        //if (capA.length < aCapReq.offset && cause.exp == None) cause.exp = Len;
        if (!capA.unsealed && cause.exp == None) begin
          cause.exp = Seal;
        end else begin
          writeback.length = aCapReq.offset;
        end
      end
      SetType: begin
        lenCheck = LenCheck{valid: True, length: capA.length, offset: aCapReq.offset, memSize: Byte, capReg: regA};
        if (!capA.unsealed && cause.exp == None) begin
          cause.exp = Seal;
        end else if (!capA.perms.permit_set_type && cause.exp == None) begin
          cause.exp = SetType;
        end else begin
          UInt#(64) newType = unpack(capA.base) + aCapReq.offset;
          writeback.perms.permit_seal = True;
          writeback.oType_eaddr = pack(newType);
        end
      end
      AndPerm: begin
        if (!capA.unsealed && cause.exp == None) begin
          cause.exp = Seal;
        end
        writeback.perms = unpack(pack(capA.perms) & pack(aCapReq.offset)[30:0]);
      end
      SetConfig: begin
        if (!pcc.perms.access_CR31 && cause.exp == None) begin
          cause = CapCause{exp:CR31, pcc: True, capReg: ?};
        end else begin
          Bool pccWrite = (pack(aCapReq.offset)[7:0] == 8'hFF) ? True:False;
          CapCause causeTemp = CapCause{
                            exp:unpack(pack(aCapReq.offset)[15:8]), 
                            pcc: pccWrite, 
                            capReg: unpack(pack(aCapReq.offset)[4:0])
                        };
          causeWrite = tagged Valid causeTemp;
          causeUpdate.enq(causeTemp);
        end
      end
      ClearTag: begin
        writeback.isCapability = False;
      end
      GetTag: begin
        response.data = zeroExtend(pack(capA.isCapability));
      end
      BranchTagSet: begin
        response.data = zeroExtend(pack(capA.isCapability));
      end
      BranchTagUnset: begin
        response.data = zeroExtend(pack(!capA.isCapability));
      end
      GetLen: begin
        response.data = pack(capA.length);
      end
      GetBase: begin
        response.data = capA.base;
      end
      GetType: begin
        response.data = capA.oType_eaddr;
      end
      GetPCC: begin
        writeback = pcc;
      end
      GetConfig: begin
        if (!pcc.perms.access_CR31 && cause.exp == None) begin
          cause = CapCause{exp:CR31, pcc: True, capReg: ?};
        end
        // Use forwarded cause register if reading the cause register.
        CapCause forwardedCauseReg = (causeUpdate.notEmpty()) ? causeUpdate.first():causeReg;
        Bit#(8) regByte = (forwardedCauseReg.pcc) ? 8'hFF:zeroExtend(forwardedCauseReg.capReg);
        response.data = zeroExtend({pack(forwardedCauseReg.exp), regByte});
      end
      ReportRegs: begin
        `ifdef BLUESIM
          reportCapRegs.enq(True);
        `endif
      end
      GetPerm: begin
        response.data = zeroExtend(pack(capA.perms));
        response.valid = True;
      end
      GetUnsealed: begin
        response.data = zeroExtend(pack(capA.unsealed));
        response.valid = True;
      end
      L: begin // Load via Capability Register
        //AddrExp addrExp <- checkAndOffset(aCapReq, capA);
        response.data = addrExpA.addr;
        if (cause.exp == None) begin
          if (!capA.perms.permit_load) begin
            cause.exp = Load;
          end else if (!capA.unsealed) begin
            cause.exp = Seal;
          end
          //else if (addrExpA.exp != None) cause.exp = addrExpA.exp;
          lenCheck.valid = True;
        end
        //aCapReq.size = capInst.memSize;
      end
      S: begin // Store via Capability Register
        //AddrExp addrExp <- checkAndOffset(aCapReq, capA);
        response.data = addrExpA.addr;
        if (cause.exp == None) begin
          if (!capA.perms.permit_store) begin
            cause.exp = Store;
          end else if (!capA.unsealed) begin
            cause.exp = Seal;
          end
          //else if (addrExpA.exp != None) cause.exp = addrExpA.exp;
          lenCheck.valid = True;
        end
        //aCapReq.size = capInst.memSize;
      end
      JALR: begin // Jump and link Capability Register
        response.data = addrExpA.addr;
        if (!capA.perms.permit_execute && cause.exp == None) begin
          cause.exp = Exe;
        end else if (!capA.unsealed && cause.exp == None) begin
          cause.exp = Seal;
        end else if (!capA.perms.non_ephemeral && cause.exp == None) begin
          cause.exp = Ephem;
        end
        newPcc = capA;              // Link the current program counter capability.
        writeback = forwardedPCC;
      end
      JR: begin // Jump to Capability Register
        response.data = addrExpA.addr;
        if (!capA.perms.permit_execute && cause.exp == None) begin
          cause.exp = Exe;
        end else if (!capA.unsealed && cause.exp == None) begin
          cause.exp = Seal;
        end else if (!capA.perms.non_ephemeral && cause.exp == None) begin
          cause.exp = Ephem;
        end
        newPcc = capA;
      end
      SealCode: begin // Seal an executable capability
        if (!capA.unsealed && cause.exp == None) begin
          cause.exp = Seal;
        end else if (!capA.perms.permit_seal && cause.exp == None) begin
          cause.exp = PerSeal;
        end else if (!capA.perms.permit_execute && cause.exp == None) begin
          cause.exp = Exe;
        end else begin
          writeback.unsealed = False;
        end
      end
      SealData: begin // Seal a non-executable capability
        if (!capA.unsealed && cause.exp == None) begin
          cause.exp = Seal;
        end else if (!capB.unsealed && cause.exp == None) begin
          cause = CapCause{exp:Seal, pcc: False, capReg: regB};
        end else if (!capB.perms.permit_seal && cause.exp == None) begin
          cause = CapCause{exp:PerSeal, pcc: False, capReg: regB};
        end else if (capA.perms.permit_execute && cause.exp == None) begin
          cause.exp = Exe;
        end else begin
          writeback.unsealed = False;
          writeback.oType_eaddr = capB.oType_eaddr;
        end
      end
      LC: begin // Load Capability Register
        response.data = addrExpA.addr;
        if (cause.exp == None) begin
          if (!capA.perms.permit_load_cap) begin
            cause = CapCause{exp:LoadCap, pcc: False, capReg: regA};
          end else if (!capA.unsealed) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regA};
          end
          lenCheck = LenCheck{
            valid: True,
            length: capA.length,
            offset: aCapReq.offset,
            memSize: Line,
            capReg: regA
          };
          debug($display("Receiving Memory Response in CapCop."));
          writeback = ?;
        end
        aCapReq.memOp = Read;

        debug($display("Doing a CLCR"));
      end
      SC: begin // Store Capability Register
        response.data = addrExpA.addr;
        if (cause.exp == None) begin
          if (!capA.perms.permit_store_cap) begin
            cause = CapCause{exp:StoreCap, pcc: False, capReg: regA};
          end else if (!capA.unsealed) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regA};
          end else if (!capA.perms.permit_store_ephemeral_cap && !capB.perms.non_ephemeral) begin
            cause = CapCause{exp:StoreEph, pcc: False, capReg: regA};
          end
          lenCheck = LenCheck{
            valid: True,
            length: capA.length,
            offset: aCapReq.offset,
            memSize: Line,
            capReg: regA
          };
        end
        aCapReq.memOp = Write;
        if (capB.isCapability) 
          response.storeData = tagged CapLine truncate(pack(capB));
        else 
          response.storeData = tagged Line truncate(pack(capB));
        debug($display("Doing a CSCR"));
      end
      Unseal: begin
        if (capA.oType_eaddr != capB.oType_eaddr && cause.exp == None) begin
          cause = CapCause{exp:Type, pcc: False, capReg: regB};
        end else if (!capB.perms.permit_seal && cause.exp == None) begin
          cause = CapCause{exp:PerSeal, pcc: False, capReg: regB};
        end else if (capA.unsealed && cause.exp == None) begin
          cause = CapCause{exp:Seal, pcc: False, capReg: regA};
        end else begin
          writeback.unsealed = True;
          writeback.perms.non_ephemeral = capA.perms.non_ephemeral && capB.perms.non_ephemeral;
        end
      end
      GetRelBase: begin
        if (capA.length != 0 && capA.base != capB.base) begin
          response.data = capA.base - capB.base;
          lenCheck = LenCheck{
            valid: True,
            length: unpack(capA.base),
            offset: unpack(capB.base),
            memSize: Byte,
            capReg: regB
          };
        end else
          response.data = 0;
      end
      CheckPerms: begin
        if ((pack(capA.perms) & pack(aCapReq.offset)[30:0]) == 0) cause = CapCause{exp:CkPerms, pcc: False, capReg: regA};
      end
      CheckType: begin
        if (capA.oType_eaddr != capB.oType_eaddr) cause = CapCause{exp:Type, pcc: False, capReg: regA};
      end
      Call: begin
        `ifdef HARDCALL
          if (capA.unsealed && cause.exp == None) begin
            cause.exp = Seal;
          end else if (capB.unsealed && cause.exp == None) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regB};
          end else if (capA.oType_eaddr != capB.oType_eaddr && cause.exp == None) begin
            cause.exp = Type;
          end else if (!capA.perms.permit_execute && cause.exp == None) begin
            cause.exp = Exe;
          end else if (!capA.perms.permit_seal && cause.exp == None) begin
            cause.exp = PerSeal;
          end else if (capA.oType_eaddr < capA.base && cause.exp == None) begin
            cause.exp = Len;
          end else begin
            capA.unsealed = True;
            newPcc = capA;
            response.data = capA.oType_eaddr;
            capB.unsealed = True;
            writeback = capB;
          end
          lenCheck = LenCheck{
            valid: True,
            length: unpack(capA.base + pack(capA.length)),
            offset: unpack(capA.oType_eaddr),
            memSize: Word,
            capReg: regA
          };
        `else
          if (capA.unsealed && cause.exp == None) begin
            cause.exp = Seal;
          end else if (capB.unsealed && cause.exp == None) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regB};
          end else if (capA.oType_eaddr != capB.oType_eaddr && cause.exp == None) begin
            cause.exp = Type;
          end else if (!capA.perms.permit_execute && cause.exp == None) begin
            cause.exp = Exe;
          end else if (!capA.perms.permit_seal && cause.exp == None) begin
            cause.exp = PerSeal;
          end else if (capA.oType_eaddr < capA.base && cause.exp == None) begin
            cause.exp = Len;
          end else begin
            cause = CapCause{exp:Call, pcc: False, capReg: regA};
          end
          lenCheck = LenCheck{
            valid: True,
            length: unpack(capA.base + pack(capA.length)),
            offset: unpack(capA.oType_eaddr),
            memSize: Word,
            capReg: regA
          };
        `endif
      end
      Return: begin
        cause = CapCause{exp:Return, pcc: True, capReg: ?};
      end
      ERET: begin
        response.data = addrExpA.addr;
      end
      JumpRegister: begin
        response.data = forwardedPCC.base + pack(aCapReq.offset);
      end
      None: begin
        cause = CapCause{exp:None, pcc: ?, capReg: ?};
        response.valid = False;
      end
      default: begin
        cause = CapCause{exp:None, pcc: ?, capReg: ?};
        response.valid = False;
      end
    endcase

    // Make sure there's room for the branch delay if we have one.
    Address testPc = (ct.jump) ? capReq.pc+4:capReq.pc;
    // Don't register an exception in the case of a branch delay because we checked it with the branch.
    if (!capBranchDelay && 
        (testPc >= ((forwardedPCC.base + pack(forwardedPCC.length)) & signExtend(4'hC)) || 
        testPc < forwardedPCC.base)) begin
      cause = CapCause{exp: Len, pcc: True, capReg: ?};
      response.valid = True;
      response.exception = ICAP;
    end

    // Assign jump to the branch delay flag.  This will be reflected in the next cycle only.
    capBranchDelay <= ct.jump;
    if (ct.jump) pccUpdate.enq(BufferedPCC{pcc: newPcc, epoch: ct.epoch});

    response.exception = (cause.exp == None)?None:CAP;
    if (capInst.op != None) begin
      debug($display("Use Cap Response. op=%x, r1=%x r2=%x exception=%d response=%x At time %d",
          capInst.op, capInst.r1, capInst.r2, response.exception, response.data, $time));
    end
    if (response.exception != None && capInst.op != None) debug(
          $display("Capability Exception! op=0x%x, capCause=0x%x causeReg=%d r1=%d r2=%d At time %d",
          capInst.op, cause.exp, cause.capReg, capInst.r1, capInst.r2, $time));
    // Prepare a null writeback value in case we need a null writeback.
    CapControlToken ctOut = ct;
    ctOut.writeCap = writeback;

    if (capInst.op != None) begin
      debug($display("Use Cap Update. op=%x, r1=%x r2=%x At time %d", capInst.op, capInst.r1, capInst.r2, $time));
    end
    if (cause.exp == None && capInst.op==SetConfig) begin
      cause = fromMaybe(cause, causeWrite);
    end
    ctOut.cause = cause;
    regFile.writeRegSpeculative(writeback,ct.doWrite);
    exe2wbQ.enq(ctOut);
    lenChecks.enq(lenCheck);
    // Pick up any exceptions from the writeback register.
    if (response.exception==None) begin
      response.exception = (cause.exp == None)?None:CAP;
    end
    return response;
  endmethod

  method ActionValue#(CoProResponse)  getAddress();
    LenCheck lenCheck = lenChecks.first;
    lenChecks.deq();
    CapCause cause = CapCause{exp:None, pcc: False, capReg: lenCheck.capReg};
    CoProResponse response = CoProResponse{valid: True, data: ?, 
                                           storeData: ?, exception: None};
    UInt#(6) size = (
      case(lenCheck.memSize)
        Line: return 32;
        DoubleWord, DoubleWordLeft, DoubleWordRight: return 8;
        Word, WordLeft, WordRight: return 4;
        HalfWord: return 2;
        Byte: return 1;
        None: return 0;
        default: return 32; // Worst case default, just in case.
      endcase
    );
    if (lenCheck.valid) begin
      //Maybe#(Address) vAddr = tagged Valid pack(unpack(cap.base) + capReq.offset);
      UInt#(65) offsetSize = zeroExtend(lenCheck.offset) + zeroExtend(size);
      if (offsetSize > zeroExtend(lenCheck.length)) begin
        cause.exp = Len;
      end
      //$display("offset: %x, size: %x, offset+size: %x, cap.length: %x", capReq.offset, size, capReq.offset+zeroExtend(size), cap.length);
    end
    lenCause.enq(cause);
    if (cause.exp != None) begin
      response.exception = CAP;
    end
    return response;
  endmethod

  method Action commitWriteback(CapWritebackRequest wbReq) if (capState == Ready);
    //CapCause fetchCheckCause = fetchCause.first;
    //fetchCause.deq;
    CapCause lenCheckCause <- toGet(lenCause).get();
    CapControlToken ct     <- toGet(exe2wbQ).get();
    Bool commit = (!wbReq.dead && wbReq.mipsExp == None);
    if (ct.jump && commit) begin
      pcc <= pccUpdate.first.pcc;
      Capability dc = pccUpdate.first.pcc;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: PCC <- tag:%d u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", $time, coreId, dc.isCapability, dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `else
        trace($display("PCC <- tag:%d u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", dc.isCapability, dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `endif
    end
    if (ct.jump && pccUpdate.notEmpty) pccUpdate.deq;
    if (ct.capInst.op==SetConfig && causeUpdate.notEmpty) causeUpdate.deq;
    if (ct.doWrite && commit) begin
      if (ct.capInst.op == LC) ct.writeCap = wbReq.memResponse;
      `ifdef BLUESIM
        debugCaps[ct.writeReg] <= ct.writeCap;
      `endif
      Capability dc = ct.writeCap;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: CapReg %d <- tag:%d u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", $time, coreId, ct.writeReg, dc.isCapability, dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `else
        trace($display("CapReg %d <- tag:%d u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", ct.writeReg, dc.isCapability, dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
      `endif
    end
    regFile.writeReg(ct.writeReg, ct.writeCap, ct.doWrite, commit);
    if (!wbReq.dead && (wbReq.mipsExp==CAP||wbReq.mipsExp==CAPCALL)) begin
      // The instruction fetch cause has the highest priority for the cap cause register!
      //if (fetchCheckCause.exp != None) ct.cause=fetchCheckCause;
      // Length exception has priority over Call exception.
      if (ct.cause.exp==None || ct.cause.exp==Call) begin
        if (lenCheckCause.exp != None) ct.cause = lenCheckCause;
      end
      causeReg <= ct.cause;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception CapCause <- CapExpCode: 0x%x CauseReg: %d", $time, coreId, ct.cause.exp, ct.cause.capReg));
      `else 
        trace($display("Exception CapCause <- CapExpCode: 0x%x CauseReg: %d", ct.cause.exp, ct.cause.capReg));
      `endif
    end else if (ct.capInst.op == SetConfig && commit) begin
      causeReg <= ct.cause;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: SetConfig CapCause <- CapExpCode: 0x%x CauseReg: %d", $time, coreId, ct.cause.exp, ct.cause.capReg));
      `else
        trace($display("SetConfig CapCause <- CapExpCode: 0x%x CauseReg: %d", ct.cause.exp, ct.cause.capReg));
      `endif
    end
    if (!wbReq.dead) begin
      ExceptionEvent ee = None;
      if (wbReq.mipsExp!=None) ee = Except;
      else if (ct.capInst.op==ERET) ee = Return;
      if (ee != None) begin
        capState <= Except;
        // Request KCC (register 29) from the register file to be placed in PCC
        // Or request EPCC (register 31) from the register file to be returned to PCC
        CapReg fetch = (ee==Except) ? 29:31;
        expFetch.enq(fetch);
        exception.enq(ee);
      end
    end
    `ifdef BLUESIM
      if (reportCapRegs.notEmpty) begin
        debugInst($display("======   RegFile   ======"));
        debugInst($display("DEBUG CAP PCC u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", pcc.unsealed, pcc.perms, pcc.oType_eaddr, pcc.base, pcc.length));
        for (Integer i = 0; i<32; i=i+1) begin
          Capability dc = debugCaps[i];
          debugInst($display("DEBUG CAP REG %d u:%d perms:0x%x type:0x%x base:0x%x length:0x%x", i, dc.unsealed, dc.perms, dc.oType_eaddr, dc.base, dc.length));
        end
        debugInst(reportCapRegs.deq());
      end
    `endif
    debug($display("CapCop Writeback, instID:%d==capWBTags.id:%d, capWBTags.valid:%d, capWB.first.instID:%d", wbReq.instId, ct.instId, ct.doWrite, ct.instId));
  endmethod
endmodule
