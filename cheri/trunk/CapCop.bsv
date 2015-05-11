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
import ForwardingPipelinedRegFileHighFrequency::*;
import ConfigReg::*;

typedef Bit#(3)  Select;
typedef Bit#(24) CType;

typedef struct {
  UInt#(64) offset; // The offset into the capability register
  Address   pc;     // PC to be validated.
  MemSize   size;
  MemOp     memOp;
} CapReq deriving(Bits, Eq);

typedef struct {
  Bool      isCapability;
  Bit#(8)   reserved;
  CType     otype;
  Perms     perms;
  Bool      sealed;
  Word      offset;
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
  Address    pc;
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

// Bounds check structure.  In the Execute stage, the coprocessor calculates
// the virtual address and hands it back to the main pipeline.  It then passes
// this structure to another stage inside the coprocessor, which notifies the
// MemAccess stage whether the access should be allowed.  
typedef struct {
  Bool      valid;
  UInt#(64) top;     // Last address, must be greater than or equal to address
  UInt#(64) address; // Address for the request
  UInt#(64) base;    // Base, must be less than or equal to address 
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
  offset: 64'b0,
  sealed: False,
  perms: unpack(31'h7FFFFFFF),
  otype: 24'b0,
  reserved: 0,
  isCapability: True
};

typedef struct {
  MemOp       memOp;
  Address     address;
  Bool        isCapability;
  Capability  capability;
  InstId      instId;
} CapMemAccess deriving(Bits, Eq);

function Address getBase(Capability cap) = cap.base;

function Address getLength(Capability cap) = pack(cap.length);

function Address getOffset(Capability cap) = cap.offset;

function CType getType(Capability cap) = cap.otype;

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
  method Action                           putCapInst(CapInst capInst);
  method Address                          getArchPc(Address pc, Epoch epoch); // Translate absolute virtual address to arch PC
  method ActionValue#(CoProResponse)      getCapResponse(CapReq capReq);
  method ActionValue#(CoProResponse)      getAddress();
  method ActionValue#(Maybe#(Capability)) commitWriteback(CapWritebackRequest wbReq);
endinterface

`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkCapCop#(Bit#(16) coreId)(CapCopIfc);
  Reg#(Capability)            pcc                 <- mkConfigReg(defaultCap);
  FIFOF#((BufferedPCC))       pccUpdate           <- mkUGFIFOF();
  ForwardingPipelinedRegFileIfc#(Capability, 2) regFile <- mkForwardingPipelinedRegFileHighFrequency();
  `ifdef BLUESIM
    Reg#(Capability) debugCaps[32];
    for (Integer i=0; i<32; i=i+1) debugCaps[i]   <- mkReg(defaultCap);
    FIFOF#(Bool) reportCapRegs <- mkUGFIFOF;
  `endif
  FIFO#(CapControlToken)      inQ                 <- mkLFIFO;
  FIFO#(CapControlToken)      dec2exeQ            <- mkFIFO;
  FIFO#(CapControlToken)      exe2memQ            <- mkFIFO;
  FIFO#(CapControlToken)      mem2wbkQ            <- mkFIFO;
  FIFO#(ExceptionEvent)       exception           <- mkFIFO;
  FIFO#(CapReg)               expFetch            <- mkFIFO;
  Reg#(CapCause)              causeReg            <- mkRegU;
  FIFOF#(CapCause)            causeUpdate         <- mkUGFIFOF;
  FIFO#(LenCheck)             lenChecks           <- mkFIFO;
  FIFO#(CapCause)             lenCause            <- mkFIFO;
  Reg#(Bool)                  capBranchDelay      <- mkReg(False);
  Reg#(CapState)              capState            <- mkConfigReg(Init);
  Reg#(UInt#(5))              count               <- mkReg(0);

  function ActionValue#(AddrExp) checkAndOffsetOffset(CapReq capReq, Capability cap);
    actionvalue
      UInt#(6) size = case (capReq.size)
        Line: return 32;
        DoubleWord, DoubleWordLeft, DoubleWordRight: return 8;
        Word, WordLeft, WordRight: return 4;
        HalfWord: return 2;
        Byte: return 1;
        default: return 32; // Worst case default, just in case.
      endcase;
      AddrExp retVal = AddrExp{
        addr: pack(unpack(cap.offset) + capReq.offset),
        exp: None
      };
      UInt#(65) endAddr = zeroExtend(unpack(retVal.addr)) + zeroExtend(size);
      UInt#(65) endLimit = zeroExtend(unpack(cap.base)) + zeroExtend(cap.length);
      //$display("offset: %x, size: %x, offset+size: %x, cap.length: %x", capReq.offset, size, capReq.offset+zeroExtend(size), cap.length);
      return retVal;
    endactionvalue
  endfunction


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
    ReadRegs#(Capability) tmp <- regFile.readRaw(expFetch.first, 0);
    if (exception.first==Except) begin
      Capability dc = pcc;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception in Capability Unit! PCC->EPCC u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `else
        trace($display("Exception in Capability Unit! PCC->EPCC u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `endif
      regFile.writeRaw(31,pcc);
      `ifdef BLUESIM
        debugCaps[31] <= pcc;
      `endif
      Capability kcc = tmp.regA;
      pcc <= kcc;
      dc = kcc;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: KCC->PCC u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `else
        trace($display("KCC->PCC u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `endif
    end else begin
      Capability epcc = tmp.regA;
      pcc <= epcc;
      Capability dc = epcc;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception Return in Capability Unit! EPCC->PCC u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `else
        trace($display("Exception Return in Capability Unit! EPCC->PCC u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
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
    if (capBranchDelay) forwardedPCC = pcc; // XXX Is this not fragile?
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
      GetBase, GetLen, GetOffset, GetType, GetPerm, GetUnsealed, GetTag: begin // Move From Capability Register Field
        fetchA = tagged Valid capInst.r2;
      end
      // For one of the capability-branch-if-tag-set/unset instructions, we
      // need to fetch the tag, which we'll then use to decide whether we branch
      BranchTagSet, BranchTagUnset: begin
        fetchA = tagged Valid capInst.r1;
      end
      IncBase, IncBase2, IncBaseNull, SetLen, AndPerm: begin // Move to Capability Register Field
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        wbReg = tagged Valid capInst.r1;
      end
      SetOffset, IncOffset: begin // Set the offset
        fetchA = tagged Valid capInst.r2;
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
        wbReg = tagged Valid capInst.r1; // Link register.
        jump = True;
      end
      JR: begin // Jump to Capability Register
        fetchA = tagged Valid capInst.r2;
        expectTags.a = True;
        jump = True;
      end
      Seal: begin // Seal a data capability
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
        // Allow even non-tagged capability casts to pointer because
        // the canonical null capability is not tagged as a capability.
        //expectTags.a = True;
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
      CmpEQ,CmpNE,CmpLT,CmpLE,CmpLTU,CmpLEU: begin
        fetchA = tagged Valid capInst.r2;
        fetchB = tagged Valid capInst.r3;
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
    AddrExp offsetAddrExp <- checkAndOffsetOffset(aCapReq, capA);
    LenCheck lenCheck = LenCheck{
                          valid: False, 
                          top: unpack(pack(capA.base)) + capA.length, 
                          address: unpack(pack(offsetAddrExp.addr)), 
                          base: unpack(pack(capA.base)), 
                          memSize: aCapReq.size, 
                          capReg: regA
                        };
    Maybe#(CapCause) causeWrite = tagged Invalid;
    case (capInst.op)
      IncBase, IncBaseNull, IncBase2: begin
        lenCheck = LenCheck{valid: True, top: capA.length, address: aCapReq.offset, base: 0, memSize: None, capReg: regA};
        if (cause.exp == Tag && aCapReq.offset==0) begin
          cause.exp = None;
        //end else if (addrExpA.exp==Len && capA.length!=aCapReq.offset && cause.exp == None) begin
        //  cause.exp = Len;
        //end else if (capA.length < aCapReq.offset && cause.exp == None) begin
        //  cause.exp = Len;
        end else if (capA.sealed && aCapReq.offset!=0 && cause.exp == None) begin
          cause.exp = Seal;
        end
        // If the offset is 0, then we are doing a cmove, so don't touch any of
        // the capability fields.
        if (capInst.op == IncBase && aCapReq.offset==0) begin
          // This is done above, but do it explicitly just to make sure...
          writeback = capA;
        // CFromPtr with a 0 source should give the canonical null capability.
        end else if (capInst.op == IncBaseNull && aCapReq.offset==0) begin
          writeback = unpack(0);
          //writeback.isCapability = True;
          //writeback.sealed = True;
        end else if (cause.exp == None) begin
          UInt#(64) newBase = unpack(capA.base) + aCapReq.offset;
          writeback.base = pack(newBase);
          writeback.length = capA.length - aCapReq.offset;
          // CFromPtr should set the offset to 0, so set the offset equal to the base
          if (capInst.op == IncBaseNull) begin
            writeback.offset = pack(newBase);
          // IncBase2 just increments the base.  IncBase leaves the offset
          // fixed, which means incrementing the base and the offset.
          end else if (capInst.op == IncBase) begin
            // Note that when we do break the ISA, we should really rationalise
            // the encodings too...
            UInt#(64) newOffset = unpack(capA.offset) + aCapReq.offset;
            writeback.offset = pack(newOffset);
          end
        end
      end
      IncOffset: begin
        if (capA.isCapability && capA.sealed && cause.exp == None) begin
          cause.exp = Seal;
        end else begin
          UInt#(64) newOffset = unpack(capA.offset) + aCapReq.offset;
          writeback.offset = pack(newOffset);
        end
      end
      SetOffset: begin
        if (capA.isCapability && capA.sealed && cause.exp == None) begin
          cause.exp = Seal;
        end else begin
          UInt#(64) newOffset = unpack(capA.base) + aCapReq.offset;
          writeback.offset = pack(newOffset);
        end
      end
      SetLen: begin
        lenCheck = LenCheck{valid: True, top: capA.length, address: aCapReq.offset, base: 0, memSize: None, capReg: regA};
        //if (addrExpA.exp==Len && capA.length!=aCapReq.offset && cause.exp == None) cause.exp = Len;
        //if (capA.length < aCapReq.offset && cause.exp == None) cause.exp = Len;
        if (capA.sealed && cause.exp == None) begin
          cause.exp = Seal;
        end else begin
          writeback.length = aCapReq.offset;
        end
      end
      SetType: begin
        lenCheck = LenCheck{valid: True, top: capA.length, address: aCapReq.offset, base: 0, memSize: Byte, capReg: regA};
        Bit#(64) rawType = pack(aCapReq.offset);
        CType newType = truncate(rawType);
        if (capA.sealed && cause.exp == None) begin
          cause.exp = Seal;
        end else if (!capA.perms.permit_set_type && cause.exp == None) begin
          cause.exp = SetType;
        end else if (rawType!=zeroExtend(newType) && cause.exp == None) begin
          cause.exp = SetType;
        end else begin
          writeback.perms.permit_seal = True;
          writeback.otype = newType;
        end
      end
      AndPerm: begin
        if (capA.sealed && cause.exp == None) begin
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
      GetOffset: begin
        Int#(64) offset = unpack(capA.offset) - unpack(capA.base);
        response.data = pack(offset);
      end
      GetType: begin
        response.data = zeroExtend(capA.otype);
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
        response.data = zeroExtend(pack(capA.sealed));
        response.valid = True;
      end
      L: begin // Load via Capability Register
        response.data = offsetAddrExp.addr;
        if (cause.exp == None) begin
          if (!capA.perms.permit_load) begin
            cause.exp = Load;
          end else if (capA.sealed) begin
            cause.exp = Seal;
          end
          lenCheck.valid = True;
          /*lenCheck.base = unpack(pack(capA.base));
          lenCheck.address = unpack(pack(offsetAddrExp.addr));
          lenCheck.top = unpack(pack(capA.base)) + capA.length;*/
        end
        //aCapReq.size = capInst.memSize;
      end
      S: begin // Store via Capability Register
        response.data = offsetAddrExp.addr;
        if (cause.exp == None) begin
          if (!capA.perms.permit_store) begin
            cause.exp = Store;
          end else if (capA.sealed) begin
            cause.exp = Seal;
          end
          lenCheck.valid = True;
          /*lenCheck.base = unpack(pack(capA.base));
          lenCheck.address = unpack(pack(offsetAddrExp.addr));
          lenCheck.top = unpack(pack(capA.base)) + capA.length;*/
        end
        //aCapReq.size = capInst.memSize;
      end
      JALR: begin // Jump and link Capability Register
        response.data = addrExpA.addr;
        if (!capA.perms.permit_execute && cause.exp == None) begin
          cause.exp = Exe;
        end else if (capA.sealed && cause.exp == None) begin
          cause.exp = Seal;
        end else if (!capA.perms.non_ephemeral && cause.exp == None) begin
          cause.exp = Ephem;
        end
        newPcc = capA;              // Link the current program counter capability.
        response.data = capA.offset;
        writeback = forwardedPCC;
        writeback.offset = pack(aCapReq.offset);
      end
      JR: begin // Jump to Capability Register
        response.data = addrExpA.addr;
        if (!capA.perms.permit_execute && cause.exp == None) begin
          cause.exp = Exe;
        end else if (capA.sealed && cause.exp == None) begin
          cause.exp = Seal;
        end else if (!capA.perms.non_ephemeral && cause.exp == None) begin
          cause.exp = Ephem;
        end
        response.data = capA.offset;
        newPcc = capA;
      end
      Seal: begin
        if (cause.exp == None) begin
          if (capA.sealed) begin
            cause.exp = Seal;
          end else if (capB.sealed) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regB};
          end else if (!capB.perms.permit_seal) begin
            cause = CapCause{exp:PerSeal, pcc: False, capReg: regB};
          end else if (capB.offset[63:24] != 0) begin
            cause = CapCause{exp:Len, pcc: False, capReg: regB};
          end else begin
            writeback.sealed = True;
            writeback.otype = truncate(capB.offset);
          end
          lenCheck.valid = True;
          lenCheck.base = unpack(pack(capB.base));
          lenCheck.address = unpack(pack(capB.offset));
          lenCheck.top = unpack(pack(capB.base)) + capB.length;
        end
      end
      LC: begin // Load Capability Register
        response.data = offsetAddrExp.addr;
        if (cause.exp == None) begin
          if (!capA.perms.permit_load_cap) begin
            cause = CapCause{exp:LoadCap, pcc: False, capReg: regA};
          end else if (capA.sealed) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regA};
          end
          /*lenCheck = LenCheck{
            valid: True,
            top: capA.length,
            address: aCapReq.offset,
            base: 0,
            memSize: Line,
            capReg: regA
          };*/
          lenCheck.valid = True;
          /*lenCheck.base = unpack(pack(capA.base));
          lenCheck.address = unpack(pack(offsetAddrExp.addr));
          lenCheck.top = unpack(pack(capA.base)) + capA.length;*/
          lenCheck.memSize = Line;
          debug($display("Receiving Memory Response in CapCop."));
          writeback = ?;
        end
        aCapReq.memOp = Read;

        debug($display("Doing a CLCR"));
      end
      SC: begin // Store Capability Register
        response.data = offsetAddrExp.addr;
        if (cause.exp == None) begin
          if (!capA.perms.permit_store_cap) begin
            cause = CapCause{exp:StoreCap, pcc: False, capReg: regA};
          end else if (capA.sealed) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regA};
          end else if (!capA.perms.permit_store_ephemeral_cap && capB.isCapability && !capB.perms.non_ephemeral) begin
            cause = CapCause{exp:StoreEph, pcc: False, capReg: regA};
          end
          /*lenCheck = LenCheck{
            valid: True,
            top: capA.length,
            address: aCapReq.offset,
            base: 0,
            memSize: Line,
            capReg: regA
          };*/
          lenCheck.valid = True;
          /*lenCheck.base = unpack(pack(capA.base));
          lenCheck.address = unpack(pack(offsetAddrExp.addr));
          lenCheck.top = unpack(pack(capA.base)) + capA.length;*/
          lenCheck.memSize = Line;
        end
        aCapReq.memOp = Write;
        if (capB.isCapability) 
          response.storeData = tagged CapLine truncate(pack(capB));
        else 
          response.storeData = tagged Line truncate(pack(capB));
        debug($display("Doing a CSCR"));
      end
      Unseal: begin
        if (capB.offset != zeroExtend(capA.otype) && cause.exp == None) begin
          cause = CapCause{exp:Type, pcc: False, capReg: regB};
        end else if (!capB.perms.permit_seal && cause.exp == None) begin
          cause = CapCause{exp:PerSeal, pcc: False, capReg: regB};
        end else if (!capA.sealed && cause.exp == None) begin
          cause = CapCause{exp:Seal, pcc: False, capReg: regA};
        end else begin
          writeback.sealed = False;
          writeback.perms.non_ephemeral = capA.perms.non_ephemeral && capB.perms.non_ephemeral;
          writeback.otype = 0;
        end
      end
      GetRelBase: begin
        // CToPtr.  CapA is the capability being turned into the pointer, CapB
        // is the ambient capability.
        Address offset = unpack(capA.offset);
        // Turn zero-length capabilities, or capabilities with a offset at the
        // start of the ambient capability into a canonical null capability.
        if (capA.isCapability) begin
          response.data = offset - capB.base;
          // Check that the offset is within the bounds of the ambient
          // capability
          /*lenCheck = LenCheck{
            valid: True,
            top: unpack(capB.base) + capB.length,
            address: unpack(offset),
            base: unpack(capB.base),
            memSize: Byte,
            capReg: regB
          };*/
        end else
          response.data = 0;
      end
      CheckPerms: begin
        if ((pack(capA.perms) & pack(aCapReq.offset)[30:0]) != pack(aCapReq.offset)[30:0]) cause = CapCause{exp:CkPerms, pcc: False, capReg: regA};
      end
      CheckType: begin
        if (capA.otype != capB.otype) cause = CapCause{exp:Type, pcc: False, capReg: regA};
      end
      CmpEQ, CmpNE, CmpLT, CmpLE, CmpLTU, CmpLEU: begin
        Bool sgndCmp = !(capInst.op == CmpLTU || capInst.op == CmpLEU);
        Int#(65) aVal = unpack((sgndCmp) ? signExtend(capA.offset):zeroExtend(capA.offset));
        Int#(65) bVal = unpack((sgndCmp) ? signExtend(capB.offset):zeroExtend(capB.offset));
        Bool aNull = !capA.isCapability;
        Bool bNull = !capB.isCapability;
        Bool equal = (aVal==bVal);
        // If one of them is NULL, they are only equal if both are NULL
        if (aNull != bNull) equal = (aNull && bNull);
        
        Bool lessThan = ?;
        // If they are equal, A is not less than B.
        if (equal) lessThan = False;
        // If one of them is NULL, they A is only less if A is NULL and B is not
        else if (aNull != bNull) lessThan = aNull && !bNull;
        else lessThan = (aVal < bVal);
        response.data = case (capInst.op)
                  CmpEQ: return (equal) ? 1:0;
                  CmpNE: return (equal) ? 0:1;
                  CmpLT, CmpLTU: return (lessThan) ? 1:0;
                  CmpLE, CmpLEU: return (lessThan || equal) ? 1:0;
                endcase;
      end
      Call: begin
        `ifdef HARDCALL
          if (!capA.sealed && cause.exp == None) begin
            cause.exp = Seal;
          end else if (!capB.sealed && cause.exp == None) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regB};
          end else if (capA.type != capB.type && cause.exp == None) begin
            cause.exp = Type;
          end else if (!capA.perms.permit_execute && cause.exp == None) begin
            cause.exp = Exe;
          end else if (!capA.perms.permit_seal && cause.exp == None) begin
            cause.exp = PerSeal;
          end else if (capA.offset < capA.base && cause.exp == None) begin
            cause.exp = Len;
          end else begin
            capA.sealed = False;
            newPcc = capA;
            response.data = capA.offset;
            capB.sealed = False;
            writeback = capB;
          end
          lenCheck = LenCheck{
            valid: True,
            top: unpack(capA.base + pack(capA.length)),
            address: unpack(capA.offset),
            base: 0,
            memSize: Word,
            capReg: regA
          };
        `else
          if (!capA.sealed && cause.exp == None) begin
            cause.exp = Seal;
          end else if (!capB.sealed && cause.exp == None) begin
            cause = CapCause{exp:Seal, pcc: False, capReg: regB};
          end else if (capA.otype != capB.otype && cause.exp == None) begin
            cause.exp = Type;
          end else if (!capA.perms.permit_execute && cause.exp == None) begin
            cause.exp = Exe;
          end else if (capB.perms.permit_execute && cause.exp == None) begin
            cause = CapCause{exp:Exe, pcc: False, capReg: regB};
          end else if (capA.offset < capA.base && cause.exp == None) begin
            cause.exp = Len;
          end else begin
            cause = CapCause{exp:Call, pcc: False, capReg: regA};
          end
          lenCheck = LenCheck{
            valid: True,
            top: unpack(capA.base + pack(capA.length)),
            address: unpack(capA.offset),
            base: unpack(capA.base),
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

	Bool deliverPipelineException = (cause.exp != None);
	if (cause.exp == Call || cause.exp == Return) deliverPipelineException = False;
    response.exception = (deliverPipelineException)?CAP:None;
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
    // Pick up any exceptions from the writeback register.
    /*if (response.exception==None) begin
      response.exception = (cause.exp == None || cause.exp == Call)?None:CAP;
    end*/
    if (cause.exp == None && capInst.op==SetConfig) begin
      cause = fromMaybe(cause, causeWrite);
    end
    ctOut.cause = cause;
    regFile.writeRegSpeculative(writeback,ct.doWrite);
    exe2memQ.enq(ctOut);
    lenChecks.enq(lenCheck);
    return response;
  endmethod

  method ActionValue#(CoProResponse)  getAddress();
    LenCheck lenCheck = lenChecks.first;
    lenChecks.deq();
    // Just pass the control token along; don't use it.  This prevents a deeper/slower FIFO.
    CapControlToken ct <- toGet(exe2memQ).get();
    mem2wbkQ.enq(ct);
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
      UInt#(65) offsetSize = zeroExtend(lenCheck.address) + zeroExtend(size);
      if ((offsetSize > zeroExtend(lenCheck.top)) ||
          (lenCheck.address < lenCheck.base)) begin
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

  method ActionValue#(Maybe#(Capability)) commitWriteback(CapWritebackRequest wbReq) if (capState == Ready);
    //CapCause fetchCheckCause = fetchCause.first;
    //fetchCause.deq;
    CapCause lenCheckCause <- toGet(lenCause).get();
    CapControlToken ct     <- toGet(mem2wbkQ).get();
    Bool commit = (!wbReq.dead && wbReq.mipsExp == None);
    Capability newPcc = pcc;
    if (ct.jump && commit) begin
      newPcc = pccUpdate.first.pcc;
      Capability dc = pccUpdate.first.pcc;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: PCC <- tag:%d u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, dc.isCapability, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `else
        trace($display("PCC <- tag:%d u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", dc.isCapability, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `endif
    end// else pcc.offset <= wbReq.pc;
    if (ct.jump && pccUpdate.notEmpty) pccUpdate.deq;
    if (ct.capInst.op==SetConfig && causeUpdate.notEmpty) causeUpdate.deq;
    if (ct.doWrite && commit) begin
      if (ct.capInst.op == LC) ct.writeCap = wbReq.memResponse;
      `ifdef BLUESIM
        debugCaps[ct.writeReg] <= ct.writeCap;
      `endif
      Capability dc = ct.writeCap;
      `ifdef MULTI
        trace($display("Time:%0d, Core:%0d, Thread:0 :: CapReg %d <- tag:%d u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, ct.writeReg, dc.isCapability, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `else
        trace($display("CapReg %d <- tag:%d u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", ct.writeReg, dc.isCapability, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
      `endif
    end
    regFile.writeReg(ct.writeReg, ct.writeCap, ct.doWrite, commit);
    if (!wbReq.dead && (wbReq.mipsExp==CAP||wbReq.mipsExp==CAPCALL||
                        wbReq.mipsExp==CTLBS)) begin
      // Length exception has priority over Call exception.
      if (ct.cause.exp==None || ct.cause.exp==Call) begin
        if (lenCheckCause.exp != None) ct.cause = lenCheckCause;
      end
      if (wbReq.mipsExp==CTLBS) ct.cause.exp = Ctlbs;
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
        newPcc.offset = wbReq.pc;
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
        debugInst($display("DEBUG CAP COREID %d", coreId));
        debugInst($display("DEBUG CAP PCC u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", pcc.sealed, pcc.perms, pcc.otype, pcc.offset-pcc.base, pcc.base, pcc.length));
        for (Integer i = 0; i<32; i=i+1) begin
          Capability dc = debugCaps[i];
          debugInst($display("DEBUG CAP REG %d u:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", i, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, dc.length));
        end
        debugInst(reportCapRegs.deq());
      end
    `endif
    pcc <= newPcc;
    debug($display("CapCop Writeback, instID:%d==capWBTags.id:%d, capWBTags.valid:%d, capWB.first.instID:%d", wbReq.instId, ct.instId, ct.doWrite, ct.instId));
    return (ct.doWrite && commit) ? tagged Valid ct.writeCap: tagged Invalid;
  endmethod
endmodule
