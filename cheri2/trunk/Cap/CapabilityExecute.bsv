/*-
 * Copyright (c) 2011 Jonathan Woodruff
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Michael Roe
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
import CHERITypes::*;
import Debug::*;
import FShow::*;
import Vector::*;

import CapabilityTypes::*;
import CapabilityMicroTypes::*;

import Library::*;
import Debug::*;

typedef struct{
  Value              result;
  Bool               bCond;
  Bool               capTag;
  Capability         capResult;
  Exception          exception;
  CapCause           capCause;  
  Bool               storeOp;
  Bool               loadOp;
  Address            memAddr;
  Maybe#(Address)    mNewPC;
  } CapExeResult deriving(Bits, Eq);

interface CapExecute;
  method ActionValue#(CapExeResult) capExec(CapOperation op, Capability pcc, Address pc, 
             Value vA, Bool validA, Capability cA, 
             Value vB, Bool validB, Capability cB, 
             Value exeResult, Bool bCond, Bit#(16) imm, CapCause capCause);
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkCapExecute(CapExecute);
  method capExec = capExecFN;
endmodule

//XXX ndave: we don't currently use exeResult, but we could definitely improve circuitry by exploiting decode. 
// The major threading bits are done in Decode and all that's left is simplifying CapapabilityExecute.

function ActionValue#(CapExeResult) capExecFN(
             CapOperation op, Capability pcc, Address pc,
             Value vA, Bool validA, Capability cA,  
             Value vB, Bool validB, Capability cB,
             Value exeResult, Bool bCond, Bit#(16) imm, CapCause capCause);
  actionvalue
    // Set up default return values
    Value                          rv = exeResult;
    Bool                         ctag = False;
    Capability                    crv = invalidCap;
    Maybe#(Exception)    newException = Invalid;
    CapCause              newCapCause = defaultCapCause;
    
    Address                   memAddr = ?;
    Bool                       loadOp = False;
    Bool                      storeOp = False;
    Address                    offset = signExtend(imm);
    Maybe#(Address)            mNewPC = Invalid;
	
    let causeA = invalidCapAccess(pcc, op.cA);
    let causeB = invalidCapAccess(pcc, op.cB);
    let causeD = invalidCapAccess(pcc, op.dest);
    let mAccessCause = firstValid(Vector::cons(causeD, Vector::cons(causeA, Vector::cons(causeB, Vector::nil))));

    let tagCauseA     = tagViolation(validA, op.cA);
    let tagCauseB     = tagViolation(validB, op.cB);
    let sealCauseA    = sealViolation(cA, op.cA);
    let sealCauseB    = sealViolation(cB, op.cB);
    let mTagSealCauseA= isValid(tagCauseA) ? tagCauseA : sealCauseA; // specially for csc
    let mTagSealCause = firstValid(Vector::cons(tagCauseA, Vector::cons(tagCauseB, Vector::cons(sealCauseA, Vector::cons(sealCauseB, Vector::nil)))));

    Value offsetcA = cA.cursor - cA.base;
    Value offsetcB = cB.cursor - cB.base;

    if (mAccessCause matches tagged Valid .cause)
      newCapCause = cause;
    else case (op.op)
      CapOp_MFC:
      begin
        let mfc_op = unpack(imm[2:0]);
        if (mfc_op == CCP_MFC_GetCause && !pcc.perms.access_EPCC)
          newCapCause = capException(ExC_AccessEPCCViolation, Invalid);
        else 
          begin 
            match {.nt, .ncrv, .nrv} = case (mfc_op) matches
              CCP_MFC_GetPerms   : return tuple3(False, ?, zeroExtend(pack(cA.perms)));
              CCP_MFC_GetType    : return tuple3(False, ?, zeroExtend(cA.otype));
              CCP_MFC_GetBase    : return tuple3(False, ?, cA.base);
              CCP_MFC_GetLength  : return tuple3(False, ?, cA.length);
              CCP_MFC_GetCause   : return tuple3(False, ?, zeroExtend(pack(capCause)));
              CCP_MFC_GetTag     : return tuple3(False, ?, zeroExtend(pack(validA)));
              CCP_MFC_GetSealed  : return tuple3(False, ?, zeroExtend(pack(cA.sealed)));
              CCP_MFC_GetPCC     : begin
                                     let pccResult = pcc;
                                     pccResult.cursor = pc + pcc.base;
                                     return tuple3(True, pccResult, pc);
                                   end
            endcase;
            ctag = nt;
            crv  = ncrv;
            rv   = nrv;
          end
      end
      CapOp_Seal:
      begin //a is cs, b is ct XXX rmn30 order of tagseal checks
        let newType = cB.cursor;
        if (mTagSealCause matches tagged Valid .cause)
          newCapCause = cause;
        else if (!cB.perms.permit_seal)
          newCapCause = capException(ExC_PermitSealViolation, op.cB);
        else if (offsetcB >= cB.length)
          newCapCause = capException(ExC_LengthViolation, op.cB);
        else if (newType >= 64'h1000000) // type must be less than 24 bits
          newCapCause = capException(ExC_LengthViolation, op.cB);
        else // do work
          begin 
            ctag = True;
            crv = cA;
            crv.sealed = True;
            crv.otype = truncate(newType);
          end
      end
      CapOp_Unseal:
      begin
        if (!validA) 
          newCapCause = capException(ExC_TagViolation, op.cA);
        else if (!validB)
          newCapCause = capException(ExC_TagViolation, op.cB);        
        else if (!cA.sealed)
          newCapCause = capException(ExC_SealViolation, op.cA);
        else if (cB.sealed)
          newCapCause = capException(ExC_SealViolation, op.cB);
        else if (offsetcB >= cB.length)
          newCapCause = capException(ExC_LengthViolation, op.cB);
        else if (zeroExtend(cA.otype) != cB.cursor)
          newCapCause = capException(ExC_TypeViolation, op.cB);
        else if (!cB.perms.permit_seal)
          newCapCause = capException(ExC_PermitSealViolation, op.cB);
        else
          begin        
            ctag = True;
            crv = cA;
            crv.sealed = False;
            crv.otype = 0;
            crv.perms.non_ephemeral = cA.perms.non_ephemeral && cB.perms.non_ephemeral;
          end
      end
      CapOp_MTC:
      begin
        CCP_MTC_Op mtc_op = unpack(imm[2:0]);
        case (mtc_op)
          CCP_MTC_AndPerms: begin // andperm
               if (mTagSealCause matches tagged Valid .cause)
                 newCapCause = cause;        
               else 
                 begin 
                   ctag = True;
                   crv = cA;
                   crv.perms = unpack (pack(cA.perms) & vA[30:0]);
                 end
             end
          CCP_MTC_SetType: begin // settype (dest = cd, cA = ca)
               CType newType = truncate(vA);
               if (mTagSealCause matches tagged Valid .cause)
                 newCapCause = cause;
               else if (!cA.perms.permit_set_type)
                 newCapCause = capException(ExC_PermitSetTypeViolation, op.cA);
               else if (zeroExtend(newType) != vA) // check that vA is not too big for type field
                 newCapCause = capException(ExC_PermitSetTypeViolation, op.cA);
               else if (vA >= cA.length)
                 newCapCause = capException(ExC_LengthViolation, op.cA);
               else if (cA.base + vA < cA.base)
                 newCapCause = capException(ExC_LengthViolation, op.cA);
               else
                 begin
                   ctag = True;
                   crv = cA;
                   crv.otype = newType;
                   crv.perms.permit_seal = True;
                 end
           end
          CCP_MTC_SetLength: begin // setlen
               if (mTagSealCause matches tagged Valid .cause)
                 newCapCause = cause;
               else if (vA > cA.length)
                 newCapCause = capException(ExC_LengthViolation, op.cA);
               else  
                 begin 
                   ctag = True;
                   crv = cA;
                   crv.length = vA;                
                 end                 
             end
          //CCP_MTC_SetCause: special case (see below)
          CCP_MTC_ClearTag: begin // cleartag
               // just leave ctag as False
               crv = cA;
             end
        endcase 
      end
      CapOp_CToPtr:
      begin
        if (tagCauseB matches tagged Valid .cause)
          newCapCause = cause;
        else if (!validA)
          rv = 0;
        else
          rv = cA.cursor - cB.base;
      end
      CapOp_SetCause: 
      begin
        if(!pcc.perms.access_EPCC) 
          begin
            newCapCause = capException(ExC_AccessEPCCViolation, Invalid);
            newException = Valid(Ex_CoProcess2);
          end
        else
          begin
            newCapCause = CapCause{capex: vA[15:8], capregname: vA[7:0]};
            newException = Valid(Ex_None);
          end
      end
      CapOp_CCall:
      begin
        if (tagCauseA matches tagged Valid .cause)
          newCapCause = cause;
        else if (tagCauseB matches tagged Valid .cause)
          newCapCause = cause;
        else if (!cA.sealed)
          newCapCause = capException(ExC_SealViolation, op.cA);
        else if (!cB.sealed)
          newCapCause = capException(ExC_SealViolation, op.cB);
        else if (cA.otype != cB.otype)
          newCapCause = capException(ExC_TypeViolation, op.cA);
        else if (!cA.perms.permit_execute)
          newCapCause = capException(ExC_PermitExecuteViolation, op.cA);
        else if (cB.perms.permit_execute)
          newCapCause = capException(ExC_PermitExecuteViolation, op.cB);
        else if (offsetcA > cA.length)
          newCapCause = capException(ExC_LengthViolation, op.cA);
        else
          begin
            newCapCause = capException(ExC_CallTrap, op.cA);
            newException = Valid(Ex_CP2Trap);
          end
      end
      CapOp_CReturn:
      begin
        newCapCause = capException(ExC_ReturnTrap, Invalid);
        newException = Valid(Ex_CP2Trap);
      end       
      CapOp_JR:
      begin 
        let newPC = offsetcA;
        if (mTagSealCause matches tagged Valid .cause)
          newCapCause = cause;
        else if (!cA.perms.permit_execute)
          newCapCause = capException(ExC_PermitExecuteViolation, op.cA);
        else if (!cA.perms.non_ephemeral)
          newCapCause = capException(ExC_NonEphermalViolation, op.cA);
        else if (newPC + 4 > cA.length)
          newCapCause = capException(ExC_LengthViolation, op.cA);
        else if (newPC[1:0] != 2'b00)
          newException = Valid(Ex_AddrErrLoad);
        else
          begin
            mNewPC = Valid(newPC);
            crv = cA;
          end
      end
      CapOp_Branch:
      begin
        // XXX rmn30 only throw this if branch taken
        if (pc + 4 + offset > pcc.length) // YYY ndave: it's unsatisfying that we do this in execute as well.
          newCapCause = capException(ExC_LengthViolation, Invalid);
        bCond = validA;
      end
      CapOp_CSCR:
      begin
        // rmn30 XXX should check source (cB) before base (cA). Could swap?
        match { .addr, .v } <- convOffset(SZ_32Byte, vA + offset, cA);
        rv = addr; // CP0 uses this to store the bad vaddr.
        if (mTagSealCauseA matches tagged Valid .cause) // NB only check cA, not cB
          newCapCause = cause;
        else if (!cA.perms.permit_store_cap)
          newCapCause = capException(ExC_PermitStoreCapViolation, op.cA);
        else if (!cA.perms.permit_store_ephemeral_cap && validB && !cB.perms.non_ephemeral)
          newCapCause = capException(ExC_PermitStoreEphemeralCapViolation, op.cA);
        else if (!v)
          newCapCause = capException(ExC_LengthViolation, op.cA);
        else if (addr[4:0] != 5'b0)
          newException = Valid(Ex_AddrErrStore);
        else
          begin // memory send
            // this will not take effect unless TLB throws the exception
            newCapCause = capException(ExC_TLBNoStoreCap, op.cB);
            newException = Valid (Ex_None);
            storeOp = True;
            memAddr = addr;
            crv     = cB;
            ctag    = validB;
          end
      end
      CapOp_CLCR:
      begin
        match { .addr, .v } <- convOffset(SZ_32Byte, vA + offset, cA);
        rv = addr; // CP0 uses this to store the bad vaddr.
        if (mTagSealCause matches tagged Valid .cause)
          newCapCause = cause;
        else if (!cA.perms.permit_load_cap)
          newCapCause = capException(ExC_PermitLoadCapViolation, op.cA);
        else if (!v)
          newCapCause = capException(ExC_LengthViolation, op.cA);
        else if (addr[4:0] != 5'b0)
          newException = Valid(Ex_AddrErrLoad);
        else
          begin // memory send
            loadOp  = True;
            memAddr = addr;
          end
      end        
      CapOp_Load, CapOp_Store:
      begin 
        match { .ls, .perm, .permEx} = (op.op == CapOp_Load) ? 
                                       tuple3("CapLoad" , cA.perms.permit_load , ExC_PermitLoadViolation) : 
                                       tuple3("CapStore", cA.perms.permit_store, ExC_PermitStoreViolation);
      
        debug2("capex", $display("CP2 EXE %s Op valA %b ", ls , validA, "op.cA: ", fshow(op.cA), "cA: ", fshow(cA), "\nvA: 0x%h ", vA, 
                       "offset: 0x%h", offset));
      
        match {.addr, .v} <- convOffset(op.accessSize, exeResult, cA);
        if (mTagSealCause matches tagged Valid .cause)
          newCapCause = cause;
        else if (!perm)
          newCapCause = capException(permEx, op.cA);
        else if (!v)
          newCapCause = capException(ExC_LengthViolation, op.cA);          
        else
          begin
            // pass capability through to memory access
            ctag = True;
            crv = cA;
            rv = addr;
          end
      end
      CapOp_Check:
      begin 
        case (unpack(imm[2:0]))
          CCP_CHECK_Perms: // CCheckPerm
            begin
              if (tagCauseA matches tagged Valid .cause)
                newCapCause = cause;
              else
                begin
                  if ((pack(cA.perms) & truncate(vA)) != truncate(vA))
                    newCapCause = capException(ExC_UserDefViolation, op.cA);
                end
            end
          CCP_CHECK_Type: //CCheckType
            begin
              if (tagCauseA matches tagged Valid .cause)
                newCapCause = cause;
              else if (tagCauseB matches tagged Valid .cause)
                newCapCause = cause;
              else if (!cA.sealed)
                newCapCause = capException(ExC_SealViolation, op.cA);
              else if (!cB.sealed)
                newCapCause = capException(ExC_SealViolation, op.cB);
              else if (cA.otype != cB.otype)
                newCapCause = capException(ExC_TypeViolation, op.cA);
            end
        endcase
      end
      CapOp_CIncBase, CapOp_CIncBase2, CapOp_CFromPtr:
      begin
        // these are the same except for when vA = 0 and treatment of offset
        ctag = validA;
        crv = cA;
        if (vA == 0) // Special cases for zero offset
          begin
            // For CIncBase[2] this is CMove so ignore exceptions
            if (op.op == CapOp_CFromPtr)
                   begin
              // CFromPtr null pointer case
                     match {.ct, .cr} = nullTaggedCap;
                     ctag = ct;
                     crv  = cr;
                   end
          end
        else
          begin
            if(mTagSealCause matches tagged Valid .cause)
              newCapCause = cause;
            else if (vA > cA.length)
              newCapCause = capException(ExC_LengthViolation, op.cA);
            else
              begin
                crv.base   = cA.base + vA;
                crv.length = cA.length - vA;
                crv.cursor = case (op.op)
                               CapOp_CIncBase:  return cA.cursor + vA; // keep cursor same relative to base
                               CapOp_CIncBase2: return cA.cursor; // just leave cursor as is, possibly out of bounds
                               CapOp_CFromPtr:  return crv.base;  // set cursor to zero relative to base
                             endcase;
              end
          end
      end
      CapOp_CIncOffset:
      begin
        //NB no tag check
        if (sealCauseA matches tagged Valid .cause &&& validA)
          newCapCause = cause;
        else
          begin
            ctag = validA;
            crv = cA;
            crv.cursor = cA.cursor + vA;
          end
      end
      CapOp_CSetOffset:
      begin
        //NB no tag check
        if (sealCauseA matches tagged Valid .cause &&& validA)
          newCapCause = cause;
        else
          begin
            ctag = validA;
            crv = cA;
            crv.cursor = cA.base + vA;
          end
      end
      CapOp_CGetOffset:
      begin
        //NB no tag/seal checks
        rv = offsetcA;
      end
      CapOp_Id: // default operation, carry through
      begin
        rv = exeResult;
      end
      CapOp_CCompare: // CPtrCmp
      begin
        let addrA = cA.cursor;
        let addrB = cB.cursor;
        CCP_Compare_Op cmp = unpack(imm[2:0]);
        // extend operands to 65 bits then do signed comparison
        let extend = (cmp == CCP_COMPARE_LTU || cmp == CCP_COMPARE_LEU) ? zeroExtend : signExtend;
        Int#(65) aSigned = unpack(extend(addrA));
        Int#(65) bSigned = unpack(extend(addrB));
        let lt = (!validA && validB) || ((validA == validB) && aSigned < bSigned);
        let eq = (validA == validB) && (addrA == addrB);
        rv = zeroExtend(pack(case (cmp)
           CCP_COMPARE_EQ: return eq;
           CCP_COMPARE_NE: return !eq;
           CCP_COMPARE_LT, CCP_COMPARE_LTU: return lt;
           CCP_COMPARE_LE, CCP_COMPARE_LEU: return lt || eq;
           endcase));
      end
    endcase 
    
    // If cap cause is set then throw a CoProcess2 exception unless
    // some other exception is given. In the case of setcause or csc
    // he other exception could be Ex_None -- this is so that we can
    // pass through the cause until writeback where we decide whether
    // to use it.
    CapException newCapEx = unpack(truncate(newCapCause.capex));
    let ex = newException matches tagged Valid .ex &&& True ? ex : (newCapEx != ExC_None ? Ex_CoProcess2 : Ex_None);
    debug2("capex", $display("CapExeResult: result: %h", rv, " tag:%b capResult: ", ctag, fshow(crv), " capCause: ", fshow(newCapCause)));

    return CapExeResult{
      result: rv,
      bCond: bCond,
      capTag: ctag, 
      capResult: crv,
      exception: ex,
      capCause: newCapCause,
      storeOp: storeOp,
      loadOp:  loadOp,
      memAddr: memAddr,
      mNewPC: mNewPC
    };
  endactionvalue
endfunction
