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
import Debug::*;

typedef enum {Memory, Branch, Arithmetic} ExecuteType
  deriving (Bits, Eq);

//Capability fields definition vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv  //

//Capability Type Field
typedef Bit#(12) CType;

// The mask that determines how many bits we use of the exponent. 
// ~('b11) to mask off the bottom two bits, etc.
// This is expected to work up to ~('b111), with an exponent alignment
// of 8 bits.
Exp expMask = ~('b000);
function Exp cleanExp(Exp exp);
  // Worst case is 58, which might be found in an unsealed
  // capability.
  //if (exp > 48) exp = 58;
  //if ((exp & ~expMask) != 0) exp = (exp + (~expMask));
  return exp & expMask;
endfunction

// These are the types to define the "base" and "length" reletive to the full
// pointer address.  The Mantissa is signed, allowing you to go out of bounds.
typedef Bit#(8) Mantis;
typedef Bit#(10) LMantis;
typedef Bit#(5)  Exp;
typedef Bit#(6)  LExp;
typedef Bit#(34) LN32Address; // Address with space for higher bits for comparison.
typedef Bit#(66) LAddress; // Address with space for higher bits for comparison.
typedef Bit#(32) N32Address; // Address field for n32 ABI
function LN32Address cleanLAddr(LN32Address a);
  // SignExtend from bit 41 to 58 as they are not part of a valid virtual address.
  LN32Address ret = a;
  //ret[58:41] = signExtend(a[41]);
  return ret;
endfunction

// A type that bundles the type and the compressed virtual address.
typedef struct {
  Bit#(2)   bot;
  Bit#(6)  oTypeLo;
  Bit#(2)   top;
  Bit#(6)  oTypeHi;
} BoundsAndType deriving(Bits, Eq, FShow); // 40-bits

typedef struct {
  Mantis   bot;
  Mantis   top;
} Bounds deriving(Bits, Eq, FShow); // 40-bits

// This is a structure to hold metainformation to
// help disambiguate the actual location of the
// top and bottom of a compressed capability.
//
// The top, bottom, and pointer of a compressed capability lie in a single, unaligned,
// power-of-two sized span, and the top and bottom might not be in the same alignment 
// region as the pointer, so to derive the top or bottom from the pointer, it may be 
// necessary to add or subtract one to the bit vector above the Mantis bits.
//
// This structure first holds booleans which indicate whether the top, bottom, and pointer
// are in the Low or High regions of the unaligned span of representable values.
// Second, it holds the integer value that must be appended to the most significant
// bits of the mantis when it is sign extended and added to the masked pointer to
// produce the top and bottom of the region.
typedef struct {
  Mantis    repBound;
  Bool      topHi;
  Bool      botHi;
  Bool      ptrHi;
  Int#(2)   top;
  Int#(2)   bot;
} ManHiBits deriving(Bits, Eq, FShow);

typedef union tagged {
  Bounds        Unsealed;
  BoundsAndType Sealed;
} BoundField deriving (Bits, Eq, FShow);

// The permissions field, including 8 "soft" permission bits.
typedef struct {
  Bit#(1)   soft;
  HardPerms hard;
} Perms deriving(Bits, Eq, FShow); // 11 bits

typedef struct {
/*Bool access_CR28; // KR2C
  Bool access_CR27; // KR1C
  Bool access_CR29; // KCC
  Bool access_CR30; // KDC
  Bool access_CR31; // EPCC*/
  Bool acces_sys_regs;
  Bool permit_seal;
  Bool permit_store_ephemeral_cap;
  Bool permit_store_cap;
  Bool permit_load_cap;
  Bool permit_store;
  Bool permit_load;
  Bool permit_execute;
  Bool non_ephemeral;
} HardPerms deriving(Bits, Eq, FShow); // 11 bits

// The full capability structure, including the "tag" bit.
typedef struct {
  Bool       isCapability;
  Perms      perms;
  Exp        exp;
  BoundField bounds;
  N32Address    pointer;
} Capability deriving(Bits, Eq, FShow); // 128 bits + 1 (tag bit)

// The an "unpacked" capability with a decoded top and bottom.
typedef struct {
  Bool      isCapability;
  Perms     perms;
  Exp       exp;
  Bool      sealed;
  Mantis    bot;
  Mantis    top;
  CType     otype;
  LN32Address  pointer;
  Mantis    ptr; // Replicate the bits of the pointer corrosponding to the top and bot.
} CapFat deriving(Bits, Eq, FShow);

function LN32Address getTopFat(CapFat cap, ManHiBits hiBits);
  LExp exp = zeroExtend(cleanExp(cap.exp));
  // The MSB of cap.top, if it is set, will be a 1
  // added to the bits above the mantissa bits.
  LMantis topBits = {pack(hiBits.top),cap.top};
  LN32Address top =   signExtend(topBits) << exp;
  // Create a mask to select only the high bits of the pointer.
  Bit#(26) mask = (-1 << (exp));
  top = cleanLAddr(({cap.pointer[33:8]&mask,0}) + top);
  return top;
endfunction

function LN32Address getBotFat(CapFat cap, ManHiBits hiBits);
  LExp exp = zeroExtend(cleanExp(cap.exp));
  // The MSB of cap.bot, if it is set, will be a -1
  // subtracted from the bits above the mantissa bits.
  LMantis botBits = {pack(hiBits.bot),cap.bot};
  LN32Address bot =   signExtend(botBits) << exp;
  // Create a mask to select only the high bits of the pointer.
  Bit#(26) mask = (-1 << (exp));
  bot = cleanLAddr(({cap.pointer[33:8]&mask,0}) + bot);
  return bot;
endfunction

function LN32Address getLengthFat(CapFat cap, ManHiBits hiBits);
  Exp exp = cleanExp(cap.exp);
  LMantis top = {pack(hiBits.top),cap.top};
  LMantis bot = {pack(hiBits.bot),cap.bot};
  LN32Address length = zeroExtend(top - bot);
  length = length << exp;
  return (length[32]==1) ? -1:length;
endfunction

function N32Address getOffsetFat(CapFat cap, ManHiBits hiBits);
  Exp exp = cleanExp(cap.exp);
  LMantis offsetMantis = zeroExtend(cap.ptr) - {pack(hiBits.bot),cap.bot};
  LN32Address mask = (-1 << (exp));
  N32Address offset = truncate(cap.pointer&(~mask) | (signExtend(offsetMantis)<<exp));
  return offset;
endfunction

function Capability packCap(CapFat fat);
  Capability thin = Capability{
    isCapability: fat.isCapability,
    perms: fat.perms,
    exp: fat.exp,
    bounds: ?,
    pointer: truncate(fat.pointer)
  };
  if (fat.sealed) 
    thin.bounds = tagged Sealed BoundsAndType{
                    oTypeHi:   fat.otype[11:6],
                    oTypeLo:   fat.otype[5:0],
                    // Should use "truncate" for precise sealed caps case.
                    top:       truncateLSB(fat.top),
                    bot:       truncateLSB(fat.bot)
                  };
  else 
    thin.bounds = tagged Unsealed Bounds{
                    top:     fat.top,
                    bot:     fat.bot
                  };
  return thin;
endfunction

function CapFat unpackCap(Capability thin);
  Bool sealed = False;
  LN32Address pointer = getPtr(thin);
  Mantis ptr = truncate(pointer >> cleanExp(thin.exp));
  Bounds bounds = getBounds(thin, ptr);
  if (thin.bounds matches tagged Sealed .s) sealed = True;
  CapFat fat = CapFat{
    isCapability: thin.isCapability,
    perms: thin.perms,
    exp: thin.exp,
    top: bounds.top,
    bot: bounds.bot,
    ptr: ptr,
    pointer: pointer,
    sealed: sealed,
    otype: getType(thin)
  };
  return fat;
endfunction

// End Capability fields definition ^^^^^^^^^^^^^^^^^^^^^^^^^^^ //

typedef Bit#(3)  Select;

typedef struct {
  N32Address   pc;
  Int#(64)  offset; // The offset into the capability, FIXME, n32
  MemSize   size;
  MemOp     memOp;
} CapReq deriving(Bits, Eq, FShow);

typedef Bit#(5) CapReg;

typedef struct {
  CapOp           op;      // Operation
  CapReg          r0;      // Potential register name from bits 25-21
  CapReg          r1;      // bits 20-16
  CapReg          r2;      // bits 15-11
  CapReg          r3;      // bits 10-6
  Maybe#(CapReg)  fetchA;
  Maybe#(CapReg)  fetchB;
  Maybe#(CapReg)  dest;
  MemSize         memSize;
  InstId          instId;
  Epoch           epoch;
} CapInst deriving(Bits, Eq);

typedef struct {
  Capability memResponse;
  Exception  mipsExp;
  N32Address    pc;
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
  LN32Address   newPtr;
  Bool       zeroOffset;
  Bool       doWrite; // Write the destination register.
  LN32Address   pc;
  Bool       pccCheck;
  LN32Address   pccBot;
  LN32Address   pccTop;
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
  LN32Address  top;     // Last address, must be greater than or equal to address
  LN32Address  address; // Address for the request
  LN32Address  bot;    // Base, must be less than or equal to address 
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
  exp: 25,
  bounds: tagged Unsealed Bounds{
    bot: 0,
    top: 8'h80 // Put 1 in the 65th bit when shifted by 48 bits.
  },
  pointer: 32'b0,
  perms: unpack(10'h3FF),
  isCapability: True
};

CapFat defaultCapFat = CapFat{
  exp: 25,
  bot: 0,
  top: 8'h80, // Put 1 in the 65th bit when shifted by 48 bits.
  ptr: 0,
  pointer: 0,
  perms: unpack(10'h3FF),
  sealed: False,                                   
  otype: 0,
  isCapability: True
};

typedef struct {
  MemOp       memOp;
  N32Address     address;
  Bool        isCapability;
  Capability  capability;
  InstId      instId;
} CapMemAccess deriving(Bits, Eq);

function LN32Address getPtr(Capability cap);
  LN32Address ret = cleanLAddr(zeroExtend(cap.pointer));
  return zeroExtend(ret);
endfunction

function Bool getSealed(Capability cap);
  case (cap.bounds) matches 
    tagged Sealed   .s: return True;
    tagged Unsealed .u: return False;
  endcase
endfunction

function Bounds getBounds(Capability cap, Mantis ptr);
  Bounds bounds = case (cap.bounds) matches
                    tagged Unsealed .b: return b;
                    tagged Sealed   .b: begin
                      // These are required for precise sealed capabilities.
                      //Bool splitRegion = (b.top<b.bot);
                      //return Bounds{bot: {ptr[19:10],b.bot}, top: {ptr[19:10] + ((splitRegion)?1:0),b.top}};
                      return Bounds{bot: {b.bot,0}, top: {b.top,0}};
                    end
                endcase;
  return bounds;
endfunction

function Mantis getRepBound(CapFat cap);
  // Select a fixed distance below the bottom as the representable boundary.
  // This distance is one page when e=0, and grows with e.
  Mantis repBound = cap.bot - 8'h10;
  return repBound;
endfunction

// To understand this function, first read the comment on the definition of the ManHiBits type.
// This function populates the fields of the ManHiBits (Mantissa High Bits) type.
function ManHiBits getHiBits(CapFat cap);
  Exp exp = cleanExp(cap.exp);
  // Get the representable boundary.
  // These are the bits of the boundary in the bit positions of the top and bottom mantissas
  // and are the same for both the lower and upper representable bound.
  Mantis repBound = getRepBound(cap);
  // The representable span usually includes addresses in two different alignment regions.
  // Each index into this region (top, bottom, pointer) is either in the top region or the
  // bottom region.  This is determined below based on the relationship to the representable
  // bound.
  ManHiBits hiBits = ManHiBits{
    repBound: repBound,
    topHi: cap.top <  repBound,
    ptrHi: cap.ptr <  repBound,
    botHi: cap.bot <  repBound,
    top: ?, bot: ?
  };
  // Finally, decode the bits that should be appended to the top of the mantissas when
  // they are shifted and added to a masked pointer to produce the top and bottom.
  // A top or bottom can be at most 1 alignment region different from the pointer.
  // (Alignment region being 1<<(20+exp), the first bit above msb of the mantissa when
  // it is in place.
  // Decide if cap.top should be -1, 0, or 1
  if ( hiBits.topHi  ==  hiBits.ptrHi)  hiBits.top =  0;
  if ( hiBits.topHi  && !hiBits.ptrHi)  hiBits.top =  1;
  if (!hiBits.topHi  &&  hiBits.ptrHi)  hiBits.top = -1;
  // Same thing for cap.bot
  if ( hiBits.botHi  ==  hiBits.ptrHi)  hiBits.bot =  0;
  if ( hiBits.botHi  && !hiBits.ptrHi)  hiBits.bot =  1;
  if (!hiBits.botHi  &&  hiBits.ptrHi)  hiBits.bot = -1;
  /****************************************************/
  return hiBits;
endfunction

typedef ManHiBits TempFields;
function TempFields getTempFields(CapFat cap) = getHiBits(cap);


function LN32Address getOffset(Capability cap, LN32Address bot);
  return (getPtr(cap) - bot);
endfunction

// Function to "cheat" and just set the pointer because we know that
// it will be in representable bounds by some other means.
function CapFat setCapPointer(CapFat cap, N32Address pointer);
  CapFat ret = cap;
  Exp exp = cleanExp(cap.exp);
  ret.pointer = zeroExtend(pointer);
  ret.ptr = truncate(ret.pointer>>exp);
  return ret;
endfunction

// Clear fields, preserving the pointer value.
function CapFat nullifyCap(CapFat cap);
  CapFat ret = cap;
  ret.isCapability = False;
  ret.exp = 25;
  ret.top = 8'h80;
  ret.bot = 0;
  ret.ptr = {1'b0,truncateLSB(cap.pointer[31:0])};
  return ret;
endfunction
  
// Check whether one "Mantis" is within 1 of another Mantis.
// This allows fuzzy representable bounds so that we go out
// of representable bounds early to pessimistically avoid 
// accounting for carries up from lower bits.
function Bool within1(Mantis a, Mantis b);
  Mantis diff = a - b;
  return (diff[7:1] == {diff[1],diff[7:2]});
endfunction

// For this function to work correctly, the offset must == pointer-cap.pointer.
// In the most critical case we have both available and picking one or the other
// is less efficient than passing both.  If the "setOffset" flag is set, this function will
// set the offset to "offset" (ignoring pointer) rather than increment the offset, assuming
// that pointer is cap.pointer+offset.
function ActionValue#(CapFat) incOffset(CapFat cap, LN32Address pointer, Bit#(64) offset, ManHiBits hiBits, Bool setOffset) =
  actionvalue
    LExp exp = zeroExtend(cleanExp(cap.exp));
    CapFat ret = cap;
    
    // Select the bits of the offset corrosponding to top and bottom (and toBound).
    Mantis offBits  = truncate(offset >> exp);
    // Offset is positive if the sign is positive, or if we will shift a 0 in at the top.
    Bool offsetPositive = offset[31]==1'b0;
    
    // First check whether the attempted offset is "in Range", that is, limited
    // to the bits corrosponding to top and bot, that is, there is no ambiguity
    // when adding the selected bits of the offset to the selected bits of the pointer.
    // This is by checking two things.  That the absolute value of the offset is
    // less than the size of the representable space, and that we have not "gone negative"
    // for the unsigned pointer.
    //
    // Check whether the absolute offset is greater than the "alignment size",
    // that is, bigger than the maximum offset allowed before wrapping around.
    // This is done by ensuring that all the bits above those represented by the
    // mantissas are uniform, that is, all ones or all zeroes, that is (again),
    // there are no significant bits above the mantissa bits of the offset.
    // This is done by comparing the top bits of the offset with itself rotated
    // by one bit.  If these are the same, all the bits are the same.
    Bit#(56) offsetTop = signExtend(offset[31:8]);
    offsetTop = (offsetTop>>exp); // arithmetic shift right.  Why no ">>>" in Bluespec?
    Bool significantBitsInOffsetTop = (offsetTop[23:0] != {offsetTop[0],offsetTop[23:1]});
    Bool n32TopGood = (setOffset)? (offset[63:32] == {offset[32], offset[63:33]}) : (offset[63:31] == {offset[31], offset[63:32]});
    Bool inRange = !significantBitsInOffsetTop && n32TopGood;
    
    Mantis repBound = hiBits.repBound;
    
    // Calculate the "toBound" bits. This will be both the distance to the
    // representable top (when interpreted as a positive number) and the
    // distance to the bottom (when appended with a "1" and interpreted
    // as a negative number.  A convenience of the two's complement representation.
    Mantis toBound   = (setOffset) ? (8'hE0    ):(repBound - cap.ptr);
    Mantis toBoundM1 = (setOffset) ? (8'hE0 - 1):(repBound - cap.ptr - 1);
    
    Bool offBitsLess = (offBits < toBound);
    Bool inLimits = (offsetPositive) ? offBitsLess:!offBitsLess;
    // If we're going up and we will reach the last potentially valid spot, we don't know if the lower bits will take us over.
    if (offsetPositive  && offBits == toBoundM1) inLimits = False;
    // If we're going down and we are in the bottom spot, even if it looks like we are in-bounds, any 
    if (!offsetPositive && cap.ptr == hiBits.repBound)   inLimits = False;
    
    Bool representableRegionBiggerThanAddressSpace = (exp >= 24);
    
    Bool outOfBounds = (!inRange || !inLimits) && !representableRegionBiggerThanAddressSpace;
      
    debug2("cap", $display("significantBitsInOffsetTop: %x, inRange: %x, offBitsLess: %x, offsetPositive: %x, inLimits: %x",
                    significantBitsInOffsetTop, inRange, offBitsLess, offsetPositive, inLimits
    ));
    debug2("cap", $display("offsetTop: %x, offBits: %x, toBound: %x",
                    offsetTop, offBits, toBound
    ));
    
    // This case statement decides the new value of pointer.
    // The new pointer is trivial in the incOffset case, as it
    // is passed in and was just an add.
    // The setOffset case is much more involved, but we know that
    // the new offset is in representable bounds.
    if (setOffset) begin
      // Get the base and add the offset.  This could be slow, but seems to pass timing.
      ret.pointer = zeroExtend((getBotFat(cap,hiBits) + truncate(offset))[31:0]);
      // Calculate the new mantissa bits of the pointer independant of the 64-bit pointer itself
      // This is possible because the lower bits of base are known to be zero.
      LMantis newPtrBits = zeroExtend(cap.bot) + zeroExtend(offBits);
      ret.ptr = (exp==25) ? {1'b0,truncate(newPtrBits)}:truncate(newPtrBits);
    end else begin
      // Trim the pointer to 64 bits and assign to return address.
      ret.pointer = zeroExtend(pointer[31:0]);
      // Update trimmed pointer.
      ret.ptr = truncate(ret.pointer>>exp);
    end
    
    // Nullify cap resets the top, bottom, and exp to max privilege
    // and clears the tag, not touching the pointer.
    if (outOfBounds) ret = nullifyCap(ret);
        
    debug2("cap", $display("CapIn   for updatePointer: ", fshow(cap)));
    debug2("cap", $display("CapDone for updatePointer: ", fshow(ret)));
    
    return ret;
  endactionvalue;

function CType getType(Capability cap);
  CType ret = (case (cap.bounds) matches
                tagged Unsealed  .u: return 0;
                tagged Sealed    .s: return unpack({s.oTypeHi,s.oTypeLo});
              endcase);
  return ret;
endfunction

// Check that the pointer of a capability is currently within the bounds
// of the capability.
function Bool capInBounds(CapFat cap, ManHiBits hb, Bool inclusive);
  Bool ptrVStop = (inclusive) ? (cap.ptr<=cap.top):(cap.ptr<cap.top);
  // Top is ok if the pointer and top are in the same alignment region
  // and the pointer is less than the top.  If they are not in the same
  // alignment region, it's ok if the top is in Hi and the bottom in Low.
  Bool topOk = (hb.topHi == hb.ptrHi) ? (ptrVStop)          :hb.topHi;
  Bool botOk = (hb.botHi == hb.ptrHi) ? (cap.ptr >= cap.bot):hb.ptrHi;
  
  return topOk && botOk;
endfunction

/* Hongyan, this function doesn't seem to be used anywhere.
function Bool boundsCheck(CapFat cap, Bit#(64) off, ManHiBits hb);
  Address addr = truncate(cap.pointer) + off;
  return (addr >= truncate(getBotFat(cap, hb)) && addr < truncate(getTopFat(cap, hb)));
endfunction
 */


function ActionValue#(CapFat) setBounds(CapFat cap, N32Address length, Bool exact) =
  actionvalue
    CapFat ret = cap;
    // Create a version of length to count the leading zeros on.
    // Inflate (the bottom bits) by 1/64th to make sure we have a buffer
    // in the representable region.
    LN32Address buffLength = zeroExtend(length) + zeroExtend(length>>2);
    UInt#(5) zeros = countZerosMSB(buffLength[33:8]);
    // 44 allows us to express the top of the address space.
    Exp newExp = pack(26-zeros);
    // Round exponent up.
    // if ((newExp & ~expMask) != 0) newExp = (newExp + (~expMask));
    newExp = cleanExp(newExp);
    debug2("cap", $display("length: %x, zeros: %x, newExp: %x", length, zeros, newExp));
    // ----------------------------------------------------
    LN32Address point = cleanLAddr(cap.pointer);
    ret.exp = newExp;
    Bit#(64) deepBot = {point[31:0],0};
    deepBot = deepBot >> newExp;
    ret.bot = truncate(deepBot[63:32]);
    if (exact && deepBot[31:0] != 0) ret.isCapability = False;
    Bit#(64) deepTop = {truncate(cap.pointer) + length[31:0],0};
    deepTop = deepTop >> newExp;
    ret.top = truncate(deepTop[63:32]);
    
    // Round up if the lower bits are non-zero.
    if (deepTop[31:0] != 0) begin
      ret.top = ret.top + 1;
      if (exact) ret.isCapability = False;
    end
    ret.ptr = truncate(point>>newExp);
    return ret;
  endactionvalue;
  
function ActionValue#(CapFat) seal(CapFat cap, ManHiBits hb, CType otype) =
  actionvalue
    CapFat ret = cap;
    ret.sealed = True;
    ret.otype = otype;
    /*
    // This version supports very small sealed capabilities, but much more efficient
    // to only support > 1024 byte sized capabilities.
    UInt#(5) upperBotBuff = countZerosMSB(cap.bot^cap.ptr);
    UInt#(5) upperTopBuff = countZerosMSB(cap.top^cap.ptr);
    UInt#(5) upperMinBuff = min(upperBotBuff, upperTopBuff);
    UInt#(5) lowerBotBuff = countZerosLSB(cap.bot);
    UInt#(5) lowerTopBuff = countZerosLSB(cap.top);
    UInt#(5) lowerMinBuff = min(lowerBotBuff, lowerTopBuff);
    Bool splitRegion = (cap.top < cap.bot);
    debug2("cap", $display("upperBotBuff: %d, upperTopBuff: %d, upperMinBuff: %d, lowerBotBuff: %d, lowerTopBuff: %d, lowerMinBuff: %d", 
                    upperBotBuff, upperTopBuff, upperMinBuff, lowerBotBuff, lowerTopBuff, lowerMinBuff));
    // Saturate at 10 to avoid rollover of the exponent.
    lowerMinBuff = min(lowerMinBuff, 10);
    debug2("cap", $display("lowerMinBuff saturated: %x", lowerMinBuff));
    // Make sure the exp adjustment respects exp alignment.
    lowerMinBuff = unpack(pack(lowerMinBuff) & truncate(expMask));
    debug2("cap", $display("lowerMinBuff corrected: %x", lowerMinBuff));
    // Optimistically update the fields of the output.
    // Clear the tag in a bit if shortening is not valid.
    ret.exp = cap.exp + zeroExtend(pack(lowerMinBuff));
    ret.ptr = truncate(cap.pointer >> ret.exp);
    Bit#(10) newBot = truncate(ret.bot>>lowerMinBuff);
    Bit#(10) newTop = truncate(ret.top>>lowerMinBuff);
    ret.bot = {ret.ptr[19:10],newBot};
    ret.top = {ret.ptr[19:10] + ((splitRegion)?1:0),newTop};
    // If this is a split region, the compression will only be valid
    // if we are selecting the top 10 bits and the pointer is in the bottom region.
    if (splitRegion && lowerMinBuff<10 && !hb.ptrHi) ret.isCapability = False;
    // Otherwise we produce a valid capability as long as the segment 
    // of differeing bits was less than 10.
    if (lowerMinBuff + upperMinBuff < 10) ret.isCapability = False;
    */
    // This version only supports > 1024 byte sized capabilities.
    if (cap.bot[5:0] != 0 || cap.top[5:0] != 0) ret.isCapability = False;
    return ret;
  endactionvalue;

function CapExpCode checkRegAccess(Perms pp, CapReg cr);
  CapExpCode ret = None;
  if (!pp.hard.acces_sys_regs && (cr==27 || cr==28 || cr==29 || cr==30 || cr==31)) 
    ret = SysRegs;
  return ret;
endfunction

function Bool priveleged(Perms pp) = pp.hard.acces_sys_regs;

function Bit#(64) getPerms(CapFat cap);
  Bit#(11) hardPerms = ({pack(cap.perms.hard)[8], 2'b00, pack(cap.perms.hard)[7:0]});
  Bit#(1) softPerms = (pack(cap.perms.soft));
  return zeroExtend({softPerms,hardPerms});
endfunction

/*
function Bool checkforAllTopZeros(Address in);
    return (in[63:32] == 32'b0);
endfunction

function Bool checkforAllTopOnes(Address in);
    return (in[63:32] == 32'hffffffff);
endfunction

function Bool checkforN32Offset(Address offset);
    return (in[63:31] == 33'h1ffffffff) && (in[63:32] == 33'h0);
endfunction
 */

interface CapCopIfc;
  method Action                           putCapInst(CapInst capInst);
  method Address                          getArchPc(Address pc, Epoch epoch); // Translate absolute virtual address to arch PC
  method ActionValue#(CoProResponse)      getCapResponse(CapReq capReq, ExecuteType opType);
  method ActionValue#(CoProResponse)      getAddress();
  method ActionValue#(CapFat)     commitWriteback(CapWritebackRequest wbReq);
endinterface
