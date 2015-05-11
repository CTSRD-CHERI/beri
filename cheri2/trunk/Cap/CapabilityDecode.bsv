/*-
 * Copyright (c) 2011 Jonathan Woodruff
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2013-2014 Robert M. Norton
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
 *
 ******************************************************************************
 *
 * Authors: 
 *   Nirav Dave <ndave@csl.sri.com>
 *   Jonathan Woodruff <jonathan.woodruff@cl.cam.ac.uk>
 * 
 ******************************************************************************
 *
 * Description: Capability Decoding Logic
 * 
 ******************************************************************************/

import FShow::*;

import MIPS::*;
import CHERITypes::*;
import DecodeTypes::*;

import CapabilityTypes::*;
import CapabilityMicroTypes::*;

import Debug::*;



function ActionValue#(DecodedResult) decodeCapInst(Bit#(32) i, DecodedResult dec);
  actionvalue
    Maybe#(CapRegName) cdest = Invalid;
    Maybe#(CapRegName) copA  = Invalid;
    Maybe#(CapRegName) copB  = Invalid;

    Operand              opA = dec.decOperandA;
    Operand              opB = dec.decOperandB;

    let posA           = i[25:21];
    let posB           = i[20:16];
    let posC           = i[15:11];    
    let posD           = i[10:6];
    
    Destination            dest = dec.decDest;
    Maybe#(Bit#(26))    moffset = Invalid;

    Stage    whenWritten = dec.decWhenWritten;
    CapOp            cop = CapOp_Id;
    
    ALUOperation          aluOp = dec.decALUOperation;
    BranchOperation        brOp = dec.decBranchOperation;
    Maybe#(MemOperation) mMemOp = dec.decmMemOperation;
    
    AccessSize accessSz = SZ_32Byte; // conservative estimate
    
    Bool displayRF = False;

    let opcode = unpack(i[31:26]);
    let exception = Ex_None;
    
    case (opcode)
      Op_COP2: //OpCP2_CoP2:
        begin 
          copA          = Valid (posC);
          let subOpCode = unpack(i[25:21]);
          case (subOpCode)
            CCP_MFC: 
              begin 
                dest = Dest_Reg (posB);                
                cop = CapOp_MFC;
                copA = Valid (posC);
                case (i[2:0])
                  0: begin // CGetPerm
                     end
                  1: begin // CGetType
                     end                  
                  2: begin // CGetBase
                     end
                  3: begin // CGetLen
                     end
                  4: begin // CGetCause
                     end                  
                  5: begin // CGetTag
                     end                  
                  6: begin // CGetUnsealed
                     end                                    
                  7: begin // CGetPCC
                       copA  = Invalid;
                       cdest = Valid(posC);
                     end
                endcase
              end
            CCP_SealCode:
              begin
                cop = CapOp_SealCode;
                cdest = Valid (posB);
                copA  = Valid (posC);
                dest  = Dest_None;
              end
            CCP_SealData:
              begin
                cop = CapOp_SealData;              
                cdest = Valid (posB);
                copA  = Valid (posC);
                copB  = Valid (posD);
                dest  = Dest_None;
              end
            CCP_Unseal:
                begin
                cop = CapOp_Unseal;
                cdest = Valid (posB);
                copA  = Valid (posC);
                copB  = Valid (posD);
                dest  = Dest_None;
              end
            CCP_MTC:
                begin
                cop = CapOp_MTC;
                dest = Dest_None;
                case (unpack(i[2:0]))
                  CCP_MTC_AndPerms: begin // CAndPerm
                       cdest = Valid (posB);
                       copA  = Valid (posC);
                       opA   = Op_RegName (posD);
                     end
                  CCP_MTC_SetType: begin // CSetType
                       cdest = Valid (posB);
                       copA  = Valid (posC);
                       opA   = Op_RegName (posD);
                     end                  
                  CCP_MTC_IncBase: begin // CIncBase
                       cdest = Valid (posB);
                       copA  = Valid (posC);
                       opA   = Op_RegName (posD);
                     end
                  CCP_MTC_FromPtr: begin // CFromPtr
                       cdest = Valid (posB);
                       copA  = Valid (posC);
                       opA   = Op_RegName (posD);
                     end
                  CCP_MTC_SetLength: begin // CSetLen
                       cdest = Valid (posB);
                       copA  = Valid (posC);
                       opA   = Op_RegName (posD);
                     end
                  CCP_MTC_SetCause: begin // Set Cause -- treated as a special case
                       cop   = CapOp_SetCause;
                       opA   = Op_RegName (posD);
                     end
                  CCP_MTC_ClearTag: begin // ClearTag
                       cdest = Valid(posB);
                       copA  = Valid(posC);
                     end
                  CCP_MTC_DumpRegs: begin // Dump CREGS
                       displayRF = True;
                     end
                endcase
              end
            CCP_CCall:
              begin
                cop = CapOp_CCall;
                //TSS modify
                //mem <- pac
                //mem <- pcc
                //mem <- idc
                //pcc <- cs
                //idc <- cb
                //pc  <- cs.optype
                copA = Valid (posB);
                copB = Valid (posC);
              end
            CCP_CReturn:
              begin
                cop = CapOp_CReturn;
              end
            CCP_JALR, CCP_JR: // cap jump register (and maybe link)
              begin
                let link= subOpCode == CCP_JALR;
                cop     = CapOp_JR;
                dest    = link ? Dest_Reg (31) : Dest_None;
                cdest   = link ? Valid(24) : Invalid;
                copA    = Valid (posC);
                opA     = Op_RegName (posD);
                brOp    = BranchOperation{
                            op_brtype:         BR_OpA,
                            op_isLikely:       brOp.op_isLikely,
                            op_isLink:         link,
                            op_BranchOnTrue:   True,
                            op_BranchOnFalse:  True
                          };            
              end        
            CCP_BTS, CCP_BTU: // branch tag set (or not)
              begin 
                dest    = Dest_None;
                cop     = CapOp_Branch;
                moffset = Valid(signExtend(i[15:0]));
                copA    = Valid (posB);
                let bs  = subOpCode == CCP_BTS;
                brOp    = BranchOperation{
                   op_brtype:         BR_Offset,
                   op_isLikely:       brOp.op_isLikely,
                   op_isLink:         brOp.op_isLink,
                   op_BranchOnTrue:   bs,
                   op_BranchOnFalse:  !bs
                   };
              end
            CCP_CHECK:
              begin
                cop = CapOp_Check;
                case (unpack(i[2:0]))
                  CCP_CHECK_Perms:
                    begin
                      copA = Valid(posB);
                      opA  = Op_RegName(posD);
                    end
                  CCP_CHECK_Type:
                    begin
                      copA = Valid(posB);
                      copB = Valid(posC);
                    end
                  default:
                  exception = dec.decException;
                endcase
              end
            CCP_CToPtr:
              begin
                cop  = CapOp_CToPtr;
                dest = Dest_Reg(posB);
                copA = Valid(posC);
                copB = Valid(posD);
              end
          endcase
        end

      Op_SDC2: //OpCP2_CSCR:  // store cap
        begin
          aluOp = ALUOperation{ op_alutype: ALU_ADD,
                                op_signed: False,
                                op_size32: False,
                                op_useImm: True,
                                op_TrapOnZero: False,
                                 op_TrapOnNonZero: False
                               };
          cop    = CapOp_CSCR;
          copA   = Valid (posB);
          copB   = Valid (posA);
          opA    = Op_RegName (posC);
          dest   = Dest_None;
          moffset = Valid(signExtend(i[10:0]));
        end

      Op_LDC2: //OpCP2_CLCR: // load cap. to cap reg
        begin
          aluOp = ALUOperation{ op_alutype: ALU_ADD,
                                op_signed: False,
                                op_size32: False,
                                op_useImm: True,
                                op_TrapOnZero: False,
                                 op_TrapOnNonZero: False
                               };
          cop    = CapOp_CLCR;
          copA   = Valid (posB);
          cdest  = Valid (posA);
	  dest   = Dest_None;
          opA    = Op_RegName (posC);
          moffset = Valid(signExtend(i[10:0]));
        end

      Op_LWC2: //OpCP2_Load: //load via cap
        begin
          aluOp = ALUOperation{ op_alutype: ALU_ADD,
                                op_signed: False,
                                op_size32: False,
                                op_useImm: True,
                                op_TrapOnZero: False,
                                op_TrapOnNonZero: False
                               };
          cop  = CapOp_Load;
          copA = Valid (posB);
          dest = Dest_Reg (posA);
          opA  = Op_RegName (posC);
          moffset = Valid(signExtend(i[10:3]));
          whenWritten = Stage_Wb;
          let isLinked = i[2:0]==3'b111; // only LLD exists
          dec.decCP0Operation.cp0_setLL = isLinked;
          dec.decFlushAfterCommit       = True;
          mMemOp = tagged Valid MemOperation{
                     op_memtype: case (i[1:0]) matches
                                   2'b00: return MEM_LB;
                                   2'b01: return MEM_LH;
                                   2'b10: return MEM_LW;
                                   2'b11: return MEM_LD;
                                 endcase,
                     op_isMemLinked: isLinked,
                     op_signed:      (i[2] == 1'b1) && (i[1:0] != 2'b11)
                   };
          accessSz = case (i[1:0]) matches
                       2'b00: return SZ_1Byte;
                       2'b01: return SZ_2Byte;
                       2'b10: return SZ_4Byte;
                       2'b11: return SZ_8Byte;
                     endcase;
          
        end

      Op_SWC2: //OpCP2_Store: store via cap
        begin
          aluOp = ALUOperation{ op_alutype: ALU_ADD,
                                op_signed: False,
                                op_size32: False,
                                op_useImm: True,
                                op_TrapOnZero: False,
                                op_TrapOnNonZero: False
                               };
          cop  = CapOp_Store;
          copA = Valid (posB);
          opA  = Op_RegName (posC); // address (offset)
          opB  = Op_RegName (posA); // data
          moffset = Valid(signExtend(i[10:3]));
          let isLinked = i[2:0]==3'b111;
          dest = isLinked ? Dest_Reg (posA) : Dest_None;
          mMemOp = tagged Valid MemOperation{
                     op_memtype: case (i[1:0]) matches
                                   2'b00: return MEM_SB;
                                   2'b01: return MEM_SH;
                                   2'b10: return MEM_SW;
                                   2'b11: return MEM_SD;
                                 endcase,
                     op_isMemLinked: isLinked, // only SCD exists
                     op_signed:      (i[2] == 1'b1) && (i[1:0] != 2'b11)
                   };          
          accessSz = case (i[1:0]) matches
                       2'b00: return SZ_1Byte;
                       2'b01: return SZ_2Byte;
                       2'b10: return SZ_4Byte;
                       2'b11: return SZ_8Byte;
                     endcase;
        end
      Op_LB, Op_LBU,
      Op_LH, Op_LHU,
      Op_LW, Op_LWL, Op_LWR, Op_LL, Op_LWU,
      Op_LD, Op_LDL, Op_LDR, Op_LLD:
        begin
          cop  = CapOp_Load;
          copA = Valid (0); // ndave: normal mips instuctions check Cap 0
          accessSz = case (opcode)
                       Op_LB, Op_LBU:                        return SZ_1Byte;
                       Op_LH, Op_LHU:                        return SZ_2Byte;
                       Op_LW, Op_LWL, Op_LWR, Op_LL, Op_LWU: return SZ_4Byte;
                       Op_LD, Op_LDL, Op_LDR, Op_LLD:        return SZ_8Byte; 
                     endcase;
        end       
      Op_SB, Op_SH,
      Op_SW, Op_SWL, Op_SWR, Op_SC,
      Op_SD, Op_SDL, Op_SDR, Op_SCD:
        begin 
          cop  = CapOp_Store;  
          copA = Valid (0); // ndave: normal mips instuctions check Cap 0
          accessSz = case (opcode)
                       Op_SB:                         return SZ_1Byte;
                       Op_SH:                         return SZ_2Byte;
                       Op_SW, Op_SWL, Op_SWR, Op_SC:  return SZ_4Byte;
                       Op_SD, Op_SDL, Op_SDR, Op_SCD: return SZ_8Byte; 
                     endcase;
        end
      default: 
	  begin
            exception = dec.decException;
	  end
    endcase
    
    //==================================================================================================

    let rv = DecodedResult{
               decALUOperation:     aluOp,
               decBranchOperation:   brOp,
               decmMemOperation:   mMemOp,
               decCP0Operation: dec.decCP0Operation,  
             `ifdef CP1X
               decCP1XOperation: dec.decCP1XOperation,
             `endif
               decmMulOperation: dec.decmMulOperation,
               decmDivOperation: dec.decmDivOperation,
               decCapOperation: CapOperation{
                                  op:     cop,
                                  dest: cdest,
                                  whenWritten: Stage_Wb,
                                  cA: copA,
                                  cB: copB,
                                  hasResult: dest != Dest_None,
                                  accessSize: accessSz,
                                  displayRF: displayRF
                                },                 
               decFlushAfterCommit: dec.decFlushAfterCommit,
               decOperandA: opA,
               decOperandB: opB,
               decOffset: fromMaybe(dec.decOffset, moffset),
               decWhenWritten: whenWritten,
               decDest: dest,                
               decException: exception,
               decDebug: dec.decDebug
             };
    return rv;
  endactionvalue
endfunction
