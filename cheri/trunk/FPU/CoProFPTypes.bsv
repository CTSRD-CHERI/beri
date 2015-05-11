/*-
 * Copyright (c) 2013 Ben Thorner
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Ben Thorner as part of his summer internship
 * and Colin Rothwell as part of his final year undergraduate project.
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
package CoProFPTypes;

import MIPS::*;

import Vector::*;
import GetPut::*;
import FloatingPoint::*;
import ClientServer::*;

/*** Floating Point Implementation register ***/
typedef struct {
	Bool f64;
	Bool l;
	Bool w;
	Bool threeD;
	Bool ps;
	Bool d;
	Bool s;
	Bit#(8) pid;
	Bit#(8) rev;
} FIR deriving (Eq);

instance Bits#(FIR,64);
	function Bit#(64) pack(FIR fir);
		Bit#(64) result = 64'b0;
		result[22] = pack(fir.f64);
		result[21] = pack(fir.l);
		result[20] = pack(fir.w);
		result[19] = pack(fir.threeD);
		result[18] = pack(fir.ps);
		result[17] = pack(fir.d);
		result[16] = pack(fir.s);
		result[15:8] = fir.pid;
		result[7:0] = fir.rev;
		return result;
	endfunction
	
	function FIR unpack(Bit#(64) bits);
		FIR result = unpack(0);
		result.f64 = unpack(bits[22]);
		result.l = unpack(bits[21]);
		result.w = unpack(bits[20]);
		result.threeD = unpack(bits[19]);
		result.ps = unpack(bits[18]);
		result.d = unpack(bits[17]);
		result.s = unpack(bits[16]);
		result.pid = bits[15:8];
		result.rev = bits[7:0];
		return result;
	endfunction
endinstance

/*** Floating Point Control and Status register ***/
typedef enum {
    RoundNearest,
    RoundZero,
    RoundPlusInf,
    RoundNegInf
} MIPSRoundingMode deriving (Bits,Eq,FShow);

typedef Vector#(8,Bool) FCC;

typedef struct {
	Bool unimplementedOperation;
    FloatingPoint::Exception fpException;
} Cause deriving (Bits,Eq,FShow);

//The standard FP exception has the correct form
typedef struct {
	FCC fcc;
	Bool flushToZero; // fs in MIPS docs
	Cause cause;
	FloatingPoint::Exception enables;
	FloatingPoint::Exception flags;
	MIPSRoundingMode roundingMode;
} FCSR deriving (Eq);

instance Bits#(FCSR,64);
	function Bit#(64) pack(FCSR fcsr);
		Bit#(64) result = 64'b0;
		result[31:25] = pack(fcsr.fcc)[7:1];
		result[24] = pack(fcsr.flushToZero);
		result[23] = pack(fcsr.fcc[0]);
		result[22:21] = 2'b0;
		result [17:12] = pack(fcsr.cause);
		result[11:7] = pack(fcsr.enables);
		result[6:2] = pack(fcsr.flags);
		result[1:0] = pack(fcsr.roundingMode);
		return result;
	endfunction

	function FCSR unpack(Bit#(64) bits);
		FCSR result = unpack(0);
		result.fcc = unpack({bits[31:25],bits[23]});
		result.flushToZero = unpack(bits[24]);
		result.cause = unpack(bits[17:12]);
		result.enables = unpack(bits[11:7]);
		result.flags = unpack(bits[6:2]);
		result.roundingMode = unpack(bits[1:0]);
		return result;
	endfunction
endinstance

instance FShow#(FCSR);
    function Fmt fshow(FCSR f);
        return $format(pack(f));
    endfunction
endinstance

/*** Instruction Fields ***/
typedef enum {
  S = 5'd16,
  D = 5'd17,
  W = 5'd20,
  L = 5'd21,
  PS = 5'd22
} Format deriving (Bits,Eq,FShow);

//Doesn't need to be 5 bits wide, and more descriptive names.
typedef enum {
    SINGLE,
    DOUBLE,
    PAIREDSINGLE
} AbstractFormat deriving (Bits, Eq);

typedef enum {
  // Arithmetic
  ABS		= 6'd05,
  ADD		= 6'd00,
  DIV		= 6'd03,
  MUL		= 6'd02,
  NEG		= 6'd07,
  SQRT		= 6'd04,
  SUB		= 6'd01,
  // Approximate Arithmetic
  RECIP		= 6'd21,
  RSQRT		= 6'd22,
  // Comparisons
  CF		= 6'd48,	// Always false
  CUN		= 6'd49,	// Unordered
  CEQ		= 6'd50,
  CUEQ		= 6'd51,	// Unordered or Equal
  COLT		= 6'd52,	// Ordered or Less Than
  CULT		= 6'd53,	// Unordered or Less Than
  COLE		= 6'd54,	// Ordered or Less Than or Equal
  CULE		= 6'd55,	// Unordered or Less Than or Equal
  CSF		= 6'd56,	// Always false
  CNGLE		= 6'd57,	// Not Greater Than or Less Than or Equal
  CSEQ		= 6'd58,	// Equal
  CNGL		= 6'd59,	// Not Greater or Less Than
  CLT		= 6'd60,	// Less Than
  CNGE		= 6'd61,	// Not Greater Than or Equal
  CLE		= 6'd62,	// Less Than or Equal
  CNGT		= 6'd63,	// Not Greater Than
  // Conversion using FCSR rounding mode
  CVTD		= 6'd33,
  CVTL		= 6'd37,
  CVTPS		= 6'd38,
  CVTS		= 6'd32,
  CVTPL		= 6'd40,
  CVTW		= 6'd36,
  // Conversion using Directed rounding mode
  CEILL		= 6'd10,
  CEILW		= 6'd14,
  FLOORL	= 6'd11,
  FLOORW	= 6'd15,
  ROUNDL	= 6'd08,    // Round to nearest
  ROUNDW	= 6'd12,
  TRUNCL	= 6'd09,
  TRUNCW	= 6'd13,
  // Move within coprocessor
  MOV		= 6'd06,
  MOVC		= 6'd17,	// Conditional on a specified code (in FCSR).
  MOVN		= 6'd19,	// Conditional on non-zero
  MOVZ		= 6'd18,	// Conditional on zero
  // Pairwise merging
  PLL		= 6'd44,
  PLU		= 6'd45,
  PUL		= 6'd46,
  PUU		= 6'd47  
} FPFunc deriving (Bits, Eq, FShow);

typedef enum { 
    Add, Abs, Sub, Neg, Mul, Div, Sqrt, RecipSqrt, Recip, Compare, ToDouble,
    ToFloat, ToWord, ToLong
} Operator deriving (Bits, Eq, FShow);

/*** Instruction Schema ***/
typedef struct {
	Format fmt;
	RegNum ft;
	RegNum fs;
	RegNum fd;
	FPFunc func;
} FPRType deriving (Bits,Eq);

typedef struct {
	CoProFPOp sub;	// Operation subcode field
	RegNum rt;
	RegNum fs;
} FPRIType deriving (Bits,Eq);

// Note that there is only one branch condition code (01000).
typedef struct {
	Bit#(3) cc;		// Condition code specifier (from FCSR).
	Bool nd;		// Nullify delay. If set, the branch is likely, ad the delay slot instruction is not executed.
	Bool tf;		// Tested for equality with a FP comparison result.
	Imm16 offset;	// Signed.
} FPBType deriving (Bits,Eq);

typedef struct {
	Format fmt;
	RegNum ft;
	RegNum fs;
	Bit#(3) cc;
	FPFunc func;
} FPCType deriving (Bits,Eq);

typedef struct {
	Format fmt;
	Bit#(3) cc;		// Condition code specifier (from FCSR).
	Bool tf;		// Tested for equality with a FP comparison result.
	RegNum fs;
	RegNum fd;
	FPFunc func;
} FPRMCType deriving (Bits,Eq);	

typedef enum {
    Load,
    Store
} MemoryOp deriving (Bits, Eq);

typedef enum {
    FS,
    FT
} OperandName deriving (Bits, Eq);

typedef struct {
    MemoryOp op;
    OperandName storeSource;
    RegNum storeReg;
    RegNum loadTarget;
} FPMemInstruction deriving (Bits,Eq);

/*** Control flow ***/
typedef union tagged {
	FPRType R;
	FPRIType RI;
	FPBType B;
	FPCType C;
	FPRMCType RMC;
    FPMemInstruction MEM;
    void InvalidInstruction;
    void Nop;
} CoProFPInst deriving (Bits,Eq);

typedef union tagged {
    Int#(32) MonadWord;
    Int#(64) MonadLong;
    MonadFPRequest#(Float) MonadFloat;
    MonadFPRequest#(Double) MonadDouble;
    MonadFPRequest#(PairedSingle) MonadPairedSingle;
    DiadFPRequest#(Float) DiadFloat;
    DiadFPRequest#(Double) DiadDouble;
    DiadFPRequest#(PairedSingle) DiadPairedSingle;
    ComparisonArgs Compare;
} ExecuteArgs deriving (Bits);

typedef struct {
    Operator op;
    ExecuteArgs args;
    Bool flushToZero;
} ExecuteRequest deriving (Bits);

typedef enum {
    MonadWord,
    MonadLong,
    MonadFloat,
    MonadDouble,
    MonadPairedSingle,
    DiadFloat,
    DiadDouble,
    DiadPairedSingle,
    CompareFloat,
    CompareDouble,
    ComparePairedSingle
} ExecuteArgType deriving (Bits);

typedef union tagged {
    MIPSReg Value;
    Tuple2#(ExecuteArgType, Bit#(32)) ValueLow;
    Tuple2#(ExecuteArgType, Bit#(32)) ValueHigh;
    ExecuteArgType Execute;
} ExecuteSource deriving (Bits);

typedef struct {
    Operator op;
    ExecuteArgType argType;
    ExecuteSource source;
    Bool flushToZero;
} ExecuteToken deriving (Bits);

typedef enum {
    None = 0,
    RespondToGet, // Return a response to main pipeline in getCoProResponse
    ExecuteFromMain, // Get data from main pipeline in getCoProResponse
    WritebackFromMain, // Get data from main pipeline in commitWriteback
    ControlFromMain, // Get control register value from main
    ExecuteMOVZ, 
    ExecuteMOVN,
    GetFromExecuteUnit, // Writeback data from execute unit
    GetExecuteCompare, // Same, for S or D comparison
    GetExecuteComparePS, // Same for PS comparison
    SimpleWriteback, // Writeback a value calculated in decode
    InvalidInstruction
} ResultAction deriving (Bits, Eq, FShow); 

typedef struct {
	FCSR fcsr;
    ResultAction resultAction;
    RegNum targetReg;
    MIPSReg result;
    MIPSReg otherOp;
} CoProFPToken deriving (Bits,Eq,FShow);

typedef struct {
    Bool commit;
    CoProFPToken token;
} WritebackToken deriving (Bits, Eq);

/*** Evaluation ***/
typedef struct {
    MIPSReg result;
    Cause exceptions;
} CoProFPResult deriving (Bits,Eq,FShow);

typedef struct {
    Bit#(2) result;
    Cause exceptions;
} CoProFPCompareResult deriving (Bits, Eq);

interface CoProFPALUOpCompare;
    method Action load(MIPSReg fs, MIPSReg ft, Format fmt, MIPSRoundingMode rm, Bit#(4) cond);
    method Bit#(2) result();
    method Cause excs();
endinterface

typedef struct {
    Format fmt;
    MIPSReg left;
    MIPSReg right;
    Bit#(4) cond;
} ComparisonArgs deriving (Bits);

interface VerilogMonadicFloatMegafunction;
    method Action place(Bit#(32) data);
    method Bit#(32) result;
endinterface

interface VerilogDiadicFloatMegafunction;
    method Action place(Bit#(32) dataa, Bit#(32) datab);
    method Bit#(32) result;
endinterface

interface VerilogMonadicDoubleMegafunction;
    method Action place(Bit#(64) data);
    method Bit#(64) result;
endinterface

interface VerilogDiadicDoubleMegafunction;
    method Action place(Bit#(64) dataa, Bit#(64) datab);
    method Bit#(64) result;
endinterface

interface Megafunction#(type req, type res);
    method Action place(req data);
    method Tuple2#(res, FloatingPoint::Exception) result;
endinterface

typedef Tuple2#(Float, Float) PairedSingle;

typedef Server#(ComparisonArgs, MIPSReg) ComparisonServer;

typedef Tuple2#(f, RoundMode) MonadFPRequest#(type f);
typedef Tuple3#(f, f, RoundMode) DiadFPRequest#(type f);

typedef Megafunction#(MonadFPRequest#(Float), Float) MonadicFloatMegafunction;
typedef Megafunction#(DiadFPRequest#(Float), Float) DiadicFloatMegafunction;
typedef Megafunction#(MonadFPRequest#(Double), Double) MonadicDoubleMegafunction;
typedef Megafunction#(DiadFPRequest#(Double), Double) DiadicDoubleMegafunction;

typedef Server#(req, Tuple2#(f, FloatingPoint::Exception))
    FloatingPointServer#(type req, type f);
typedef FloatingPointServer#(MonadFPRequest#(Float), Float) MonadicFloatServer;
typedef FloatingPointServer#(DiadFPRequest#(Float), Float) DiadicFloatServer;
typedef FloatingPointServer#(MonadFPRequest#(Double), Double)
    MonadicDoubleServer;
typedef FloatingPointServer#(DiadFPRequest#(Double), Double) DiadicDoubleServer;
typedef FloatingPointServer#(MonadFPRequest#(PairedSingle), PairedSingle)
    MonadicPairedSingleServer;
typedef FloatingPointServer#(DiadFPRequest#(PairedSingle), PairedSingle)
    DiadicPairedSingleServer;

interface CombinedDiadicServers;
    interface DiadicFloatServer float;
    interface DiadicPairedSingleServer pairedSingle;
endinterface

interface TwoPrecisionDiadicServers;
    interface DiadicFloatServer float;
    interface DiadicDoubleServer double;
endinterface

interface MultipleFormatMonadicServer;
    interface MonadicFloatServer float;
    interface MonadicDoubleServer double;
    interface MonadicPairedSingleServer pairedSingle;
endinterface

interface MultipleFormatDiadicServers;
    interface DiadicFloatServer float;
    interface DiadicPairedSingleServer pairedSingle;
    interface DiadicDoubleServer double;
endinterface

// We commonly have to specify pipeline length with a numeric type.
// This interface and payload are designed to make doing this then unwrapping
// the type as painless as possible.
interface WithInt#(numeric type theInt, type payloadType);
    interface payloadType payload;
endinterface

function payloadType getPayload(WithInt#(delay, payloadType) wrapped);
    return wrapped.payload;
endfunction

endpackage
