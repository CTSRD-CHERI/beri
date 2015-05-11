/*-
 * Copyright (c) 2011 Jonathan Woodruff
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2013 Michael Roe
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
 *   Nirav Dave <ndave@csl.sri.com>
 *   Jonathan Woodruff <jonathan.woodruff@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Capability CoProcessor ISA Types
 *
 ******************************************************************************/

import FShow::*;

import MIPS :: *;
import TraceTypes :: *;

//--------------------------------------------------------------------------------------------------------
// Capability-based Types
//--------------------------------------------------------------------------------------------------------

typedef Bit#(5) CapRegName;

typedef struct {
  Bit#(16)               sw_perms;//15-30 sw defined
  Bool                access_KR2C;//14
  Bool                access_KR1C;//13
  Bool                 access_KCC;//12
  Bool                 access_KDC;//11
  Bool                access_EPCC;//10
  Bool                   reserved;//9
  Bool            permit_set_type;//8
  Bool                permit_seal;//7
  Bool permit_store_ephemeral_cap;//6
  Bool           permit_store_cap;//5
  Bool            permit_load_cap;//4
  Bool               permit_store;//3
  Bool                permit_load;//2
  Bool             permit_execute;//1
  Bool              non_ephemeral;//0
} Perms deriving(Bits, Eq); // 15 bits

Perms defPerms = Perms{
  sw_perms:               16'hffff,
  access_KR2C:                True,//14
  access_KR1C:                True,//13
  access_KCC:                 True,//12
  access_KDC:                 True,//11
  access_EPCC:                True,//10
  reserved:                   True,//9
  permit_set_type:            True,//8
  permit_seal:                True,//7
  permit_store_ephemeral_cap: True,//6
  permit_store_cap:           True,//5
  permit_load_cap:            True,//4
  permit_store:               True,//3
  permit_load:                True,//2
  permit_execute:             True,//1
  non_ephemeral:              True //0
};

typedef Bit#(24) CType;

// Capability type. Note that although whereas offset as used in the
// ISA is relative to base we use an absolute address (cursor) to
// avoid an extra operand on address calculations 
// i.e. cursor = base + offset

typedef struct {
  Bit#(8)   reserved;  // padding
  CType     otype;
  Perms     perms;
  Bool      sealed;
  Address   cursor;
  Address   base;
  Value     length;
} Capability deriving(Bits, Eq);

typedef Tuple2#(Bool, Capability) TaggedCapability;

instance FShow#(Capability);
  function Fmt fshow(Capability cap);
    return $format("%x/%x/%b/%x/%x/%x (t/p/s/o/b/l)", cap.otype, pack(cap.perms), cap.sealed, cap.cursor - cap.base, cap.base, cap.length);
  endfunction
endinstance

function Fmt show_tagged_cap(Bool tag, Capability cap);
    return $format("%b/%x/%x/%b/%x/%x/%x (T/t/p/s/o/b/l)", tag, cap.otype, pack(cap.perms), cap.sealed, cap.cursor - cap.base, cap.base, cap.length);
endfunction

instance FShow#(TaggedCapability);
  function Fmt fshow(TaggedCapability tc);
    match {.tag, .cap} = tc;
    return show_tagged_cap(tag, cap);
  endfunction
endinstance

// The omnipotent/universal cap.
Capability defaultCap = Capability{
            reserved:           0,
            otype:              0,
            sealed:         False,
            perms:       defPerms,
            cursor:      minBound,
            base:        minBound,
            length:      maxBound
  };

// The impotent/nil cap.
Capability invalidCap = Capability{
            reserved:           0,
            otype:              0,
            sealed:         False,
            perms:      unpack(0),
            cursor:      minBound,
            base:        minBound,
            length:      minBound
  };

// Canonical null pointer cap.
TaggedCapability nullTaggedCap = tuple2(
   False,
   invalidCap);

function Capability unsealCap(Capability x);
  let rv = x;
  rv.sealed = False;
  return rv;
endfunction

function Capability sealCap(Capability x);
  let rv = x;
  rv.sealed = True;
  return rv;
endfunction

`ifdef CAP
function ShortCap capToShortCap(Bool tag, Capability long);
  return ShortCap{
    isCapability: tag,
    perms: ShortPerms{
      permit_seal: long.perms.permit_seal,
      permit_store_ephemeral_cap: long.perms.permit_store_ephemeral_cap,
      permit_store_cap: long.perms.permit_store_cap,
      permit_load_cap: long.perms.permit_load_cap,
      permit_store: long.perms.permit_store,
      permit_load: long.perms.permit_load,
      permit_execute: long.perms.permit_execute,
      non_ephemeral: long.perms.non_ephemeral
    },
    sealed: long.sealed,
    otype:  long.otype[21:0],
    offset: word2short(long.cursor - long.base),
    base: word2short(long.base),
    length: word2short(pack(long.length))
  };
endfunction
`endif

//--------------------------------------------------------------------------------------------------------
// Capability Exceptions
//--------------------------------------------------------------------------------------------------------

typedef enum {
  ExC_None                    = 8'h00,
  ExC_LengthViolation         = 8'h01,
  ExC_TagViolation            = 8'h02,
  ExC_SealViolation           = 8'h03,
  ExC_TypeViolation           = 8'h04,
  ExC_CallTrap                = 8'h05,
  ExC_ReturnTrap              = 8'h06,
  ExC_TSSUnderFlow            = 8'h07,
  ExC_UserDefViolation        = 8'h08,
  ExC_TLBNoStoreCap           = 8'h09,
  ExC_NonEphermalViolation    = 8'h10,
  ExC_PermitExecuteViolation  = 8'h11,
  ExC_PermitLoadViolation     = 8'h12,
  ExC_PermitStoreViolation    = 8'h13,
  ExC_PermitLoadCapViolation  = 8'h14,
  ExC_PermitStoreCapViolation = 8'h15,
  ExC_PermitStoreEphemeralCapViolation = 8'h16,
  ExC_PermitSealViolation     = 8'h17,
  ExC_PermitSetTypeViolation  = 8'h18,
  ExC_AccessEPCCViolation     = 8'h1a,
  ExC_AccessKDCViolation      = 8'h1b,
  ExC_AccessKCCViolation      = 8'h1c,
  ExC_AccessKR1CViolation     = 8'h1d,
  ExC_AccessKR2CViolation     = 8'h1e,
  ExC_FirstCustom             = 8'h1f, // the lowest exception number not yet allocated
  ExC_FAKELEGTOMAKECORRECTSIZE = 8'hFF
} CapException deriving(Bits, Eq, FShow);

instance Ord#(CapException);
  function compare(x,y) = compare(pack(x), pack(y));
endinstance

// These two functions are not in fact used, although they look useful.
//function Bit#(4) capExceptionPriority(CapException c); // lower is higher priority
//  case (c)
//    ExC_AccessEPCCViolation    : return 1;
//    ExC_AccessKDCViolation     : return 1;
//    ExC_AccessKCCViolation     : return 1;
//    ExC_AccessKR1CViolation    : return 1;
//    ExC_AccessKR2CViolation    : return 1;
//    ExC_TagViolation           : return 2;
//    ExC_SealViolation          : return 3;
//    ExC_TypeViolation          : return 4;
//    ExC_PermitSealViolation    : return 5;
//    ExC_PermitSetTypeViolation : return 6;
//    ExC_PermitExecuteViolation : return 7;
//    ExC_PermitLoadViolation    : return 8;
//    ExC_PermitStoreViolation   : return 8;
//    ExC_PermitLoadCapViolation : return 9;
//    ExC_PermitStoreCapViolation: return 9;
//    ExC_PermitStoreEphemeralCapViolation: return 10;
//    ExC_NonEphermalViolation   : return 11;
//    ExC_LengthViolation        : return 12;
//    ExC_CallTrap               : return 13;
//    ExC_ReturnTrap             : return 13;
//    ExC_None                   : return 14;
//    default                   : return 15; // None
//  endcase
//endfunction
//
//function CapException joinCapException(CapException c1, CapException c2); // c1 over c2
//  return (capExceptionPriority(c1) < capExceptionPriority(c2)) ? c1 : c2;
//endfunction
//
//function CapCause mergeCapCause(CapCause c1, CapCause c2);
//  return ((c1.capex < c2.capex) ? c2 : c1);
//endfunction

typedef enum {
  CCP_MFC       = 5'h00, // Move From Capability Register Field
  CCP_None      = 5'h01, // used to be CSealCode
  CCP_Seal      = 5'h02,
  CCP_Unseal    = 5'h03,
  CCP_MTC       = 5'h04, // Move to Capability Register Field
  CCP_CCall     = 5'h05,  // Protected Procedure Call to cross a protection boundry.
  CCP_CReturn   = 5'h06,  // Return to previous protection domain.
  CCP_JALR      = 5'h07,
  CCP_JR        = 5'h08,
  CCP_BTU       = 5'h09,  // Branch tag unset
  CCP_BTS       = 5'h0a,  // Branch tag set
  CCP_CHECK     = 5'h0b,
  CCP_CToPtr    = 5'h0c,
  CCP_Cursors   = 5'h0d,
  CCP_Compare   = 5'h0e,
  CCP_None[15:31] // allows use of default clause to catch undefined codes
} Cp2SubOpCode deriving (Eq, Bits);

typedef enum {
   CCP_MFC_GetPerms    = 3'd0,
   CCP_MFC_GetType     = 3'd1,
   CCP_MFC_GetBase     = 3'd2,
   CCP_MFC_GetLength   = 3'd3,
   CCP_MFC_GetCause    = 3'd4,
   CCP_MFC_GetTag      = 3'd5,
   CCP_MFC_GetSealed   = 3'd6,
   CCP_MFC_GetPCC      = 3'd7
} CCP_MFC_Op deriving (Eq, Bits);

typedef enum {
   CCP_MTC_AndPerms    = 3'd0,
   CCP_MTC_SetType     = 3'd1,
   CCP_MTC_IncBase     = 3'd2,
   CCP_MTC_SetLength   = 3'd3,
   CCP_MTC_SetCause    = 3'd4,
   CCP_MTC_ClearTag    = 3'd5,
   CCP_MTC_DumpRegs    = 3'd6,
   CCP_MTC_FromPtr     = 3'd7
} CCP_MTC_Op deriving (Eq, Bits);

typedef enum {
   CCP_CHECK_Perms     = 3'h0,
   CCP_CHECK_Type      = 3'h1,
   CCP_CHECK_None[2:7]  // allows use of default clause to catch undefined codes
} CCP_CHECK_Op deriving (Eq, Bits);

typedef enum {
  CCP_CUROSRS_IncOffset = 3'h0,
  CCP_CUROSRS_SetOffset = 3'h1,
  CCP_CUROSRS_GetOffset = 3'h2,
  CCP_CUROSRS_IncBase2  = 3'h3,
  CCP_CUROSRS_None[4:7]  // allows use of default clause to catch undefined codes
} CCP_Cursors_Op deriving (Eq, Bits);

typedef enum {
  CCP_COMPARE_EQ      = 3'h0,
  CCP_COMPARE_NE      = 3'h1,
  CCP_COMPARE_LT      = 3'h2,
  CCP_COMPARE_LE      = 3'h3,
  CCP_COMPARE_LTU     = 3'h4,
  CCP_COMPARE_LEU     = 3'h5,
  CCP_COMPARE_None[6:7]  // allows use of default clause to catch undefined codes
} CCP_Compare_Op deriving (Eq, Bits);

//=============================================================================
// Bounds Checking Analysis
//=============================================================================
/*
function ActionValue#(Tuple2#(Address, Bool))
                    convOffset(AccessSize sz, Address off, Capability c);
  actionvalue
    let len = extend(lenSZ(sz));
    // Assumes off sign extended
    Bool lowerValid = off < c.length;
    Bool upperValid = off + len <= c.length;
    Address addr    = c.base + off;
    return tuple2(addr, lowerValid && upperValid);
  endactionvalue
endfunction
*/

/*
// Alternative version:
function ActionValue#(Tuple2#(Address, Bool))
                    convOffset(AccessSize sz, Address off, Capability c);
  actionvalue
    let len = extend(lenSZ(sz));
    // Assumes off sign extended XXX rmn30: is it trusted? potential vulnerability?
    Bool lowerValid = off < c.length;
    //Bool upperValid = off + len <= c.length;

     let minusOffMinusLen = (
	case (sz)
	   SZ_1Byte: ~off;
	   SZ_2Byte: ((~off & (~1)) | (off & 1));
	   SZ_4Byte: ((~off & (~3)) | (off & 3));
	   SZ_8Byte: ((~off & (~7)) | (off & 7));
	   SZ_32Byte: ((~off & (~31)) | (off & 31));
	   default: ((~off & (~31)) | (off & 31));
	endcase
			);
     Bool upperValid = (c.length + minusOffMinusLen >= 0);

    Address addr    = c.offset + off;
    return tuple2(addr, lowerValid && upperValid);
  endactionvalue
endfunction
*/

// cursors version
function ActionValue#(Tuple2#(Address, Bool))
                    convOffset(AccessSize sz, Address off, Capability c);
  actionvalue
    // Assumes off sign extended
    // Potentially split this over two stages or apply the above optmisation.
    Address addr    = c.cursor + off;
    Bool baseValid  = addr >= c.base;
    Bool upperValid = addr + zeroExtend(lenSZ(sz)) <= c.base + c.length;
    return tuple2(addr, baseValid && upperValid);
  endactionvalue
endfunction

//=============================================================================
// Exception
//=============================================================================

typedef struct { // 16
  Bit#(8)                   capex; // Not CapException because of CSetCause custom values
  Bit#(8)              capregname; // Not CapRegName because 0xff used to indicate invalid
} CapCause deriving (Bits, Eq);

instance FShow#(CapCause);
  function Fmt fshow(CapCause cap);
    CapException ex = unpack(cap.capex);
    return $format("CapCause{ ex: 0x%x (", cap.capex, (cap.capex < pack(ExC_FirstCustom)) ? fshow(ex) :  fshow("custom"), "), reg: 0x%x }", cap.capregname);
  endfunction
endinstance

CapCause defaultCapCause = CapCause{capex: pack(ExC_None), capregname: 0};

function CapCause capException(CapException capex, Maybe#(CapRegName) mcrn);
  let crn = case (mcrn) matches
              tagged Valid .c: return zeroExtend(pack(c));
              tagged Invalid:  return 8'hff;
            endcase;
  return CapCause{capex: zeroExtend(pack(capex)), capregname: crn};
endfunction

function Maybe#(CapCause) invalidCapAccess(Capability pcc, Maybe#(CapRegName) mn);
  return ((!pcc.perms.access_EPCC && mn == tagged Valid 31) ? Valid (capException(ExC_AccessEPCCViolation, mn)):
          (!pcc.perms.access_KDC  && mn == tagged Valid 30) ? Valid (capException(ExC_AccessKDCViolation,  mn)):
          (!pcc.perms.access_KCC  && mn == tagged Valid 29) ? Valid (capException(ExC_AccessKCCViolation,  mn)):
          (!pcc.perms.access_KR2C && mn == tagged Valid 28) ? Valid (capException(ExC_AccessKR2CViolation, mn)):
	  (!pcc.perms.access_KR1C && mn == tagged Valid 27) ? Valid (capException(ExC_AccessKR1CViolation, mn)):
	  Invalid);
endfunction

function Maybe#(CapCause) tagViolation(Bool valid, Maybe#(CapRegName) mn);
  return !valid &&& mn matches tagged Valid .c ?
             Valid (capException(ExC_TagViolation, mn)):
             Invalid;
endfunction

function Maybe#(CapCause) sealViolation(Capability cap, Maybe#(CapRegName) mn);
  return cap.sealed &&& mn matches tagged Valid .c ?
             Valid (capException(ExC_SealViolation, mn)):
             Invalid;
endfunction
