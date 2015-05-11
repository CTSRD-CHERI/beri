/*-
 * Copyright (c) 2011 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013-2014 Robert M. Norton
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
 *   Jonathan Woodruff <jonathan.woodruff@cl.cam.ac.uk>
 *   Nirav Dave <ndave@csl.sri.com>
 * 
 ******************************************************************************
 *
 * Description: Capability CoProcessor
 * 
 ******************************************************************************/

import MIPS::*;
import CHERITypes::*;
import CapabilityTypes::*;
import FShow::*;

//=============================================================================
// Microarchitectural Capability Types
//=============================================================================

typedef enum {
  CapOp_MFC       = 5'h0, // Move From Capability Register Field
  CapOp_None      = 5'h1, // used to be seal code
  CapOp_Seal      = 5'h2,
  CapOp_Unseal    = 5'h3,
  CapOp_MTC       = 5'h4, // Move to Capability Register Field
  CapOp_CCall     = 5'h5,  // Protected Procedure Call to cross a protection boundry. 
  CapOp_CReturn   = 5'h6,  // Return to previous protection domain.
  CapOp_JR        = 5'h7, 
  CapOp_Branch    = 5'h8, 
  CapOp_CSCR      = 5'h9,
  CapOp_CLCR      = 5'hA,
  CapOp_Load      = 5'hB, // possibly linked
  CapOp_Store     = 5'hC, // possibly linked
  CapOp_Id        = 5'hD,
  CapOp_Check     = 5'hE,
  CapOp_SetCause  = 5'hF,
  CapOp_CToPtr    = 5'h10,
  CapOp_CFromPtr  = 5'h11,
  CapOp_CIncBase  = 5'h12,
  CapOp_CIncBase2 = 5'h13,
  CapOp_CIncOffset = 5'h14,
  CapOp_CSetOffset = 5'h15,
  CapOp_CGetOffset = 5'h16,
  CapOp_CCompare   = 5'h17
} CapOp deriving (Bits, Eq, FShow);

// instance FShow#(CapOp);
//   function Fmt fshow(CapOperation op);
//     return $format("CapOperation{ op: ", fshow(op.op), "...",
//                                ", cdest: ", fshow(op.dest),
//                                ", cA: ",  fshow(op.cA),
//                                ", cB: ",  fshow(op.cB), "}");
//   endfunction
// endinstance	  
  
  

typedef struct {
  CapOp                 op;  // Operation
  Maybe#(CapRegName)  dest;  // cap dest
  Stage        whenWritten;
  Maybe#(CapRegName)    cA;  // cap src (cs)
  Maybe#(CapRegName)    cB;  // cap src (ct)
  Bool           hasResult;  // has a non cap result
  AccessSize    accessSize;  
  Bool           displayRF;
} CapOperation deriving(Bits, Eq);
	
instance FShow#(CapOperation);
  function Fmt fshow(CapOperation op);
    return $format("CapOperation{ op: ", fshow(op.op), "...",
                               ", cdest: ", fshow(op.dest),
                               ", cA: ",  fshow(op.cA),
                               ", cB: ",  fshow(op.cB), "}");
  endfunction
endinstance	
	
typedef struct{
  ThreadID  thread;
  ThreadState   ts;
  CapOperation  op;
  Bit#(16)     imm;
  Bool       fetEx;
  Address  fetchAddr;
} DecCapInst deriving(Bits, Eq);

typedef struct{
  ThreadID           thread;
  ThreadState            ts;
  CapOperation           op;
  Bool                  tag;
  Capability            cap;
  Bool           getMemResp;
  CapCause     capException;
  Address           memAddr;
} ExeCapInst deriving(Bits, Eq);

typedef struct {
   ThreadID   tid;
   CapRegName   r;
} ThreadCapReg deriving(Bits, Eq, Bounded);

function Maybe#(Maybe#(TaggedCapability)) searchCExe(ExeCapInst i, ThreadCapReg r);
  if (i.op.dest == tagged Valid r.r && i.thread == r.tid) // matches dest
    begin 
      let tup = tuple2(i.tag, i.cap);
      return Valid ((i.op.whenWritten <= Stage_Exe) ? tagged Valid tup : Invalid);
	end
  else
    return Invalid;
endfunction

typedef struct{
  ThreadID               thread;
  ThreadState                ts;
  CapOperation               op;
  Bool                      tag;
  Capability                cap;
  Bool               getMemResp;
  CapCause         capException;
} MemCapInst deriving(Bits, Eq);

function Maybe#(Maybe#(TaggedCapability)) searchCMem(MemCapInst i, ThreadCapReg r);
  if (i.op.dest == tagged Valid r.r && i.thread == r.tid) // matches dest
    begin
      let tup = tuple2(i.tag, i.cap);
      return Valid ((i.op.whenWritten <= Stage_Mem) ? tagged Valid tup : Invalid);
    end
  else
    return Invalid;
endfunction
