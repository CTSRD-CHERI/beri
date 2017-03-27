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

typedef enum {Memory, Branch, Arithmetic} ExecuteType
  deriving (Bits, Eq);

//Capability fields definition vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv  //

//Capability Type Field
typedef Bit#(16) CType;

typedef Bit#(0) ManHiBits;

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
typedef Int#(16) Mantis;
typedef Bit#(6) Exp;
typedef Bit#(66) LAddress; // Address with space for higher bits for comparison.

// The permissions field, including 8 "soft" permission bits.
typedef struct {
  Bit#(8)   soft;
  HardPerms hard;
} Perms deriving(Bits, Eq, FShow); // 23 bits

typedef struct {
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
} HardPerms deriving(Bits, Eq, FShow); // 23 bits

// The full capability structure, including the "tag" bit.
typedef struct {
  Bool     isCapability;
  Perms    perms;
  //Bool     base_eq_pointer;
  Bit#(2)  unused;
  Exp      exp;
  Mantis   toTop;
  Mantis   toBot;
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
  //Bool      base_eq_pointer;
  Bool      sealed;
  CType     otype;
  Bit#(2)  unused;
} CapFat deriving(Bits, Eq, FShow);

function LAddress getTopFat(CapFat cap, ManHiBits hiBits);
  return cap.top;
endfunction

function LAddress getBotFat(CapFat cap, ManHiBits hiBits);
  return cap.bot;
endfunction

function LAddress getLengthFat(CapFat cap, ManHiBits hiBits);
  LAddress length = cap.top - cap.bot;
  return (length < 66'h10000000000000000) ? length:66'hFFFFFFFFFFFFFFFF;
endfunction

function Address getOffsetFat(CapFat cap, ManHiBits hiBits);
  return truncate(cap.pointer - cap.bot);
endfunction

// The mask that determines how many bits we use of the exponent. 
// ~('b11) to mask off the bottom two bits, etc.
Exp expMask = ~('b0);

function Mantis makeMantis(LAddress pointer, LAddress bound, Exp exp, Bool roundUp);
  exp = (exp<50) ? exp:50;
  exp = exp & expMask;
  // Inverse of this:
  // top/bot = (signExtend(pack(cap.toTop))<<exp) + (getPtr(cap)&(-1<<exp));
  //Mantis toBound = truncate((bound - (pointer&(-1<<exp))) >> exp);
  Mantis toBound = unpack(truncate((bound>>exp) - (pointer>>exp)));
  /*if (roundUp) begin
    //LAddress mask = (-1<<exp);
    //if ((diff&mask) != 0) 
    // Not sure how best to express this...
    LAddress newBound = (signExtend(pack(toBound))<<exp) + pointer;
    if (newBound < bound) toBound = toBound + 1;
  end*/
  return toBound;
endfunction

function Capability packCap(CapFat fat);
  Capability thin = Capability{
    isCapability: fat.isCapability,
    perms: fat.perms,
    exp: fat.exp,
    toTop: makeMantis(fat.pointer, fat.top, fat.exp, True),
    toBot: makeMantis(fat.pointer, fat.bot, fat.exp, False),
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
    top: getTop(thin),
    bot: getBase(thin),
    pointer: getPtr(thin),
    //base_eq_pointer: thin.base_eq_pointer,
    sealed: sealed,
    otype: getType(thin),
    unused: thin.unused
  };
/*  if (!thin.isCapability) begin
    fat = defaultCapFat;
    fat.isCapability = False;
    fat.top = zeroExtend(pack(thin)[127:64]);
    fat.bot = zeroExtend(pack(thin)[63:0]);
  end*/
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
  LAddress   capAbot;
  LAddress   capAtop;
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
  exp: 50, // Shift by 50 to get the 15th bit of toBot and toTop up to the 65th bit.
  toBot: 0,
  toTop: 16'h4000,
  pointer: tagged Full 64'b0,
  perms: unpack(23'h7FFFFF),
  //base_eq_pointer: True,
  unused: 0,
  isCapability: True
};

CapFat defaultCapFat = CapFat{
  exp: 50, // Shift by 50 to get the 15th bit of toBot and toTop up to the 65th bit.
  bot: 0,
  top: 66'h10000000000000000,
  pointer: 0,
  perms: unpack(23'h7FFFFF),
  sealed: False,                                   
  otype: 0,
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
  Exp exp = (cap.exp < 50)?cap.exp:50;
  exp = exp & expMask;
  bot = (bot&(-1<<exp)) + (signExtend(pack(cap.toBot))<<exp);
  //bot = bot & (-1 << exp); // Mask the base to align it.
  return bot;
endfunction

function LAddress getTop(Capability cap);
  Exp exp = (cap.exp < 50)?cap.exp:50;
  exp = exp & expMask;
  //LAddress top = (signExtend(pack(cap.toTop))<<exp);
  LAddress top = (signExtend(pack(cap.toTop))<<exp) + (getPtr(cap)&(-1<<exp));
  //top = top & (-1 << exp);
  //The below alternative is huge!  Area +4% of DE4 when this style is used in getTop and getBase.
  //LAddress top = getPtr(cap) >> cap.exp;
  //top = top + signExtend(pack(cap.toTop));
  //top = top << cap.exp;
  return top;
endfunction

function LAddress getLength(LAddress bot, LAddress top);
  LAddress length = top-bot;
  return (length < 66'h10000000000000000) ? length:66'hFFFFFFFFFFFFFFFF;
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

// To provide compatability with candidate 3.
function ManHiBits getHiBits(CapFat cap);
  return ?;
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

function ActionValue#(CapFat) updatePointer(CapFat cap, LAddress pointer, ManHiBits hiBits) =
  actionvalue
    // Trim the pointer to 64 bits.
    Int#(66) offset = unpack(pointer - cap.pointer);
    trace($display("offset: %x, new pointer: %x, cap.pointer: %x",
                   offset, pointer, cap.pointer));
    CapFat newCap <- updatePointerOffset(cap, pointer, offset);
    return newCap;
  endactionvalue;

function ActionValue#(CapFat) updatePointerOffset(CapFat cap, LAddress ptr, Int#(66) offset) =
  actionvalue
    // Trim the pointer to 64 bits.
    LAddress p = zeroExtend(ptr[63:0]);
    CapFat ret = cap;
    ret.pointer = p;
    
    Exp exp = (cap.exp < 50)?cap.exp:50;
    exp = exp & expMask;
    ret.exp = exp;
    // Mask of mantissa + top bits.
    LAddress mask    = ((-1)<<exp);

    ret.bot = ret.bot&mask;
    ret.top = ret.top&mask;

    // The new to top and to bottom (unshifted)
    LAddress newToBot = (p&mask)-(cap.bot&mask);
    LAddress newToTop = (p&mask)-(cap.top&mask);
    // New mask to isolate the bits that would be truncated.
    Bit#(7) topExp = zeroExtend(exp) + 15; // Exponent to shift above the mantissa.
    LAddress topMask = ((-1)<<topExp);
    // Isolate the "truncated" bits.
    newToBot = newToBot&topMask;
    newToTop = newToTop&topMask;
    Bool outOfBounds = False;
    //$display("newPointer:%x mask:%x bottop:%x toptop:%x capA.bot:%x capA.top:%x newExp:%x", newPointer, mask, bottop, toptop, capA.bot, capA.top, newExp);
    // Throw an exception if the top bits are not a valid sign extension.
    if (newToBot!=0 && newToBot!=topMask) outOfBounds = True;
    if (newToTop!=0 && newToTop!=topMask) outOfBounds = True;
    
    // This leaves some out-of-bounds range on the table but is much faster.
    /* Only allow going out of bounds by the length of the capability on each side of the bounds.
    Bool outOfBounds = False;
                                                           // LAddress length = cap.top - cap.bot;  
    if ( p > ((cap.top<<1) - cap.bot)                    // = p > (cap.top + length)            
      || p < zeroExtend(((cap.bot<<1) - cap.top)[63:0])) // = p < (cap.bot - length)            
        outOfBounds = True;
    trace($display("%x > %x ?", p, ((cap.top<<1) - cap.bot)));
    trace($display("%x < %x ?", p, ((cap.bot<<1) - cap.top)[63:0]));
    trace($display("outOfBounds = ", fshow(outOfBounds)));
    */
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

function ActionValue#(CapFat) setBounds(CapFat cap, Address length) =
  actionvalue
    CapFat ret = cap;
    ret.bot = cap.pointer;
    UInt#(7) zeros = countZerosMSB(length);
    // using the constant 49 here would allow us to perfectly represent the most significant
    // bit of the length, but we use 50 to give us one extra MSB, and therefore one less bit
    // of precision.  This is necessary for the potential "round-up" add at the end, and also
    // to give space for the pointer to move out of bounds.
    Exp newExp = (zeros > 50) ? 0:truncate(50-pack(zeros));
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
  endactionvalue;
  
function ActionValue#(CapFat) seal(CapFat cap, CType otype) =
  actionvalue
    CapFat ret = cap;
    ret.sealed = True;
    ret.otype = otype;
    return ret;
  endactionvalue;

typedef Bit#(0) TempFields;

function TempFields getTempFields(CapFat a);
  return 0;
endfunction

  
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
  Bit#(15) hardPerms = signExtend(pack(cap.perms.hard));
  Bit#(16) softPerms = zeroExtend(pack(cap.perms.soft));
  return zeroExtend({softPerms,hardPerms});
endfunction

interface CapCopIfc;
  method Action                           putCapInst(CapInst capInst);
  method Address                          getArchPc(Address pc, Epoch epoch); // Translate absolute virtual address to arch PC
  method ActionValue#(CoProResponse)      getCapResponse(CapReq capReq, ExecuteType opType);
  method ActionValue#(CoProResponse)      getAddress();
  method ActionValue#(Maybe#(CapFat))     commitWriteback(CapWritebackRequest wbReq);
endinterface
