/*-
 * Copyright (c) 2011-2012 Jonathan Woodruff
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
 * Copyright (c) 2014 Alexandre Joannou
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
 *   Robert Norton <robert.norton@cl.cam.ac.uk>
 * 
 ******************************************************************************
 *
 * Description: Microarchitectural Types
 * 
 ******************************************************************************/

import MIPS::*;
import MemTypes::*;
import DefaultValue::*;

import FShow::*;

`ifdef CAP
import CapabilityTypes::*;
//import CapabilityMicroTypes::*;
`endif


//-----------------------------------------------------------------------------------------------
// MIPS Microarchitectural Data Types
//-------------------------------------------------------------------------------------------------


// Configuration Parameters.
// The macros are defined by the configuration in the make file.
// 
`ifndef IWAYS
`define IWAYS 1
`endif
`ifndef DWAYS
`define DWAYS 1
`endif


// Number of bits of ThreadID ( # threads = 2**ThreadSZ)
typedef `THREADSZ       ThreadSZ;
// Number of ICache ways   
typedef `IWAYS             IWays;
// Number of DCache ways   
typedef `DWAYS             DWays;
// Size of mask for large page support (currently not supported)
typedef 0           PageMaskBits;

// Types derived from above
typedef Bit#(ThreadSZ)     ThreadID;
typedef TExp#(ThreadSZ)    NumThreads;  // 2**ThreadSZ
typedef Bit#(TLog#(IWays)) IWayIdx;     // Index of a way within icache cache line
typedef Bit#(TLog#(DWays)) DWayIdx;     // Index of a way within dcache cache line
typedef Bit#(PageMaskBits) PageMask;    // Page mask for tlb

typedef Bit#(4) Epoch;

// Thread state which is part of the control token
typedef struct {
  KSU                          modeBits;
  Bool                       errorLevel;
  Bool                   exceptionLevel;
  CacheCA                cacheAlgorithm;
  ASID                             asid;
  Bool                            llBit;
`ifndef NOWATCH   
  //Watch Regsters (18 + 19)
  Bit#(61)                   watchVaddr;
  Bool                           watchI;
  Bool                           watchR;
  Bool                           watchW;
  Bool                           watchG;
  ASID                        watchASID;
  Bit#(9)                     watchMask;
`endif
} ThreadState deriving(Bits, Eq, FShow);

typedef struct{
  Bool printRegisterState;
  Bool terminate;
} DebugOp deriving(Bits, Eq, FShow);

typedef union tagged{
  void       Dest_None; 
  RegName    Dest_Reg;
  void       Dest_HI;
  void       Dest_LO;         
  void       Dest_HILO;
  CP0RegName Dest_CoProc0;
  `ifdef CP1X
  void       Dest_CoProc1X;
  `endif
} Destination deriving(Bits, Eq, FShow); 

// Pointer to a register in a particular thread, used as the key in
// search FIFOs for forwarding.
typedef struct {
   ThreadID thread;
   RegName       r;
  } ThreadRegName deriving(Bits, Eq, FShow);

typedef union tagged {             // YYY ndave: if we pull out HI and LO operands into two booleans
  RegName    Op_RegName;           //            (readsHI/readLO) we can avoid the having to remember
  Value      Op_Value;             //            MADD, etc. read HILO unexpectedly. 
  void       Op_HI;       
  void       Op_LO;
  CP0RegName Op_CoProc0;
} Operand deriving(Bits, Eq, FShow);

function Value getOpValue(Operand o);
  case (o) matches
    tagged Op_Value .x: return x;
    default:            return ?;
  endcase
endfunction

function Bool  isOpHI(Operand op) = (op == Op_HI);
function Bool  isOpLO(Operand op) = (op == Op_LO);
function Bool isOpCP0(Operand op) = case(op) matches
                                      tagged Op_CoProc0 .*: return True;
                                      default:              return False;
                                    endcase;

typedef enum{MNONE, MUL, MSUB, MADD} MulOp deriving (Bits, Eq, FShow);

typedef struct{
  Bool mul_signed;
  Bool mul_size32;
  MulOp mul_op;
} MulOperation deriving(Bits, Eq, FShow);               
  
function Bool isMAddSubOp(Maybe#(MulOperation) mop);
  case (mop) matches
	tagged Valid .op: return (op.mul_op==MADD || op.mul_op==MSUB);
	tagged   Invalid: return False;
  endcase
endfunction
  
typedef struct{
  Bool div_signed;
  Bool div_size32;                                           
} DivOperation deriving(Bits, Eq, FShow);    
  
typedef struct{
  ALUOp op_alutype;
  Bool  op_useImm;
  Bool  op_signed;
  Bool  op_size32;          
  Bool  op_TrapOnZero;    
  Bool  op_TrapOnNonZero;
} ALUOperation deriving(Bits, Eq, FShow);

typedef struct{
  BranchOp op_brtype;
  Bool     op_isLikely; // likely ops nullify branch delay slows on failure
  Bool     op_isLink; // is Link? if so ALU result is dropped, replaced with PC + 8
  Bool     op_BranchOnTrue;
  Bool     op_BranchOnFalse;
} BranchOperation deriving(Bits, Eq, FShow);

typedef struct{
  MemOp op_memtype;
  Bool  op_isMemLinked;
  Bool  op_signed;
} MemOperation deriving(Bits, Eq, FShow);

typedef struct{
  CP0Inst  cp0_inst;
  Bool     cp0_size32;
  Bool     cp0_hasResult;
  Maybe#(CP0RegName) cp0_opA;
  Maybe#(CP0RegName) cp0_dest;
  Bit#(3)        cp0_sel; 
  Bool     cp0_setLL; 
} CP0Operation  deriving(Bits, Eq, FShow);

`ifdef CP1X
typedef struct{
  Bool cp1X_hasResult;
  Bool cp1X_dest;
} CP1XOperation  deriving(Bits, Eq, FShow);
`endif

typedef enum{
  ALU_IdA, ALU_LT, ALU_EQ, ALU_LE,      
  ALU_ShiftL, ALU_ShiftR, ALU_MOVZ, ALU_MOVN, 
  ALU_AND, ALU_OR,  ALU_XOR, ALU_NOR,
  ALU_ADD, ALU_SUB
} ALUOp deriving(Bits, Eq, FShow);

typedef enum{
  BR_PC8, BR_OpA, BR_Offset, BR_Abs
} BranchOp deriving(Bits, Eq, FShow);

typedef union tagged{
  void MEM_LDL; void MEM_LDR; void MEM_LWL; void MEM_LWR;
  void MEM_SDL; void MEM_SDR; void MEM_SWL; void MEM_SWR;
  void MEM_LB;  void MEM_LH;  void MEM_LW;  void MEM_LD;
  void MEM_SB;  void MEM_SH;  void MEM_SW;  void MEM_SD;
  Bit#(5) MEM_PREF;
  Bit#(5) MEM_CACHE;
} MemOp deriving(Bits, Eq, FShow);   

function Bool isStoreOp(MemOperation x); 
  case (x.op_memtype)
    MEM_SDL, MEM_SDR, MEM_SWL, MEM_SWR, 
    MEM_SB,  MEM_SH,  MEM_SW,  MEM_SD: return True;
    default:                           return False;
  endcase
endfunction

//-------------------------------------------------------------------------------------------------
// Pipeline Stages
//-------------------------------------------------------------------------------------------------

//ndave: This is currently only used for forwarding. As such we only need places which produce results
typedef enum{
  Stage_Exe = 0,
  Stage_Mem = 1,
  Stage_Wb  = 2       
} Stage deriving(Bits, Eq, FShow);  
    
instance Ord#(Stage);
  function Ordering compare (Stage x, Stage y) = compare(pack(x), pack(y));
endinstance

typedef struct {
  ThreadID     thread;
  ThreadState      ts;
  Epoch         epoch;
  Address          pc;  
  Address      nextPC;
  Address  nextNextPC;
  Exception exception;
} FetInst deriving(Bits, Eq, FShow);

typedef struct {
  ThreadID     thread;
  ThreadState      ts;
  Epoch         epoch;
  Address          pc;  
  Address      nextPC;
  Address  nextNextPC;
  Exception exception;
  ALUOperation          aluOperation;
  BranchOperation    branchOperation;
  Maybe#(MemOperation) mmemOperation;
  CP0Operation          cp0Operation;
  `ifdef CP1X
  CP1XOperation        cp1XOperation;
  `endif
  Maybe#(MulOperation) mmulOperation;
  Maybe#(DivOperation) mdivOperation;   
  `ifdef CAP
  Bool                    getCapResp;
  `endif 
  Bool              flushAfterCommit;
  Destination    dest;    
  Operand         opA;
  Operand         opB;
  Bit#(26)     offset;
  Stage   whenWritten;
  DebugOp       debug;
  Bit#(32)       inst;
} DecInst deriving(Bits, Eq, FShow);

// function Maybe#(Maybe#(Value)) searchDec(DecInst i, RegName r);
//   return (i.dest == tagged Dest_Reg r) ? tagged Valid Invalid : Invalid; // it exists, but we have no value
// endfunction

typedef struct {
  ThreadID           thread;
  ThreadState            ts;
  Address                pc;  
  Address            nextPC;
  Exception       exception;
  Bool           getMulResp;
  Bool           getDivResp;
  Maybe#(MemOperation) mmemOperation;
  CP0Operation cp0Operation;
  `ifdef CP1X
  CP1XOperation        cp1XOperation;
  `endif
  Stage         whenWritten;
  Bool              flushAfterCommit;
  Destination          dest;
  Operand               opA; // destValue
  Operand               opB; // destValue2 (in case of MUL/DIV for LO). Data for stores
  Bool              isDelay;
  DebugOp             debug;
  Bit#(32)             inst;
} ExeInst deriving(Bits, Eq, FShow);

function Maybe#(Maybe#(Value)) searchExe(ExeInst i, ThreadRegName tr);
  if (i.dest == tagged Dest_Reg tr.r && i.thread == tr.thread && tr.r != 0) // matches dest
    return tagged Valid ((i.whenWritten <= Stage_Exe) ? tagged Valid (getOpValue(i.opA)) : Invalid);
  else
    return Invalid;   
endfunction

typedef struct {
  ThreadID         thread;
  ThreadState          ts;
  Address              pc;  
  Address          nextPC;
  Exception     exception;
  Bool         getMemResp;
  Bool         getMulResp;
  Bool         getDivResp;
  Stage       whenWritten;
  Bool   flushAfterCommit;
  Destination        dest;
  Operand             opA; // destValue
  Operand             opB; // destValue2 (in case of MUL/DIV for LO). Data for stores
  Bool            isDelay;
  DebugOp           debug;
  Bit#(32)           inst;
} MemInst deriving (Bits, Eq, FShow);    

function Maybe#(Maybe#(Value)) searchMem(MemInst i, ThreadRegName tr);
  if (i.dest == tagged Dest_Reg tr.r && i.thread == tr.thread && tr.r != 0) // matches dest
    return tagged Valid ((i.whenWritten <= Stage_Mem) ? tagged Valid (getOpValue(i.opA)) : Invalid);
  else
    return Invalid;   
endfunction

interface Memory;
  method Action req(CheriMemRequest request); // Initiate memory operation
  method ActionValue#(CheriMemResponse) resp();              // Retrieve memory operation response
endinterface

interface MemInvalidate;
  method Action invalidate (Address x);
endinterface  

interface DCache;
  method ActionValue#(Exception)           req(ThreadID thread,
                                               ThreadState ts,
                                               `ifdef CAP   
                                               Bool fromCap,
                                               `endif
                                               VirtualMemRequest request);
  method ActionValue#(Exception)           commit(Bool commit); // Only call if req returns Ex_None
  method ActionValue#(CheriMemResponse)    resp();              // Only call if req returns Ex_None, regardless of commit return value
endinterface

interface DMem;
  method ActionValue#(Exception)           req(ThreadID thread, ThreadState ts, MemOperation op, Address a, Value v);
  method ActionValue#(Exception)           commit(Bool commit); // Only call if req returns Ex_None
  method ActionValue#(Value)               resp();              // Only call if req returns Ex_None, regardless of commit return value
endinterface

interface IMem;
  method ActionValue#(Exception)           req(ThreadID thread, ThreadState ts, Address x);
  method ActionValue#(Tuple2#(Exception, Bit#(32))) resp(); // Only call if req returns Ex_None
  interface MemInvalidate invalidate;
endinterface

//----------------------------------------------------------------------------------------------- 
// Types for memory requests
//-----------------------------------------------------------------------------------------------

function CheriMemRequest virtualToPhyMemReq(VirtualMemRequest vr);
    CheriMemRequest req = defaultValue;
    req.addr = unpack(truncate(pack(vr.addr)));
    req.masterID = vr.masterID;
    req.transactionID = vr.transactionID;
    case (vr.operation) matches
        tagged Read .rop : begin
            req.operation = tagged Read {
                uncached:rop.uncached,
                linked:rop.linked,
                noOfFlits:rop.noOfFlits,
                bytesPerFlit:rop.bytesPerFlit
            };
        end
        tagged Write .wop : begin
            req.operation = tagged Write {
                uncached:wop.uncached,
                conditional:wop.conditional,
                byteEnable:wop.byteEnable,
                data:wop.data,
                last:wop.last
            };
        end
        tagged CacheOp .cop : begin
            req.operation = tagged CacheOp cop;
        end
    endcase
    return req;
endfunction

typedef MemoryRequest#(Address,UInt#(TLog#(TMul#(2,CORE_COUNT))),256) VirtualMemRequest;

typedef enum {
    Read, Write, Cache
} MemCmd deriving (Bits, Eq, Bounded, FShow);

typedef struct{
  Bool     isMerge;
  Bool    isSigned;
  Bool    negateUnaligned;
  MemCmd       cmd;
  AccessSize    sz;                
  Bit#(8) byteMask;
  Bit#(3)   offset;
  Bit#(2)     word;
} MemRespData deriving(Bits, Eq, FShow);
