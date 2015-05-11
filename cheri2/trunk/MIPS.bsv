/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2012 Jonathan Woodruff
 * Copyright (c) 2010-2011 Simon W. Moore
 * Copyright (c) 2011-2012 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
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
 *   Simon William Moore <simon.moore@cl.cam.ac.uk>
 *   Robert M. Norton <robert.norton@cl.cam.ac.uk>
 * 
 ******************************************************************************
 *
 * Description: MIPS ISA Data Types
 * 
 ******************************************************************************/

import FShow::*;

typedef Bit#(5) RegName;
typedef Bit#(6) CP0RegName; // Co Processor Registers

//-----------------------------------------------------------------------------------------------
// MIPS Architectural Data Types
//-------------------------------------------------------------------------------------------------

typedef Bit#(64) Value;
typedef Bit#(64) Address;
typedef Bit#(8)  ASID;
typedef enum{
  SZ_1Byte,
  SZ_2Byte,
  SZ_4Byte,
  SZ_8Byte,
  SZ_32Byte
} AccessSize deriving(Bits, Eq, FShow);

function Bit#(6) lenSZ(AccessSize sz);
  case(sz) matches
    SZ_1Byte:  return 1;
    SZ_2Byte:  return 2;
    SZ_4Byte:  return 4;
    SZ_8Byte:  return 8;
    SZ_32Byte: return 32;
    default:   return 32; // Worst case default, just in case.
  endcase
endfunction

typedef enum {
  Op_SPECIAL  = 6'd00,
  Op_REGIMM   = 6'd01,
  Op_J        = 6'd02,
  Op_JAL      = 6'd03,
  Op_BEQ      = 6'd04,
  Op_BNE      = 6'd05,
  Op_BLEZ     = 6'd06,
  Op_BGTZ     = 6'd07,
  Op_ADDI     = 6'd08,
  Op_ADDIU    = 6'd09,
  Op_SLTI     = 6'd10,
  Op_SLTIU    = 6'd11,
  Op_ANDI     = 6'd12,
  Op_ORI      = 6'd13,
  Op_XORI     = 6'd14,
  Op_LUI      = 6'd15,
  Op_COP0     = 6'd16,
  Op_COP1     = 6'd17,
  Op_COP2     = 6'd18,
  Op_COP1X    = 6'd19,
  Op_BEQL     = 6'd20,
  Op_BNEL     = 6'd21,
  Op_BLEZL    = 6'd22,
  Op_BGTZL    = 6'd23,
  Op_DADDI    = 6'd24,
  Op_DADDIU   = 6'd25,
  Op_LDL      = 6'd26,
  Op_LDR      = 6'd27,
  Op_SPECIAL2 = 6'd28,
  Op_JALX     = 6'd29,
  Op_MDMX     = 6'd30,
  Op_SPECIAL3 = 6'd31,
  Op_LB       = 6'd32,
  Op_LH       = 6'd33,
  Op_LWL      = 6'd34,
  Op_LW       = 6'd35,
  Op_LBU      = 6'd36,
  Op_LHU      = 6'd37,
  Op_LWR      = 6'd38,
  Op_LWU      = 6'd39,
  Op_SB       = 6'd40,
  Op_SH       = 6'd41,
  Op_SWL      = 6'd42,
  Op_SW       = 6'd43,
  Op_SDL      = 6'd44,
  Op_SDR      = 6'd45,
  Op_SWR      = 6'd46,
  Op_CACHE    = 6'd47,
  Op_LL       = 6'd48,
  Op_LWC1     = 6'd49,
  Op_LWC2     = 6'd50,
  Op_PREF     = 6'd51,
  Op_LLD      = 6'd52,
  Op_LDC1     = 6'd53,
  Op_LDC2     = 6'd54,
  Op_LD       = 6'd55,
  Op_SC       = 6'd56,
  Op_SWC1     = 6'd57,
  Op_SWC2     = 6'd58,
  Op_NONE     = 6'd59,
  Op_SCD      = 6'd60,
  Op_SDC1     = 6'd61,
  Op_SDC2     = 6'd62,
  Op_SD       = 6'd63
} OpCode deriving (Bits, Eq, FShow);

typedef enum {
  F_SLL     = 6'd00,
  F_MOVCI   = 6'd01,
  F_SRL     = 6'd02,
  F_SRA     = 6'd03,
  F_SLLV    = 6'd04,
  F_NONE05  = 6'd05,
  F_SRLV    = 6'd06,
  F_SRAV    = 6'd07,
  F_JR      = 6'd08,
  F_JALR    = 6'd09,
  F_MOVZ    = 6'd10,
  F_MOVN    = 6'd11,
  F_SYSCALL = 6'd12,
  F_BREAK   = 6'd13,
  F_NONE14  = 6'd14,
  F_SYNC    = 6'd15,
  F_MFHI    = 6'd16,
  F_MTHI    = 6'd17,
  F_MFLO    = 6'd18,
  F_MTLO    = 6'd19,
  F_DSLLV   = 6'd20,
  F_NONE21  = 6'd21,
  F_DSRLV   = 6'd22,
  F_DSRAV   = 6'd23,
  F_MULT    = 6'd24,
  F_MULTU   = 6'd25,
  F_DIV     = 6'd26,
  F_DIVU    = 6'd27,
  F_DMULT   = 6'd28,
  F_DMULTU  = 6'd29,
  F_DDIV    = 6'd30,
  F_DDIVU   = 6'd31,
  F_ADD     = 6'd32,
  F_ADDU    = 6'd33,
  F_SUB     = 6'd34,
  F_SUBU    = 6'd35,
  F_AND     = 6'd36,
  F_OR      = 6'd37,
  F_XOR     = 6'd38,
  F_NOR     = 6'd39,
  F_NONE40  = 6'd40,
  F_NONE41  = 6'd41,
  F_SLT     = 6'd42,
  F_SLTU    = 6'd43,
  F_DADD    = 6'd44,
  F_DADDU   = 6'd45,
  F_DSUB    = 6'd46,
  F_DSUBU   = 6'd47,
  F_TGE     = 6'd48,
  F_TGEU    = 6'd49,
  F_TLT     = 6'd50,
  F_TLTU    = 6'd51,
  F_TEQ     = 6'd52,
  F_NONE53  = 6'd53,
  F_TNE     = 6'd54,
  F_NONE55  = 6'd55,
  F_DSLL    = 6'd56,
  F_NONE57  = 6'd57,
  F_DSRL    = 6'd58,
  F_DSRA    = 6'd59,
  F_DSLL32  = 6'd60,
  F_NONE61  = 6'd61,
  F_DSRL32  = 6'd62,
  F_DSRA32  = 6'd63
} FuncType deriving (Bits, Eq, FShow);

typedef enum
{
  F2_MADD    = 6'h00,
  F2_MADDU   = 6'h01,
  F2_MUL     = 6'h02,
  F2_MSUB    = 6'h04,
  F2_MSUBU   = 6'h05,
  F2_MNONE3F = 6'h3F
} Func2Type deriving (Bits, Eq, FShow);


typedef enum
{
  F3_RDHWR   = 6'b111011,
  F3_NONE    = 6'h3F
} Func3Type deriving (Bits, Eq, FShow);

typedef enum {
  RI_BLTZ    = 5'b00000, 
  RI_BGEZ    = 5'b00001, 
  RI_BLTZL   = 5'b00010,
  RI_BGEZL   = 5'b00011,
  RI_TEQI    = 5'b01100, 
  RI_TGEI    = 5'b01000, 
  RI_TGEIU   = 5'b01001, 
  RI_TLTI    = 5'b01010, 
  RI_TLTIU   = 5'b01011, 
  RI_TNEI    = 5'b01110,
  RI_BLTZAL  = 5'b10000, 
  RI_BGEZAL  = 5'b10001,
  RI_BLTZALL = 5'b10010,
  RI_BGEZALL = 5'b10011
} RegImmFunc deriving (Bits, Eq, FShow);

typedef enum {
  CP_MFC  = 5'b00000, // Move from CPX
  CP_DMFC = 5'b00001, // Doubleword move from CPX
  CP_CFC  = 5'b00010, // Copy from CP1/CP2 control (unused)
  CP_CTC  = 5'b00110, // Copy to CP1/CP2 control (unused)
  CP_MTC  = 5'b00100, // Move to CPX
  CP_DMTC = 5'b00101, // Doubleword move to CPX
  CP_INST = 5'b10000  // This is an instruction.
} CoProOp deriving (Bits, Eq, FShow);

typedef enum {
  CP0_RDE  = 6'b000001, // Read indexed TLB entry
  CP0_WIE  = 6'b000010, // Write indexed TLB entry
  CP0_WRE  = 6'b000110, // Write random TLB entry
  CP0_PME  = 6'b001000, // Probe matching TLB entry (TLBP)
  CP0_ERET = 6'b011000, // Exception return
  CP0_WAIT = 6'b100000, // Wait
  CP0_RDHWR = 6'b001111, // Read hardware register (internal use)   
  CP0_XCP1 = 6'b101111, // Check whether cp1 is enabled (internal use)
  CP0_XCP2 = 6'b011111, // Check whether cp2 is enabled (internal use)
  CP0_NONE = 6'b111111  // spacer for sizing
} CP0Inst deriving (Bits, Eq, FShow);

typedef enum {
   KSU_K = 2'd0, // Kernel
   KSU_S = 2'd1, // Supervisor
   KSU_U = 2'd2, // User
   KSU_INVALID = 2'd3 // not used by MIPS
} KSU deriving(Bits, Eq);

instance Ord#(KSU);
   function Bool \<  (KSU x, KSU y) = (pack(x) <  pack(y));
   function Bool \<= (KSU x, KSU y) = (pack(x) <= pack(y));  
   function Bool \>  (KSU x, KSU y) = (pack(x) >  pack(y));     
   function Bool \>= (KSU x, KSU y) = (pack(x) >= pack(y));
endinstance

function KSU currentMode(KSU ksu, Bool exl, Bool erl);
  return (exl || erl) ? KSU_K : ksu;
endfunction

instance FShow#(KSU);
  function Fmt fshow(KSU ksu);
    case (ksu) matches
      tagged KSU_K: return $format("Kernel");
      tagged KSU_S: return $format("Supervisor");
      tagged KSU_U: return $format("User");
      default     : return $format("INVALID");
    endcase
  endfunction
endinstance

// Cache coherency algorithm as defined by MIPS spec., so far we only
// implement cached/uncached.
typedef enum {
  CA_UNCACHED      = 3'd2, // Don't cache this page
  CA_CACHED        = 3'd3, // Cache this page but don't broadcast writes
  CA_SPACER        = 3'd4
} CacheCA deriving (Bits, Eq, FShow, Bounded);

typedef enum{
	MMU_NONE = 3'b000,
	MMU_TLB  = 3'b001,
	MMU_BAT  = 3'b010,
	MMU_DUMMY = 3'b111 // XXX ndave: needed to get 3-bit value
} MMUType	deriving(Bits, Eq, FShow);

// Exception type used internally by cheri2, note that this contains a few extra values 
// which are not MIPS exceptions and should not be exposed to the programmer.
typedef union tagged {
  void Ex_Interrupt;     // 0
  void Ex_Modify;        // 1
  void Ex_TLBLoad;       // 2
  void Ex_TLBStore;      // 3         
  void Ex_AddrErrLoad;   // 4 
  void Ex_AddrErrStore;  // 5 
  void Ex_InstBusErr;    // 6 // implementation dependent
  void Ex_DataBusErr;    // 7 // implementation dependent
  void Ex_SysCall;       // 8
  void Ex_BreakPoint;    // 9 
  void Ex_RI;            // 10 // reserved instruction exception (opcode not recognized) XXX could use better name
  void Ex_CoProcess1;    // 11 Attempted coprocessor inst for disabled coprocessor. Floating point emulation starts here.
  void Ex_Overflow;      // 12 Overflow from trapping arithmetic instructions (e.g. add, but not addu).
  void Ex_Trap;          // 13
  void Ex_CP2Trap;       // 14 CP2 Trap (CCall, CReturn) INTERNAL
  void Ex_FloatingPoint; // 15
  void Ex_Exp16;         // 16 Unused (was TLB cap load forbidden CHERI EXTENSION)
  void Ex_TLB17;         // 17 Unused (was TLB cap store forbidden INTERNAL)
  void Ex_CoProcess2;    // 18 Exception from Coprocessor 2 (extenstion to ISA)
  void Ex_TLBLoadInst;   // 19 TLB instruction miss INTERNAL
  void Ex_AddrErrInst;   // 20 Instruction address error INTERNAL
  void Ex_TLBInvInst;    // 21 TLB instruction load invalid INTERNAL
  void Ex_MDMX;          // 22 Tried to run an MDMX instruction but SR(dspOrMdmx) is not enabled.
  void Ex_Watch;         // 23 Physical address of load and store matched WatchLo/WatchHi registers
  void Ex_MCheck;        // 24 Disasterous error in control system, eg, duplicate entries in TLB.
  void Ex_Thread;        // 25 Thread related exception (check VPEControl(EXCPT))
  void Ex_DSP;           // 26 Unable to do DSP ASE Instruction (lack of DSP)
  void Ex_Suspended;     // 27 Fake exception used when polling for interrupt in waiting thread -- INTERNAL
  void Ex_TLBLoadInv;    // 28 TLB matched but valid bit not set INTERNAL
  void Ex_TLBStoreInv;   // 29 TLB matched but valid bit not set INTERNAL
  void Ex_CacheErr;      // 30 Parity/ECC error in cache.
  void Ex_None;          // 31 No Error
} Exception deriving (Bits, Eq, FShow);

// ISA defined exception codes.
typedef union tagged {
  void MIPS_Ex_Interrupt;     // 0
  void MIPS_Ex_Modify;        // 1
  void MIPS_Ex_TLBLoad;       // 2
  void MIPS_Ex_TLBStore;      // 3         
  void MIPS_Ex_AddrErrLoad;   // 4 ADEL
  void MIPS_Ex_AddrErrStore;  // 5 ADES
  void MIPS_Ex_InstBusErr;    // 6 // implementation dependant
  void MIPS_Ex_DataBusErr;    // 7 // implementation dependant
  void MIPS_Ex_SysCall;       // 8
  void MIPS_Ex_BreakPoint;    // 9 
  void MIPS_Ex_RI;            // 10 // reserved instruction exception (opcode not recognized) XXX could use better name
  void MIPS_Ex_CoProcess1;    // 11 Attempted coprocessor inst for disabled coprocessor. Floating point emulation starts here.
  void MIPS_Ex_Overflow;      // 12 Overflow from trapping arithmetic instructions (e.g. add, but not addu).
  void MIPS_Ex_Trap;          // 13
  void MIPS_Ex_Exp14;         // Place holder
  void MIPS_Ex_FloatingPoint; // 15
  void MIPS_Ex_Exp16;         // 16 unused (was TLB cap load forbidden CHERI EXTENSION)
  void MIPS_Ex_Exp17;         // 17 unused (was TLB cap store forbidden CHERI EXTENSION)
  void MIPS_Ex_CoProcess2;    // Exception from Coprocessor 2 (extenstion to ISA)
  void MIPS_Ex_Exp19;         // Place holder
  void MIPS_Ex_Exp20;         // Place holder
  void MIPS_Ex_Exp21;         // Place holder
  void MIPS_Ex_MDMX;          // 22 Tried to run an MDMX instruction but SR(dspOrMdmx) is not enabled.
  void MIPS_Ex_Watch;         // 23 Physical address of load and store matched WatchLo/WatchHi registers
  void MIPS_Ex_MCheck;        // 24 Disasterous error in control system, eg, duplicate entries in TLB.
  void MIPS_Ex_Thread;        // 25 Thread related exception (check VPEControl(EXCPT))
  void MIPS_Ex_DSP;           // 26 Unable to do DSP ASE Instruction (lack of DSP)
  void MIPS_Ex_Exp27;         // Place holder
  void MIPS_Ex_Exp28;         // Place holder
  void MIPS_Ex_Exp29;         // Place holder
  void MIPS_Ex_CacheErr;      // 30 Parity/ECC error in cache.
  void MIPS_Ex_None;          // No Error
   } MIPSException deriving (Bits, Eq, FShow, Bounded);

function MIPSException exceptionToMIPS(Exception e);
  case (e)
    Ex_TLBLoadInv:  return MIPS_Ex_TLBLoad;
    Ex_TLBStoreInv: return MIPS_Ex_TLBStore;
    Ex_TLBLoadInst: return MIPS_Ex_TLBLoad;
    Ex_AddrErrInst: return MIPS_Ex_AddrErrLoad;
    Ex_TLBInvInst:  return MIPS_Ex_TLBLoad;
    Ex_CP2Trap:     return MIPS_Ex_CoProcess2;
    default:        return unpack(pack(e));
  endcase
endfunction

function Bool isAddressException(Exception e);
  case (e)
    Ex_TLBLoad:      return True;
    Ex_TLBStore:     return True;
    Ex_TLBLoadInv:   return True;
    Ex_TLBStoreInv:  return True;
    Ex_AddrErrLoad:  return True;
    Ex_AddrErrStore: return True;
    Ex_Modify:       return True;
    Ex_TLBLoadInst:  return True;
    Ex_AddrErrInst:  return True;
    Ex_TLBInvInst:   return True;
    Ex_DataBusErr:   return True;
    Ex_InstBusErr:   return True;
    default:         return False;
  endcase
endfunction

// Much like above but does not include address error exceptions (which do not update
// context/xcontext -- technically not defined but gxemul doesn't)
function Bool isTLBException(Exception e);
  case (e)
    Ex_TLBLoad:      return True;
    Ex_TLBStore:     return True;
    Ex_TLBLoadInv:   return True;
    Ex_TLBStoreInv:  return True;
    Ex_Modify:       return True;
    Ex_TLBLoadInst:  return True;
    Ex_TLBInvInst:   return True;
    default:         return False;
  endcase
endfunction

function Exception convertToInstructionException(Exception e);
  case (e)
    Ex_TLBLoad:     return Ex_TLBLoadInst;
    Ex_AddrErrLoad: return Ex_AddrErrInst;  
    Ex_TLBLoadInv:  return Ex_TLBInvInst;
    Ex_DataBusErr:  return Ex_InstBusErr;
    default:        return e;
  endcase
endfunction

function Bool isInstructionFetchException(Exception e);
  case (e)
    Ex_TLBLoadInst: return True;
    Ex_AddrErrInst: return True;
    Ex_TLBInvInst:  return True;
    Ex_InstBusErr:  return True;
    default:        return False;
  endcase
endfunction

function Exception joinException(Exception e1, Exception e2);
  return (e1 == Ex_None) ? e2 : e1; // left-handed bias
endfunction

function Address getExceptionEntryROM(Exception ex);
  case(ex)
    Ex_Interrupt:     return 64'hFFFFFFFFBFC00380;
    Ex_Modify:        return 64'hFFFFFFFFBFC00380;
    Ex_TLBLoad:       return 64'hFFFFFFFFBFC00280;
    Ex_TLBStore:      return 64'hFFFFFFFFBFC00280;
    Ex_TLBLoadInv:    return 64'hFFFFFFFFBFC00380;
    Ex_TLBStoreInv:   return 64'hFFFFFFFFBFC00380;
    Ex_AddrErrLoad:   return 64'hFFFFFFFFBFC00380;
    Ex_AddrErrStore:  return 64'hFFFFFFFFBFC00380;
    Ex_InstBusErr:    return 64'hFFFFFFFFBFC00380;
    Ex_DataBusErr:    return 64'hFFFFFFFFBFC00380;
    Ex_SysCall:       return 64'hFFFFFFFFBFC00380;
    Ex_BreakPoint:    return 64'hFFFFFFFFBFC00380;
    Ex_RI:            return 64'hFFFFFFFFBFC00380;
    Ex_CoProcess1:    return 64'hFFFFFFFFBFC00380;
    Ex_Overflow:      return 64'hFFFFFFFFBFC00380;
    Ex_Trap:          return 64'hFFFFFFFFBFC00380;
    Ex_CP2Trap:       return 64'hFFFFFFFFBFC00480;
    Ex_FloatingPoint: return 64'hFFFFFFFFBFC00380;
    Ex_CoProcess2:    return 64'hFFFFFFFFBFC00380;
    Ex_MDMX:          return 64'hFFFFFFFFBFC00380;
    Ex_Watch:         return 64'hFFFFFFFFBFC00380;
    Ex_MCheck:        return 64'hFFFFFFFFBFC00380;
    Ex_Thread:        return 64'hFFFFFFFFBFC00380;
    Ex_DSP:           return 64'hFFFFFFFFBFC00380;
    Ex_CacheErr:      return 64'hFFFFFFFFBFC00300;
    default:          return 64'hFFFFFFFFBFC00380;
  endcase
endfunction

function Address getExceptionEntryRAM(Exception ex);
  case(ex)
    Ex_Interrupt:     return 64'hFFFFFFFF80000180;
    Ex_Modify:        return 64'hFFFFFFFF80000180;
    Ex_TLBLoad:       return 64'hFFFFFFFF80000080;
    Ex_TLBStore:      return 64'hFFFFFFFF80000080;
    Ex_TLBLoadInv:    return 64'hFFFFFFFF80000180;
    Ex_TLBStoreInv:   return 64'hFFFFFFFF80000180;
    Ex_AddrErrLoad:   return 64'hFFFFFFFF80000180;
    Ex_AddrErrStore:  return 64'hFFFFFFFF80000180;
    Ex_InstBusErr:    return 64'hFFFFFFFF80000180;
    Ex_DataBusErr:    return 64'hFFFFFFFF80000180;
    Ex_SysCall:       return 64'hFFFFFFFF80000180;
    Ex_BreakPoint:    return 64'hFFFFFFFF80000180;
    Ex_RI:            return 64'hFFFFFFFF80000180;
    Ex_CoProcess1:    return 64'hFFFFFFFF80000180;
    Ex_Overflow:      return 64'hFFFFFFFF80000180;
    Ex_Trap:          return 64'hFFFFFFFF80000180;
    Ex_CP2Trap:       return 64'hFFFFFFFF80000280;
    Ex_FloatingPoint: return 64'hFFFFFFFF80000180;
    Ex_CoProcess2:    return 64'hFFFFFFFF80000180;
    Ex_MDMX:          return 64'hFFFFFFFF80000180;
    Ex_Watch:         return 64'hFFFFFFFF80000180;
    Ex_MCheck:        return 64'hFFFFFFFF80000180;
    Ex_Thread:        return 64'hFFFFFFFF80000180;
    Ex_DSP:           return 64'hFFFFFFFF80000180;
    Ex_CacheErr:      return 64'hFFFFFFFFA0000100;
    default:          return 64'hFFFFFFFF80000180;
  endcase
endfunction

/* Number of bits of virtual address. In theory this could be
/* increased up to 49 and everything should just work™, although this
/* has not been tested.  */
typedef 40             SEGBITS;
/* Size in bytes of each virtual segment (user, kernel etc) */
typedef TExp#(SEGBITS) SEGSIZE;
/* Number of bits of physical address */
typedef 36             PABITS;
/* Size in bytes of physical address space */
typedef TExp#(PABITS)  PASIZE;
/* Page size defined as number of bits of address.
 * For now we only support a fixed 4k page.
 */
typedef 12               PAGEBITS;
/* As PAGEBITS but for an even/odd pair of pages. */
typedef 13              PAGE2BITS;
/* Number of bits in the page frame number (i.e. phyiscal page
/* number). */
typedef TSub#(PABITS,PAGEBITS) PFNBITS;
/* Number of bits in virtual page number. */
typedef TSub#(SEGBITS, PAGEBITS) VPNBITS;
/* Number of bits of address for an even/odd pair of pages.*/
typedef TSub#(VPNBITS, 1)        VPN2BITS;
/* Type for number identifying an even/odd pair of virtual pages. */
typedef Bit#(VPN2BITS)           VPN2;
/* Number of bits of filler needed in a virtual address to make up to
/* 64 bits (see below)*/
typedef TSub#(64, TAdd#(2, SEGBITS)) FILLBITS;

/* Structure of a virtual address */
typedef struct {
   Bit#(2)                 r;
   Bit#(FILLBITS)       fill;
   Bit#(VPN2BITS)       vpn2;
   Bit#(1)           oddEven;
   Bit#(PAGEBITS) pageOffset;
} VAddr deriving(Bits);

// Function to decode a MIPS address based on segments defined in chapter 4 of MIPS64 Vol. III
// Returns (priv. mode, isMapped, cacheMode, is32Compat, Address Error)
function Tuple5#(KSU, Bool, CacheCA, Bool, Bool) decodeAddr(Address a, CacheCA cacheMode);
  KSU mode = KSU_K;            // Least privileged mode in which segement is accessible
  Bool mapped = True;          // Whether the address should be passed through the TLB
  CacheCA cacheCA = CA_CACHED; // Coherency algorithm to use (if unmapped)
  Bool compat32 = a[63:31]==33'h1ffffffff;       // Whether to drop the top 35 bits (for 32-bit compatibility)
  Bool addressErr = a[61:0] >= fromInteger(valueOf(SEGSIZE));
  // ZZZ rmn30 might be clearer to restructure this as a single case statement
  case (a[63:62])
      2'b11: // xkseg: kernel mapped
      begin 
        mode = KSU_K;
        if (compat32) 
          begin // 32-bit compatibility segments
            addressErr = False;
            case(a[30:29])
              2'b11: // kseg3: 32-bit kernel mapped
              begin
                     // as per xkseg
              end
              2'b10: // sseg:  32-bit supervisor mapped
              begin
                mode = KSU_S;
              end
              2'b01: // kseg1: 32-bit kernel unmapped, uncached
              begin
                mapped = False;
                cacheCA = CA_UNCACHED;
              end
              2'b00: // kseg0: 32-bit kernel unmapped, (maybe) cached
              begin
                mapped = False; 
                cacheCA = cacheMode; // from status reg
              end
            endcase
          end
      end
      2'b10: // xkphys: kernel unmapped
      begin 
        mode = KSU_K;
        mapped = False;
        cacheCA = unpack(a[61:59]);
        addressErr = a[58:0] >= fromInteger(valueOf(PASIZE));
      end
      2'b01: // xsseg: supervisor mapped
      begin 
        mode = KSU_S;
      end
      2'b00: // [x]useg: user mapped, no special behaviour needed for 32-bit compatibility
      begin
        mode = KSU_U;
      end
    endcase
  return tuple5(mode, mapped, cacheCA, compat32, addressErr);
endfunction
