/*-
 * Copyright (c) 2015 Jonathan Woodruff
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

// This is a bit of a dummy library used for testing that implements some
// functions of the compressed capability library with uncompressed capabilities.
import MIPS::*;
import Debug::*;

typedef enum {Memory, Branch, Arithmetic} ExecuteType
  deriving (Bits, Eq);

typedef Bit#(24) CType;
typedef Bit#(65) LAddress;

function LAddress cleanLAddr(LAddress a);
  // SignExtend from bit 41 to 58 as they are not part of a valid virtual address.
  LAddress ret = a;
  //ret[58:41] = signExtend(a[41]);
  return ret;
endfunction

typedef Bit#(0) ManHiBits;

// The permissions field, including 8 "soft" permission bits.
typedef struct {
  Bit#(16)  soft;
  PermsHard hard;
} Perms deriving(Bits, Eq, FShow); // 31 bits

typedef struct {
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
} PermsHard deriving(Bits, Eq, FShow); // 31 bits

// The full capability structure, including the "tag" bit.
typedef struct {
  Bool      isCapability;
  Bit#(8)   reserved;
  CType     otype;
  Perms     perms;
  Bool      sealed;
  Word      pointer;
  Address   base;
  Bit#(64)  length;
} Capability deriving(Bits, Eq, FShow);

// The an "unpacked" capability with a decoded top and bottom.
typedef Capability CapFat;

function LAddress getTopFat(CapFat cap, ManHiBits hiBits);
  return zeroExtend(cap.base + cap.length);
endfunction

function LAddress getBotFat(CapFat cap, ManHiBits hiBits);
  return zeroExtend(cap.base);
endfunction

function LAddress getLengthFat(CapFat cap, ManHiBits hiBits);
  return zeroExtend(cap.length);
endfunction

function Address getOffsetFat(CapFat cap, ManHiBits hiBits);
  return cap.pointer - cap.base;
endfunction

function Capability packCap(CapFat fat);
  return fat;
endfunction

function CapFat unpackCap(Capability thin);
  return thin;
endfunction

// End Capability fields definition ^^^^^^^^^^^^^^^^^^^^^^^^^^^ //

typedef Bit#(3)  Select;

typedef struct {
  Address   pc;
  Int#(64)  offset; // The offset into the capability
  MemSize   size;
  MemOp     memOp;
} CapReq deriving(Bits, Eq, FShow);

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
  CapFat     writeCap;      // Capability to be written
  CapReg     writeReg; // Capability register to be written
  LAddress   newPtr;
  Bool       zeroOffset;
  Bool       doWrite; // Write the destination register.
  LAddress   pc;
  Bool       pccCheck;
  LAddress   pccBot;
  LAddress   pccTop;
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
  LAddress  bot;    // Base, must be less than or equal to address 
  MemSize   memSize; // Instruction ID that requests the update
  CapReg    capReg;
  Bool      ovExp;   // Throw an exception on overflow.
} LenCheck deriving(Bits, Eq, FShow);

typedef struct {
  CapReg     capReg;
  Bool       pcc;
  CapExpCode exp;
} CapCause deriving(Bits, Eq, FShow);

typedef struct {
  CapFat  pcc;
  Epoch   epoch;
} BufferedPCC deriving(Bits, Eq);

Capability defaultCap = Capability{
  length: 64'hFFFFFFFFFFFFFFFF,
  base: 64'b0,
  pointer: 64'b0,
  sealed: False,
  perms: unpack(31'h7FFFFFFF),
  otype: 24'b0,
  reserved: 0,
  isCapability: True
};

CapFat defaultCapFat = defaultCap;

typedef struct {
  MemOp       memOp;
  Address     address;
  Bool        isCapability;
  Capability  capability;
  InstId      instId;
} CapMemAccess deriving(Bits, Eq);

function LAddress getPtr(Capability cap);
  return zeroExtend(cap.pointer);
endfunction

function Bool getSealed(Capability cap);
  return cap.sealed;
endfunction

// To understand this function, first read the comment on the definition of the ManHiBits type.
// This function populates the fields of the ManHiBits (Mantissa High Bits) type.
function ManHiBits getHiBits(CapFat cap);
  return 0;
endfunction

typedef ManHiBits TempFields;
function TempFields getTempFields(CapFat cap) = getHiBits(cap);

function LAddress getOffset(Capability cap, LAddress bot);
  return (getPtr(cap) - bot);
endfunction

// Function to "cheat" and just set the pointer because we know that
// it will be in representable bounds by some other means.
function CapFat setCapPointer(CapFat cap, Address pointer);
  CapFat ret = cap;
  ret.pointer = zeroExtend(pointer);
  return ret;
endfunction

// Clear fields, preserving the pointer value.
function CapFat nullifyCap(CapFat cap);
  CapFat ret = cap;
  ret.isCapability = False;
  ret.length = 0;
  ret.base = 0;
  return ret;
endfunction

// For this function to work correctly, the offset must == pointer-cap.pointer.
// In the most critical case we have both available and picking one or the other
// is less efficient than passing both.  If the "setOffset" flag is set, this function will
// set the offset to "offset" (ignoring pointer) rather than increment the offset, assuming
// that pointer is cap.pointer+offset.
function ActionValue#(CapFat) incOffset(CapFat cap, LAddress pointer, Bit#(64) offset, ManHiBits hiBits, Bool setOffset) =
  actionvalue
    CapFat ret = cap;
    if (setOffset) ret.pointer = cap.base + offset;
    else ret.pointer = truncate(pointer);
    
    return ret;
  endactionvalue;

function CType getType(Capability cap);
  return cap.otype;
endfunction

// Check that the pointer of a capability is currently within the bounds
// of the capability.
function Bool capInBounds(CapFat cap, ManHiBits hb, Bool inclusive);
  Bool topOk = cap.pointer < cap.base + cap.length;
  Bool botOk = cap.base <= cap.pointer;
  return topOk && botOk;
endfunction

function Bool boundsCheck(CapFat cap, Bit#(64) off, ManHiBits hb);
  Address pointer = cap.pointer + off;
  Bool topOk = pointer < (cap.base + cap.length);
  Bool botOk = cap.base <= pointer;
  return topOk && botOk;
endfunction


function ActionValue#(CapFat) setBounds(CapFat cap, Address length) =
  actionvalue
    CapFat ret = cap;
    ret.base = ret.pointer;
    ret.length = length;
    return ret;
  endactionvalue;
  
function ActionValue#(CapFat) seal(CapFat cap, ManHiBits hb, CType otype) =
  actionvalue
    CapFat ret = cap;
    ret.sealed = True;
    ret.otype = otype;
    return ret;
  endactionvalue;

function CapExpCode checkRegAccess(Perms pp, CapReg cr);
  CapExpCode ret = None;
  if      (!pp.hard.access_CR27 && cr==27) ret = CR27;
  else if (!pp.hard.access_CR28 && cr==28) ret = CR28;
  else if (!pp.hard.access_CR29 && cr==29) ret = CR29;
  else if (!pp.hard.access_CR30 && cr==30) ret = CR30;
  else if (!pp.hard.access_CR31 && cr==31) ret = CR31;
  return ret;
endfunction

function Bool priveleged(Perms pp) = pp.hard.access_CR31;

function Bit#(64) getPerms(CapFat cap);
  return zeroExtend(pack(cap.perms));
endfunction

interface CapCopIfc;
  method Action                           putCapInst(CapInst capInst);
  method Address                          getArchPc(Address pc, Epoch epoch); // Translate absolute virtual address to arch PC
  method ActionValue#(CoProResponse)      getCapResponse(CapReq capReq, ExecuteType opType);
  method ActionValue#(CoProResponse)      getAddress();
  method ActionValue#(CapFat)     commitWriteback(CapWritebackRequest wbReq);
endinterface