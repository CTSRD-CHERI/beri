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

import MIPS::*;

//Capability fields definition vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv  //

//Capability Type Field
typedef Bit#(16) CType;

// A type that bundles the type and the compressed virtual address.
typedef struct {
  Bit#(5)   seg;
  CType     otype;
  Bit#(43)  address;
} TypePointer deriving(Bits, Eq, FShow); // 64-bits

// The tagged union of a simple 64-bit address and a compressed address
// plus a type.  The tag of this field is the "sealed" bit of the capability.
typedef union tagged {
  Address     Full;
  TypePointer Typed;
} Pointer deriving (Bits, Eq, FShow);

// These are the types to define the "base" and "length" reletive to the full
// pointer address.  The Mantissa is signed, allowing you to go out of bounds.
typedef Bit#(16) Mantis;
typedef Bit#(6) Exp;
typedef Bit#(65) LAddress; // Address with space for higher bits for comparison.

// The permissions field, including 8 "soft" permission bits.
typedef struct {
  Bit#(8) soft;
  Bool access_CR28; // KR2C
  Bool access_CR27; // KR1C
  Bool access_CR29; // KCC
  Bool access_CR30; // KDC
  Bool access_CR31; // EPCC
  Bool undefined;
  Bool permit_set_type;
  Bool permit_seal;
  Bool permit_store_ephemeral_cap;
  Bool permit_store_cap;
  Bool permit_load_cap;
  Bool permit_store;
  Bool permit_load;
  Bool permit_execute;
  Bool non_ephemeral;
} Perms deriving(Bits, Eq, FShow); // 23 bits

// The full capability structure, including the "tag" bit.
typedef struct {
  Bool     isCapability;
  Perms    perms;
  //Bool     base_eq_pointer;
  Bit#(2)  unused;
  Exp      exp;
  Mantis   topBits;
  Mantis   botBits;
  Pointer  pointer;
} Capability deriving(Bits, Eq, FShow); // 128 bits + 1 (tag bit)

// The an "unpacked" capability with a decoded top and bottom.
typedef struct {
  Bool      isCapability;
  Perms     perms;
  Exp       exp;
  LAddress  top;
  LAddress  bot;
  LAddress  pointer;
  LAddress  mask;
  //Bool      base_eq_pointer;
  Bool      sealed;
  CType     otype;
  Bit#(2)  unused;
} CapFat deriving(Bits, Eq, FShow);

// The mask that determines how many bits we use of the exponent. 
// ~('b11) to mask off the bottom two bits, etc.
Exp expMask = ~('b0);

function Mantis makeMantis(LAddress pointer, LAddress bound, Exp exp, Bool roundUp);
  exp = (exp<49) ? exp:49;
  exp = exp & expMask;
  Mantis limit = unpack(truncate(bound>>exp));
  return limit;
endfunction

function Capability packCap(CapFat fat);
  Capability thin = Capability{
    isCapability: fat.isCapability,
    perms: fat.perms,
    exp: fat.exp,
    topBits: makeMantis(fat.pointer, fat.top, fat.exp, True),
    botBits: makeMantis(fat.pointer, fat.bot, fat.exp, False),
    pointer: ?,
    unused: fat.unused
  };
  if (fat.sealed) thin.pointer = tagged Typed TypePointer{
                                                  seg: fat.pointer[63:59],
                                                  otype: fat.otype,
                                                  address: truncate(fat.pointer)
                                              };
  else thin.pointer = tagged Full truncate(fat.pointer);
  return thin;
endfunction

function CapFat unpackCap(Capability thin);
  Bool sealed = False;
  if (thin.pointer matches tagged Typed .tp) sealed = True;
  CapFat fat = CapFat{
    isCapability: thin.isCapability,
    perms: thin.perms,
    exp: thin.exp,
    mask: ((-1)<<thin.exp),
    top: getTop(thin),
    bot: getBase(thin),
    pointer: getPtr(thin),
    //base_eq_pointer: thin.base_eq_pointer,
    sealed: sealed,
    otype: getType(thin),
    unused: thin.unused
  };
  return fat;
endfunction

// End Capability fields definition ^^^^^^^^^^^^^^^^^^^^^^^^^^^ //

typedef Bit#(3)  Select;

typedef struct {
  Address   pc;
  Int#(64)  offset; // The offset into the capability
  MemSize   size;
  MemOp     memOp;
} CapReq deriving(Bits, Eq);

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
  exp: 49, // Shift by 50 to get the 16th bit of botBits and topBits up to the 65th bit.
  botBits: 0,
  topBits: 16'h8000,
  pointer: tagged Full 64'b0,
  perms: unpack(23'h7FFFFF),
  //base_eq_pointer: True,
  unused: 0,
  isCapability: True
};

CapFat defaultCapFat = CapFat{
  exp: 49, // Shift by 49 to get the 16th bit of botBits and topBits up to the 65th bit.
  bot: 0,
  top: 65'h10000000000000000,
  pointer: 0,
  perms: unpack(23'h7FFFFF),
  sealed: False,                                   
  otype: 0,
  //base_eq_pointer: True,
  isCapability: True,
  unused: 0
};

typedef struct {
  MemOp       memOp;
  Address     address;
  Bool        isCapability;
  Capability  capability;
  InstId      instId;
} CapMemAccess deriving(Bits, Eq);

function LAddress getPtr(Capability cap);
  Address ret = 0;
  case (cap.pointer) matches
    tagged Full  .p: ret = p;
    tagged Typed .tp: begin
      ret[58:0] = signExtend(tp.address);
      ret[63:59] = tp.seg;
    end
  endcase
  return zeroExtend(ret);
endfunction

function Bool getSealed(Capability cap);
  Bool ret = False;
  if (cap.pointer matches tagged Typed .tp) ret = True;
  return ret;
endfunction

function LAddress getBase(Capability cap);
  LAddress bot = zeroExtend(getPtr(cap));
  Exp exp = (cap.exp < 49)?cap.exp:49;
  exp = exp & expMask;
  LAddress bot = ptr&(-1<<exp);
  bot[exp+15:exp] = cap.botBits;
  bot = bot;
  return bot;
endfunction

function LAddress getTop(Capability cap);
  Exp exp = (cap.exp < 49)?cap.exp:49;
  exp = exp & expMask;
  //LAddress top = (signExtend(pack(cap.toTop))<<exp);
  LAddress top = ptr&(-1<<exp);
  top[exp+15:exp] = cap.topBits;
  top = top;
  return top;
endfunction

function LAddress getLength(LAddress bot, LAddress top);
  LAddress length = top-bot;
  return (length < 65'h10000000000000000) ? length:65'hFFFFFFFFFFFFFFFF;
endfunction

/*
function LAddress getLength(Capability cap);
  Mantis shortLength = cap.toTop - cap.toBot;
  LAddress length = signExtend(pack(shortLength)) << cap.exp;
  return (length < 66'h10000000000000000) ? length:66'hFFFFFFFFFFFFFFFF;
endfunction
*/
function LAddress getOffset(Capability cap, LAddress bot);
  return (getPtr(cap) - bot);
endfunction

function Pointer buildPtr(Address ptr, CType otype, Bool validType);
  Pointer ret = tagged Full ptr;
  if (validType) 
    ret = tagged Typed TypePointer{
                         seg: truncateLSB(ptr), 
                         otype: otype,
                         address: truncate(ptr)
                       };
  return ret;
endfunction

function ActionValue#(CapFat) updatePointer(CapFat cap, LAddress ptr) =
  actionvalue
    Bool outOfBounds = False;
    if (ptr > (cap.top + 1024)) outOfBounds = True;
    if (ptr < (cap.bot - 1024)) outOfBounds = True;
    
    // Also, if it is sealed and we have changed the 16 bits of the otype, we are outOfBounds.
    // We will only arrive here for a sealed capability if it is untagged since a sealed capability cannot be modified.
    if (cap.sealed && cap.isCapability) begin
      TypePointer tp = unpack(truncate(p));
      if (cap.otype != tp.otype) outOfBounds = True;
      ret.otype = tp.otype;
      tp.otype = signExtend(tp.address[42]);
      ret.pointer = zeroExtend(pack(tp));
    end
    if (outOfBounds && ret.isCapability) begin
      ret.isCapability = False;
      ret.exp = 0;
      ret.top = p;
      ret.bot = p;
    end
    return ret;
  endactionvalue;

function CType getType(Capability cap);
  CType ret = (case (cap.pointer) matches
                tagged Full  .p: return 0;
                tagged Typed .tp: return tp.otype;
              endcase);
  return ret;
endfunction

function Bool outOfRange(CapFat cap);
  return (cap.pointer < cap.bot || cap.pointer >= cap.top);
endfunction

function Exp truncateExp(Exp e);
  Exp ret = e & expMask;
  if (ret != e) ret = e + (~expMask) + 1;
  return ret;
endfunction

function CapFat setBounds(CapFat cap, Address length);
  CapFat ret = cap;
  ret.bot = cap.pointer;
  repLength = length + 2048; // Make sure there is always space.
  UInt#(7) zeros = countZerosMSB(repLength);
  Exp newExp = (zeros > 49) ? 0:truncate(49-pack(zeros));
  newExp = truncateExp(newExp);
  ret.exp = newExp;
  LAddress mask = -1<<newExp;
  // Conservatively mask the bottom to emulate/prepare for compression.
  ret.bot = ret.bot&mask;
  // Add one to "round up" the toTop.
  LAddress plusOne = ((zeroExtend(length)&~(mask)) != 0) ? (1<<newExp):0;
  LAddress toTop = (zeroExtend(length)&mask) + plusOne;
  ret.top = (cap.pointer+toTop)&mask;
  return ret;
endfunction

function CapExpCode checkRegAccess(Perms pp, CapReg cr);
  CapExpCode ret = None;
  if      (!pp.access_CR27 && cr==27) ret = CR27;
  else if (!pp.access_CR28 && cr==28) ret = CR28;
  else if (!pp.access_CR29 && cr==29) ret = CR29;
  else if (!pp.access_CR30 && cr==30) ret = CR30;
  else if (!pp.access_CR31 && cr==31) ret = CR31;
  return ret;
endfunction

function Bool priveleged(Perms pp) = pp.access_CR31;

interface CapCopIfc;
  method Action                           putCapInst(CapInst capInst);
  method Address                          getArchPc(Address pc, Epoch epoch); // Translate absolute virtual address to arch PC
  method ActionValue#(CoProResponse)      getCapResponse(CapReq capReq);
  method ActionValue#(CoProResponse)      getAddress();
  method ActionValue#(Bool)               targetInBounds(Address testPc); // Does not require "action" except to print debug.
  method ActionValue#(Maybe#(CapFat))     commitWriteback(CapWritebackRequest wbReq);
endinterface