/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2014 Robert M. Norton
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
 * 
 ******************************************************************************
 *
 * Description: Decode Logic
 * 
 ******************************************************************************/

import FShow::*;

import Debug::*;
import MIPS::*;
import CHERITypes::*;

import DecodeTypes::*;

`ifdef CAP
import CapabilityTypes::*;
import CapabilityMicroTypes::*;
import CapabilityDecode::*;
`endif

function ActionValue#(DecodedResult) decodeFN(Bit#(32) i, Address pc);
  actionvalue
    OpCode opcode     = unpack(i[31:26]);
    let imm           = i[25:0];
    let rs            = i[25:21];
    let rt            = i[20:16];  
    let rd            = i[15:11];
    let sa            = i[10:6];
    
    // rmn30: XXX what does unpack do with values which aren't defined in enumerations?
    FuncType   funcType   = unpack(i[5:0]);
    Func2Type  func2Type  = unpack(i[5:0]);
    Func3Type  func3Type  = unpack(i[5:0]);

    RegImmFunc regImmType = unpack(rt);

    CoProOp    copro0Type = unpack(rs);
    CP0Inst    cp0Inst    = unpack(i[5:0]);
    Bool     hasCP0Result = False;
    Bool            setLL = False;
    Bit#(3)        cp0sel = i[2:0]; // which coprocessor

    `ifdef CP1X
    Bool          useCP1X = False;
    Bool    hasCP1XResult = False;
    `endif

    //Initialize output
    ALUOp op_alu        = ALU_IdA;
    Bool  isSigned      = False;
    Bool  size32        = False;
    Bool  useImm        = False;

    Maybe#(MulOp) mulOp = Invalid;
    Bool        isDivOp = False;

    Maybe#(MemOp) op_mem = Invalid;
    Bool     isMemLinked = False;
  
    BranchOp      op_br = BR_PC8;
    
    CP0Inst      op_cp0 = CP0_NONE;
    
    Bool  flushOnCommit = False;
    Bool  trapTrue      = False;
    Bool  trapFalse     = False;
    Bool  branchTrue    = False;
    Bool  branchFalse   = False;  
    Bool  isLikely      = False;
    Bool  link          = False; // is link Op
    Operand opA         = tagged Op_RegName rs;
    Operand opB         = tagged Op_RegName rt;
    Stage whenWritten   = Stage_Exe;
    Destination dest    = tagged Dest_Reg rd;
    Exception exception = Ex_None;

    //debug state               
    Bool printRegisterState = False;
    Bool terminate          = False;
    
    `ifdef CAP
    Maybe#(CapOperation) mcapOp = tagged Invalid;
    `endif
                
    //$display("Decoding as (",opcode,",", rs,",",rt,",",rd,")"); 
    case (opcode)
      Op_SPECIAL: 
        case (funcType)
          F_SLL:
            begin
              op_alu = ALU_ShiftL;
              size32 = True;
              opA    = Op_Value (zeroExtend(sa)); // shift amount
            end
          F_MOVCI:
            begin
              debug($display("FIXME MOVCI unimplemented XXX")); //XXX
              exception = Ex_RI;
              op_cp0  = CP0_XCP1;
            end
          F_SRL:
            begin
              op_alu = ALU_ShiftR;
              size32 = True;
              opA    = Op_Value (zeroExtend(sa)); // shift amount
            end
          F_SRA:
            begin
              op_alu = ALU_ShiftR;
              isSigned = True;
              size32 = True;
              opA    = Op_Value (zeroExtend(sa)); // shift amount
            end
          F_SLLV: // shift is in rs 
            begin
              op_alu = ALU_ShiftL;
              size32 = True;
            end
          F_SRLV:
            begin
              op_alu = ALU_ShiftR;
              size32 = True;
            end
          F_SRAV:
            begin
              op_alu   = ALU_ShiftR;
              isSigned = True;
              size32   = True;
            end
          F_JR: // OpB is set as new PC
            begin
              op_alu = ALU_IdA;
              op_br  = BR_OpA;
              dest   = Dest_None;// no record
              branchTrue  = True;
              branchFalse = True;
            end
          F_JALR:
            begin // OpB is set as new PC, dest remains and we record PC + 8
              op_br  = BR_OpA;
              link   = True;
              branchTrue  = True;
              branchFalse = True;             
            end 
          F_MOVZ: // Conditional assignment can remove dest during execute
            begin
              op_alu = ALU_MOVZ;
            end
          F_MOVN: // Conditional assignment can remove dest during execute
            begin
              op_alu = ALU_MOVN;
            end
          F_SYSCALL:
            begin // no operands, so may stall less
              opA       = Op_Value (?);
              opB       = Op_Value (?);
              dest      = Dest_None;// no operation
              exception = Ex_SysCall;
            end
          F_BREAK:
            begin // no operands, so may stall less
              opA       = Op_Value (?);
              opB       = Op_Value (?);
              dest      = Dest_None;// no operation
              exception = Ex_BreakPoint;
            end
          F_SYNC:
            begin
              opA       = Op_Value (?);
              opB       = Op_Value (?);
              dest      = Dest_None;// no operation
              flushOnCommit = True;
            end
          F_MFHI:
            begin
              op_alu = ALU_IdA;
              opA    = Op_HI;
              opB    = Op_Value (?);
            end
          F_MTHI:
            begin
              op_alu = ALU_IdA;
              opB    = Op_Value (?);              
              dest   = Dest_HI;
            end
          F_MFLO:
            begin
              op_alu = ALU_IdA;
              opA    = Op_LO;
              opB    = Op_Value (?);              
            end
          F_MTLO:
            begin
              op_alu = ALU_IdA;  
              opB    = Op_Value (?);
              dest   = Dest_LO;
            end
          F_DSLLV:
            begin
              op_alu = ALU_ShiftL;  
            end
          F_DSRLV:
            begin
              op_alu = ALU_ShiftR;  
            end
          F_DSRAV:
            begin
              op_alu   = ALU_ShiftR;  
              isSigned = True;        
            end
          F_MULT:
            begin
              op_alu   = ALU_IdA;
              size32   = True;
              dest     = Dest_HILO;
              isSigned = True;
              mulOp    = Valid(MUL);
              whenWritten = Stage_Wb;
            end
          F_MULTU:
            begin
              op_alu      = ALU_IdA;
              size32      = True;
              dest        = Dest_HILO;
              mulOp       = Valid(MUL);
              whenWritten = Stage_Wb;
            end
          F_DIV:
            begin
              isDivOp = True;
              size32  = True;
              isSigned = True;
              dest    = Dest_HILO;
              whenWritten = Stage_Wb;
            end
          F_DIVU:
            begin
              isDivOp = True;
              size32 = True;
              dest   = Dest_HILO;
              whenWritten = Stage_Wb;             
            end
          F_DMULT:
            begin
              op_alu      = ALU_IdA; 
              dest        = Dest_HILO;
              mulOp       = Valid(MUL);
              isSigned    = True;
              whenWritten = Stage_Wb;             
            end
          F_DMULTU:
            begin
              op_alu      = ALU_IdA; 
              dest        = Dest_HILO;
              mulOp       = Valid(MUL);
              whenWritten = Stage_Wb;
            end  
          F_DDIV:
            begin
              isDivOp = True;
              whenWritten = Stage_Wb;
              dest     = Dest_HILO;
              isSigned = True;
            end
          F_DDIVU:
            begin
              isDivOp     = True;
              whenWritten = Stage_Wb;
              dest     = Dest_HILO;
            end  
          F_DDIVU:
            begin
              isDivOp     = True;
              whenWritten = Stage_Wb;
              dest   = Dest_HILO;
            end    
          F_ADD:
            begin
              op_alu   = ALU_ADD;  
              size32   = True;
              isSigned = True;
            end   
          F_ADDU:
            begin
              op_alu = ALU_ADD;  
              size32 = True;
            end   
          F_SUB:
            begin
              op_alu   = ALU_SUB;  
              size32   = True;
              isSigned = True;
            end   
          F_SUBU:
            begin
              op_alu = ALU_SUB;  
              size32 = True;
            end     
          F_AND:
            begin
              op_alu = ALU_AND;
            end
          F_OR:
            begin
              op_alu = ALU_OR;
            end
          F_XOR:
            begin
              op_alu = ALU_XOR;
            end  
          F_NOR:
            begin
              op_alu = ALU_NOR;
            end  
          F_SLT:
            begin //store LT into dest
              op_alu   = ALU_LT;
              isSigned = True;
            end  
          F_SLTU:
            begin //store LT unsigned into dest
              op_alu = ALU_LT;
            end  
          F_DADD:
            begin
              op_alu   = ALU_ADD;  
              isSigned = True;
            end   
          F_DADDU:
            begin
              op_alu   = ALU_ADD;  
            end   
          F_DSUB:
            begin
              op_alu   = ALU_SUB;  
              isSigned = True;
            end   
          F_DSUBU:
            begin
              op_alu = ALU_SUB;  
            end
          F_TGE:
            begin
              op_alu      = ALU_LT;  
              trapFalse   = True;
              dest        = Dest_None;
              isSigned    = True;
            end  
          F_TGEU:
            begin
              op_alu      = ALU_LT;  
              trapFalse   = True;
              dest        = Dest_None;
            end  
          F_TLT:
            begin
              op_alu      = ALU_LT;  
              trapTrue    = True;
              dest        = Dest_None;
              isSigned    = True;      
            end  
          F_TLTU:
            begin
              op_alu      = ALU_LT;  
              trapTrue    = True;
              dest        = Dest_None;
            end    
          F_TEQ:
            begin
              op_alu      = ALU_EQ;  
              trapTrue    = True;
              dest        = Dest_None;
            end    
          F_TNE:
            begin
              op_alu      = ALU_EQ;  
              trapFalse   = True;
              dest        = Dest_None;
            end    
          F_DSLL:
            begin
              op_alu      = ALU_ShiftL;
              opA         = Op_Value (zeroExtend(sa)); // shift amount
            end  
          F_DSRL:
            begin
              op_alu      = ALU_ShiftR;
              opA         = Op_Value (zeroExtend(sa)); // shift amount
            end  
          F_DSRA:
            begin
              op_alu      = ALU_ShiftR;
              isSigned    = True;       
              opA         = Op_Value (zeroExtend(sa)); // shift amount
            end  
          F_DSLL32:
            begin
              op_alu      = ALU_ShiftL;
              opA         = Op_Value (zeroExtend({1'b1,sa})); // shift amount
            end  
          F_DSRL32:
            begin
              op_alu      = ALU_ShiftR;
              opA         = Op_Value (zeroExtend({1'b1,sa})); // shift amount
            end  
          F_DSRA32:
            begin
              op_alu      = ALU_ShiftR;
              isSigned    = True;       
              opA         = Op_Value (zeroExtend({1'b1,sa})); // shift amount
            end  
          default:
            begin
              debug($display("Decode: Unhandled SPECIAL Inst type %d", funcType));
              exception   = Ex_RI;
            end          
        endcase // end SPECIAL
      Op_REGIMM:
        case (regImmType) 
          RI_BLTZ: //As Reg 0 == 0 we need not change opB
            begin
              dest          = Dest_None;
              op_alu        = ALU_LT; 
              opB           = Op_Value (0);
              op_br         = BR_Offset;
              branchTrue    = True;
              isSigned      = True;
            end
          RI_BGEZ:
            begin
              dest          = Dest_None;
              op_alu        = ALU_LT; 
              opB           = Op_Value (0);
              op_br         = BR_Offset;
              branchFalse   = True;
              isSigned      = True;           
            end
          RI_BLTZL:
            begin
              dest          = Dest_None;
              op_alu        = ALU_LT; 
              opB           = Op_Value (0);
              op_br         = BR_Offset;
              branchTrue    = True;
              isLikely      = True;
              isSigned      = True;           
            end  
          RI_BGEZL:
            begin
              dest          = Dest_None;
              op_alu        = ALU_LT; 
              opB           = Op_Value (0);
              op_br         = BR_Offset;
              branchFalse   = True;
              isLikely      = True;
              isSigned      = True;           
            end  
          RI_TEQI: // YYY sign extended imm, but op is not "signed"
            begin
              dest        = Dest_None;
              op_alu      = ALU_EQ;
              opB         = Op_Value (?);
              useImm      = True; 
              trapTrue    = True;
            end    
          RI_TGEI:
            begin
              dest        = Dest_None;
              op_alu      = ALU_LT;
              opB         = Op_Value (?);
              useImm      = True;
              trapFalse   = True;
              isSigned    = True;
            end
          RI_TGEIU:
            begin
              dest        = Dest_None;
              op_alu      = ALU_LT;
              opB         = Op_Value (?);
              useImm      = True;
              trapFalse   = True;
            end  
          RI_TLTI:
            begin
              dest        = Dest_None;
              op_alu      = ALU_LT;
              opB         = Op_Value (?);
              useImm      = True;
              trapTrue    = True;
              isSigned    = True;
            end    
          RI_TLTIU:
            begin
              dest        = Dest_None;
              op_alu      = ALU_LT;
              opB         = Op_Value (?);
              useImm      = True;
              trapTrue    = True;
            end    
          RI_TNEI:
            begin
              dest        = Dest_None;
              op_alu      = ALU_EQ;
              opB         = Op_Value (?);
              useImm      = True;
              trapFalse   = True;
            end    
          RI_BLTZAL:
            begin
              op_alu        = ALU_LT;        // condition <0
              opB           = Op_Value (0);
              op_br         = BR_Offset;     
              branchTrue    = True;
              link          = True; // ignore LT result for storage and use PC+8
              dest          = Dest_Reg (31); // store in addr 31
              isSigned      = True;           
            end
          RI_BGEZAL:
            begin
              op_alu        = ALU_LT; 
              opB           = Op_Value (0);
              op_br         = BR_Offset;
              branchFalse   = True;
              link          = True; // ignore LT result for storage and use PC+8
              dest          = Dest_Reg (31); // store in addr 31
              isSigned      = True;           
            end
          RI_BLTZALL:
            begin
              op_alu        = ALU_LT; 
              opB           = Op_Value (0);
              op_br         = BR_Offset;
              branchTrue    = True;
              isLikely      = True;
              link          = True; // ignore LT result for storage and use PC+8
              dest          = Dest_Reg (31); // store in addr 31
              isSigned      = True;           
            end  
          RI_BGEZALL:
            begin
              op_alu        = ALU_LT; 
              opB           = Op_Value (0);
              op_br         = BR_Offset;
              branchFalse   = True;
              isLikely      = True;
              link          = True; // ignore LT result for storage and use PC+8
              dest          = Dest_Reg (31); // store in addr 31
              isSigned      = True;           
            end  
          default:
            begin
              debug($display("Decode: Unhandled REGIMM Inst type %d", rt));
              exception = Ex_RI;
            end          
        endcase
      Op_J:     
        begin
          dest        = Dest_None;
          op_br       = BR_Abs;
          branchTrue  = True;
          branchFalse = True;
        end
      Op_JAL:     
        begin
          dest        = Dest_Reg (31);
          link        = True;
          op_br       = BR_Abs;
          branchTrue  = True;
          branchFalse = True;
        end
      Op_BEQ:
        begin
          dest          = Dest_None;
          op_alu        = ALU_EQ;
          branchTrue    = True;
          op_br         = BR_Offset;
        end
      Op_BNE:
        begin
          dest          = Dest_None;
          op_alu        = ALU_EQ;
          branchFalse   = True;
          op_br         = BR_Offset;
        end
      Op_BLEZ:
        begin
          dest          = Dest_None;
          op_alu        = ALU_LE;
          opB           = Op_Value (0);
          branchTrue    = True;
          op_br         = BR_Offset;
          isSigned      = True;   
        end
      Op_BGTZ:
        begin
          dest          = Dest_None;
          op_alu        = ALU_LE;
          opB           = Op_Value (0);
          branchFalse   = True;
          op_br         = BR_Offset;
          isSigned      = True;
        end
      Op_ADDI: // rt is dest
        begin
          op_alu   = ALU_ADD;          
          opB      = Op_Value (?);
          useImm   = True;
          dest     = Dest_Reg (rt);
          size32   = True;          
          isSigned = True;
        end
      Op_ADDIU: // rt is dest
        begin
          op_alu = ALU_ADD;
          opB    = Op_Value (?);
          useImm = True;
          dest   = Dest_Reg (rt);
          size32 = True;
        end  
      Op_SLTI:
        begin //store LT into dest
          op_alu   = ALU_LT;
          opB      = Op_Value (?);
          useImm   = True;
          dest     = Dest_Reg (rt);
          isSigned = True;
        end  
      Op_SLTIU:
        begin //store LT into dest
          op_alu   = ALU_LT;
          opB      = Op_Value (?);
          useImm   = True;
          dest     = Dest_Reg (rt);
        end        
      Op_ANDI:
        begin
          op_alu = ALU_AND;
          opB    = Op_Value (?);
          useImm = True;
          dest   = Dest_Reg (rt);
        end  
      Op_ORI:
        begin
          op_alu = ALU_OR;
          opB    = Op_Value (?);
          useImm = True;          
          dest   = Dest_Reg (rt);
        end
      Op_XORI:
        begin
          op_alu = ALU_XOR;
          opB    = Op_Value (?);
          useImm = True;          
          dest   = Dest_Reg (rt);
        end
      Op_LUI: // translate to shift of 16 (prevents 1 case)
        begin
          op_alu = ALU_ShiftL;   
          opA    = Op_Value (16);
          opB    = Op_Value (?);
          dest   = Dest_Reg (rt);       
          useImm = True;
        end
      Op_COP0:
        begin
          case (copro0Type)
            CP_MFC:
            begin
              size32 = True;
              dest   = Dest_Reg (rt);
              whenWritten = Stage_Wb;
              op_alu = ALU_IdA;
              isSigned = True;
              opA    = Op_CoProc0 (zeroExtend(rd));
              opB    = Op_Value (?);
              hasCP0Result = True;
            end
            CP_DMFC:
            begin
              dest   = Dest_Reg (rt);
              whenWritten = Stage_Wb;               
              op_alu = ALU_IdA;
              opA    = Op_CoProc0 (zeroExtend(rd));
              opB    = Op_Value (?);
              hasCP0Result = True;              
            end
            CP_MTC:
            begin
              size32 = True;
              op_alu = ALU_IdA;
              opA    = Op_RegName (rt);
              opB    = Op_Value   (?);
              dest   = Dest_CoProc0 (zeroExtend(rd));
              whenWritten = Stage_Wb;
              isSigned = True;
              flushOnCommit = True;
              if (rd == 5'b11010) 
                begin
                  printRegisterState = True;
                end
              if (rd == 5'b10111)
                begin 
                  terminate = True;
                end
            end
            CP_DMTC:
            begin
              op_alu = ALU_IdA;
              opA    = Op_RegName (rt);
              opB    = Op_Value   (?);
              dest   = Dest_CoProc0 (zeroExtend(rd));
              whenWritten = Stage_Wb;               
              flushOnCommit = True;              
            end     
            CP_INST:
            begin
              // The following instructions operate on CP0 registers only.
              dest           = Dest_None;
              opA            = Op_Value  (?);
              opB            = Op_Value (?);
              op_cp0         = cp0Inst;
              case(cp0Inst) 
                CP0_RDE: // Read indexed TLB entry (TLBR)
                begin 
                  flushOnCommit = True;
                  //move indexed tlb to CP0 Regs
                end
                CP0_WIE: // Write indexed TLB entry
                begin 
                  flushOnCommit = True;
                end
                CP0_WRE: // Write random TLB entry
                begin 
                  flushOnCommit = True;
                end     
                CP0_PME: // Probe matching TLB entry
                begin
                  //send probe
                  flushOnCommit = True;
                end
                CP0_ERET: // Exception return
                begin
                  // Nothing special here
                end
                CP0_WAIT:
                begin
                  op_cp0 = CP0_WAIT;
                  flushOnCommit = True;
                end
                default:
                  exception = Ex_RI;
              endcase
            end
            default:
              exception = Ex_RI;
          endcase
        end
      Op_COP2:
        begin 
          op_cp0 = CP0_XCP2;
          exception = Ex_RI; // CP2 will override if present
          dest = Dest_None;
	  opA = Op_Value (0);
	  opB = Op_Value (0);
        end
      Op_COP1:
        begin
          debug($display("XXX FILL in COPX instructions"));
          exception = Ex_RI;
          op_cp0  = CP0_XCP1;          
        end 
      `ifdef CP1X
      Op_COP1X:
        begin
          useCP1X = True;
          op_cp0  = CP0_XCP1;
          case (copro0Type)
            CP_MFC:
            begin
              dest   = Dest_Reg (rt);
              whenWritten = Stage_Wb;
              op_alu = ALU_OR;
              opA    = Op_Value (0);
              opB    = Op_Value (0);
              hasCP1XResult = True;
            end
            CP_MTC:
            begin
              op_alu = ALU_OR;
              opA    = Op_RegName (rt);
              opB    = Op_Value   (0);
              dest   = Dest_CoProc1X;
              whenWritten = Stage_Wb;
            end
            default:
              exception = Ex_RI;
          endcase
        end
      `elsif
      Op_COP1X:
        begin
          debug($display("XXX FILL in COPX instructions"));
          exception = Ex_RI;
          op_cp0    = CP0_XCP1;          
        end 
      `endif
      Op_BEQL: //likely
        begin
          dest          = Dest_None;
          op_alu        = ALU_EQ;
          branchTrue    = True;
          op_br         = BR_Offset;
          isLikely      = True;
        end
      Op_BNEL: //likely
        begin
          dest          = Dest_None;
          op_alu        = ALU_EQ;         
          branchFalse   = True;
          op_br         = BR_Offset;
          isLikely      = True;
        end
      Op_BLEZL: //likely
        begin
          dest        = Dest_None;
          op_alu      = ALU_LE;
          opB         = Op_Value (0);
          branchTrue  = True;
          op_br       = BR_Offset;
          isLikely    = True;  
          isSigned    = True;
        end
      Op_BGTZL: //likely
        begin
          dest        = Dest_None;
          op_alu      = ALU_LE;
          opB         = Op_Value (0);
          branchFalse = True;
          op_br       = BR_Offset;
          isLikely    = True;
          isSigned    = True;     
        end
      Op_DADDI: // rt is dest
        begin
          op_alu = ALU_ADD;          
          opB      = Op_Value (?);
          useImm   = True;
          dest     = Dest_Reg (rt);
          isSigned = True;
        end
      Op_DADDIU: // rt is dest
        begin
          op_alu = ALU_ADD;
          opB    = Op_Value (?);
          useImm = True;
          dest   = Dest_Reg (rt);
        end  
      Op_LDL: //ndave: we need old rt as input
        begin
          op_alu      = ALU_ADD; 
          op_mem      = tagged Valid MEM_LDL;
          useImm      = True;
          whenWritten = Stage_Wb;
          dest        = Dest_Reg (rt);
        end
      Op_LDR:
        begin
          op_alu      = ALU_ADD; 
          op_mem      = tagged Valid MEM_LDR;
          useImm      = True;
          whenWritten = Stage_Wb;         
          dest        = Dest_Reg (rt);
        end   
      Op_SPECIAL2:
        begin
          case (func2Type) matches
            F2_MADD:
            begin
              op_alu      = ALU_IdA; 
              dest        = Dest_HILO;
              whenWritten = Stage_Wb;
              mulOp       = Valid(MADD);
              isSigned    = True;
              size32      = True;
            end
            F2_MADDU:
            begin
              op_alu      = ALU_IdA; 
              dest        = Dest_HILO;
              whenWritten = Stage_Wb;
              mulOp       = Valid(MADD);
              size32      = True;
            end
            F2_MUL:
            begin //dest = rd
              op_alu      = ALU_IdA; 
              whenWritten = Stage_Wb;
              mulOp       = Valid(MUL);
              isSigned    = True;
              size32      = True;
            end
            F2_MSUB:
            begin
              op_alu      = ALU_IdA; 
              dest        = Dest_HILO;
              whenWritten = Stage_Wb;
              mulOp       = Valid(MSUB);
              isSigned    = True;
              size32      = True;
            end
            F2_MSUBU:
            begin
              op_alu      = ALU_IdA; 
              dest        = Dest_HILO;
              whenWritten = Stage_Wb;
              mulOp       = Valid(MSUB);
              size32      = True;
            end           
            default:
            begin
              debug($display("UNDEFINED SPECIAL2 Instruction."));
              exception = Ex_RI;
            end           
          endcase
        end
      Op_JALX:
        begin
          debug($display("JALX Instruction. FILL ME IN (XXX)"));
          exception = Ex_RI;
        end  
      Op_MDMX:
        begin
          debug($display("MDMX Instruction. FILL ME IN (XXX)"));
          exception = Ex_RI;
        end    
      Op_SPECIAL3:
        begin
          case (func3Type) matches
            F3_RDHWR:
            begin
              op_cp0 = CP0_RDHWR;
              opA    = Op_CoProc0 (zeroExtend(rd));
              dest   = Dest_Reg(rt);
	      whenWritten = Stage_Wb;
	    end
            default:
            begin
              debug($display("UNDEFINED SPECIAL3 Instruction."));
              exception = Ex_RI;
            end
          endcase
        end
      Op_LB:
        begin
          op_alu      = ALU_ADD;
          op_mem      = tagged Valid MEM_LB;
          opB         = Op_Value (?);
          useImm      = True;
          whenWritten = Stage_Wb;
          dest        = Dest_Reg (rt);
          isSigned    = True;
        end
      Op_LH:
        begin
          op_alu      = ALU_ADD; 
          op_mem      = tagged Valid MEM_LH;
          opB         = Op_Value (?);
          useImm      = True;
          whenWritten = Stage_Wb;
          dest        = Dest_Reg (rt);
          isSigned    = True;  
        end
      Op_LWL:
        begin
          op_alu      = ALU_ADD; 
          op_mem      = tagged Valid MEM_LWL;
          useImm      = True;
          whenWritten = Stage_Wb;
          dest        = Dest_Reg (rt);  
          isSigned    = True;
        end
      Op_LW:
        begin 
          op_alu      = ALU_ADD; 
          op_mem      = tagged Valid MEM_LW;
          opB         = Op_Value (?);
          useImm      = True;
          whenWritten = Stage_Wb;         
          dest        = Dest_Reg (rt);
          isSigned    = True;  
        end
      Op_LBU:
        begin
          op_alu      = ALU_ADD; 
          op_mem      = tagged Valid MEM_LB;
          opB         = Op_Value (?);
          useImm      = True;
          whenWritten = Stage_Wb;
          dest        = Dest_Reg (rt);
        end
      Op_LHU:
        begin
          op_alu      = ALU_ADD; 
          op_mem      = tagged Valid MEM_LH;
          opB         = Op_Value (?);
          useImm      = True;
          whenWritten = Stage_Wb;
          dest        = Dest_Reg (rt);
        end  
      Op_LWR:
        begin
          op_alu      = ALU_ADD; 
          op_mem      = tagged Valid MEM_LWR;
          useImm      = True;
          whenWritten = Stage_Wb;         
          dest        = Dest_Reg (rt);
          isSigned    = True;   
        end
      Op_LWU:
        begin 
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_LW;
          opB    = Op_Value (?);
          useImm = True;
          whenWritten = Stage_Wb;         
          dest   = Dest_Reg (rt);
        end  
      Op_SB:
        begin 
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_SB;
          useImm = True;
          whenWritten = Stage_Wb;
          dest   = Dest_None;
        end  
      Op_SH:
        begin 
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_SH;
          useImm = True;
          dest   = Dest_None;
        end    
      Op_SWL:
        begin
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_SWL;
          useImm = True;
          dest   = Dest_None;
        end 
      Op_SW:
        begin
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_SW;
          useImm = True;
          dest   = Dest_None;          
        end   
      Op_SDL:
        begin
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_SDL;
          useImm = True;          
          dest   = Dest_None;          
        end 
      Op_SDR:
        begin
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_SDR;
          useImm = True;
          dest   = Dest_None;          
        end   
      Op_SWR:
        begin
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_SWR;
          useImm = True;
          dest   = Dest_None;          
        end   
      Op_CACHE:
        begin
          op_alu = ALU_ADD; 
          opB    = Op_Value (?);
          useImm = True;
          dest   = Dest_None;
          op_mem = tagged Valid MEM_CACHE (rt);
        end
      Op_LL:
        begin
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_LW;
          opB    = Op_Value (?);
          useImm = True;
          whenWritten = Stage_Wb;         
          dest   = Dest_Reg (rt);    
          isMemLinked = True;
          isSigned    = True;
          flushOnCommit = True;
          setLL = True;
        end
      Op_LWC1: // XXX load word to Floating point
        begin
          debug($display("LWC1 Instruction. FILL ME IN"));  
          exception = Ex_RI;
          op_cp0  = CP0_XCP1;
        end
      Op_LWC2: // XXX load word to CP2
        begin
          debug($display("LWC2 Instruction. FILL ME IN"));
          exception = Ex_RI; // CP2 will override if present
          op_cp0 = CP0_XCP2;
        end
      Op_PREF:
        begin
          opA    = Op_Value (?);
          opB    = Op_Value (?);
          dest   = Dest_None;
          //PREF is not currently implemented. We should ignore,
          //not throw a Reserved Instruction Exception.
          //op_alu = ALU_ADD; 
          //opB    = Op_Value (?);
          //useImm = True;
          //dest   = Dest_None;
          //op_mem = tagged Valid MEM_PREF (rt);
        end
      Op_LLD:
        begin
          op_alu = ALU_ADD; 
          op_mem = tagged Valid MEM_LD;
          opB    = Op_Value (?);
          useImm = True;
          whenWritten = Stage_Wb;         
          dest   = Dest_Reg (rt);    
          isMemLinked = True;
          flushOnCommit = True;
          setLL = True;
        end
      Op_LDC1: // XXX load word to Floating point
        begin
          debug($display("LDC1 Instruction. FILL ME IN"));  
          exception = Ex_RI;
          op_cp0  = CP0_XCP1;
        end
      Op_LDC2: // load word to CP2
        begin
          op_cp0 = CP0_XCP2;
          exception = Ex_RI; // CP2 will override if present          
          `ifdef CAP
          opA = Op_Value (0);
          opB = Op_Value (0);
          `endif          
        end
      Op_LD: 
        begin
          op_alu = ALU_ADD; 
          opB    = Op_Value (?);
          useImm = True;
          whenWritten = Stage_Wb;         
          dest   = Dest_Reg (rt);    
          op_mem = tagged Valid MEM_LD;
        end
      Op_SC: 
        begin
          op_alu = ALU_ADD; 
          useImm = True;
          dest   = Dest_Reg(rt);
          whenWritten = Stage_Wb;
          op_mem = tagged Valid MEM_SW;
          isMemLinked = True;   
          flushOnCommit = True;          
        end  
      Op_SWC1: // XXX storeword to Floating point
        begin
          debug($display("SWC1 Instruction. FILL ME IN"));  
          exception = Ex_RI;
          op_cp0  = CP0_XCP1;
        end
      Op_SWC2: // store word to CP2
        begin
          exception = Ex_RI; // CP2 will override if present
          op_cp0 = CP0_XCP2;
        end
      Op_SCD: 
        begin
          op_alu = ALU_ADD; 
          useImm = True;
          dest   = Dest_Reg(rt);
          whenWritten = Stage_Wb;
          op_mem = tagged Valid MEM_SD;
          isMemLinked = True;
          flushOnCommit = True; 
        end    
      Op_SDC1: // XXX storeword to Floating point
        begin
          debug($display("SDC1 Instruction. FILL ME IN"));  
          exception = Ex_RI;
          op_cp0  = CP0_XCP1;
        end
      Op_SDC2: // store word to CP2
        begin
          op_cp0 = CP0_XCP2;
          exception = Ex_RI;  // CP2 will override if present          
          `ifdef CAP
          opA = Op_Value (0);
          opB = Op_Value (0);
          `endif
        end  
      Op_SD: 
        begin
          op_alu = ALU_ADD; 
          useImm = True;
          dest   = Dest_None;// no record
          op_mem = tagged Valid MEM_SD;
        end    
      default:
        begin 
          debug($display("Unrecognised instruction: 0x%X at PC: %X", pack(i), pc));
          exception = Ex_RI;
        end
    endcase

    //Capability Operation
    let rv = DecodedResult{
       decALUOperation: ALUOperation{
                          op_alutype:         op_alu,
                          op_signed:          isSigned,
                          op_size32:          size32,
                          op_useImm:          useImm,
                          op_TrapOnZero:      trapFalse,
                          op_TrapOnNonZero:   trapTrue
                        },
       decBranchOperation: BranchOperation{
                             op_brtype:          op_br,
                             op_isLikely:        isLikely,
                             op_isLink:          link,
                             op_BranchOnTrue:    branchTrue,
                             op_BranchOnFalse:   branchFalse
                           },
       decmMemOperation: case (op_mem) matches
                           tagged Invalid:  return Invalid;
                           tagged Valid .o: return tagged Valid MemOperation{
                                                                  op_memtype:     o,
                                                                  op_isMemLinked: isMemLinked,
                                                                  op_signed:      isSigned
                                                                };
                         endcase,
       decCP0Operation: CP0Operation{
                          cp0_size32: size32, 
                          cp0_inst: op_cp0,
                          cp0_opA:  case (opA) matches
                                      tagged Op_CoProc0 .c: return Valid(c);
                                      default:              return Invalid;
                                    endcase,
                          cp0_dest: case (dest) matches
                                       tagged Dest_CoProc0 .t: return Valid(t);
                                       default:                return Invalid;
                                    endcase,
                          cp0_hasResult: hasCP0Result,
                          cp0_sel:       cp0sel,
                          cp0_setLL:     setLL
                        },
      `ifdef CP1X
       decCP1XOperation: CP1XOperation{
                           cp1X_dest: case (dest) matches
                                        tagged Dest_CoProc1X: return True;
                                        default:              return False;
                                      endcase,
                           cp1X_hasResult: hasCP1XResult
                         },
      `endif
       decmMulOperation: case (mulOp) matches
                           tagged Valid .op: Valid (MulOperation{mul_op: op, mul_signed: isSigned, mul_size32: size32});
                           default:          Invalid;
                         endcase, 
       decmDivOperation: (isDivOp) ? tagged Valid DivOperation{div_signed: isSigned, div_size32: size32}: Nothing,
       `ifdef CAP
       decCapOperation: ?, // To be filled in by decodeCapInst below.
       `endif
       decFlushAfterCommit: flushOnCommit,
       decOperandA: opA,
       decOperandB: opB,
       decOffset: imm,
       decWhenWritten: whenWritten,
       decDest: dest,
       decException: exception,
       decDebug: DebugOp{printRegisterState: printRegisterState, terminate: terminate}
    };
  		  
    `ifdef CAP // all functional aspects are folded behind function in Capability Lib.
    let cap_rv <- decodeCapInst(i, rv);
    rv = cap_rv;
   `endif

   return rv;


  



  endactionvalue
endfunction

interface Decode;
  method ActionValue#(DecodedResult) decode(Bit#(32) i, Address pc);
endinterface   
  
(* synthesize, options="-aggressive-conditions" *)
module mkDecode(Decode);
  method decode = decodeFN;  
endmodule
