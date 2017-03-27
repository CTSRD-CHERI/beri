/*-
 * Copyright (c) 2014 Robert Norton
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
 *   Robert Norton <robert.norton@cl.cam.ac.uk>
 * 
 ******************************************************************************
 *
 * Description: Format of the structure used for tracing on cheri and cheri2.
 * 
 ******************************************************************************/
`ifdef CAP
  `define USECAP 1
`elsif CAP128
  `define USECAP 1
`elsif CAP64
  `define USECAP 1
`endif
 
`ifdef USECAP
  typedef struct {
    Bit#(4)   seg;
    Bit#(8)   addrHi;
    Bit#(20)  addrLo;
  } ShortAddr deriving(Bits, Eq);
  
  typedef struct {
    Bool permit_seal;
    Bool permit_store_ephemeral_cap;
    Bool permit_store_cap;
    Bool permit_load_cap;
    Bool permit_store;
    Bool permit_load;
    Bool permit_execute;
    Bool non_ephemeral;
  } ShortPerms deriving(Bits, Eq); // 8 bits
  
  function ShortAddr word2short(Bit#(64) word);
    return ShortAddr{
      seg: word[62:59],
      addrHi: word[39:32],
      addrLo: word[19:0]
    };
  endfunction
  
  typedef struct {
    Bool        isCapability; // 1
    Bool        sealed;       // 1
    ShortPerms  perms;        // 8
    Bit#(22)    otype;        // 22
    ShortAddr offset;         // 32
    ShortAddr base;           // 32
    ShortAddr length;         // 32
  } ShortCap deriving(Bits, Eq); // 128 bits
`endif
 
typedef enum {
   TraceType_Invalid   = 4'd0,
   TraceType_ALU       = 4'd1,
   TraceType_Load      = 4'd2,
   TraceType_Store     = 4'd3,
   TraceType_Timestamp = 4'd4,
   TraceType_CapOp     = 4'd11,
   TraceType_CapLoad   = 4'd12,
   TraceType_CapStore  = 4'd13
} TraceType deriving (Bits, Eq, FShow);

typedef struct {
  Bool        valid; // 1
  TraceType entry_type; // 4
  Bit#(5)        ex; // 5
  Bit#(10)    count; // 10
  Bit#(8)      asid; // 8
  Bool       branch; // 1
  Bit#(3)  reserved; // 3
  Bit#(32)     inst; // 32
  Bit#(64)       pc; // 64
  Bit#(64)  regVal1; // 64
  Bit#(64)  regVal2; // 64
} TraceEntry deriving (Bits, Eq, FShow); // total=256

/**
 * Format of the trace entry used for the v2 disk format.
 * This is used for tracing directly to disk in simulation
 * in cheri2. cf the v2_disk structure in include/cheri_debug.h
 */
typedef struct {
  Bit#(8) entry_type;
  Bit#(8)  exception;
  Bit#(16)     count;
  Bit#(32)      inst;
  Bit#(64)        pc;
  Bit#(64)   regVal1;
  Bit#(64)   regVal2;
  Bit#(8)     thread;
  Bit#(8)       asid;
} TraceEntryDisk_v2 deriving (Bits, Eq, FShow); // total=34 bytes

function TraceEntryDisk_v2 traceEntryToDiskV2(TraceEntry te);
  return TraceEntryDisk_v2 {
   entry_type: zeroExtend(pack(te.entry_type)),
    exception: zeroExtend(pack(te.ex)),
        count: zeroExtend(pack(te.count)),
         inst: te.inst,
           pc: te.pc,
      regVal1: te.regVal1,
      regVal2: te.regVal2,
       thread: zeroExtend(pack(te.reserved)),
         asid: te.asid
     };
endfunction
