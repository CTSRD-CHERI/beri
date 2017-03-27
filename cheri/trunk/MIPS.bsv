/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Robert N. M. Watson
 * Copyright (c) 2013 Simon W. Moore
 * Copyright (c) 2013-2017 Alexandre Joannou
 * Copyright (c) 2013, 2014 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
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

`ifdef CAP
  `define USECAP 1
`elsif CAP128
  `define USECAP 1
`elsif CAP64
  `define USECAP 1
`endif
 
import MemTypes :: *;
import ClientServer :: *;
import MasterSlave :: *;
import FIFO :: *;
import FIFOF :: *;
import Vector::*;
`ifdef STATCOUNTERS
import StatCounters::*;
import GetPut::*;
`endif

typedef Bit#(5) RegNum; // A MIPS register number
typedef Bit#(16) Imm16; // A 16 bit immediate from a MIPS instruction
typedef Bit#(64) MIPSReg; // A MIPS register, 64-bit for this processor
typedef Bit#(64) Address; // A virtual address
typedef Bit#(40) PhyAddress; // A physical address, 40 bits in standard 64-bit MIPS
typedef Bit#(64) Word; // A memory word
typedef Bit#(CheriDataWidth) Line; // A full memory bus flit.
typedef UInt#(4)  InstId; // 16 possible instruction IDs, hopefully more than can fit in the pipeline at a time to avoid duplicates
typedef UInt#(3)  Epoch; // An epoch identifier. 8 possible values avoids potential wrap around, though 4 should be enough.

typedef union tagged{
  Bit#(8)   Byte;
  Bit#(16)  HalfWord;
  Bit#(32)  Word;
  Bit#(64)  DoubleWord;
  Line      Line;
  `ifdef USECAP
    Bit#(CapWidth) CapLine;
  `endif
} SizedWord deriving(Bits, Eq, FShow);

typedef enum {RegFile, ControlToken, Debug, None, CoPro0, CoPro1, CoPro2} FetchSrc deriving(Bits, Eq, FShow);
  
// The memory operation required by an instruction may be a read, a write, a read or write of a 256-bit "capability", 
// segment descriptor, a cache operation, or none at all.
typedef enum {Read, Write, ICacheOp, DCacheOp, None} MemOp deriving(Bits, Eq, FShow);

// The branch type of an instruction may be no branch at all, a branch reletive to the current program counter,
// an unconditional jump to a 24-bit immediate offset, or an unconditional jump to a register value.  These each
// have different implications to the pipeline and branch predictor.
typedef enum {None, Branch, Jump, JumpReg} BranchType deriving(Bits, Eq, FShow);

// The size of an instructions memory access may be none (no memory access), byte, halfword, word, doubleword or line (256 bits).
// MIPS also has word and doubleword left and write memory operations which are odd.
typedef enum {
  CapWord,
  DoubleWord, 
  DoubleWordLeft,
  DoubleWordRight,
  Word,
  WordLeft,
  WordRight,
  HalfWord, 
  Byte,
  None
} MemSize deriving(Bits, Eq, FShow);

// The ControlTokenT is the structure that contains most of the state of an instruction as it passes down
// the pipeline.
typedef struct {
  InstId    id;      // Id to distinguish instructions in the pipeline.
  Epoch     epoch;   // The branch predictor epoch of this instruciton.
  // The actual instruction.  This is a tagged type so that we can refer to the instruction fields relevant to the instruction type.
  InstructionT inst;        
  Bool      branchDelay; // Is this instruction in a branch delay slot.  If so, don't update the PC
  Branch    branch;      // Jump or branch status, ie, on what condition to we jump or branch and have we done it already.
  Bool      branchLikely;  // Is it a likely branch?  (If so, flush the pipe/don't commit the branch dealy if it doesn't branch)
  BranchType branchType;   // The type of jump or branch operation that this instruction requires.
  //Bool      dupe;          // Throw away the token at the end of the pipe.
  Bool      dead;          // Throw away the result at the end of the pipe.
  Bit#(1)   carryout;     // Carry out of the arithmetic operation in execute, ie, the 65th bit of a 64 bit operation.
                          // Used for checking for overflow in comparisons.
  RegNum    dest;         // The MIPS architectural register number of the operation destination.
  Bit#(3)   coProSelect; // The shadow register to select in the coprocessor. This is used in the Capability Coprocessor, not in CP0.
  WriteBack writeDest;   // The destination register file for writeback, including "none" for no writeback.
                         // RegFile and CoPro0 are examples.
  Bool      pendingWrite; // Whether this operation will produce the result in Execute (e.g. ADD) or Writeback (e.g. Load).
  Bool      sixtyFourBitOp;  // Is this a 64-bit operation?  ie, should we sign extend the result (for some cases)?
  Bool      signedOp;  // Is this a signed operation?
  AluOp     alu;       // What function should the alu perform?  ie, add, subtract, xor...
  TestOp    test;      // What kind of test should we perform for this instruction? eg, Equal, Less than, Load Linked, Store Conditional
  Exception exception;  // What exception is this instruction going to throw? (hopefully none)
                        // This is an internal exception code rather than an architecturally visible MIPS exception code because different
                        // causes can throw the same visible exception code but with different effects, so we need more detailed
                        // cause information in the pipeline.
  Bit#(64)  opA;  // The value of operand A for this instruction
  FetchSrc  opAsrc;  // Source of operand A.
  Bit#(64)  opB;     // The value of operand B for this instruction
  FetchSrc  opBsrc;  // Source of operand B.
  SizedWord storeData; // The value of data to store for this instruction
  FetchSrc  storeDatasrc;  // Source of store data.
  MIPSReg   pc; // The program counter for this instruction
  MIPSReg   archPc;  // The architectural program counter for this instruction.
                     // The architectural PC could be different from the actual program counter if the capability coprocessor
                     // has a program counter capability that has shifted the program counter base. 
  Int#(20)  pcUpdate;  // The value which we should add or subtract from the current PC to get the new PC.
  PCSource  newPcSource; // The source of the new PC, ie, adding pcUpdate, taking the result from operand B, etc.
  Bool      writePC; // Actually update the PC when this instruction completes.  (We might not do this for branch delay slots for example.)
  MemOp     mem; // The memory operation this instruction should perform.  Read, write, etc.
  MemSize   memSize;  // The width of the memory operation this instruction should perform.  Byte, Word, etc.
  Bool      signExtendMem; // Sign extend the result of a memory load.
  Bool      link; // Writeback the PC+8 to a register.  Used for jump and link instructions to store the return address. 
  CacheOperation   cop; // The cache operation to perform and which cache to perform it on.  Usually a nop.
  Bool      observesCP0; // This instruction might be sensitive to any outstanding CP0 updates, and should stall if one is in flight.
  `ifdef USECAP
    CapOp     capOp; // Capability operation to perform (if the capabiltiy unit is included)
  `endif
  Bool      fromDebug;  // Whether this instruction is from debug or not.
  Bool      flushPipe; // Flush the pipe after this instruction.
  Bool      writeRegMask;  // Write the register file mask of non-zero registers.
  `ifdef MULTI
    Bit#(16)  coreCount;
    Bit#(16)  coreID;
    Bit#(8)   threadID;
  `endif
} ControlTokenT deriving (Bits);

// Default values for a newly constructed control token.
  ControlTokenT defaultControlToken = ControlTokenT{
      id: 1,
      epoch: ?,
      pc: 64'h0000000000000000,
      archPc: ?,
      inst: classifyMIPSInstruction(0),
      branchDelay: False,
      branch: Never,
      branchLikely: False,
      branchType: None,
      dead: False,
      carryout: 1'b0,
      dest: ?,
      coProSelect: 3'b0,
      writeDest: None,
      pendingWrite: False,
      sixtyFourBitOp: True,
      signedOp: False,
      alu: Add,
      test: Nop,
      exception: None,
      opA: 64'b0,
      opAsrc: RegFile,
      opB: 64'b0,
      opBsrc: RegFile,
      mem: None,
      memSize: DoubleWord,
      signExtendMem: True,
      storeData: ?,
      storeDatasrc: None,
      newPcSource: PCUpdate,
      pcUpdate: 4,
      writePC: True,
      cop: CacheOperation{inst: CacheNop, cache: None, indexed: True},
      observesCP0: False,
      `ifdef USECAP
        capOp: None,
      `endif
      link: False,
      fromDebug: False,
      flushPipe: False,
      writeRegMask: False
    };

// ----------------------------- Instructions -----------------------------

// This is the "tagged union" instruction type.
// This means that an instruction can be any one of these types, i.e. the instruction bits can have
// a different set of field names depending on the instruction category.  These are basic MIPS instruction
// categories.
typedef union tagged { 
  Itype Immediate;
  Jtype Jump;         
  Rtype Register;
  Ctype Coprocessor;
} InstructionT deriving (Bits, Eq, FShow);

// Immediate type instructions have an immediate operand rather than only register operands.
typedef struct {
  OpCode op; // The opcode field, which is shared with the other instruciton types.
  RegNum rs; // A source operand register number (usually).
  RegNum rt; // The destination register number (usually).
  Imm16 imm; // A 16 bit immediate value
} Itype deriving (Bits, Eq, FShow);

typedef struct {
  OpCode op; // The opcode field, which is shared with the other instruciton types.
  Bit#(26) imm; // A 26 bit immediate value used to append to the upper address bits on a jump.
} Jtype deriving (Bits, Eq, FShow);

typedef struct {
  OpCode op; // The opcode field, which is shared with the other instruciton types.
  RegNum rs; // A source operand register number (usually).
  RegNum rt; // Another source operand register number (usually).
  RegNum rd; // A destination register number (usually).
  Bit#(5) sa;  // Shift amount for immediate shift instructions, but otherwise 0 (usually).
  Func f;  // A function field, basically an extension to the opcode field.
} Rtype deriving (Bits, Eq, FShow);

typedef struct {
  OpCode     op; // The opcode field, which is shared with the other instruciton types.
  CapOpCode  cOp; // Coprocessor operation.
  RegNum     r1; // A register number, function depending on instruction.
  RegNum     r2; // Another register number
  RegNum     r3; // Another register number, though these last three fields might be an immediate value.
  Bit#(3)    spacer;
  Bit#(3)    select;
} Ctype deriving(Bits, Eq, FShow);
// -----------------------------------------------------------------------

// Potential ALU operations.  See Execute for details.
// Most of these are single cycle, but Mul, Div, MulI, Madd & Msub submit to a side pipeline.
// Also Cop1, Cap & Cop3 are implementation dependant.
typedef enum {  Add, Sub, Or, Xor, 
            And, Nor, SLT, SLTU, 
            SLL, SRA, SRL, //CLZ,
            Mul, Div, MulI, Madd, Msub,
            THi, TLo, FHi, FLo, 
            MOVZ, MOVN, Cop1, Cap, Nop
} AluOp deriving(Bits, Eq, FShow);

// Test operation, including not only arithmetic tests but also load linked and store conditional.
typedef enum { EQ, GE, LT, NE, LL, SC, Nop
} TestOp deriving(Bits, Eq, FShow);

// A type to indicate where the new PC will come from. PCUpdate for a <20 bit addition, opB for
// a register value or similiar, Immediate if this is a jump and the immediate is to be appended
// to upper bits rather than added.
typedef enum { PCUpdate, OpB, Immediate
} PCSource deriving(Bits, Eq, FShow);

// These are the defined function codes for "register immediate" type functions, which have the
// immediate format but use this function code in place of the "rt" register number since they don't have
// a destination register.
typedef enum {
  BLTZ = 5'b00000, 
  BGEZ = 5'b00001, 
  BLTZL = 5'b00010,
  BGEZL = 5'b00011,
  TEQI = 5'b01100, 
  TGEI = 5'b01000, 
  TGEIU = 5'b01001, 
  TLTI = 5'b01010, 
  TLTIU = 5'b01011, 
  TNEI = 5'b01110,
  BLTZAL = 5'b10000, 
  BGEZAL = 5'b10001,
  BLTZALL = 5'b10010,
  BGEZALL = 5'b10011
} RegImmFunc deriving(Bits, Eq, FShow);

// The target register file for an instruction writeback.  The register file is standard, CoPro0 is the system
// control processor, and HiLo are the multiply and divide result registers.
typedef enum {RegFile, CoPro0, CoPro2, HiLo, None} WriteBack deriving(Bits, Eq, FShow);
// The status of a branch operation.  If it remains to be tested, it is tagged with the appropriate condition,
// but if the branch has been evaluated already, we set to DoneTaken or DoneNotTaken as appropriate.  Also
// this can be "True" (do the branch unconditionally) or "False", this is not a branch.
typedef enum {EQ, GEZ, GTZ, LEZ, LTZ, NE, DoneTaken, DoneNotTaken, `ifdef USECAP CapTag, `endif Always, Never} Branch deriving(Bits, Eq, FShow);

// Values of the standard MIPS opcode field.  See the MIPS spec for details.
typedef enum {
  SPECIAL,
  REGIMM,
  J,
  JAL,
  BEQ,
  BNE,
  BLEZ,
  BGTZ,
  
  ADDI,
  ADDIU,
  SLTI,
  SLTIU,
  ANDI,
  ORI,
  XORI,
  LUI,
  
  COP0,
  COP1,
  COP2,
  COP3,
  BEQL,
  BNEL,
  BLEZL,
  BGTZL,
  
  DADDI,
  DADDIU,
  LDL,
  LDR,
  SPECIAL2,
  JALX,
  MDMX,
  SPECIAL3,
  
  LB,
  LH,
  LWL,
  LW,
  LBU,
  LHU,
  LWR,
  LWU,
  
  SB,
  SH,
  SWL,
  SW,
  SDL,
  SDR,
  SWR,
  CACHE,
  
  LL,
  LWC1,
  LWC2,
  PREF,
  LLD,
  LDC1,
  LDC2,
  LD,
  
  SC,
  SWC1,
  SWC2,
  NONE,
  SCD,
  SDC1,
  SDC2,
  SD
} OpCode deriving (Bits, Eq, FShow);

// Values of the function field for the SPECIAL opcode.  See MIPS spec for meaning.
typedef enum
{
  SLL,
  MOVCI,
  SRL,
  SRA,
  SLLV,
  NONE1,
  SRLV,
  SRAV,
  
  JR,
  JALR,
  MOVZ,
  MOVN,
  SYSCALL,
  BREAK,
  NONE2,
  SYNC,
  
  MFHI,
  MTHI,
  MFLO,
  MTLO,
  DSLLV,
  NONE3,
  DSRLV,
  DSRAV,
  
  MULT,
  MULTU,
  DIV,
  DIVU,
  DMULT,
  DMULTU,
  DDIV,
  DDIVU,
  
  ADD,
  ADDU,
  SUB,
  SUBU,
  AND,
  OR,
  XOR,
  NOR,
  
  NONE4,
  NONE5,
  SLT,
  SLTU,
  DADD,
  DADDU,
  DSUB,
  DSUBU,
  
  TGE,
  TGEU,
  TLT,
  TLTU,
  TEQ,
  NONE6,
  TNE,
  NONE7,
  
  DSLL,
  NONE8,
  DSRL,
  DSRA,
  DSLL32,
  NONE9,
  DSRL32,
  DSRA32
} Func deriving(Bits, Eq, FShow);

// Values of the function field for the SPECIAL2 opcode.  See MIPS spec for meaning.
typedef enum
{
  MADD,
  MADDU,
  MUL,
  NONE03,
  MSUB,
  MSUBU,
  NONE06,
  NONE07,
  
  NONE08,
  NONE09,
  NONE0A,
  NONE0B,
  NONE0C,
  NONE0D,
  NONE0E,
  NONE0F,
  
  NONE10,
  NONE11,
  NONE12,
  NONE13,
  NONE14,
  NONE15,
  NONE16,
  NONE17,
  
  NONE18,
  NONE19,
  NONE1A,
  NONE1B,
  NONE1C,
  NONE1D,
  NONE1E,
  NONE1F,
  
  NONE20,
  //CLZ,
  NONE21,
  NONE22,
  NONE23,
  NONE24,
  //DCLZ,
  NONE25,
  NONE26,
  NONE27,
  
  NONE28,
  NONE29,
  NONE2A,
  NONE2B,
  NONE2C,
  NONE2D,
  NONE2E,
  NONE2F,
  
  NONE30,
  NONE31,
  NONE32,
  NONE33,
  NONE34,
  NONE35,
  NONE36,
  NONE37,
  
  NONE38,
  NONE39,
  NONE3A,
  NONE3B,
  NONE3C,
  NONE3D,
  NONE3E,
  NONE3F
} Func2 deriving(Bits, Eq, FShow);

// Values of the function field for the SPECIAL3 opcode.  See MIPS spec for meaning.
typedef enum
{
  NONE00,
  NONE01,
  NONE02,
  NONE03,
  NONE04,
  NONE05,
  NONE06,
  NONE07,
  
  NONE08,
  NONE09,
  NONE0A,
  NONE0B,
  NONE0C,
  NONE0D,
  NONE0E,
  NONE0F,
  
  NONE10,
  NONE11,
  NONE12,
  NONE13,
  NONE14,
  NONE15,
  NONE16,
  NONE17,
  
  NONE18,
  NONE19,
  NONE1A,
  NONE1B,
  NONE1C,
  NONE1D,
  NONE1E,
  NONE1F,
  
  NONE20,
  NONE21,
  NONE22,
  NONE23,
  NONE24,
  NONE25,
  NONE26,
  NONE27,
  
  NONE28,
  NONE29,
  NONE2A,
  NONE2B,
  NONE2C,
  NONE2D,
  NONE2E,
  NONE2F,
  
  NONE30,
  NONE31,
  NONE32,
  NONE33,
  NONE34,
  NONE35,
  NONE36,
  NONE37,
  
  NONE38,
  NONE39,
  NONE3A,
  RDHWR,
  NONE3C,
  NONE3D,
  NONE3E,
  NONE3F
} Func3 deriving(Bits, Eq, FShow);

// CP0 (and potentially generic coprocessor) opcodes, found in bits 25:21 of a coprocessor instruction.
typedef enum {
  MFC  = 5'b00000,
  DMFC = 5'b00001,
  CFC  = 5'b00010,
  CTC  = 5'b00110,
  MTC  = 5'b00100,
  DMTC = 5'b00101,
  INST = 5'b10000 //This is an instruction.
} CoProOp deriving(Bits, Eq, FShow);

// CP0 instruction codes, found in bits 0-5 of a CP0 instruction with a "1" in bit 25.
typedef enum {
  RDE  = 5'b000001, // Read indexed TLB entry
  WIE  = 5'b000010, // Write indexed TLB entry
  WRE  = 5'b000110, // Write random TLB entry
  PME  = 5'b001000, // Probe matching TLB entry
  ERET = 5'b011000, // Exception return
  Big  = 5'b100000  // To ensure this datatype is 6 bits.
} CP0Inst deriving(Bits, Eq, FShow);

// Opcodes for the capability memory protection coprocessor instructions, found in bits 25:21 of a COP2 instruction.
typedef enum {
  MFC      = 5'h00,  // Move From Capability Register Field
  CSetBounds = 5'h01, // Set both the base of a capability from the offset of the source and the length from a general purpose register.
  CSeal    = 5'h02,  // Seal a capability
  CUnseal  = 5'h03,  // Create a Data Capability from a sealed Capability
  MTC      = 5'h04,  // Move to Capability Register Field
  CCall    = 5'h05,  // Protected Procedure Call to cross a protection boundry. (unimplemented so far)
  CReturn  = 5'h06,  // Return to previous protection domain.
  CJALR    = 5'h07,  // Jump and link Capability Register
  CJR      = 5'h08,  // Jump to Capability Register
  CBTU     = 5'h09,
  CBTS     = 5'h0a,
  Check    = 5'h0b,
  CRelBase = 5'h0c,
  COffset  = 5'h0d,
  CCompare = 5'h0e,
  CClear   = 5'h0f,
  CLLSC    = 5'h10,
  CBEZ     = 5'h11,
  CBNZ     = 5'h12,
  None13   = 5'h13,
  None14   = 5'h14,
  None15   = 5'h15,
  None16   = 5'h16,
  None17   = 5'h17,
  None18   = 5'h18,
  None19   = 5'h19,
  None1a   = 5'h1a,
  None1b   = 5'h1b,
  None1c   = 5'h1c,
  None1d   = 5'h1d,
  None1e   = 5'h1e,
  None1f   = 5'h1f
} CapOpCode deriving(Bits, Eq, FShow);

// Values in the select field for offset ops
typedef enum {
  CIncOffset = 3'h0,
  CSetOffset = 3'h1,
  CGetOffset = 3'h2,
  Unused     = 3'h4 // <- Make sure Bluespec derives this as a 3-bit value
} OffsetOpCode deriving(Bits, Eq, FShow);


// the CapOp type is used internally as an operation code for the capability memory protection unit.
typedef enum {
  // FetchA = r1
  BranchTagUnset, // Branch if the operand register is not a valid capability (segment descriptor)
  BranchTagSet,   // Branch if the operand register is a valid capability (segment descriptor)
  BranchEqZero,   // Branch if the operand capability is zero
  BranchNEqZero,  // Branch if the operand capability is not zero
  SC,             // Store capability 
  LC,             // Load capability
  S,              // Store (width is stored elsewhere)
  L,              // Load (width is stored elsewhere)
  Call,           // Capability protected procedure call
  CallFast,       // Capability protected procedure call in hardware
  CheckType,      // Compare the type of two capabilities, throw exception if they don't match.
  CheckPerms,     // Compare general purpose value with permissions, throw exception if asserted bits don't match.
  // FetchA = r2
  GetPerm,        // Get the permissions field of the capability operand and place in general purpose target register
  GetBase,        // Get the base field of the capability operand and place in general purpose target register
  GetLen,         // Get the length field of the capability operand and place in general purpose target register
  GetType,        // Get the type field of the capability operand and place in general purpose target register
  GetSealed,      // Get the "sealed" flag of the capability operand and place in general purpose target register
  GetTag,         // Get the valid capability flag from a capability register into a general purpose register.
  AndPerm,        // And the permissions field of a capability with a general purpose value producing a capability result.
  SetBounds,      // Set both the base of a capability from the offset of the source and the length from a general purpose register.
  SetBoundsExact, // Set both the base of a capability from the offset of the source and the length from a general purpose register, exception if not exact.
  ClearTag,       // Clear the valid capability flag on a capability register
  IncBaseNull,    // Increment base, make capability null if increment amount is 0 (for C semantics)
  IncOffset,      // Increment the offset value (no bounds checking)
  SetOffset,      // Set the offset value
  GetOffset,      // Move the offset value to an integer register
  JR,             // Jump capability register
  JALR,           // Jump and link capability register
  CmpEQ,          // Compare two capability pointers are equal
  CmpNE,          // Compare two capability pointers are not equal
  CmpLT,          // Compare one capability pointer is less than another
  CmpLE,          // Compare one capability pointer is less than or equal to another
  CmpLTU,         // Compare one capability pointer is less than another unsigned
  CmpLEU,         // Compare one capability pointer is less than or equal to another unsigned
  CmpEQX,         // Compare two capabilities are binary equals
  // FetchA = r3
  Seal,           // Seal a capability
  Unseal,         // Unseal a capability given possession of an unsealed executable one of the same type
  GetRelBase,     // Get the difference between the base of one capability and other. (to convert base to c0 reletive pointer.)
  Subtract,       // Subtract two capability addresses, put the result in a general-purpose register
  // No FetchA
  GetPCC,         // Get the current program counter capability and place in a capability register
  SetPCCOffset,   // Get PCC, set the offset, write to a general-purpose register.
  GetConfig,      // Get the capability config register into a general purpose register.
  SetConfig,      // Set the capability config register from a general purpose register.
  Return,         // Capability protected procedure return
  Clear,          // Clear a set of capability registers
  Move,           // Simply move a capability register
  ReportRegs,     // Debug register report, only valid simulation.
  JumpRegister,   // Perform a target offset reletive to PCC for a general purpose jump register operation
  ERET,           // An ERET, return the entry point 
  LegacyL,        // A legacy load
  LegacyS,        // A legacy store
  None            // Do nothing
} CapOp deriving(Bits, Eq, FShow);

// Values of the function field for 3-operand (or less) capability instructions.
typedef enum
{
  CapFuncGetPermOld,
  CapFuncGetTypeOld,
  CapFuncGetBaseOld,
  CapFuncGetLenOld,
  CapFuncGetCauseOld,
  CapFuncGetTagOld,
  CapFuncGetSealedOld,
  CapFuncGetPCCOld,
  
  CapFuncSetBounds,
  CapFuncSetBoundsExact,
  CapFuncSub,
  CapFuncSeal,
  CapFuncUnseal,
  CapFuncAndPerm,
  CapFuncSetOffset,
  CapFuncIncOffset,
  
  CapFuncCToPtr,
  CapFuncCFromPtr,
  CapFuncEQ,
  CapFuncNE,
  CapFuncLT,
  CapFuncLE,
  CapFuncLTU,
  CapFuncLEU,
  
  CapFuncEXEQ,
  NONE19,
  NONE1A,
  NONE1B,
  NONE1C,
  NONE1D,
  NONE1E,
  NONE1F,
  
  NONE20,
  NONE21,
  NONE22,
  NONE23,
  NONE24,
  NONE25,
  NONE26,
  NONE27,
  
  NONE28,
  NONE29,
  NONE2A,
  NONE2B,
  NONE2C,
  NONE2D,
  NONE2E,
  NONE2F,
  
  NONE30,
  NONE31,
  NONE32,
  NONE33,
  NONE34,
  NONE35,
  NONE36,
  NONE37,
  
  NONE38,
  NONE39,
  NONE3A,
  NONE3B,
  NONE3C,
  NONE3D,
  NONE3E,
  CapFuncTwoOp
} CapFuncThreeOpCode deriving(Bits, Eq, FShow);

// Values of the function field for 2-operand capability instructions.
typedef enum
{
  CapFuncGetPerm,
  CapFuncGetType,
  CapFuncGetBase,
  CapFuncGetLen,
  CapFuncGetTag,
  CapFuncGetSealed,
  CapFuncGetOffset,
  CapFuncGetPCCSetOffset,
  
  CapFuncCheckPerm,
  CapFuncCheckType,
  CapFuncMove,
  CapFuncClearTag,
  NONE0C,
  NONE0D,
  NONE0E,
  NONE0F,
  
  NONE10,
  NONE11,
  NONE12,
  NONE13,
  NONE14,
  NONE15,
  NONE16,
  NONE17,
  
  NONE18,
  NONE19,
  NONE1A,
  NONE1B,
  NONE1C,
  NONE1D,
  NONE1E,
  CapFuncOneOp
} CapFuncTwoOpCode deriving(Bits, Eq, FShow);

// Values of the function field for 1-operand capability instructions.
typedef enum
{
  CapFuncGetPCC,
  CapFuncGetCause,
  CapFuncSetCause,
  CapFuncCJR,
  NONE04,
  NONE05,
  NONE06,
  NONE07,
  
  NONE08,
  NONE09,
  NONE0A,
  NONE0B,
  NONE0C,
  NONE0D,
  NONE0E,
  NONE0F,
  
  NONE10,
  NONE11,
  NONE12,
  NONE13,
  NONE14,
  NONE15,
  NONE16,
  NONE17,
  
  NONE18,
  NONE19,
  NONE1A,
  NONE1B,
  NONE1C,
  NONE1D,
  NONE1E,
  NONE1F
} CapFuncOneOpCode deriving(Bits, Eq, FShow);



// Exception codes for the capability unit.
// The capability memory protection unit has its own exception codes in its "config" register which
// give detailed cause information when a CP2 exception fires.
typedef enum {
  None     = 8'h00, // No exeption
  Len      = 8'h01, // Length violation
  Tag      = 8'h02, // Use of a value as a capability (segment descriptor) when it was its valid capability flag was not set
  Seal     = 8'h03, // Use of a sealed capability in an unpermitted way
  Type     = 8'h04, // Attempted use of capabilities which was not permitted because of non-matching types
  Call     = 8'h05, // Use of a Call instruction (if hardware implementation is not present)
  Return   = 8'h06, // Use of a Return instruction (if hardware implementation is not present)
  None08   = 8'h07, 
  CkPerms  = 8'h08,  
  Ctlbs    = 8'h09, // Attempt to store a capability in a page that does not allow capabilities to be stored.
  Inxact   = 8'h0a, // A capability maniuplation was not able to exactly represent its result
  None0b   = 8'h0b,
  None0c   = 8'h0c,
  None0d   = 8'h0d,
  None0e   = 8'h0e,
  None0f   = 8'h0f,
  // The below error codes are offset from the previous ones because the match the permissions bit field of a capability 1-to-1.
  Ephem    = 8'h10, // Violation of ephemeral permission of a capability
  Exe      = 8'h11, // Violation of executable permission of a capability
  Load     = 8'h12, // Violation of load permission of a capability
  Store    = 8'h13, // Violation of store permission of a capability
  LoadCap  = 8'h14, // Violation of load capability permission of a capability
  StoreCap = 8'h15, // Violation of store capability permission of a capability
  StoreEph = 8'h16, // Violation of store ephemeral capabilty permission of a capability
  PerSeal  = 8'h17, // Violation of the permit seal permission of a capability
  SysRegs  = 8'h18, // Violation of the set type permission of a capability
  None19   = 8'h19,
  None1a   = 8'h1a, // Violation of the "Access CR31" permission on the capability in PCC
  None1b   = 8'h1b, // Violation of the "Access CR30" permission on the capability in PCC
  None1c   = 8'h1c, // Violation of the "Access CR29" permission on the capability in PCC
  None1d   = 8'h1d, // Violation of the "Access CR27" permission on the capability in PCC
  None1e   = 8'h1e, // Violation of the "Access CR28" permission on the capability in PCC
  None1f   = 8'h1f,
  N20=8'h20,N21=8'h21,N22=8'h22,N23=8'h23,N24=8'h24,N25=8'h25,N26=8'h26,N27=8'h27,
  N28=8'h28,N29=8'h29,N2a=8'h2a,N2b=8'h2b,N2c=8'h2c,N2d=8'h2d,N2e=8'h2e,N2f=8'h2f,
  N30=8'h30,N31=8'h31,N32=8'h32,N33=8'h33,N34=8'h34,N35=8'h35,N36=8'h36,N37=8'h37,
  N38=8'h38,N39=8'h39,N3a=8'h3a,N3b=8'h3b,N3c=8'h3c,N3d=8'h3d,N3e=8'h3e,N3f=8'h3f,
  N40=8'h40,N41=8'h41,N42=8'h42,N43=8'h43,N44=8'h44,N45=8'h45,N46=8'h46,N47=8'h47,
  N48=8'h48,N49=8'h49,N4a=8'h4a,N4b=8'h4b,N4c=8'h4c,N4d=8'h4d,N4e=8'h4e,N4f=8'h4f,
  N50=8'h50,N51=8'h51,N52=8'h52,N53=8'h53,N54=8'h54,N55=8'h55,N56=8'h56,N57=8'h57,
  N58=8'h58,N59=8'h59,N5a=8'h5a,N5b=8'h5b,N5c=8'h5c,N5d=8'h5d,N5e=8'h5e,N5f=8'h5f,
  N60=8'h60,N61=8'h61,N62=8'h62,N63=8'h63,N64=8'h64,N65=8'h65,N66=8'h66,N67=8'h67,
  N68=8'h68,N69=8'h69,N6a=8'h6a,N6b=8'h6b,N6c=8'h6c,N6d=8'h6d,N6e=8'h6e,N6f=8'h6f,
  N70=8'h70,N71=8'h71,N72=8'h72,N73=8'h73,N74=8'h74,N75=8'h75,N76=8'h76,N77=8'h77,
  N78=8'h78,N79=8'h79,N7a=8'h7a,N7b=8'h7b,N7c=8'h7c,N7d=8'h7d,N7e=8'h7e,N7f=8'h7f,
  N80=8'h80,N81=8'h81,N82=8'h82,N83=8'h83,N84=8'h84,N85=8'h85,N86=8'h86,N87=8'h87,
  N88=8'h88,N89=8'h89,N8a=8'h8a,N8b=8'h8b,N8c=8'h8c,N8d=8'h8d,N8e=8'h8e,N8f=8'h8f,
  N90=8'h90,N91=8'h91,N92=8'h92,N93=8'h93,N94=8'h94,N95=8'h95,N96=8'h96,N97=8'h97,
  N98=8'h98,N99=8'h99,N9a=8'h9a,N9b=8'h9b,N9c=8'h9c,N9d=8'h9d,N9e=8'h9e,N9f=8'h9f,
  Na0=8'ha0,Na1=8'ha1,Na2=8'ha2,Na3=8'ha3,Na4=8'ha4,Na5=8'ha5,Na6=8'ha6,Na7=8'ha7,
  Na8=8'ha8,Na9=8'ha9,Naa=8'haa,Nab=8'hab,Nac=8'hac,Nad=8'had,Nae=8'hae,Naf=8'haf,
  Nb0=8'hb0,Nb1=8'hb1,Nb2=8'hb2,Nb3=8'hb3,Nb4=8'hb4,Nb5=8'hb5,Nb6=8'hb6,Nb7=8'hb7,
  Nb8=8'hb8,Nb9=8'hb9,Nba=8'hba,Nbb=8'hbb,Nbc=8'hbc,Nbd=8'hbd,Nbe=8'hbe,Nbf=8'hbf,
  Nc0=8'hc0,Nc1=8'hc1,Nc2=8'hc2,Nc3=8'hc3,Nc4=8'hc4,Nc5=8'hc5,Nc6=8'hc6,Nc7=8'hc7,
  Nc8=8'hc8,Nc9=8'hc9,Nca=8'hca,Ncb=8'hcb,Ncc=8'hcc,Ncd=8'hcd,Nce=8'hce,Ncf=8'hcf,
  Nd0=8'hd0,Nd1=8'hd1,Nd2=8'hd2,Nd3=8'hd3,Nd4=8'hd4,Nd5=8'hd5,Nd6=8'hd6,Nd7=8'hd7,
  Nd8=8'hd8,Nd9=8'hd9,Nda=8'hda,Ndb=8'hdb,Ndc=8'hdc,Ndd=8'hdd,Nde=8'hde,Ndf=8'hdf,
  Ne0=8'he0,Ne1=8'he1,Ne2=8'he2,Ne3=8'he3,Ne4=8'he4,Ne5=8'he5,Ne6=8'he6,Ne7=8'he7,
  Ne8=8'he8,Ne9=8'he9,Nea=8'hea,Neb=8'heb,Nec=8'hec,Ned=8'hed,Nee=8'hee,Nef=8'hef,
  Nf0=8'hf0,Nf1=8'hf1,Nf2=8'hf2,Nf3=8'hf3,Nf4=8'hf4,Nf5=8'hf5,Nf6=8'hf6,Nf7=8'hf7,
  Nf8=8'hf8,Nf9=8'hf9,Nfa=8'hfa,Nfb=8'hfb,Nfc=8'hfc,Nfd=8'hfd,Nfe=8'hfe,Nff=8'hff
} CapExpCode deriving(Bits, Eq, FShow);

// Below are constants that define the size of the TLB.
typedef 256 TLBSize;  // TLBSize is the size of the direct-mapped portion of the TLB
typedef 8  LogTLBSize; // LogTLBSize must be the log base 2 of TLBSize
typedef 16 AssosTLBSize; // AssosTLBSize is the size of the fully associative array at the bottom of the TLB
typedef 4  LogAssosTLBSize; // LogAssosTLB size must be log2(AssosTLBSIze)
typedef 272 TLBSizeTotal; // TLBSizeTotal must be TLBSize + AssosTLBSize
typedef 9  LogTLBSizePlusOne; // LogTLBSizePlusOne must be LgTLBSize + 1, just like it says on the tin.
// The below declarations are integer versions of the above types to be used when integer values are needed
Integer tlbSize = valueOf(TLBSize);
Integer logTLBSize = valueOf(LogTLBSize);
Integer assosTLBSize = valueOf(AssosTLBSize);
Integer logAssosTLBSize = valueOf(LogAssosTLBSize);

// These lines setup the number of interfaces in the TLB.
`ifdef DMA_VIRT
    typedef 5 NumTLBLookups; // Virtual DMA needs i and d TLB interfaces.
`else
    typedef 3 NumTLBLookups; // Total number of TLB lookups
`endif

// The TLBEntry type is a complete TLB record and includes flags for the interfaces in which it is used.
// The TLBEntry type is used for both TLB writes and TLB reads.
typedef struct {
  Bool      write;    // Is this a write?
  Bool      random;   // Is it a write random? (or indexed)
  Bit#(LogTLBSizePlusOne)     tlbAddr;  // I added this for conveniance.
  TlbAssosEntry  assosEntry;  // These bits are split off into another type so we can easily load them into a BRAM.
  TlbEntryLo    entryLo0;
  TlbEntryLo    entryLo1;
} TLBEntryT deriving(Bits, Eq, FShow); // ~146 bits

// The TLBAssosEntry is the associatve portion of the TLB entry, ie the portion of the entry that must be stored
// in registers and not in a BRAM for the associative entries of the TLB.
typedef struct {
  TlbEntryHi  entryHi; // The MIPS architectural EntryHi field. 
  Bool    valid;    // Always valid for a stored entry.  Will be returned invalid if there is no entry.
  Bit#(12)  pageMask;  // Mask of valid bits to compare (i.e. for varying the page size)
  Bit#(5)   whichLoBit; // Bit to check for which EntryLo to use, the MSB of the page mask.
  Bool      g;      // Global.  This virtual address maps in all spaces.
} TlbAssosEntry deriving(Bits, Eq, FShow); // 78 bits

// The TlbRequest type is used to interact with the TLB during a memory request.
typedef struct {
  Address    addr;      // The virtual address being requested
  Bool       write;     // Whether this access is a write
  Bool       ll;        // Whether this access ia a load linked operation
  Bool       fromDebug; // Whether this instruction is from the debug unit
  Exception  exception; // Whether(or what) exception has fired for this instruction in the pipeline already
  InstId     instId;    // The id of the instruction that made this memory request.
} TlbRequest deriving(Bits, Eq, FShow);

// The TlbResponse type is returned from the TLB to the L1 cache on every memory request.
typedef struct {
  Bool        valid;
  PhyAddress  addr;       // The physical address returned from the translation
  Exception   exception;  // The instruction's exception state as seen by the TLB (possibly modified by the TLB itself).  
  Bool        write;      // Whether this is a write operation
  Bool        ll;         // Whether this is a load linked operation
  Bool        cached;     // Whether this is a cached operation
  Bool        fromDebug;  // Whether this instruction is from the debug unit
  Privilege   priv;       // The privilege level of this instruction, ie user, kernel, or supervisor
  InstId      instId;     // The id of the instruction that made this memory request.
  `ifdef USECAP
    Bool      noCapLoad;    // Allow capability load.
    Bool      noCapStore;   // Allow capability store.
  `endif
} TlbResponse deriving(Bits, Eq, FShow);

// The CacheRequestInstT structure is used in the L1 instruction cache server interface.
typedef struct {
  CacheOperation     cop;         // The cache operation, the most common being read and write, but includes invalidate operations.
  InstId             instId;      // The id of the instruction making the request
  InstructionT       defaultInst;
  TlbResponse        tr;
} CacheRequestInstT deriving (Bits, Eq, FShow);

// The CacheResponseInstT is the instruction cache response.
typedef struct {
  Exception    exception; // The current instruction exception state as seen by the instruction cache 
                         // (which may have been updated by it)
  InstructionT inst;      // The 64-bit response from the instruction cache.  (The instruction word is selected externally).
} CacheResponseInstT deriving(Bits, Eq, FShow);

typedef enum {User, Supervisor, Kernel} Privilege deriving (Bits, Eq, FShow); // Privilege level of an operation

// An exception report delivered from the system control processor (CP0) to the writeback stage.
typedef struct {
  Bool        bev;       // The current privelege level of the processor
  Bool        exl;       // The exception status of the processor
  Exception   exception; // Any exception raised for this instruction by CP0.
} Cp0ExceptionReport deriving(Bits, Eq, FShow);

// An exception writeback operation from the writeback stage to CP0 (the system control processor).
typedef struct {
  Exception exception; // The exception raised by this instruction
  Address victim;      // The victim of the exception (probably the PC of the instruction, or PC-4 if it's a branch delay slot)
  Address entry;       // The exception entry point.  Not needed by CP0 but used in writeback
  Bool branchDelay;    // Whether this instruction is in a branchDelay slot
  InstId   instId;     // The id of the instruction for this exception
  Bit#(32) instruction;// Instruction that raised the exception
  Bool dead;           // Whether or not this instruction is dead already
} ExceptionWriteback deriving(Bits, Eq, FShow);

// StatusRegister is the type for the CP0 (system control coprocessor) status register from the MIPS spec
typedef struct {
  CoProEn cpEn;  // Coprocessor Enables
  Bool rp;  // Reduced Power: Does nothing!
  Bool fr;  // Floating Point Register Fusion: Does nothing!
  Bool re;  // Reverse Endian: Currently does nothing!
  Bool mx;  // DSP or MDMX: Does nothing! We don't have an MDMX unit.
  Bool px;  // Use 32-bit addressing with 64-bit instructions in user mode.
  Bool bev;  // Use ROM (kseg1) for exception entry points.  Normally set to 0 when running.
  Bool ts;  // Set by proc if two TLB entries match to prevent proc damage.  This is not necissary for us.
  Bool sr;  // Set by proc if a soft reset or a non-maskable interupt occurred.
  Bool nmi;  // Set by proc if a non-maskable interupt occurred.
  bit[2:0] z0;// Set to zero.
  bit[7:0] im;// Determines which sources can cause exceptions.
  Bool kx;  // kernel uses 64-bit addressing (different TLB miss entry point)
  Bool sx;  // supervisor uses 64-bit addressing (different TLB miss entry point)
  Bool ux;  // user-mode uses 64-bit addressing and instructions (different TLB miss entry point).  If ad32in64m is set, you can use 64-bit instructions but only 32-bit addressing.
  bit[1:0] ksu; // Current cpu privilege level.  0 = kernel, 1 = supervisor, 2 = user.
  Bool erl;  // Set by proc when it gets bad data.  Not used.
  Bool exl;  // Set by proc on an exception, forces kernel mode & disables interupts until software sets new privalige level and interrupt mask.
  Bool ie;  // Global interupt enable.
} StatusRegister deriving(Bits, Eq, FShow); // 32 bits

// The CoProEn is the type for the coprocessor enable field of the MIPS status register (above). 
typedef struct {
  Bool cu3;  // Now unused.
  Bool cu2;  // Capability unit (if included).
  Bool cu1;  // FPU.
  Bool cu0;  // Allows user-mode to access CP0 instructions!
} CoProEn deriving(Bits, Eq, FShow);

// CauseRegister is type for the MIPS architectural system control processor (CP0) cause register
typedef struct {
  Bool     bd;    // Exception victim was in the branch delay slot and EPC points to the branch, not the victim.
  Bool     ti;    // Exception caused by internal timer.
  bit[1:0] ce;   // Coprocessor instruction for a coprocessor not enabled by SR(coProX_en).
  Bool     dc;    // Stop count register.  This is writeable. (Not implemented.  Only for newer MIPS64s)
  Bool     pci;  // Performance counter overflowed in CP0.  
  bit[1:0] z01;   // 0s
  Bool     iv;    // Enable special entry point for interrupts.  This is writable.
  Bool     wp;    // Reads True if a watchpoint triggered during the interupt and needs to be observed when it is over.  Also, write True to enable special entries for interrupts.
  bit[5:0] z02;  // 0s
  bit[7:0] ipDummy;    // Pending interrupts corrosponding to the enabled interrupts in SR(intMask).
  Bool     z03;  // 0
  ExpCode  excCode; // Which exception happened, 5 bits.
  bit[1:0] z04;  // 0s
} CauseRegister deriving(Bits, Eq, FShow); // 32 bits

// The Exception enumerated type is the internal exception type used in the main control token.
// Many of these correspond to MIPS architectural exception codes, but some MIPS exception codes
// (defined in the ExpCode enumerated type) can have multiple internal causes which require different
// responses in the pipeline.
typedef enum {
  Int,    // Interrupt
  Mod,    // Tried to modify read only page
  ITLB,   // No TLB entry for instruction fetch.
  ITLBI,  // Instruction TLB entry is invalid.
  DTLBL,  // No TLB entry for a load from the data interface.
  DTLBS,  // No TLB entry for a store.  
          // If CPU is not in exception mode, i.e. SR(exptnLevl) != 1, this is a TLB miss handled by a special entry point.
  DTLBLI, // Data TLB load is invalid, but present in the table.
  DTLBSI, // Data TLB store is invalid, but present in the table.
  CTLBS,  // Storing a capability in a TLB entry that does not allow it.
  IADEL,  // Instruction Load error
  DADEL,  // Data Load error
  DADES,  // Data Store error.  These could be attempting to access above kuseg or attempting a mis-aligned access.
  IBE,    // Instruction bus error.
  DBE,    // Data bus error.  These are implementation dependent.
  Syscall,// Executed a syscall instruction
  Bp,     // Executed a break instruction.
  RI,     // Instruction code not recognized
  CP0,    // Attempted coprocessor instruction for disabled coprocessor 0.
  CP1,    // Attempted coprocessor instruction for disabled coprocessor 1.
  CP2,    // Attempted coprocessor instruction for disabled coprocessor 2.
  CP3,    // Attempted coprocessor instruction for disabled coprocessor 3.
  Ov,     // Overflow from trapping arithmetic instructions (e.g. add, but not addu).
  TRAP,   // Condition met on a conditional trap instruction.
  CAP,    // Exception from Capability Coprocessor, which is a C2E exception.
  ICAP,   // Exception from Capability Coprocessor for instruction fetch.
  CAPCALL,// Secure procedure call or return from the Capability Coprocessor.
  Watch,  // Physical address of load and store matched WatchLo/WatchHi registers.
  Dead,   // Exception to indicate a killed instruction.  It will not writeback and report.
  FPE,	  // Floating Point exception.
  NMI,    // Non-maskable interrupt, or software reset.
  None
} Exception deriving (Bits, Eq, FShow);

// The ExpCode enumerated type is the MIPS architectural exception code field from
// the MIPS cause register in the system control processor (CP0)
typedef enum {
  Int       = 5'd0, // Interrupt
  Mod       = 5'd1, // Tried to modify read only page
  TLBL      = 5'd2, // No TLB entry for a load.
  TLBS      = 5'd3, // No TLB entry for a store.  If CPU is not in exception mode, i.e. SR(exptnLevl) != 1, this is a TLB miss handled by a special entry point.
  ADEL      = 5'd4, // Load error
  ADES      = 5'd5, // Store error.  These could be attempting to access above kuseg or attempting a mis-aligned access.
  IBE       = 5'd6, // Instruction bus error.
  DBE       = 5'd7, // Data bus error.  These are implementation dependent.
  Syscall   = 5'd8, // Executed a syscall instruction
  Bp        = 5'd9, // Executed a break instruction.
  RI        = 5'd10,// Instruction code not recognized
  CpU       = 5'd11,// Attempted coprocessor instruction for disabled coprocessor.  Floating point emulation starts here.
  Ov        = 5'd12,// Overflow from trapping arithmetic instructions (e.g. add, but not addu).
  TRAP      = 5'd13,// Condition met on a conditional trap instruction.
  FPE       = 5'd15,// Floating point exception.
  C2E       = 5'd18,// Exception from coprocessor 2, an extension to the instruction set.
  MDMX      = 5'd22,// Tried to run an MDMX instruction but SR(dspOrMdmx) is not enabled.
  Watch     = 5'd23,// Physical address of load and store matched WatchLo/WatchHi registers.
  MCheck    = 5'd24,// Disasterous error in control system, eg, duplicate entries in TLB.
  Thread    = 5'd25,// Thread related exception, but VPEControl(EXCPT) tells you more.
  DSP       = 5'd26,// Tried DSP ASE instruction, but we don't have DSP.
  CacheErr  = 5'd30,// Parity/ECC error in cache.
  None      = 5'd31
} ExpCode deriving (Bits, Eq, FShow);

// The getExceptionCode function converts internal exception codes (Exception type) to 
// MIPS architecturally defined ones (ExpCode)
function ExpCode getExceptionCode(Exception exc);
  ExpCode ret = None;
  case(exc)
    Int:      ret = Int;
    Mod:      ret = Mod;
    ITLB:     ret = TLBL;
    ITLBI:    ret = TLBL;
    DTLBL:    ret = TLBL;
    DTLBS:    ret = TLBS;
    DTLBLI:   ret = TLBL;
    DTLBSI:   ret = TLBS;
    CTLBS:    ret = C2E;
    IADEL:    ret = ADEL;
    DADEL:    ret = ADEL;
    DADES:    ret = ADES;
    IBE:      ret = IBE;
    DBE:      ret = DBE;
    Syscall:  ret = Syscall;
    Bp:       ret = Bp;
    RI:       ret = RI;
    CP0:      ret = CpU;
    CP1:      ret = CpU;
    CP2:      ret = CpU;
    CP3:      ret = CpU;
    Ov:       ret = Ov;
    TRAP:     ret = TRAP;
    CAP:      ret = C2E;
    ICAP:     ret = C2E;
    CAPCALL:  ret = C2E;
    Watch:    ret = Watch;
    Dead:     ret = None;
    default:  ret = None;
  endcase
  return ret;
endfunction

// The PRId type is for the MIPS processor ID architectural register in the system control processor, CP0
typedef struct {
  Bit#(8) compOp;  // Company Options. Not important.
  Bit#(8) compID;  // Company ID. Not important.
  Bit#(8) cpuID;  // CPU ID. Use 4=R4000?
  Bit#(8) revsn;  // CPU Revision.  Not used. 
} PRId deriving(Bits, Eq, FShow); // 32 bits

typedef struct {
  Bit#(16) coreCount;
  Bit#(16) coreID;
} COREId deriving(Bits, Eq, FShow);

// The Config0 type defines the fields of the MIPS architectural config regitster in the system control proceesor, CP0
typedef struct {
  Bool      m;    // Continuation bit.  1 if there is another configuration register. 
  Bit#(15)  impl;  //
  Bool      be;    // True if Big endian.
  Bit#(2)   at;    // 0=MIPS32, 1=MIPS64 inst with MIPS32 address MAP, 2=MIPS64 inst & address map.
  Bit#(3)   ar;    // 0=MIPS32/64 release 1, 1=MIPS32/64 release 2
  Bit#(3)   mt;    // MMU type: 0=None, 1=MIPS32/64-compliant TLB, 2=BAT type, 3=MIPS32-standard FMT fixed mapping
  Bit#(3)   z0;    // Zeros
  Bool      vi;    // I-cache is virtually tagged. (False for us I guess?)
  CacheCA   c;    // Cache algorithm or cache coherency attribute for multi-processor systems.
} Config0 deriving(Bits, Eq, FShow); // 32 bits

// The Config1 type defines the fields of the first config shadow register in CP0, according to the MIPS spec. 
typedef struct {
  Bool  m;      // Continuation bit.  1 if there is another configuration register. 
  Bit#(6) mmuSize;  // Size of the TLB array. (MMU has MMUSize+1 entries) 
  L1ChCfg iCache;    // Instruction cache configuration
  L1ChCfg dCache;    // Data cache configuration
  Bool  c2;      // True if there is a coprocessor 2.
  Bool  md;      // True if MDMX is implemented in the floating point unit.
  Bool  pc;      // True if there is at least one performance counter in the design.
  Bool  wr;      // True if there is at least one watchpoint register.
  Bool  ca;      // True if MIPS16e is available.
  Bool  ep;      // True if EJTAG unit is available.
  Bool  fp;      // True if Floating Point unit is available.
} Config1 deriving(Bits, Eq, FShow); // 32 bits

// The L1ChCfg type defines a level 1 cache configuration and is used in fields of the Config1 CP0 register.
typedef struct {
  Bit#(3) s;  //  Number of Cache index positions is 64 * 2^S. Mult by Assosiativity for total number of cache lines. (128)
  Bit#(3) l;  //  Cache line size = 2*2^L.  L=0 if there is no cache. (4)
  Bit#(3) a;  //  Assosiativity = A+1.  (A=0 for direct mapped)
} L1ChCfg deriving(Bits, Eq, FShow); // 32 bits

// The Config2 type defines the fields of the second config shadow register in CP0 according to the MIPS spec. 
typedef struct {
  Bool  m;      // Continuation bit.  1 if there is another configuration register. 
  LxChCfg l3ch;    // Instruction cache configuration
  Bool  space;    // Actually a part of the L2ch SU field, but we're not using it anyway.  This lets L2 and L3 have the same format.
  LxChCfg l2ch;    // Data cache configuration
} Config2 deriving(Bits, Eq, FShow); // 32 bits

// The Config3 type defines the fields of the third config shadow register in CP0 according to the MIPS spec. 
typedef struct {
  Bool   m;    // Continuation bit.  1 if there is another configuration register.  There won't be.
  Bit#(17) zero4;  //
  Bool   ulri;
  Bit#(3)zero3;
  Bool   dspp;  // True if MIPS DSP extension is implemented
  Bool   zero2;  //
  Bool   lpa;  // True if Large Physical Addressing is available, ie addresses over 2^36
  Bool   veic;  // True if we have an EIC-compatible interrupt controller
  Bool   vInt;  // True if the CPU can handle vectored interrupts
  Bool   sp;  // True if the CPU supports <4k page sizes.  We don't.
  Bool   zero1;  // 
  Bool   mt;  // True if the CPU does multithreading, the MIPS MT extension.
  Bool   sm;  // True if the CPU supports "SmartMIPS".  We don't.
  Bool   tl;  // True if the CPU can record and output instruction traces.  Advanced feature of EJTAG.
} Config3 deriving(Bits, Eq, FShow); // 32 bits

// The Config6 type describes the sixth shadow register of the MIPS config register.  This definition is inferred from 
// nlm (netlogic micro) source code in freeBSD for their large TLB implementation.
typedef struct { 
  Bit#(16) tlbSize;       // Size of TLB-1, up to 65k entries.
  Bit#(13) zerosB;
  Bool     enableLargeTlb; // Enable the larger TLB size
  Bit#(2)  zerosA;    // 
} Config6 deriving(Bits, Eq, FShow); // 32 bits

// The LxChCfg structure defines the properties of a cache and is used in Config2 for both the L2 (which exists) 
// and the L3 (which doesn't, yet).
typedef struct {
  Bit#(3) tu;  //  Configuration bits.  Could be writable.
  Bit#(4) ts;  //  Number of Cache index positions is 64 * 2^S. Mult by Assosiativity for total number of cache lines. (128)
  Bit#(4) tl;  //  Cache line size = 2*2^L.  L=0 if there is no cache. (4)
  Bit#(4) ta;  //  Assosiativity = A+1.  (A=0 for direct mapped)
} LxChCfg deriving(Bits, Eq, FShow); // 15 bits

// HWREna is the type of the CP0 register number 7.0.
// HWREna controls which "hardware registers" are available from userspace
// using the rdhwr instruction.
typedef struct {
  Bool cpunum;    //  This CPU number
  Bool synci_step;//  Cache line size
  Bool cc;        //  Count register
  Bool ccres;     //  Count resolution
  Bool insts;     //  Instruction counter
  Bool instTLBMiss; //  I-TLB miss counter
  Bool dataTLBMiss; //  D-TLB miss counter
  `ifdef STATCOUNTERS
  Vector#(8,Bool) statcounters; // CHERI specific statcounters
  `endif
  Bool tls;       //  Thread local storage
} HWREna deriving(Bits, Eq, FShow);

/* Not implementing these for now.  Newer than R4000. ----------------------------------------------------------------------------------------------------- 
typedef struct {
  Bit#(2)  oz;      // 2'b10.  This ensures that the exception base is in the kseg0 region.
  Bit#(18) exceptionBase;  // Base address for exception vectors at a resolution of 4Kbytes.
  Bit#(2)  oo;      // 2'b10
  Bit#(10) cpuNum;    // Hardwired CPU number.
} EBase deriving(Bits, Eq, FShow); // 32 bits

typedef struct {
  Bit#(3)   ipti;    // Timer counter interrupt.
  Bit#(3)   ippci;    // Performance counter interrupt.
  Bit#(16)  zeros1;
  Bit#(5)   vs;    // Exception vector spacing = VS*32 bytes. (1, 2, 4, 8 & 16 are valid).
  Bit#(5)   zeros0;
} IntCtl deriving(Bits, Eq, FShow); // 32 bits*/

/* Not going to implement shadow registers... --------------------------------------------------------------------
typedef struct {
  Bit#(4)   CSS;    // The register set currently in use.
  Bit#(2)   Zeros0; 
  Bit#(4)   PSS;    // "Previous" register set.  Writable.
  Bit#(2)   Zeros1; 
  Bit#(4)   ESS;    // Shadow register set to be used for "all other exceptions".  Writable.
  Bit#(2)   Zeros2; 
  Bit#(4)   EICSS;    // In EIC mode, an external interrupt selects a shadow register set.
  Bit#(4)   Zeros3;
  Bit#(4)   HSS;    // Number of shadow register sets - 1.  Can be changed on multi-theading CPUs. 
  Bool    Zeros4;
} SRSCtl deriving(Bits, Eq, FShow); // 32 bits
              -------------------------------------------------------------------- */

// The TlbEntryHi type describes the format of the EntryHi CP0 register in MIPS, and also the high portion
// of each TLB entry
typedef struct {
  Bit#(2)   r;    // Address space privilige, which is just the high order bits of the VPN.
          // 0=xuseg, 1=sxxeg, 2=xkphys, 3=xkseg
  Bit#(27)  vpn2;  // Virtual Page Number.  Each Hi entry represents 2 Lo entries, so the last bit insn't matched.
  Bit#(8)   asid;  // Address Space Identifier.
} TlbEntryHi deriving(Bits, Eq, FShow); // 64 bits

// The TlbEntryLo type describes the format of the EntryLo 0 & 1 CP0 register in MIPS, and also the two low records
// of each TLB entry
typedef struct { 
  `ifdef USECAP
    Bool    noCapStore; // Allow storing capabilities
    Bool    noCapLoad;  // Allow loading capabilities
  `endif
  //Bit#(28)  zeros;
  Bit#(28)  pfn;  // Physical address of the page.
  CacheCA   c;    // Cache algorithm or cache coherency attribute for multi-processor systems.
  Bool      d;    // Dirty - True if writes are allowed.  Writes will cause exception otherwise.
  Bool      v;    // Valid - If False, attempts to use this location cause an exception.
  Bool      g;    // Global - If True this entry will match regardless of ASID.  Both "Lo(G)"s in an odd/even pair should be identical.
} TlbEntryLo deriving(Bits, Eq, FShow); // 34-36 bits

// The Context type describes the format of the context CP0 register from the MIPS spec, used for a table of TLB entries.
typedef struct {
  Bit#(41)  pteBase;  // The Base address of the table of virtual address mappings.
  Bit#(19)  badVPN2;  // The page address after a TLB exception (high-order bits of BadVAddr
  Bit#(4)   zeros;    // Offset by 4 so that this can structure can be used as a pointer into a table of vitual address mappings.
} Context deriving(Bits, Eq, FShow); // 64 bits

// The XContext type describes the format of the xcontext CP0 register from the MIPS spec, used for a table of 64-bit TLB entries.
typedef struct {
  Bit#(31)  pteBase;  // The Base address of the table of virtual address mappings.
  Bit#(2)   r;      // Address space privilige, which is just the high order bits of the VPN.
            // 0=xuseg, 1=sxxeg, 2=xkphys, 3=xkseg
  Bit#(27)  badVPN2;  // The page address after a TLB exception (high-order bits of BadVAddr
  Bit#(4)   zeros;    // Offset by 4 so that this can structure can be used as a pointer into a table of vitual address mappings.
} XContext deriving(Bits, Eq, FShow); // 64 bits

// The CacheCA enumerated type lists valid cache behaviours for memory or for a page of the TLB.
typedef enum {
  Zero          = 3'd0, // (To facilitate writes of zero to this field)
  Uncached      = 3'd2, // Don't cache this page
  Cached        = 3'd3, // Cache this page but don't broadcast writes
  Spacer        = 3'd4  // (Make sure there are 3 bits in this field)
} CacheCA deriving(Bits, Eq, FShow);

`ifndef CHERIOS
interface TranslationIfc;
  method ActionValue#(TlbResponse) request(TlbRequest req);
  method ActionValue#(TlbResponse) response();
endinterface
`endif // CHERIOS

// The CPOIfc interface is the interface for the system control processor, or coprocessor 0 (CP0).
interface CP0Ifc;
  method Action                             readReq(RegNum rn, Bit#(3) sel);  // Initiate a CP0 register read
  method Bool writePending; // Report whether there is a write pending in CP0
  method ActionValue#(Word)                 readGet(Bool goingToWrite); // Deliver a read CP0 register to the main pipeline
  method Action                             writeReg(RegNum rn, Bit#(3) sel, Word data, Bool forceKernelMode, Bool writeBack); // Write a CP0 register
  method Cp0ExceptionReport                 getException(); // Get an exception report from CP0 (in writeback)
  method Action                             putException(ExceptionWriteback exp, Address ivaddr, MIPSReg dvaddr); // Report the final exception to CP0 from writeback
  method ActionValue#(Bool)                 setLlScReg(Address matchAddress, Bool link, Bool store); // Set the load linked address
  method Action                             interrupts(Bit#(5) interruptLines); // Put the external interrupt line state into CP0
  method CoProEn                            getCoprocessorEnables(); // Report the current state of the coprocessor enable signals.
  method HWREna                             getHardwareRegisterEnables();
  method Bit#(8)                            getAsid(); // Report the current address space identifier.
  method Action                             putCount(Bit#(48) commonCount); // Put the common count register for all cores.
  method Action                             putCacheConfiguration(L1ChCfg iCacheConfig, L1ChCfg dCacheConfig); // Recieve a report of 
                                                                     // the L1 cache configurations.  This allows the caches to define their
                                                                     // own configurations.
  method Action                             putDeterministicCycleCount(Bool cycleCount);
  // Whether the CP0 thinks tracing should be turned on
  method Bool                               shouldTrace();
  `ifndef CHERIOS
      interface TranslationIfc tlbLookupInstruction; // Initiate an instruction TLB lookup
      interface TranslationIfc tlbLookupData;        // Initiate a data TLB lookup
  `endif // CHERIOS
  `ifdef DMA_VIRT
    interface Vector#(2, TranslationIfc) tlbs; // For the DMA
  `endif

endinterface

// The CoProIfc interface is a generic interface for coprocessors.
// This interface and example stub code that implements it can be a starting point for extending the processor.
interface CoProIfc;
  interface Client#(CoProMemAccess, CoProReg) coProMem;  // A memory client interface to allow initiating memory requests
  method Action                          putCoProInst(CoProInst inst); // Put a coprocessor instruction, initiated in the Decode stage
  method ActionValue#(CoProResponse) getCoProResponse(CoProVals vals); // Get a response from the coprocessor, exercised in the Execute stage
  method Action                       commitWriteback(CoProWritebackRequest wbReq); // Commit a writeback to the coprocessor in the writeback stage.
endinterface

// The CoProImmediate type is an immediate field that might be used in the example coprocessor instruction format.
typedef Bit#(6) CoProImmediate;

// The CoProInst type is a generic instruction format for a custom coprocessor.
typedef struct {
  CoProXOp        op; // Coprocessor Operation
  RegNum          regNumA;  // Source register A
  RegNum          regNumB;  // Source register B
  RegNum          regNumDest; // The destination register
  CoProImmediate  imm;  // Immediate operand
  InstId          instId; // id of the initiating instruction
  OpCode          mipsOp; // The MIPS operation, in case it is useful to the coprocessor.
} CoProInst deriving(Bits, Eq, FShow);

// The CoProReg type is the type used for the registers of the example coprocessor.
typedef Data#(CheriDataWidth) CoProReg;

// CoProVals is the type used for submitting operands from the main pipeline from execute into the coprocessor.
typedef struct {
  MIPSReg   opA;  // Operand A
  MIPSReg   opB;  // Operand B
} CoProVals deriving(Bits, Eq, FShow);

// CoProResponse is the type returned from the coprocessor to the main pipeline in execute.
typedef struct {
  Bool        valid; // Data is valid
  Word        data;  // Data value
  SizedWord   storeData;
  Exception   exception; // An exception code
} CoProResponse deriving(Bits, FShow);

// CoProMemAccess is the type of a memory request from the generic coprocessor.
typedef struct {
  MemOp       memOp;    // Memory operation
  Address     address;  // Virtual address of the request
  CoProReg    coProReg; // Coprocessor register value for a write
} CoProMemAccess deriving(Bits, Eq, FShow);

// CoProWritebackRequest is the type submitted to the generic coprocessor in writeback to report the instructions commit status.
typedef struct {
  Bool	 dead;
  Bool   commit;
  InstId instId;        // Instruction ID that requests the update
  Word   data;
} CoProWritebackRequest deriving(Bits, Eq, FShow);

// The enumerated CoProXOp type describes set of generic set of coprocessor operations that might be a starting point
// for a custom coprocessor.
typedef enum {
  MFC      = 5'h00,  // Move a word from a coprocessor register field
  DMFC     = 5'h01,  // Move a double word from a coprocessor register field
  Op2      = 5'h02,
  Op3      = 5'h03,
  MTC      = 5'h04,  // Move a word to a coprocessor register field
  DMTC     = 5'h05,  // Move a double word to a coprocessor register field
  Op6      = 5'h06,
  Op7      = 5'h07,
  Op8      = 5'h08,
  Op9      = 5'h09,
  Op10     = 5'h0A,
  Op11     = 5'h0B,
  Op12     = 5'h0C,               
  Op13     = 5'h0D,
  Op14     = 5'h0E,
  Op15     = 5'h0F,
  Load     = 5'h10,
  Store    = 5'h11,
  Op18     = 5'h12,
  Op19     = 5'h13,
  Op20     = 5'h14,
  Op21     = 5'h15,
  Op22     = 5'h16,
  Op23     = 5'h17,
  Op24     = 5'h18,            
  Op25     = 5'h19,
  Op26     = 5'h1A,
  Op27     = 5'h1B,
  Op28     = 5'h1C,
  Op29     = 5'h1D,
  Op30     = 5'h1E,
  None     = 5'h1F
} CoProXOp deriving (Bits, Eq, FShow);

// The enumerated CoProFPOp type describes defined values of the op field of floating point (CP1) instructions.
typedef enum {
  MFC      = 5'h00,  // Move a word from a coprocessor register field
  DMFC     = 5'h01,  // Move a double word from a coprocessor register field
  CFC      = 5'h02,	 // Move a control word from a coprocessor register field
  Op3      = 5'h03,
  MTC      = 5'h04,  // Move a word to a coprocessor register field
  DMTC     = 5'h05,  // Move a double word to a coprocessor register field
  CTC      = 5'h06,  // Move a control word to a corprocessor register field
  Op7      = 5'h07,
  BC1      = 5'h08,  // Branch
  Op9      = 5'h09,
  Op10     = 5'h0A,
  Op11     = 5'h0B,
  Op12     = 5'h0C,               
  Op13     = 5'h0D,
  Op14     = 5'h0E,
  Op15     = 5'h0F,
  Op16     = 5'h10,
  Op17     = 5'h11,
  Op18     = 5'h12,
  Op19     = 5'h13,
  Op20     = 5'h14,
  Op21     = 5'h15,
  Op22     = 5'h16,
  Op23     = 5'h17,
  Op24     = 5'h18,            
  Op25     = 5'h19,
  Op26     = 5'h1A,
  Op27     = 5'h1B,
  Op28     = 5'h1C,
  Op29     = 5'h1D,
  Op30     = 5'h1E,
  None     = 5'h1F    // Note that this should really be reserved
} CoProFPOp deriving(Bits, Eq, FShow);

// The enumerated CoProFPXOp type describes defined values of the op field of extended floating point (CP3(or X)) instructions.
typedef enum {
    LWXC1  = 6'h00,
    LDXC1  = 6'h01,

    SWXC1  = 6'h08,
    SDXC1  = 6'h09,

    UNRECOGNISED = 6'h3F //A bit ugly, but will do for now.
} CoProFPXOp deriving(Bits, Eq, FShow);

/***** Register file interface and types *****/
// Register file interface determines the number of rename registers.
typedef ForwardingPipelinedRegFileIfc#(MIPSReg, 4) MIPSRegFileIfc;

typedef enum {
  None,
  Simple,
  Conditional,
  Pending
} WriteType deriving (Bits, Eq, FShow);

interface ForwardingPipelinedRegFileIfc#(type regType, numeric type renameRegs);
  method Action reqRegs(ReadReq req);
  // These two methods, getRegs and writeRegSpeculative should be called in the
  // same rule, Execute.
  method ActionValue#(ReadRegs#(regType)) readRegs();
  method Action writeRegSpeculative(regType data, Bool write);
  method Action writeReg(regType data, Bool committing);
  method Action writeRaw(RegNum regW, regType data);
  method Action readRawPut(RegNum regA);
  method ActionValue#(regType) readRawGet();
  method Action putDebugRegs(regType a, regType b);
  method Action clearRegs(Bit#(32) mask);
endinterface

typedef struct {
  Epoch     epoch;
  RegNum    a;
  RegNum    b;
  WriteType write;
  RegNum    dest;
  Bool      fromDebug;
  Bool      rawReq;
} ReadReq deriving (Bits, Eq, FShow);

typedef struct {
  regType regA;
  regType regB;
} ReadRegs#(type regType) deriving (Bits, Eq, FShow);

/****** Debug Reporting Functions ******/

// Translate a subset of the AluOp values into a string for debug printouts.
function String aluOpString(AluOp o);
  case(o)
    Add:  aluOpString = "Add";
    Sub:  aluOpString = "Sub";
    Or:   aluOpString = "Or";
    Xor:  aluOpString = "Xor";
    And:  aluOpString = "And";
    Nor:  aluOpString = "Nor";
    SLT:  aluOpString = "SLT";
    SLTU: aluOpString = "SLTU";
    SLL:  aluOpString = "SLL";
    SRA:  aluOpString = "SRA";
    SRL:  aluOpString = "SRL";
    Nop:  aluOpString = "Nop";
    Mul:  aluOpString = "Mul";
    Div:  aluOpString = "Div";
    MOVZ: aluOpString = "MovZ";
    MOVN: aluOpString = "MovN";
  endcase
endfunction

// Translate a subset of the MemSize values into a string for debug printouts
function String memSizeString(MemSize s);
  case(s)
    CapWord: memSizeString = "CapWord";
    DoubleWord: memSizeString = "DoubleWord";
    DoubleWordLeft: memSizeString  = "DoubleWordLeft";
    DoubleWordRight: memSizeString = "DoubleWordRight";
    Word: memSizeString = "Word";
    WordLeft:  memSizeString = "WordLeft";
    WordRight: memSizeString = "WordRight";
    HalfWord: memSizeString = "HalfWord";
    Byte: memSizeString = "Byte";
    None: memSizeString = "None";
    default: memSizeString = "Unknown";
  endcase
endfunction

// Translate a subset of the MemOp type into a string for debug printouts
function String memOpString(MemOp o);
  case(o)
    Read: memOpString = "Read";
    Write: memOpString = "Write";
    DCacheOp, ICacheOp: memOpString = "CacheOp";
    None: memOpString = "None";
  endcase
endfunction

function Bit#(n) reverseBytes(Bit#(n) x) provisos (Mul#(8,n8,n));
  Vector#(n8,Bit#(8)) vx = unpack(x);
  return pack(Vector::reverse(vx));
endfunction

function Word storeRotate(ControlTokenT c);
  Word data = ?;
  if (c.storeData matches tagged DoubleWord .d) data = d;
  Bit#(3) offset = truncate(c.opA);
  case(c.memSize)
    WordLeft: begin
      data[31:0] = reverseBytes(data[31:0]);
      Bit#(5) shift = {truncate(offset),3'b0};
      data[31:0] = data[31:0] << shift;
      data[31:0] = reverseBytes(data[31:0]);
    end
    WordRight: begin
      data[31:0] = reverseBytes(data[31:0]);
      Bit#(5) shift = {(2'd3 - truncate(offset)),3'b0};
      data[31:0] = data[31:0] >> shift;
      data[31:0] = reverseBytes(data[31:0]);
    end
    DoubleWordLeft: begin
      data = reverseBytes(data);
      Bit#(6) shift = {3'b0,truncate(offset)}*6'h8;
      data = data << shift;
      data = reverseBytes(data);
    end
    DoubleWordRight: begin
      data = reverseBytes(data);
      Bit#(6) shift = (6'd7 - {3'b0,truncate(offset)})*6'h8;
      data = data >> shift;
      data = reverseBytes(data);
    end
  endcase
  return data;
endfunction

// Function to display the contents of a control token in a human readable format.
function Action displayControlToken(ControlTokenT c);
  return action
    if (c.dead) $display("!!! DEAD !!!!");
    $display("PC: %x - %x", c.pc, pack(c.inst)[31:0]);
    $display("Instruction ID: %d, Epoch: %d", c.id, c.epoch);
    if (c.branchDelay) $display("This one is in a branch delay slot.");
    if (c.branch != Never) $display("This is a branch.");
    $display("ALU: %s", aluOpString(c.alu));
    $display("Op A/Result: %X", c.opA);
    $display("Op B: %X", c.opB);
    $display("Write Destination: %X", pack(c.writeDest));
    $write("64-bit: %X, ", pack(c.sixtyFourBitOp));
    $write("Signed Op: %X, ", pack(c.signedOp));  
    $display("Destination Register: %X", c.dest);
    if (c.exception != None) $display("!!! There was an Exception!!! Type: ", fshow(c.exception));
    $write("Memory operation: %s, ", memOpString(c.mem));
    $write("Store data: %X, ", c.storeData);
    $write("Memory size: %s, ", memSizeString(c.memSize));
    $display("Sign Extend: %X", pack(c.signExtendMem));
    $write("Write PC: %X ", c.writePC);
    Address jumpTarget = ?;
    if (c.inst matches tagged Jump .ji)
      jumpTarget = {c.pc[63:28], ji.imm, 2'b0};
    Address target = ?;
    case (c.newPcSource)
      PCUpdate:   target = pack(unpack(c.pc) + signExtend(c.pcUpdate));
      OpB:     target = c.opB;
      Immediate:   target = jumpTarget;
    endcase
    `ifdef MULTI
      $display("coreCount: %d", c.coreCount);
      $display("coreID: %d", c.coreID);
    `endif
    $display("newPC: %X", target);
    $display("Time: %t", $time());
    $display("================================");
  endaction;
endfunction

// The displayTrace function prints a record for an instruction commit.
// This function is meant to produce instruction commit reports for a concise trace of execution.
`ifndef MULTI
function Action displayTrace(ControlTokenT c, MIPSReg writeResult, Bit#(48) instCount);
  return action
    Bit#(64) curTime <- $time;
    Bit#(64) cycles = curTime/10;
    //$display("cyc%5d - %x : %x", cycles, c.pc, pack(c.inst));
    if (!c.dead) begin
      case (c.writeDest)
        RegFile: 
          $write("Reg %d <- %x ", c.dest, writeResult);
        CoPro0:
          if (c.dest != 31)
            $write("CP0 Reg %d <- %x ", c.dest, writeResult);
          else begin
            CP0Inst cp0Inst = unpack(writeResult[5:0]);
            case (cp0Inst)
              RDE: $write("CP0 Read indexed entry");
              WIE: $write("CP0 Write indexed entry");
              WRE: $write("CP0 Write random entry");
              PME: $write("CP0 Probe matching entry");
              ERET: $write("CP0 Exception return");
            endcase
          end
        HiLo:
          $write("Will update Hi and/or Lo");
      endcase
      case (c.mem)
        Read: 
          $write("loaded from address %x", c.opA);
        Write: begin
          Word storeDouble = ?;
          if (c.storeData matches tagged DoubleWord .d) storeDouble = d; 
          RegNum src = ?;
          if (c.inst matches tagged Immediate .ii) src = ii.rt;
          `ifdef USECAP
            else if (c.inst matches tagged Coprocessor .ci) src = unpack(pack(ci.cOp));
          `endif
          case (c.memSize)
            Byte: $display("Address %x <- %x, from Reg %d", c.opA, storeRotate(c)[7:0], src);
            HalfWord: $display("Address %x <- %x, from Reg %d", c.opA, storeRotate(c)[15:0], src);
            Word, WordLeft, WordRight: $display("Address %x <- %x, from Reg %d", c.opA, storeRotate(c)[31:0], src);
            DoubleWord, DoubleWordLeft, DoubleWordRight: $display("Address %x <- %x, from Reg %d", c.opA, storeRotate(c), src);
            `ifdef USECAP
              CapWord: $display("Address %x <-", c.opA, fshow(c.storeData), " from CapReg %d", src);
            `endif
            default: $display("Address %x <- %x, from Reg %d", c.opA, storeRotate(c), src);
          endcase
        end
        None:
          $write("");
      endcase
      $write("\n");
      $display("inst %5d - %x : %x", instCount, c.pc, pack(c.inst));
      if (c.branch != Never || c.branchDelay) begin
        $write("     ");
        if (c.branch != Never) $write("branch ");
        if (c.branchDelay) $write("branch delay slot ");
      end
    end
    if (c.dead) $write("!CANCELED!");
    $write("\n");
    $write("\n");
  endaction;
endfunction
`else
function Action displayTrace(ControlTokenT c, MIPSReg writeResult, Bit#(48) instCount, Bit#(16) coreID);
  return action
    if (!c.dead) begin
      $write("\n");
      Bit#(64) curTime <- $time;
      Bit#(64) cycles = curTime/10;
      //$display("cyc%5d - %x : %x", cycles, c.pc, pack(c.inst));

      case (c.writeDest)
        RegFile: 
          $display("Time:%0d, Core:%0d, Thread:0 :: Reg %d <- %x", curTime, coreID, c.dest, writeResult);
        CoPro0:
          if (c.dest != 31)
            $display("Time:%0d, Core:%0d, Thread:0 :: CP0 Reg %d <- %x", curTime, coreID, c.dest, writeResult);
          else begin
            CP0Inst cp0Inst = unpack(writeResult[5:0]);
            case (cp0Inst)
              RDE: $display("Time:%0d, Core:%0d, Thread:0 :: CP0 Read indexed entry", curTime, coreID);
              WIE: $display("Time:%0d, Core:%0d, Thread:0 :: CP0 Write indexed entry", curTime, coreID);
              WRE: $display("Time:%0d, Core:%0d, Thread:0 :: CP0 Write random entry", curTime, coreID);
              PME: $display("Time:%0d, Core:%0d, Thread:0 :: CP0 Probe matching entry", curTime, coreID);
              ERET: $display("Time:%0d, Core:%0d, Thread:0 :: CP0 Exception return", curTime, coreID);
            endcase
          end
        HiLo:
          $display("Time:%0d, Core:%0d, Thread:0 :: Will update Hi and/or Lo", curTime, coreID);
      endcase

      case (c.mem)
        Read: 
          $display("Time:%0d, Core:%0d, Thread:0 :: loaded from address %x", curTime, coreID, c.opA);
        Write: begin
          Word storeDouble = ?;
          if (c.storeData matches tagged DoubleWord .d) storeDouble = d; 
          RegNum src = ?;
          if (c.inst matches tagged Immediate .ii) src = ii.rt;
          `ifdef USECAP
            else if (c.inst matches tagged Coprocessor .ci) src = unpack(pack(ci.cOp));
          `endif
          case (c.memSize)
            Byte: $display("Time:%0d, Core:%0d, Thread:0 :: Address %x <- %x, from Reg %d", curTime, coreID, c.opA, storeRotate(c)[7:0], src);
            HalfWord: $display("Time:%0d, Core:%0d, Thread:0 :: Address %x <- %x, from Reg %d", curTime, coreID, c.opA, storeRotate(c)[15:0], src);
            Word, WordLeft, WordRight: $display("Time:%0d, Core:%0d, Thread:0 :: Address %x <- %x, from Reg %d", curTime, coreID, c.opA, storeRotate(c)[31:0], src);
            DoubleWord, DoubleWordLeft, DoubleWordRight: $display("Time:%0d, Core:%0d, Thread:0 :: Address %x <- %x, from Reg %d", curTime, coreID, c.opA, storeRotate(c), src);
            `ifdef USECAP
            	CapWord: $display("Time:%0d, Core:%0d, Thread:0 :: Address %x <-", curTime, coreID, c.opA, fshow(c.storeData), " from CapReg %d", src);
            `endif
            default: $display("Time:%0d, Core:%0d, Thread:0 :: Address %x <- %x, from Reg %d", curTime, coreID, c.opA, storeRotate(c), src);
          endcase
        end
      endcase

      $display("Time:%0d, Core:%0d, Thread:0 :: inst %5d - %x : %x", curTime, coreID, instCount, c.pc, pack(c.inst)); 

      if (c.branch != Never || c.branchDelay) begin
        if (c.branch != Never) $display("Time:%0d, Core:%0d, Thread:0 :: branch", curTime, coreID);
        if (c.branchDelay) $display("Time:%0d, Core:%0d, Thread:0 :: branch delay slot", curTime, coreID);
      end
      $write("\n");
    end
  endaction;
endfunction
`endif

// The PcAndEpoch type is returned from the Branch predictor to the main pipeline
typedef struct {
  Address pc;   // The program counter for the next instruction fetch
  Epoch   epoch;// The epoch of this program counter.  This epoch will be placed in the control token
                // and will tell us at the end of the pipeline if it was fetched on a mispredicted branch.
} PcAndEpoch deriving(Bits, Eq, FShow);

// BranchIfc is the interface for the branch predictor unit.  There are several implementations that use this interface.
interface BranchIfc;
  method ActionValue#(PcAndEpoch) getPc(InstId id, Bool fromDebug);
  // Get the next PC in the instruction fetch stage.
  // putTarget reports instruction information from the scheduler/rename stage of the pipeline that can be used to predict the target.
  // The branch type of the instruction, whether it is a likely branch, the current PC, the bits of the instruction, the epoch of the instruction,
  // and whether it includes a link operation are enough to construct most targets (but not register targets) and to make quite intelligent
  // predictions.
  method Action putTarget(BranchType branchType, Bool branchLikely, Address pc, InstructionT instruction, Epoch instEpoch, InstId id, Bool fromDebug, Bool link);
  // pcWriteback is used to deliver a report on the committed branch behaviour of an instruction.  The operands are sufficient
  // to tell the branch unit whether the prediction was a hit or a miss and what the correct target was.
  method Action pcWriteback(Bool dead, Address truePc, Bool doWriteback, Bool exception, Bool fromDebug, Bool taken);
  method Epoch getEpoch(); // report the current epoch of the system.
endinterface  

// PipeStageIfc is a generic interface for the pipeline, and is simply a FIFO interface of ControlTokens.
typedef FIFO#(ControlTokenT) PipeStageIfc;

typedef struct {
  MIPSReg result;
  UInt#(2) renameReg;
} WritebackResult deriving(Bits, Eq, FShow);

// The WritebackIfc interface is the interface of the writeback module which implements the writeback stage of the pipeline.
interface WritebackIfc;
  interface FIFOF#(Bool) getHiLoCommit;
  method Action putCycleCount(Bit#(48) count);
  method ActionValue#(Bool) nextWillCommit();
endinterface

interface CacheInstIfc;
  method Action put(CacheRequestInstT reqIn);
  method ActionValue#(CacheResponseInstT) getRead();
  method Action invalidate(PhyAddress addr);
  method L1ChCfg getConfig();
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef STATCOUNTERS
  interface Get#(ModuleEvents) cacheEvents;
  `endif
endinterface: CacheInstIfc

interface CacheDataIfc;
  method Action put(CacheRequestDataT reqIn);
  method ActionValue#(CacheResponseDataT) getResponse();
  method Action invalidate(PhyAddress addr);
  method ActionValue#(Bool) getInvalidateDone;
  method Action nextWillCommit(Bool committing);
  method L1ChCfg getConfig();
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef STATCOUNTERS
  interface Get#(ModuleEvents) cacheEvents;
  `endif
endinterface: CacheDataIfc

typedef struct {
  CacheOperation cop;
  Bit#(TDiv#(data_width,8)) byteEnable;
  MemSize memSize;
  Line        data;
  `ifdef USECAP
    Bool              capability;
  `endif
  InstId      instId;
  Epoch       epoch;
  TlbResponse tr;
} CacheRequestDataTGeneric#(numeric type data_width) deriving (Bits, Eq, FShow);

typedef CacheRequestDataTGeneric#(CheriDataWidth) CacheRequestDataT;

typedef struct {
  Exception   exception;
  `ifdef USECAP
    Bool           isCap;
  `endif
  Line             data;
  Bool             scResult;
} CacheResponseDataT deriving (Bits, Eq, FShow);

typedef struct {
  Exception   exception;
  `ifdef USECAP
    Bool           isCap;
    Bit#(CapWidth) loadedCap;
  `endif
  Word             data;
  Bool             scResult;
} MemResponseDataT deriving (Bits, Eq, FShow);

// Memory access type.  Note that MemNull used as part of arbiterlock release message.
typedef enum { MemRead, MemWrite, MemNull} MemAccessT deriving(Bits, Eq, FShow);

function InstructionT classifyMIPSInstruction(Bit#(32) instBits);
  InstructionT inst = ?;
  OpCode op = unpack(instBits[31:26]);
  Func func = unpack(instBits[5:0]);
  case (op)
    SPECIAL: begin
      if (func==MOVCI) inst = tagged Coprocessor  unpack(instBits);
      else inst = tagged Register  unpack(instBits);
    end
    SPECIAL2,SPECIAL3,COP0: inst = tagged Register  unpack(instBits);
    COP1,COP2,COP3,LWC1,LDC1,SWC1,SDC1,LWC2,LDC2,SWC2,SDC2:  inst = tagged Coprocessor  unpack(instBits);
    J,JAL,JALX:  inst = tagged Jump      unpack(instBits);
    default:     inst = tagged Immediate unpack(instBits);
  endcase
  return inst;
endfunction

function BytesPerFlit memSizeTobpf(MemSize m);
  return case (m) matches
    Byte: BYTE_1;
    HalfWord: BYTE_2;
    Word:      BYTE_4;
    WordLeft:  BYTE_4;
    WordRight: BYTE_4;
    DoubleWord:      BYTE_8;
    DoubleWordLeft:  BYTE_8;
    DoubleWordRight: BYTE_8; 
    //: BYTE_16;
    `ifdef USECAP
      CapWord: capBytesPerFlit;
    `endif
  endcase;
endfunction

`ifndef BLUESIM
  `define NOPRINTS 1
`endif

function Action debug(Action a);
  action 
    `ifndef NOPRINTS
      Bool debugB <- $test$plusargs("debug");
      if (debugB)
        a;
    `endif
  endaction
endfunction

function Action trace(Action a);
  action 
    `ifndef NOPRINTS
      Bool traceB <- $test$plusargs("trace");
      if (traceB)
        a;
    `endif
  endaction
endfunction

function Action cachedump(Action a); 
  action
    `ifndef NOPRINTS
      Bool cachedumpB <- $test$plusargs("cachedump");
      if (cachedumpB)
        a;
    `endif
  endaction
endfunction

function Action tlbtrace(Action a);
  action 
    `ifndef NOPRINTS
      Bool traceB <- $test$plusargs("tlbTrace");
      if (traceB)
        a;
    `endif
  endaction
endfunction

function Action ctrace(Action a);
  action 
    `ifndef NOPRINTS
      Bool traceB <- $test$plusargs("cTrace");
      if (traceB)
        a;
    `endif
  endaction
endfunction

function Action debugInst(Action a);
  action
    `ifdef BLUESIM
      Bool debugInstB <- $test$plusargs("regDump");
      if (debugInstB)
        a;
    `endif
  endaction
endfunction

