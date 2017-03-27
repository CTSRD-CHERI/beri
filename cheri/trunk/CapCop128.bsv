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

import Capability128Libs::*;
export Capability128Libs::*;

export mkCapCop;

typedef enum {Init, Ready} CapState
  deriving (Bits, Eq);
typedef enum {Except, Return, None} ExceptionEvent
  deriving (Bits, Eq);

// The full capability structure, including the "tag" bit.
typedef struct {
  Capability fromMem;
  CapFat     fromPipe;
  Bool       useFromMem;
  Bool       commit;
} CapWriteback deriving(Bits, Eq, FShow); // 128 bits + 1 (tag bit)
  
`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkCapCop#(Bit#(16) coreId)(CapCopIfc);
  Reg#(CapFat)                pcc                   <- mkConfigReg(defaultCapFat);
  FIFOF#(BufferedPCC)         pccUpdate             <- mkUGFIFOF1();
  ForwardingPipelinedRegFileIfc#(CapFat, 4) regFile <- mkForwardingPipelinedRegFile();
  `ifdef BLUESIM
    Reg#(CapFat) debugCaps[32];
    for (Integer i=0; i<32; i=i+1) debugCaps[i]   <- mkConfigReg(defaultCapFat);
    FIFOF#(Bool) reportCapRegs <- mkUGFIFOF;
  `endif
  FIFO#(CapFetchToken)        inQ                 <- mkLFIFO;
  FIFO#(CapFetchToken)        dec2exeQ            <- mkFIFO;
  FIFO#(CapControlToken)      exe2memQ            <- mkFIFO;
  FIFO#(CapControlToken)      mem2wbkQ            <- mkFIFO;
  FIFOF#(ExceptionEvent)      exception           <- mkFIFOF;
  Reg#(CapCause)              causeReg            <- mkConfigRegU;
  FIFOF#(CapCause)            causeUpdate         <- mkUGFIFOF;
  FIFO#(LenCheck)             lenChecks           <- mkFIFO;
  FIFO#(CapCause)             lenCause            <- mkFIFO;
  Reg#(Bool)                  capBranchDelay      <- mkReg(False);
  Reg#(CapState)              capState            <- mkConfigReg(Init);
  Reg#(UInt#(5))              count               <- mkReg(0);

  rule initialize(capState == Init);
    regFile.writeRaw(pack(count),defaultCapFat);
    count <= count + 1;
    if (count == 31) begin
      capState <= Ready;
    end
  endrule

  rule doException(capState == Ready);
    CapFat regVal <- regFile.readRawGet();
    CapFat dc = regVal;
    if (exception.first==Except) begin
      trace($display("Time:%0d, Core:%0d, Thread:0 :: KCC->PCC s:%d perms:0x%x type:0x%x offset:0x%x pointer:0x%x base:0x%x length:0x%x", 
                     $time, coreId, dc.sealed, getPerms(dc), dc.otype, getOffsetFat(dc, getTempFields(dc)), dc.pointer, getBotFat(dc, getTempFields(dc)), getLengthFat(dc, getTempFields(dc))));
      //dc <- updatePointer(pcc, zeroExtend(exceptionPointer), getTempFields(pcc), causeReg);
      dc = pcc;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception in Capability Unit! PCC->EPCC s:%d perms:0x%x type:0x%x offset:0x%x pointer:0x%x base:0x%x length:0x%x", 
                     $time, coreId, dc.sealed, getPerms(dc), dc.otype, getOffsetFat(dc, getTempFields(dc)), dc.pointer, getBotFat(dc, getTempFields(dc)), getLengthFat(dc, getTempFields(dc))));
      regFile.writeRaw(31,dc);
      `ifdef BLUESIM
        debugCaps[31] <= dc;
      `endif
    end else begin
      trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception Return in Capability Unit! EPCC->PCC s:%d perms:0x%x type:0x%x offset:0x%x pointer:0x%x base:0x%x length:0x%x",
                     $time, coreId, dc.sealed, getPerms(dc), dc.otype, getOffsetFat(dc, getTempFields(dc)), dc.pointer, getBotFat(dc, getTempFields(dc)), getLengthFat(dc, getTempFields(dc))));
    end
    regVal = setCapPointer(regVal, truncate(getBotFat(regVal, getTempFields(regVal))));
    pcc <= regVal;
    exception.deq();
  endrule
  
  // This rule moves from the input queue to a larger queue.
  // These are seperated for timing.
  rule inQtoBuffer;
    dec2exeQ.enq(inQ.first);
    inQ.deq;
  endrule
  
  CapFat forwardedPCC = (pccUpdate.notEmpty() && pccUpdate.first.epoch==dec2exeQ.first.epoch) ?
                         pccUpdate.first.pcc:pcc;

  method Address getArchPc(Address pc, Epoch epoch);
    return (pc - truncate(forwardedPCC.pointer));
  endmethod

  method Action putCapInst(capInst) if (capState == Ready && !exception.notEmpty());
    ExpectTags expectTags = ExpectTags{a:False, b:False};
    CapCause cause = CapCause{exp: None, pcc: False, capReg: ?};
    Bool jump = False;
    case (capInst.op)
      SC,LC,L,S,IncBaseNull,AndPerm,SetBounds,GetRelBase,LegacyL,LegacyS: begin 
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
    CapFetchToken ctOut = CapFetchToken{
                                  capInst: capInst, 
                                  cause: cause, 
                                  expectTags: expectTags,
                                  regA: capInst.fetchA,
                                  regB: capInst.fetchB,
                                  readA: capInst.doFetchA,
                                  readB: capInst.doFetchB,
                                  zeroOffset: False,
                                  pccCheck: True,
                                  doWrite: False,
                                  jump: jump,
                                  instId: capInst.instId,
                                  writeRegMask: False,
                                  epoch: capInst.epoch
                                };

    ctOut.cause.capReg = capInst.fetchA;

    if (capInst.doWriteDest && cause.exp == None) begin
      ctOut.writeReg = capInst.dest;
      ctOut.doWrite = True;
    end
    
    WriteType wt = None;
    if (ctOut.doWrite) begin
      case (capInst.op)
        LC: wt = Pending;
        `ifndef FAST_SETBOUNDS
          SetBounds, SetBoundsExact: wt = Pending;
        `endif
        default: wt = Simple;
      endcase
    end
    ReadReq regReq = ReadReq{
                    epoch: capInst.epoch,
                    a: capInst.fetchA,
                    b: capInst.fetchB,
                    write: wt,
                    dest: capInst.dest,
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
    CapFetchToken ft <- toGet(dec2exeQ).get();
    CapControlToken ct = fetchTok2ControlTok(ft);
    ct.writeCap = ?;
    ct.newPtr = ?;
    ct.pc = ?;
    ct.pccBot = ?;
    ct.pccTop = ?;
    ct.newRegMask = ?;
    CapInst capInst = ct.capInst;
    CapCause cause = ct.cause;
    ExpectTags expectTags = ct.expectTags;

    ReadRegs#(CapFat) capRegs <- regFile.readRegs();
    CapFat capA = capRegs.regA;
    CapFat capB = capRegs.regB;
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
    
    CapFat writeback = capA;
    
    CapReq aCapReq = CapReq{
      pc: capReq.pc,
      offset: capReq.offset,
      size: capReq.size,
      memOp: Read
    };
    debug2("cap", $display("gotCapResponse! op=%d", fshow(capInst.op)));
    debug2("cap", $display("gotCapResponse! Operand A CapReg %d =", regA, fshow(capA)));
    debug2("cap", $display("gotCapResponse! Operand B CapReg %d =", regB, fshow(capB)));
    Bit#(128) capBits = truncate(pack(packCap(capB)));
    Line line = truncate({capBits,capBits,capBits,capBits});
    CoProResponse response = CoProResponse{valid: True, 
                                           data: pack(capReq.offset), 
                                           storeData: tagged Line line, 
                                           exception: None
                                       };
    TempFields tempA = getTempFields(capA);
    LAddress capAbot = getBotFat(capA, tempA);
    LAddress capAtop = getTopFat(capA, tempA);
    TempFields tempPCC = getTempFields(forwardedPCC);
    //ct.capAbot = capAbot;
    //ct.capAtop = capAtop;
    TempFields tempB = getTempFields(capB);
    ct.zeroOffset = (aCapReq.offset==0);
    LAddress checkedPointer = capA.pointer + zeroExtend(pack(aCapReq.offset));
    //LAddress basePlusOffset = zeroExtend((capAbot + zeroExtend(pack(aCapReq.offset)))[63:0]);
    LenCheck lenCheck = LenCheck{
                          valid: False, 
                          top: capAtop, 
                          address: checkedPointer,   
                          bot: capAbot,
                          memSize: aCapReq.size, 
                          capReg: regA,
                          ovExp: False
                        };
    Maybe#(CapCause) causeWrite = tagged Invalid;
    CapFat newPcc = capA;
    //writeback <- updatePointerOffset(capA, checkedPointer, signExtend(aCapReq.offset));
    // Ensure that the optimiser knows that these will not use an address calculation operand, which involves an add.
    case (opType)
      Arithmetic: begin
        case (capInst.op)
          Move: writeback = capA;
          IncOffset: begin
            writeback <- incOffset(capA, checkedPointer, pack(aCapReq.offset), tempA, False);
            if (capA.isCapability && capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end 
          end
          SetOffset, IncBaseNull: begin
            writeback <- incOffset(capA, 0, pack(aCapReq.offset), tempA, True);
            if (capInst.op == IncBaseNull && ct.zeroOffset) begin
              if (cause.exp == Tag) cause.exp = None; // Clear any tag exception.
              writeback = unpack(0);
            end else if (capA.isCapability && capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end 
          end
          SetBounds, SetBoundsExact: begin
            if (capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end if (!capInBounds(capA, tempA, True)) begin
              cause.exp = Len;
            end else begin
              `ifndef FAST_SETBOUNDS
                // Stash the length in the "top" field, do the setBounds in the next cycle.
                ct.newPtr = zeroExtend(pack(aCapReq.offset));
              `else
                writeback <- setBounds(capA, pack(aCapReq.offset), (capInst.op==SetBoundsExact));
                if (cause.exp == None) begin
                  Bool setBoundsExactFailed = !writeback.isCapability;
                  if (setBoundsExactFailed) begin
                    cause = CapCause{exp: Inxact, pcc: False, capReg: ct.regB};
                    response.exception = CAP;
                  end // If there is no exception, the writeback will continue and succeed.
                end
              `endif
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
            LAddress length = getLengthFat(capA,tempA);
            response.data = truncate((length[64]==1) ? -1:length);
          end
          GetBase: begin
            response.data = truncate(capAbot);
          end
          GetOffset: begin
            //lenCheck.top = capA.pointer;
            response.data = getOffsetFat(capA, tempA);
            //response.data = truncate(capA.pointer - capAbot);
          end
          GetType: begin
            response.data = zeroExtend(capA.otype);
          end
          GetPCC: begin
            // Simply set the pointer to PC because we know it is in bounds,
            // and therefore surely within representable bounds.
            writeback = setCapPointer(forwardedPCC, capReq.pc);
          end
          SetPCCOffset: begin
            // Set the offset of PCC and write to a capability register.
            writeback <- incOffset(forwardedPCC, 0, pack(aCapReq.offset), tempPCC, True);
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
            writeback <- seal(capB, tempB, truncate(capA.pointer));
            Bool sealFailed = !writeback.isCapability;
            if (cause.exp == None) begin
              if (capB.sealed) begin
                cause = CapCause{exp:Seal, pcc: False, capReg: regB};
              end else if (capA.sealed) begin
                cause.exp = Seal;
              end else if (!capA.perms.hard.permit_seal) begin
                cause.exp = PerSeal;
              end else if (capA.pointer[63:24] != 0) begin
                cause.exp = Len;
              end else if (!capInBounds(capB, tempB, False)) begin
                // This is not a restriction in the uncompressed case!
                // This is to ensure that trimming the representation does
                // not leave us with a pointer out of new, smaller representable bounds.
                cause = CapCause{exp:Inxact, pcc: False, capReg: regB};
              end else if (sealFailed) begin
                cause = CapCause{exp: Inxact, pcc: False, capReg: ct.regB};
                response.exception = CAP;
              end // If there is no exception, the writeback will continue and succeed.
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
            end else if (capA.pointer != zeroExtend(capB.otype) && cause.exp == None) begin
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
            lenCheck.top = capB.pointer;
            if (!capB.isCapability) begin
              lenCheck.top = capAbot; // Result will be 0.
            end
            // CToPtr.  CapA is the capability being turned into the pointer, CapB
            // is the ambient capability.
            // Turn zero-length capabilities, or capabilities with a pointer at the
            // start of the ambient capability into a canonical null capability.
            //if (capB.isCapability) begin
            //  response.data = truncate(capB.pointer - capAbot);
            //end else
            //  response.data = 0;
          end
          Subtract: begin
            response.data = truncate(capA.pointer - capB.pointer);
          end
          CheckPerms: begin
            if ((pack(getPerms(capB)) & truncate(pack(aCapReq.offset))) != truncate(pack(aCapReq.offset)) && cause.exp == None) 
              cause = CapCause{exp:CkPerms, pcc: False, capReg: regB};
          end
          CheckType: begin
            if (capA.otype != capB.otype  && cause.exp == None) 
              cause = CapCause{exp:Type, pcc: False, capReg: regB};
          end
          CmpEQ, CmpNE, CmpLT, CmpLE, CmpLTU, CmpLEU: begin
            Bool sgndCmp = !(capInst.op == CmpLTU || capInst.op == CmpLEU);
            Int#(65) aVal = unpack((sgndCmp) ? signExtend(capA.pointer[63:0]):zeroExtend(capA.pointer[63:0]));
            Int#(65) bVal = unpack((sgndCmp) ? signExtend(capB.pointer[63:0]):zeroExtend(capB.pointer[63:0]));
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
          CmpEQX: begin
              response.data = architecturalFieldCompare(capA, capB) ? 1:0;
            end
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
            ct.newRegMask = truncate(pack(aCapReq.offset));
          end
          Call: begin
            Bool capAPermitSeal = False;
            if (capA.sealed) capAPermitSeal = True;
            if (!capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else if (!capB.sealed && cause.exp == None) begin
              cause = CapCause{exp:Seal, pcc: False, capReg: regB};
            end else if (capA.otype != capB.otype && cause.exp == None) begin
              cause.exp = Type;
            end else if (!capA.perms.hard.permit_execute && cause.exp == None) begin
              cause.exp = Exe;
            end else if (!capAPermitSeal && cause.exp == None) begin
              cause.exp = PerSeal;
            end else if (cause.exp == None) begin
              cause = CapCause{exp:Call, pcc: False, capReg: regA};
            end
            // We're just doing the bounds-check here since it doesn't involve an offset.
            lenCheck.memSize = Word;
            lenCheck.valid = True;
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
            if (!capA.perms.hard.permit_execute && cause.exp == None) begin
              cause.exp = Exe;
            end else if (capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else if (!capA.perms.hard.non_ephemeral && cause.exp == None) begin
              cause.exp = Ephem;
            end
            lenCheck.valid = True;
            lenCheck.address = zeroExtend(capA.pointer);
            lenCheck.memSize = Word;
            //newPcc = capA;              
            response.data = truncate(capA.pointer);
            //writeback <- updatePointer(forwardedPCC, zeroExtend(pack(aCapReq.offset)));
            //writeback = forwardedPCC; // Link the current program counter capability.
            writeback = setCapPointer(forwardedPCC, pack(aCapReq.offset));
            //writeback.pointer = zeroExtend(pack(aCapReq.offset));
          end
          JR: begin // Jump to Capability Register
            if (!capA.perms.hard.permit_execute && cause.exp == None) begin
              cause.exp = Exe;
            end else if (capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else if (!capA.perms.hard.non_ephemeral && cause.exp == None) begin
              cause.exp = Ephem;
            end
            lenCheck.valid = True;
            lenCheck.address = zeroExtend(capA.pointer);
            lenCheck.memSize = Word;
            response.data = truncate(capA.pointer);
            //newPcc = capA;
          end
          CallFast: begin
            Bool capAPermitSeal = False;
            if (capA.sealed) capAPermitSeal = True;
            if (!capA.sealed && cause.exp == None) begin
              cause.exp = Seal;
            end else if (!capB.sealed && cause.exp == None) begin
              cause = CapCause{exp:Seal, pcc: False, capReg: regB};
            end else if (capA.otype != capB.otype && cause.exp == None) begin
              cause.exp = Type;
            end else if (!capA.perms.hard.permit_execute && cause.exp == None) begin
              cause.exp = Exe;
            end else if (!capAPermitSeal && cause.exp == None) begin
              cause.exp = PerSeal;
            end else begin
              capA.sealed = False;
              //newPcc = capA;
              response.data = truncate(capA.pointer);
              capB.sealed = False;
              writeback = capB;
            end
            lenCheck.memSize = Word;
          end
          ERET: begin
            //response.data = truncate(basePlusOffset);
            ct.newPtr = zeroExtend(pack(aCapReq.offset));
          end
          JumpRegister: begin
            response.data = truncate(forwardedPCC.pointer) + pack(aCapReq.offset);
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
            response.data = truncate(checkedPointer);
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
            response.data = truncate(checkedPointer);
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
            response.data = truncate(checkedPointer);
            if (cause.exp == None) begin
              if (!capA.perms.hard.permit_load_cap) begin
                cause = CapCause{exp:LoadCap, pcc: False, capReg: regA};
              end else if (capA.sealed) begin
                cause = CapCause{exp:Seal, pcc: False, capReg: regA};
              end
              lenCheck.valid = True;
              lenCheck.memSize = CapWord;
              debug2("cap", $display("Receiving Memory Response in CapCop."));
              //writeback = ?;
            end
            aCapReq.memOp = Read;
            debug2("cap", $display("Doing a CLCR"));
          end
          SC: begin // Store Capability Register
            response.data = truncate(checkedPointer);
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
            
            if (capB.isCapability) response.storeData = tagged CapLine truncate(line);
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
      newPcc.pointer = capAbot;
      newPcc.ptr = newPcc.bot;
      pccUpdate.enq(BufferedPCC{pcc: newPcc, epoch: ct.epoch});
    end
    
    // Don't register an exception in the case of a branch delay because we checked it with the branch.
    ct.pccCheck = !capBranchDelay;
    ct.pc = zeroExtend(testPc);
    ct.pccTop = getTopFat(forwardedPCC, tempPCC) & signExtend(4'hC);
    ct.pccBot = forwardedPCC.pointer;
    if (!capBranchDelay && !forwardedPCC.isCapability) begin
      cause = CapCause{exp: Tag, pcc: True, capReg: ?};
      response.valid = True;
      response.exception = ICAP;
      debug2("cap", $display("PCC tag is not set! testPc: %x forwardedPCC: ",
          testPc, fshow(forwardedPCC)));
    end

    Bool deliverPipelineException = (cause.exp != None);
    if (cause.exp == Call || cause.exp == Return) deliverPipelineException = False;
    response.exception = (deliverPipelineException)?CAP:None;
    if (capInst.op != None) begin
      debug2("cap", $display("Use Cap Response. op=%x, r1=%x r2=%x At time %d",
          capInst.op, capInst.r1, capInst.r2, $time, fshow(response.storeData)));
    end
    if (response.exception != None && capInst.op != None) debug2(
          "cap", $display("Capability Exception! op=0x%x, capCause=0x%x causeReg=%d r1=%d r2=%d At time %d",
          capInst.op, cause.exp, cause.capReg, capInst.r1, capInst.r2, $time));
    // Prepare a null writeback value in case we need a null writeback.
    CapControlToken ctOut = ct;
    ctOut.writeCap = writeback;

    if (capInst.op != None) begin
      debug2("cap", $display("Use Cap Update. op=%x, r1=%x r2=%x At time %d", capInst.op, capInst.r1, capInst.r2, $time));
    end
    if (cause.exp == None && capInst.op==SetConfig) begin
      cause = fromMaybe(cause, causeWrite);
    end
    ctOut.cause = cause;
    regFile.writeRegSpeculative(writeback,ct.doWrite);
    exe2memQ.enq(ctOut);
    if (lenCheck.valid) debug2("cap", $display("Enqing LenCheck ", fshow(lenCheck)));
    lenChecks.enq(lenCheck);
    return response;
  endmethod

  method ActionValue#(CoProResponse)  getAddress();
    LenCheck lenCheck = lenChecks.first;
    lenChecks.deq();
    CapControlToken ct <- toGet(exe2memQ).get();
    CapCause cause = CapCause{exp:None, pcc: False, capReg: lenCheck.capReg};
    CoProResponse response = CoProResponse{valid: True, data: ?, 
                                        storeData: ?, exception: None};
    TempFields tempWriteCap = getTempFields(ct.writeCap);
    LAddress capAtop = lenCheck.top;
    LAddress capAbot = lenCheck.bot;
    // Perform "slow" (non-forwarded) operations.
    LAddress basePlusOffset = zeroExtend((capAbot + ct.newPtr)[63:0]);
    case (ct.capInst.op)
      `ifndef FAST_SETBOUNDS
        SetBounds, SetBoundsExact: begin
          CapFat original = ct.writeCap;
          ct.writeCap <- setBounds(ct.writeCap, truncate(ct.newPtr), (ct.capInst.op==SetBoundsExact));
          debug2("cap", $display("Did Setbounds! Initial Cap: ", fshow(original)));
          debug2("cap", $display("length: %x ", ct.newPtr));
          debug2("cap", $display("New Cap: ", fshow(ct.writeCap)));
          Bool setBoundsExactFailed = !ct.writeCap.isCapability;
          if (ct.cause.exp == None) begin
            if (setBoundsExactFailed) begin
              cause = CapCause{exp: Inxact, pcc: False, capReg: ct.regB};
              response.exception = CAP;
            end // If there is no exception, the writeback will continue and succeed.
          end
        end
      `endif
      GetRelBase: begin
        LAddress length = capAtop - capAbot;
        debug2("cap", $display("Calculating length! capAtop: %x, capAbot: %x, top-bot: %x ", capAtop, capAbot, length));
        response.data = truncate(length);
        //if (ct.capInst.op==GetLen && length[64]==1) response.data = -1;
      end
      ERET: begin
        response.data = truncate(basePlusOffset);
      end
    endcase
    mem2wbkQ.enq(ct);

    // Check the bounds of PCC.
    // These are related to instruction fetch, and so are the highest priority and overwrite previous exceptions.
    if (ct.pccCheck &&
        ((ct.pc >= ct.pccTop) || (ct.pc <  ct.pccBot))) begin
      cause = CapCause{exp: Len, pcc: True, capReg: ?};
      response.exception = ICAP;
      debug2("cap", $display("PCC out of bounds! testPc: %x pccTop: %x pccBot: %x ",
          ct.pc, ct.pccTop, ct.pccBot));
    end
    
    // Check the bounds of any capability operation.
    Address size = (
      case(lenCheck.memSize)
        CapWord: return 16;
        DoubleWord, DoubleWordLeft, DoubleWordRight: return 8;
        Word, WordLeft, WordRight: return 4;
        HalfWord: return 2;
        Byte: return 1;
        None: return 0;
        default: return 16; // Worst case default, just in case.
      endcase
    );
    if (lenCheck.valid) begin
      //Maybe#(Address) vAddr = tagged Valid pack(unpack(cap.base) + capReq.offset);
      // If we are not throwing an exception on overflow, zero out the top bits of all the operands.
      if (!lenCheck.ovExp) begin
        //lenCheck.top[65:64] = 0;
        lenCheck.address = zeroExtend(lenCheck.address[63:0]);
        lenCheck.bot = zeroExtend(lenCheck.bot[63:0]);
      end
      LAddress lastByte = lenCheck.address + zeroExtend(size);
      if (cause.exp == None &&
          (lastByte > lenCheck.top) ||
          (lenCheck.address < lenCheck.bot)) begin
        cause.exp = Len;
        response.exception = CAP;
      end
      debug2("cap", $display("Cap length check, At time %d,  bot: %x, addr: %x (size:%x), top: %x, cause.exp:%x,  cause.pcc:%x, cause.capReg:%d", 
                             $time, lenCheck.bot, lenCheck.address, size, lenCheck.top, 
                             cause.exp, cause.pcc, cause.capReg));
    end
    lenCause.enq(cause);
    return response;
  endmethod

  method ActionValue#(CapFat) commitWriteback(CapWritebackRequest wbReq) if (capState == Ready);
    //CapCause fetchCheckCause = fetchCause.first;
    //fetchCause.deq;
    CapCause lenCheckCause <- toGet(lenCause).get();
    CapControlToken ct     <- toGet(mem2wbkQ).get();
    Bool commit = (!wbReq.dead && wbReq.mipsExp == None);
    CapFat newPcc = pcc;
    CapFat dc = ?; // Convenience name for debug printing.
    CapWriteback wb = CapWriteback{
      fromMem: wbReq.memResponse,
      fromPipe: ct.writeCap,
      useFromMem: ct.capInst.op==LC,
      commit: commit
    };
    //capWriteback.enq(wb); // Use this line if we want to delay the writeback.
    // Do these two lines if we want to attempt to writeback without delay.
    CapFat writeCap = (wb.useFromMem) ? unpackCap(wb.fromMem):wb.fromPipe;
    regFile.writeReg(writeCap, wb.commit);
    // --------------------------------------------------------------------
    if (ct.jump && commit) begin
      newPcc = pccUpdate.first.pcc;
      dc = pccUpdate.first.pcc;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: PCC <- tag:%d s:%d perms:0x%x type:0x%x offset:0x%x pointer:0x%x base:0x%x length:0x%x", 
                     $time, coreId, dc.isCapability, dc.sealed, getPerms(dc), dc.otype, getOffsetFat(dc, getTempFields(dc)), dc.pointer, getBotFat(dc, getTempFields(dc)), getLengthFat(dc, getTempFields(dc))));
    end
    if (ct.jump && pccUpdate.notEmpty) pccUpdate.deq;
    if (ct.capInst.op==SetConfig && causeUpdate.notEmpty) causeUpdate.deq;
    if (ct.doWrite && commit) begin
      writeCap = (ct.capInst.op==LC) ? unpackCap(wbReq.memResponse):ct.writeCap;
      `ifdef BLUESIM
        debugCaps[ct.writeReg] <= writeCap;
      `endif
      dc = writeCap;
      debug2("cap", $display("CapReg %d <- ", ct.writeReg, fshow(writeCap)));
      trace($display("Time:%0d, Core:%0d, Thread:0 :: CapReg %d <- tag:%d s:%d perms:0x%x type:0x%x offset:0x%x pointer:0x%x base:0x%x length:0x%x",
      								 $time, coreId, ct.writeReg, dc.isCapability, dc.sealed, getPerms(dc), dc.otype, getOffsetFat(dc, getTempFields(dc)), dc.pointer, 
                       getBotFat(dc, getTempFields(dc)), getLengthFat(dc, getTempFields(dc)), fshow(dc)));
    end

    if (!wbReq.dead && (wbReq.mipsExp==CAP  ||wbReq.mipsExp==CAPCALL||
                        wbReq.mipsExp==CTLBS||wbReq.mipsExp==ICAP)) begin
      // The instruction fetch cause has the highest priority for the cap cause register!
      //if (fetchCheckCause.exp != None) ct.cause=fetchCheckCause;
      // Length exception has priority over Call exception.
      if (ct.cause.exp==None || ct.cause.exp==Call) begin
        if (lenCheckCause.exp != None) ct.cause = lenCheckCause;
      end
      if (wbReq.mipsExp==CTLBS) ct.cause.exp = Ctlbs;
      if (wbReq.mipsExp==ICAP) ct.cause = CapCause{exp: Len, pcc: True, capReg: ?};
      causeReg <= ct.cause;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: Exception CapCause <- CapExpCode: 0x%x CauseReg: %d PCC: %d", 
                     $time, coreId, ct.cause.exp, ct.cause.capReg, ct.cause.pcc));
    end else if (ct.capInst.op == SetConfig && commit) begin
      causeReg <= ct.cause;
      trace($display("Time:%0d, Core:%0d, Thread:0 :: SetConfig CapCause <- CapExpCode: 0x%x CauseReg: %d PCC: $d", 
                     $time, coreId, ct.cause.exp, ct.cause.capReg, ct.cause.pcc));
    end

    if (commit && ct.writeRegMask) regFile.clearRegs(ct.newRegMask);
    if (!wbReq.dead) begin
      ExceptionEvent ee = None;
      if (wbReq.mipsExp!=None) ee = Except;
      else if (ct.capInst.op==ERET) ee = Return;
      if (ee != None) begin
        // Just set the pointer because we know it is in bounds under normal circumstances.
        newPcc = setCapPointer(newPcc, wbReq.pc);
        // If it was out of bounds, treat as out of representable bounds.
        if (ct.cause.exp == Len && ct.cause.pcc) newPcc = nullifyCap(newPcc);
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
        debugInst($display("DEBUG CAP PCC t:%d s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x",
                           pcc.isCapability, pcc.sealed, getPerms(pcc), pcc.otype, getOffsetFat(pcc, getTempFields(pcc))[63:0], getBotFat(pcc, getTempFields(pcc))[63:0], getLengthFat(pcc, getTempFields(pcc))[63:0]));
        for (Integer i = 0; i<32; i=i+1) begin
          dc = debugCaps[i];
          debugInst($display("DEBUG CAP REG %d t:%d s:%d perms:0x%x type:0x%x offset:0x%x base:0x%x length:0x%x",
                             i, dc.isCapability, dc.sealed, getPerms(dc), dc.otype, getOffsetFat(dc, getTempFields(dc))[63:0], getBotFat(dc, getTempFields(dc))[63:0], getLengthFat(dc, getTempFields(dc))[63:0]));
        end
        debugInst(reportCapRegs.deq());
      end
    `endif
    if (!exception.notEmpty()) pcc <= newPcc;
    dc = newPcc;
    debug2("cap", $display("PCC <- t:%d s:%d perms:0x%x type:0x%x offset:0x%x pointer:0x%x base:0x%x length:0x%x",
                           dc.isCapability, dc.sealed, getPerms(dc), dc.otype, getOffsetFat(dc, getTempFields(dc)), dc.pointer, getBotFat(dc, getTempFields(dc)), getLengthFat(dc, getTempFields(dc))));
    debug2("cap", $display("CapCop Writeback, instID:%d==capWBTags.id:%d, capWBTags.valid:%d, capWB.first.instID:%d", wbReq.instId, ct.instId, ct.doWrite, ct.instId));
    return writeCap;
  endmethod
endmodule
