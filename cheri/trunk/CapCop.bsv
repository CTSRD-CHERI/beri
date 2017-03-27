/*-
 * Copyright (c) 2016 Alexandre Joannou
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
import Debug::*;
import ClientServer::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import ForwardingPipelinedRegFile::*;
import ConfigReg::*;

typedef Bit#(3)  Select;
typedef Bit#(24) CType;
typedef Bit#(65) LAddress;

typedef enum {Memory, Branch, Arithmetic} ExecuteType
  deriving (Bits, Eq);

typedef struct {
  Address   pc;
  Bit#(64)  offset; // The offset into the capability register
  MemSize   size;
  MemOp     memOp;
} CapReq deriving(Bits, Eq, FShow);

typedef struct {
  Bool      isCapability;
  Bit#(8)   reserved;
  CType     otype;
  Perms     perms;
  Bool      sealed;
  Word      offset;
  Address   base;
  Bit#(64)  length;
} Capability deriving(Bits, Eq, FShow);

typedef Capability CapFat;

function CapFat unpackCap(Capability thin);
  return thin;
endfunction

typedef Bit#(5) CapReg;

typedef struct {
  CapOp           op;      // Operation
  CapReg          r0;      // Potential register name from bits 25-21
  CapReg          r1;      // bits 20-16
  CapReg          r2;      // bits 15-11
  CapReg          r3;      // bits 10-6
  Bool            doFetchA;
  CapReg          fetchA;
  Bool            doFetchB;
  CapReg          fetchB;
  Bool            doWriteDest;
  CapReg          dest;
  MemSize         memSize;
  InstId          instId;
  Epoch           epoch;
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
  Bool       writeRegMask;
  Bit#(32)   newRegMask;
  Epoch      epoch;
} CapControlToken deriving(Bits, Eq);

// Bounds check structure.  In the Execute stage, the coprocessor calculates
// the virtual address and hands it back to the main pipeline.  It then passes
// this structure to another stage inside the coprocessor, which notifies the
// MemAccess stage whether the access should be allowed.  
typedef struct {
  Bool      valid;
  LAddress  top;     // Last address, must be greater than or equal to address
  LAddress  address; // Address for the request
  LAddress  base;    // Base, must be less than or equal to address 
  MemSize   memSize; // Instruction ID that requests the update
  CapReg    capReg;
  Bool      ovExp;   // Throw an exception on overflow.
} LenCheck deriving(Bits, Eq);

typedef struct {
  Bit#(16)  soft;
  PermsHard hard;
} Perms deriving(Bits, Eq, FShow); // 31 bits

typedef struct {
  Bit#(4) unused;
  Bool acces_sys_regs; // EPCC
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
} PermsHard deriving(Bits, Eq, FShow); // 31 bits

typedef struct {
  CapReg     capReg;
  Bool       pcc;
  CapExpCode exp;
} CapCause deriving(Bits, Eq);

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

function Bool getSealed(Capability cap) = cap.sealed;

function CapExpCode checkRegAccess(Perms pp, CapReg cr);
  CapExpCode ret = None;
  if (!pp.hard.acces_sys_regs && (cr==27 || cr==28 || cr==29 || cr==30 || cr==31)) 
    ret = SysRegs;
  return ret;
endfunction

function Bool priveleged(Perms pp) = pp.hard.acces_sys_regs;

function Bit#(64) getPerms(CapFat cap);
  Bit#(15) hardPerms = signExtend(pack(cap.perms.hard));
  Bit#(16) softPerms = pack(cap.perms.soft);
  return zeroExtend({softPerms,hardPerms});
endfunction

typedef enum {Init, Ready} CapState
  deriving (Bits, Eq);
typedef enum {Except, Return, None} ExceptionEvent
  deriving (Bits, Eq);

interface CapCopIfc;
  method Action                           putCapInst(CapInst capInst);
  method Address                          getArchPc(Address pc, Epoch epoch); // Translate absolute virtual address to arch PC
  method ActionValue#(CoProResponse)      getCapResponse(CapReq capReq, ExecuteType opType);
  method ActionValue#(CoProResponse)      getAddress();
  method ActionValue#(CapFat)             commitWriteback(CapWritebackRequest wbReq);
endinterface

`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkCapCop#(Bit#(16) coreId)(CapCopIfc);
  Reg#(Capability)            pcc                 <- mkConfigReg(defaultCap);
  FIFOF#((BufferedPCC))       pccUpdate           <- mkUGFIFOF1();
  ForwardingPipelinedRegFileIfc#(Capability, 4) regFile <- mkForwardingPipelinedRegFile();
  `ifdef BLUESIM
    Reg#(Capability) debugCaps[32];
    for (Integer i=0; i<32; i=i+1) debugCaps[i]   <- mkReg(defaultCap);
    FIFOF#(Bool) reportCapRegs <- mkUGFIFOF;
  `endif
  FIFO#(CapControlToken)      inQ                 <- mkLFIFO;
  FIFO#(CapControlToken)      dec2exeQ            <- mkFIFO;
  FIFO#(CapControlToken)      exe2memQ            <- mkFIFO;
  FIFO#(CapControlToken)      mem2wbkQ            <- mkFIFO;
  FIFOF#(ExceptionEvent)      exception           <- mkFIFOF;
  Reg#(CapCause)              causeReg            <- mkReg(unpack(0));
  FIFOF#(CapCause)            causeUpdate         <- mkUGFIFOF;
  FIFO#(LenCheck)             lenChecks           <- mkFIFO;
  FIFO#(CapCause)             lenCause            <- mkFIFO;
  Reg#(Bool)                  capBranchDelay      <- mkReg(False);
  Reg#(CapState)              capState            <- mkConfigReg(Init);
  Reg#(UInt#(5))              count               <- mkReg(0);
  
  rule initialize(capState == Init);
    Capability cap = defaultCap;
    regFile.writeRaw(pack(count),defaultCap);
    count <= count + 1;
    if (count == 31) begin
      capState <= Ready;
    end
  endrule

  rule doException(capState == Ready);
    Capability regVal <- regFile.readRawGet();
    Capability dc = regVal;
    if (exception.first==Except) begin
      // We're resorting to installing KCC to increase privilege 
      trace($display("Time:%0d, Core:%0d, Thread:0 :: KCC->PCC s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, getLength(dc)));
      dc = pcc;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception in Capability Unit! PCC->EPCC s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, getLength(dc)));
      regFile.writeRaw(31,pcc);
      `ifdef BLUESIM
        debugCaps[31] <= pcc;
      `endif
    end else begin
      // We're restoring epcc into pcc.
      trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception Return in Capability Unit! EPCC->PCC s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, getLength(dc)));
    end
    pcc <= regVal;
    exception.deq();
  endrule
  
  // This rule moves from the input queue to a larger queue.
  // These are seperated for timing.
  rule inQtoBuffer;
    dec2exeQ.enq(inQ.first);
    inQ.deq;
  endrule
  
  Capability forwardedPCC = (pccUpdate.notEmpty() &&
                             pccUpdate.first.epoch==dec2exeQ.first.epoch) ?
                             pccUpdate.first.pcc:pcc;

  method Address getArchPc(Address pc, Epoch epoch);
    return (pc - forwardedPCC.base);
  endmethod

  method Action putCapInst(capInst) if (capState == Ready && !exception.notEmpty());
    ExpectTags expectTags = ExpectTags{a:False, b:False};
    CapCause cause = CapCause{exp: None, pcc: False, capReg: ?};
    Bool jump = False;
    case (capInst.op)
      SC,LC,L,S,IncBaseNull,AndPerm,SetBounds,SetBoundsExact,GetRelBase,LegacyL,LegacyS: begin 
        expectTags.a = True;
      end
      CheckPerms: begin
        expectTags.b = True;
      end
      CheckType,Call,Seal,Unseal: begin
        expectTags.a = True;
        expectTags.b = True;
      end
      CallFast: begin
        expectTags.a = True;
        expectTags.b = True;
        jump = True;
      end
      IncOffset: begin // Add to the pointer
        if (capInst.r3 == 0) capInst.op = Move;
      end
      JALR,JR: begin // Jump and link Capability Register
        expectTags.a = True;
        jump = True;
      end
    endcase
    // Throw exceptions if improper registers are read, but always fetch to avoid stalls.
    CapControlToken ctOut = CapControlToken{
                                  capInst: capInst, 
                                  cause: cause, 
                                  expectTags: expectTags,
                                  regA: capInst.fetchA,
                                  regB: capInst.fetchB,
                                  readA: capInst.doFetchA,
                                  readB: capInst.doFetchB,
                                  writeCap: ?,
                                  writeReg: ?,
                                  doWrite: False,
                                  jump: jump,
                                  instId: capInst.instId,
                                  writeRegMask: False,
                                  newRegMask: ?,
                                  epoch: capInst.epoch
                                };

    ctOut.cause.capReg = capInst.fetchA;

    if (capInst.doWriteDest && cause.exp == None) begin
      ctOut.writeReg = capInst.dest;
      ctOut.doWrite = True;
    end
    
    WriteType wt = None;
    if (ctOut.doWrite) begin
      if (capInst.op==LC) wt = Pending;
      else wt = Simple;
    end
    ReadReq regReq = ReadReq{
                    epoch: capInst.epoch,
                    a: capInst.fetchA,
                    b: capInst.fetchB,
                    write: wt,
                    dest: ctOut.writeReg,
                    fromDebug: False,
                    rawReq: False
                  };
    regFile.reqRegs(regReq);
    debug2("cap", $display("%t Selecting to fetch CapRegA=%d and CapRegB=%d for instId=%d", $time(), regReq.a, regReq.b, capInst.instId));
    inQ.enq(ctOut);

    if (capInst.op != None) begin
      debug2("cap", $display("Use Cap Request. op=%x, r1=%x r2=%x At time %d", capInst.op, capInst.r1, capInst.r2, $time));
    end
  endmethod

  method ActionValue#(CoProResponse) getCapResponse(CapReq capReq, ExecuteType opType) if (capState == Ready
                                     && !(pccUpdate.notEmpty && dec2exeQ.first.jump) // Not if there is an outstanding jump and this is a jump 
                                     && causeUpdate.notFull);
    CapControlToken ct <- toGet(dec2exeQ).get();
    CapInst capInst = ct.capInst;
    CapCause cause = ct.cause;
    ExpectTags expectTags = ct.expectTags;

    ReadRegs#(Capability) capRegs <- regFile.readRegs();
    Capability capA = capRegs.regA;
    Capability capB = capRegs.regB;
    CapReg regA = ct.regA;
    CapReg regB = ct.regB;
                               
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
    debug2("cap", $display("gotCapResponse! time:%0d op=", $time, fshow(capInst.op)));
    debug2("cap", $display("gotCapResponse! Operand A CapReg %d =", regA, fshow(capA)));
    debug2("cap", $display("gotCapResponse! Operand B CapReg %d =", regB, fshow(capB)));
    CoProResponse response = CoProResponse{valid: True, 
                                           data: capReq.offset,  
                                           storeData:?, 
                                           exception: None
                                       };
    Bool zeroOffset = (aCapReq.offset==0);
    LAddress offsetAddrExp = zeroExtend(capA.offset) + zeroExtend(pack(aCapReq.offset));
    LenCheck lenCheck = LenCheck{
                          valid: False, 
                          top: zeroExtend(capA.base) + zeroExtend(getLength(capA)),
                          address: offsetAddrExp,
                          base: zeroExtend(capA.base),
                          memSize: aCapReq.size, 
                          capReg: regA,
                          ovExp: False
                        };
    Maybe#(CapCause) causeWrite = tagged Invalid;
    case (opType)
      Arithmetic: begin
        case (capInst.op)
          /*IncBase, IncBase2: begin
            lenCheck = LenCheck{
                          valid: True, 
                          top: zeroExtend(capA.length), 
                          address: zeroExtend(aCapReq.offset), 
                          base: 0, 
                          memSize: None, 
                          capReg: regA,
                          ovExp: False
                      };
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
              Bit#(64) newBase = unpack(capA.base) + aCapReq.offset;
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
                Bit#(64) newOffset = unpack(capA.offset) + aCapReq.offset;
                writeback.offset = pack(newOffset);
              end
            end
          end*/
          Move: writeback = capA;
          SetOffset, IncBaseNull, IncOffset: begin
            if (capInst.op == IncBaseNull && zeroOffset) begin
              if (cause.exp == Tag) cause.exp = None; // Clear any tag exception.
              writeback = unpack(0);
            end else if (capA.isCapability && capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else begin
              if (capInst.op == IncOffset) writeback.offset = truncate(offsetAddrExp);
              else                         writeback.offset = capA.base   + zeroExtend(pack(aCapReq.offset));
            end
          end
          /*
          IncOffset: begin
            if (aCapReq.offset==0) begin
              writeback = capA;
            end else if (capA.isCapability && capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else begin
              Bit#(64) newOffset = unpack(capA.offset) + aCapReq.offset;
              writeback.offset = pack(newOffset);
            end
          end
          SetOffset: begin
            if (capA.isCapability && capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else begin
              Bit#(64) newOffset = unpack(capA.base) + aCapReq.offset;
              writeback.offset = pack(newOffset);
            end
          end
          
          SetLen: begin
            lenCheck = LenCheck{
                            valid: True, 
                            top: zeroExtend(capA.length), 
                            address: zeroExtend(aCapReq.offset), 
                            base: 0,
                            memSize: None,
                            capReg: regA,
                            ovExp: False
                      };
            //if (addrExpA.exp==Len && capA.length!=aCapReq.offset && cause.exp == None) cause.exp = Len;
            //if (capA.length < aCapReq.offset && cause.exp == None) cause.exp = Len;
            if (capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else begin
              writeback.length = aCapReq.offset;
            end
          end*/
          SetBounds, SetBoundsExact: begin
            if (capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end if (capA.offset < capA.base) begin // Check that the new base is >= old base.
              cause.exp = Len;
            end else begin
              writeback.length = aCapReq.offset;
              writeback.base = capA.offset;
            end
            lenCheck.valid = True;
            lenCheck.memSize = None;
            lenCheck.ovExp = True;
          end
          AndPerm: begin
            if (capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end
            writeback = capA;
            writeback.perms.hard = unpack(pack(capA.perms.hard) & truncate(pack(aCapReq.offset)));
            writeback.perms.soft = capA.perms.soft & truncate(pack(aCapReq.offset)[32:15]);
          end
          SetConfig: begin
            if (!priveleged(forwardedPCC.perms) && cause.exp == None) begin
              cause = CapCause{exp:SysRegs, pcc: True, capReg: ?};
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
          GetLen: begin
            response.data = pack(getLength(capA));
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
            writeback = forwardedPCC;
            writeback.offset = aCapReq.pc;
          end
          SetPCCOffset: begin
            writeback = forwardedPCC;
            writeback.offset = writeback.base + aCapReq.offset;
          end
          GetConfig: begin
            if (!priveleged(forwardedPCC.perms) && cause.exp == None) begin
              cause = CapCause{exp:SysRegs, pcc: True, capReg: ?};
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
            response.data = getPerms(capA);
            response.valid = True;
          end
          GetSealed: begin
            response.data = zeroExtend(pack(capA.sealed));
            response.valid = True;
          end
          Seal: begin
            writeback = capB;
            if (cause.exp == None) begin
              if (capB.sealed) begin
                cause = CapCause{exp:Seal, pcc: False, capReg: regB};
              end else if (capA.sealed) begin
                  cause.exp = Seal;
                end else if (!capA.perms.hard.permit_seal) begin
                  cause.exp = PerSeal;
                end else if (capA.offset[63:24] != 0) begin
                  cause.exp = Len;
              end else begin
                writeback.sealed = True;
                writeback.otype = truncate(capA.offset);
              end
              lenCheck.valid = True;
              lenCheck.memSize = Byte;
            end
          end
          Unseal: begin
            writeback = capB;
            if (!capB.sealed && cause.exp == None) begin
              cause = CapCause{exp:Seal, pcc: False, capReg: regB};
            end else if (capA.sealed && cause.exp == None) begin
              cause = CapCause{exp:Seal, pcc: False, capReg: regA};
            end else if (capA.offset != zeroExtend(capB.otype) && cause.exp == None) begin
              cause = CapCause{exp:Type, pcc: False, capReg: regA};
            end else if (!capA.perms.hard.permit_seal && cause.exp == None) begin
              cause = CapCause{exp:PerSeal, pcc: False, capReg: regA};
            end else begin
              writeback.sealed = False;
              writeback.otype = 0;
              writeback.perms.hard.non_ephemeral = capB.perms.hard.non_ephemeral && capA.perms.hard.non_ephemeral;
            end
            lenCheck.valid = True;
            lenCheck.memSize = Byte;
          end
          GetRelBase: begin
            // CToPtr.  CapB is the capability being turned into the pointer, CapA
            // is the ambient capability.
            // Turn zero-length capabilities, or capabilities with a pointer at the
            // start of the ambient capability into a canonical null capability.
            if (capB.isCapability) begin
              response.data = truncate(capB.offset - capA.base);
            end else
              response.data = 0;
          end
          Subtract: begin
            response.data = capA.offset - capB.offset;
          end
          CheckPerms: begin
            if ((pack(capB.perms) & pack(aCapReq.offset)[30:0]) != pack(aCapReq.offset)[30:0] && cause.exp == None) 
              cause = CapCause{exp:CkPerms, pcc: False, capReg: regB};
          end
          CheckType: begin
            if (capA.otype != capB.otype && cause.exp == None) 
              cause = CapCause{exp:Type, pcc: False, capReg: regB};
          end
          CmpEQ, CmpNE, CmpLT, CmpLE, CmpLTU, CmpLEU: begin
            Bool sgndCmp = !(capInst.op == CmpLTU || capInst.op == CmpLEU);
            Int#(65) aVal = unpack((sgndCmp) ? signExtend(capA.offset):zeroExtend(capA.offset));
            Int#(65) bVal = unpack((sgndCmp) ? signExtend(capB.offset):zeroExtend(capB.offset));
            Bool aNull = !capA.isCapability;
            Bool bNull = !capB.isCapability;
            Bool equal = (aVal==bVal);
            // If both are NULL, they are equal even if the values differ
            if (aNull != bNull) equal = False;
            
            Bool lessThan = ?;
            // If they are equal, A is not less than B.
            if (equal) lessThan = False;
            // If A is NULL and B is not, then it is less than
            else if (aNull != bNull) lessThan = (aNull && !bNull);
            else lessThan = (aVal < bVal);
            response.data = case (capInst.op)
                      CmpEQ: return (equal) ? 1:0;
                      CmpNE: return (equal) ? 0:1;
                      CmpLT, CmpLTU: return (lessThan) ? 1:0;
                      CmpLE, CmpLEU: return (lessThan || equal) ? 1:0;
                    endcase;
          end
          CmpEQX: response.data = (capA==capB) ? 1:0;
          Clear: begin
            ct.writeRegMask = True;
            if (!pp.hard.acces_sys_regs) begin
              if      (pack(aCapReq.offset)[27]!=1'b1)
                  cause = CapCause{exp: SysRegs, pcc: False, capReg: 27};
              else if (pack(aCapReq.offset)[28]!=1'b1)
                  cause = CapCause{exp: SysRegs, pcc: False, capReg: 28};
              else if (pack(aCapReq.offset)[29]!=1'b1)
                  cause = CapCause{exp: SysRegs, pcc: False, capReg: 29};
              else if (pack(aCapReq.offset)[30]!=1'b1)
                  cause = CapCause{exp: SysRegs, pcc: False, capReg: 30};
              else if (pack(aCapReq.offset)[31]!=1'b1)
                  cause = CapCause{exp: SysRegs, pcc: False, capReg: 31};
            end
            ct.newRegMask = truncate(aCapReq.offset);
            debug2("cap", $display("Got a CClearReg %x At time %d", ct.newRegMask, $time));
          end
          Call: begin
            if (!capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else if (!capB.sealed && cause.exp == None) begin
              cause = CapCause{exp:Seal, pcc: False, capReg: regB};
            end else if (capA.otype != capB.otype && cause.exp == None) begin
              cause.exp = Type;
            end else if (!capA.perms.hard.permit_execute && cause.exp == None) begin
              cause.exp = Exe;
            end else if (capB.perms.hard.permit_execute && cause.exp == None) begin
              cause = CapCause{exp:Exe, pcc: False, capReg: regB};
            end else if (capA.offset < capA.base && cause.exp == None) begin
              cause.exp = Len;
            end else if (cause.exp == None) begin
              cause = CapCause{exp:Call, pcc: False, capReg: regA};
            end
            lenCheck.memSize = Word;
          end
          Return: begin
            cause = CapCause{exp:Return, pcc: True, capReg: ?};
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
      end
      Branch: begin
        Bool nullTest = (pack(capA)==0);
        case (capInst.op)
          BranchTagSet: begin
            response.data = zeroExtend(pack(capA.isCapability));
          end
          BranchTagUnset: begin
            response.data = zeroExtend(pack(!capA.isCapability));
          end
          BranchEqZero: begin
            response.data = zeroExtend(pack(nullTest));
          end
          BranchNEqZero: begin
            response.data = zeroExtend(pack(!nullTest));
          end
          JALR: begin // Jump and link Capability Register
            //response.data = truncate(addrA);
            if (!capA.perms.hard.permit_execute && cause.exp == None) begin
              cause.exp = Exe;
            end else if (capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else if (!capA.perms.hard.non_ephemeral && cause.exp == None) begin
              cause.exp = Ephem;
            end
            lenCheck.valid = True;
            lenCheck.address = zeroExtend(capA.offset);
            lenCheck.memSize = Word;
            newPcc = capA;              
            response.data = capA.offset;
            writeback = forwardedPCC; // Link the current program counter capability.
            writeback.offset = pack(aCapReq.offset);
          end
          JR: begin // Jump to Capability Register
            //response.data = truncate(addrA);
            if (!capA.perms.hard.permit_execute && cause.exp == None) begin
              cause.exp = Exe;
            end else if (capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else if (!capA.perms.hard.non_ephemeral && cause.exp == None) begin
              cause.exp = Ephem;
            end
            lenCheck.valid = True;
            lenCheck.address = zeroExtend(capA.offset);
            lenCheck.memSize = Word;
            response.data = capA.offset;
            newPcc = capA;
          end
          CallFast: begin
            if (!capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else if (!capB.sealed && cause.exp == None) begin
              cause = CapCause{exp:Seal, pcc: False, capReg: regB};
            end else if (capA.otype != capB.otype && cause.exp == None) begin
              cause.exp = Type;
            end else if (!capA.perms.hard.permit_execute && cause.exp == None) begin
              cause.exp = Exe;
            end else if (capB.perms.hard.permit_execute && cause.exp == None) begin
              cause = CapCause{exp:Exe, pcc: False, capReg: regB};
            end else if (capA.offset < capA.base && cause.exp == None) begin
              cause.exp = Len;
            end else begin
              capA.sealed = False;
              newPcc = capA;
              response.data = capA.offset;
              capB.sealed = False;
              writeback = capB;
            end
            lenCheck.memSize = Word;
          end
          ERET: begin
            response.data = capA.base + pack(aCapReq.offset);
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
      end
      Memory: begin
        case (capInst.op)
          L,LegacyL: begin // Load via Capability Register
            response.data = truncate(offsetAddrExp);
            if (cause.exp == None) begin
              if (!capA.perms.hard.permit_load) begin
                cause.exp = Load;
              end else if (capA.sealed) begin
                cause.exp = Seal;
              end
              lenCheck.valid = True;
            end
          end
          S,LegacyS: begin // Store via Capability Register
            response.data = truncate(offsetAddrExp);
            if (cause.exp == None) begin
              if (!capA.perms.hard.permit_store) begin
                cause.exp = Store;
              end else if (capA.sealed) begin
                cause.exp = Seal;
              end
              lenCheck.valid = True;
            end
          end
          LC: begin // Load Capability Register
            response.data = truncate(offsetAddrExp);
            if (cause.exp == None) begin
              if (!capA.perms.hard.permit_load_cap) begin
                cause = CapCause{exp:LoadCap, pcc: False, capReg: regA};
              end else if (capA.sealed) begin
                cause = CapCause{exp:Seal, pcc: False, capReg: regA};
              end
              lenCheck.valid = True;
              lenCheck.memSize = CapWord;
              debug2("cap", $display("Receiving Memory Response in CapCop."));
            end
            aCapReq.memOp = Read;
            debug2("cap", $display("Doing a CLCR"));
          end
          SC: begin // Store Capability Register
            response.data = truncate(offsetAddrExp);
            if (cause.exp == None) begin
              if (!capA.perms.hard.permit_store_cap) begin
                cause = CapCause{exp:StoreCap, pcc: False, capReg: regA};
              end else if (capA.sealed) begin
                cause = CapCause{exp:Seal, pcc: False, capReg: regA};
              end else if (!capA.perms.hard.permit_store_ephemeral_cap && capB.isCapability && !capB.perms.hard.non_ephemeral) begin
                cause = CapCause{exp:StoreEph, pcc: False, capReg: regA};
              end
              lenCheck.valid = True;
              lenCheck.memSize = CapWord;
            end
            aCapReq.memOp = Write;
            if (capB.isCapability) 
              response.storeData = tagged CapLine truncate(pack(capB));
            else 
              response.storeData = tagged Line truncate(pack(capB));
            debug2("cap", $display("Doing a CSCR"));
            writeback = capB; // Just so that it can be reported in writeback.
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
      end
    endcase
    
    // Make sure there's room for the branch delay if we have one.
    Address testPc = capReq.pc;
    // Assign jump to the branch delay flag.  This will be reflected in the next cycle only.
    capBranchDelay <= ct.jump;
    if (ct.jump) begin
      testPc = capReq.pc+4;
      pccUpdate.enq(BufferedPCC{pcc: newPcc, epoch: ct.epoch});
    end
    
    // Don't register an exception in the case of a branch delay because we checked it with the branch.
    if (!capBranchDelay &&
        (testPc >= ((forwardedPCC.base + pack(getLength(forwardedPCC))) & signExtend(4'hC)) ||
        testPc < forwardedPCC.base)) begin
      cause = CapCause{exp: Len, pcc: True, capReg: ?};
      response.valid = True;
      response.exception = ICAP;
    end
    
    Bool deliverPipelineException = (cause.exp != None);
    if (cause.exp == Call || cause.exp == Return) deliverPipelineException = False;
    response.exception = (deliverPipelineException)?CAP:None;
    if (capInst.op != None) begin
      debug2("cap", $display("Use Cap Response. op=%x, r1=%x r2=%x exception=%d response=%x At time %d",
          capInst.op, capInst.r1, capInst.r2, response.exception, response.data, $time));
    end
    if (response.exception != None && capInst.op != None) debug(
          $display("Capability Exception! op=0x%x, capCause=0x%x causeReg=%d r1=%d r2=%d At time %d",
          capInst.op, cause.exp, cause.capReg, capInst.r1, capInst.r2, $time));
    // Prepare a null writeback value in case we need a null writeback.
    CapControlToken ctOut = ct;
    ctOut.writeCap = writeback;

    if (capInst.op != None) begin
      debug2("cap", $display("Use Cap Update. op=%x, r1=%x r2=%x At time %d", capInst.op, capInst.r1, capInst.r2, $time));
    end
    // Pick up any exceptions from the writeback register.
    /*if (response.exception==None) begin
      response.exception = (cause.exp == None || cause.exp == Call)?None:CAP;
    end*/
    if (cause.exp == None && capInst.op==SetConfig) begin
      cause = fromMaybe(cause, causeWrite);
    end
    ctOut.cause = cause;
    regFile.writeRegSpeculative(writeback,True);
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
    Bit#(6) size = (
      case(lenCheck.memSize)
        CapWord: return 32;
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
      // If we are not throwing an exception on overflow, zero out the top bits of all the operands.
      if (!lenCheck.ovExp) begin
        lenCheck.top[64] = 0;
        lenCheck.address[64] = 0;
        lenCheck.base[64] = 0;
      end
      LAddress lastByte = lenCheck.address + zeroExtend(size);
      if ((lastByte > lenCheck.top) ||
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

  method ActionValue#(CapFat) commitWriteback(CapWritebackRequest wbReq) if (capState == Ready/* && !exception.notEmpty()*/);
    //CapCause fetchCheckCause = fetchCause.first;
    //fetchCause.deq;
    CapCause lenCheckCause <- toGet(lenCause).get();
    CapControlToken ct     <- toGet(mem2wbkQ).get();
    Bool commit = (!wbReq.dead && wbReq.mipsExp == None);
    Capability newPcc = pcc;
    if (ct.jump && commit) begin
      newPcc = pccUpdate.first.pcc;
      Capability dc = pccUpdate.first.pcc;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: PCC <- tag:%d s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, dc.isCapability, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, getLength(dc)));
    end// else pcc.offset <= wbReq.pc;
    if (ct.jump && pccUpdate.notEmpty) pccUpdate.deq;
    if (ct.capInst.op==SetConfig && causeUpdate.notEmpty) causeUpdate.deq;
    if (ct.doWrite && commit) begin
      if (ct.capInst.op == LC) ct.writeCap = wbReq.memResponse;
      `ifdef BLUESIM
        debugCaps[ct.writeReg] <= ct.writeCap;
      `endif
      Capability dc = ct.writeCap;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: CapReg %d <- tag:%d s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", $time, coreId, ct.writeReg, dc.isCapability, dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, getLength(dc)));
    end
    regFile.writeReg(ct.writeCap, commit);
    if (!wbReq.dead && (wbReq.mipsExp==CAP  ||wbReq.mipsExp==CAPCALL||
                        wbReq.mipsExp==CTLBS||wbReq.mipsExp==ICAP)) begin
      // Length exception has priority over Call exception.
      if (ct.cause.exp==None || ct.cause.exp==Call) begin
        if (lenCheckCause.exp != None) ct.cause = lenCheckCause;
      end
      if (wbReq.mipsExp==CTLBS) ct.cause.exp = Ctlbs;
      if (wbReq.mipsExp==ICAP) ct.cause = CapCause{exp: Len, pcc: True, capReg: ?};
      causeReg <= ct.cause;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception CapCause <- CapExpCode: 0x%x CauseReg: %d", $time, coreId, ct.cause.exp, ct.cause.capReg));
    end else if (ct.capInst.op == SetConfig && commit) begin
      causeReg <= ct.cause;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: SetConfig CapCause <- CapExpCode: 0x%x CauseReg: %d", $time, coreId, ct.cause.exp, ct.cause.capReg));
    end
    if (commit && ct.writeRegMask) regFile.clearRegs(ct.newRegMask);
    if (!wbReq.dead) begin
      ExceptionEvent ee = None;
      if (wbReq.mipsExp!=None) ee = Except;
      else if (ct.capInst.op==ERET) ee = Return;
      if (ee != None) begin
        newPcc.offset = wbReq.pc;
        // Request KCC (register 29) from the register file to be placed in PCC
        // Or request EPCC (register 31) from the register file to be returned to PCC
        CapReg fetch = (ee==Except) ? 29:31;
        regFile.readRawPut(fetch);
        exception.enq(ee);
      end
    end
    `ifdef BLUESIM
      if (reportCapRegs.notEmpty) begin
        debugInst($display("======   RegFile   ======"));
        debugInst($display("DEBUG CAP COREID %d", coreId));
        debugInst($display("DEBUG CAP PCC t:%d s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", pcc.isCapability, pcc.sealed, pcc.perms, pcc.otype, pcc.offset-pcc.base, pcc.base, getLength(pcc)));
        for (Integer i = 0; i<32; i=i+1) begin
          Capability dc = debugCaps[i];
          debugInst($display("DEBUG CAP REG %d t:%d s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x", i, dc.isCapability, 
          dc.sealed, dc.perms, dc.otype, dc.offset-dc.base, dc.base, getLength(dc)));
        end
        debugInst(reportCapRegs.deq());
      end
    `endif
    if (!exception.notEmpty()) pcc <= newPcc;
    debug2("cap", $display("CapCop Writeback, instID:%d==capWBTags.id:%d, capWBTags.valid:%d, capWB.first.instID:%d", wbReq.instId, ct.instId, ct.doWrite, ct.instId));
    return ct.writeCap;
  endmethod
endmodule
