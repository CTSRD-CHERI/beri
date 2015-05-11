/*-
 * Copyright (c) 2013 Bjoern A. Zeeb
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Robert N. M. Watson
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014 Alexandre Joannou
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

import MIPS::*;

import ClientServer::*;
import GetPut::*;
import FIFO::*;
import FIFOF::*;
import ConfigReg::*;
import TLB::*;
import Vector::*;
import Debug::*;

import MemTypes::*;

typedef struct {
  Word   data;
  InstId instId;
} IdWord deriving (Bits, Eq);

typedef struct {
  Exception exception;
  InstId    instId;
} IdExp deriving (Bits, Eq);

typedef struct {
  RegNum regNum;
  Bit#(3) sel;
} C0ProReg deriving (Bits, Eq);

`ifdef NOT_FLAT
  (*synthesize*)
`endif

module mkCP0#(Bit#(16) coreId)(CP0Ifc);
  FIFO#(C0ProReg)  readReqs          <- mkLFIFO;
  FIFOF#(Bool)     tlbReads          <- mkFIFOF;
  FIFOF#(Address)  tlbProbes         <- mkSizedFIFOF(1); // Only one element because this will happen rarely so no need to waste space.
  FIFOF#(Bool)     tlbProbeResponses <- mkUGFIFOF;

  RWire#(Bit#(41)) pteWire           <- mkRWire;
  RWire#(Bit#(31)) xpteWire          <- mkRWire;
  FIFOF#(Bool)     eretHappened      <- mkUGFIFOF1;

  FIFOF#(C0ProReg) rnUpdate          <- mkFIFOF;
  FIFOF#(Word)     dataUpdate        <- mkFIFOF;
  FIFOF#(Bool)     forceUpdate       <- mkFIFOF;
  FIFOF#(void)     expectWrites      <- mkUGSizedFIFOF(4);
  FIFO#(void)      deqExpectWrites   <- mkFIFO;

  //FIFOF#(CauseRegister) causeUpdate0 <- mkUGFIFOF1;
  //FIFOF#(CauseRegister) causeUpdate1 <- mkUGFIFOF1;
  //FIFOF#(bit[7:0])      causeUpdate2 <- mkUGFIFOF1; // For clearing interrupts
  //FIFOF#(bit[7:0])      causeUpdate3 <- mkUGFIFOF1; // For setting interrupts

   `ifdef COP1
     Bool coPro1 = True;
  `else
     Bool coPro1 = False;
  `endif

  StatusRegister defaultSR = StatusRegister{
    ie  : False,    // Global interrupt enable.
    exl : False,    // Set by proc on an exception, forces kernel mode & disables
                    // interrupts until software sets new privilege level and
                    // interrupt mask.
    erl : False,    // Set by proc when it gets bad data.  Not used.
    ksu : 2'b0,     // Current cpu privilege level.  0 = kernel,
                    // 1 = supervisor, 2 = user.
    ux  : True,     // user-mode uses 64-bit addressing and instructions
                    // (different TLB miss entry point).  If ad32in64m is set, you
                    // can use 64-bit instructions but only 32-bit addressing.
    sx  : True,     // supervisor uses 64-bit addressing
                    // (different TLB miss entry point)
    kx  : True,     // kernel uses 64-bit addressing (different TLB miss entry point)
    im  : 8'h00,    // Determines which sources can cause exceptions.
    z0  : 3'b0,     // Set to zero.
    nmi : False,    // Set by proc if a non-maskable interrupt occurred.
    sr  : False,    // Set by proc if a soft reset or a non-maskable interrupt
                    // occurred.
    ts  : False,    // Set by proc if two TLB entries match to prevent proc
                    // damage.  This is not necessary for us.
    bev : True,     // Use ROM (kseg1) for exception entry points.
                    // Normally set to 0 when running.
    px  : False,    // Use 32-bit addressing with 64-bit instructions in user mode.
    mx  : False,    // 0, we don't have an MDMX unit.
    re  : False,    // Currently does nothing!
    `ifdef COP1
      fr  : True,     // The FPU has 64 bit registers if true. False unsupported.
    `else
      fr : False,
    `endif
    rp  : False,    // Does nothing!
    cpEn: CoProEn {
      cu0 : False,  // Allows user-mode to access CP0 instructions!
                    // It is assumed that coprocessor 0 is present.
      cu1 : coPro1, // If FPU is present, give access
      cu2 : False,  // ? Might use for Capabilities ?
      cu3 : coPro1  // We implement a couple of COP1X extensions
    }
  };

  PRId defaultProcID = PRId{
    revsn  : 8'h0, // CPU Revision.  Not used.
    cpuID  : 8'h4, // CPU ID. Use 4=R4000?
    compID : 8'h0, // Company ID. Not important.
    compOp : 8'h0  // Company Options. Not important.
  };

  Config0 defaultConfig0 = Config0{
    c  : Cached,   // Cache algorithm or cache coherency attribute
                   // for multi-processor systems.
    vi : False,    // I-cache is virtually tagged. (False for us I guess?)
    z0 : 3'b000,   // Zeros
    mt : 3'd1,     // MMU type: 0=None, 1=MIPS32/64-compliant TLB,
                   // 2=BAT type, 3=MIPS32-standard FMT fixed mapping
    ar : 3'd0,     // 0=MIPS32/64 release 1, 1=MIPS32/64 release 2
    at : 2'd2,     // 0=MIPS32, 1=MIPS64 inst with MIPS32 address MAP,
                   // 2=MIPS64 inst & address map.
    be : True,     // True if Big endian.
    impl: 15'b0,   // Custom stuff
    m  : True      // Continuation bit. 1 if there is another
                   // configuration register.
  };

  LxChCfg l2ChCfg = LxChCfg{
    ta : 3, // Associativity = A+1.  (A=0 for direct mapped)
    tl : 6, // Cache line size = 2*2^L.  L=0 if there is no cache. (128)
    ts : 1, // Number of Cache index positions is 64 * 2^S. Mult by
            // Associativity for total number of cache lines. (128)
    tu : 3  // Configuration bits.  Could be writeable.
  };

  LxChCfg l3ChCfg = LxChCfg{
    ta : 0, // Associativity = A+1.  (A=0 for direct mapped)
    tl : 0, // Cache line size = 2*2^L.  L=0 if there is no cache. (4)
    ts : 0, // Number of Cache index positions is 64 * 2^S. Mult by
            // Associativity for total number of cache lines. (128)
    tu : 0  // Configuration bits. Could be writeable.
  };

  `ifdef CAP
    Bool coPro2 = True;
  `else
    Bool coPro2 = False;
  `endif

  Config1 defaultConfig1 = Config1{
    fp : coPro1, // True if Floating Point unit is available.
    ep : False,  // True if EJTAG unit is available.
    ca : False,  // True if MIPS16e is available.
    `ifdef NOWATCH
      wr : False,// True if there is at least one watchpoint register.
    `else
      wr : True, // True if there is at least one watchpoint register.
    `endif
    pc : False,  // True if there is at least one performance counter
                 // in the design.
    md : False,  // True if MDMX is implemented in the floating point unit.
    c2 : coPro2, // True if there is a coprocessor 2.
    dCache:?,    // Data cache configuration
    iCache:?,    // Instruction cache configuration
    mmuSize: 15, // Size of the TLB array. (MMU has MMUSize+1 entries)
    m : True     // Continuation bit.  1 if there is another
                 // configuration register.
  };

  Config2 defaultConfig2 = Config2{
    l2ch  : l2ChCfg, // Data (?L2?) cache configuration
    space : False,   // Actually a part of the L2ch SU field.
    l3ch  : l3ChCfg, // Instruction (?) cache configuration
    m     : True     // Continuation bit. 1 if there is another
                     // configuration register.
  };

  Config3 defaultConfig3 = Config3{
    tl    : False, // True if the CPU can record and output instruction
                   // traces.  Advanced feature of EJTAG.
    sm    : False, // True if the CPU supports "SmartMIPS".  We don't.
    mt    : False, // True if the CPU does multithreading, the MIPS MT extension.
    zero1 : False, //
    sp    : False, // True if the CPU supports <4k page sizes.  We don't.
    vInt  : False, // True if the CPU can handle vectored interrupts
    veic  : False, // True if we have an EIC-compatible interrupt controller
    lpa   : False, // True if Large Physical Addressing is available,
                   // ie addresses over 2^36
    zero2 : False, //
    dspp  : False, // True if MIPS DSP extension is implemented
    zero3 : 0,     // 3 bits of zeros
    ulri  : True,
    zero4 : 0,     // 16 bits of zeros
    m     : True   // Continuation bit. 1 if there is another configuration
                   // register. There won't be.
  };

  // This register is inferred from nlm's source code in freeBSD
  Config6 defaultConfig6 = Config6{
    tlbSize : 143,
    zerosB  : 0,
    enableLargeTlb: False,
    zerosA  : 0
  };

  TlbEntryLo defaulttlbEntryLo = TlbEntryLo{
    `ifdef CAP
      noCapLoad : False,
      noCapStore : False,
    `endif
    //zeros : 0,
    pfn : 28'b0,  // Physical address of the page.
    c   : Cached, // Cache algorithm or cache coherency attribute
                  // for multi-processor systems.
    d   : True,   // Dirty - True if writes are allowed.  Writes will
                  // cause exception otherwise.
    v   : True,   // Valid - If False, attempts to use this location cause
                  // an exception.
    g   : False   // Global - If True this entry will match regardless of
                  // ASID.  Both "Lo(G)"s in an odd/even pair should be
                  // identical.
  };

  TlbEntryHi defaultTlbEntryHi = TlbEntryHi{
    r    : 2'b0,  // Address space privilege, which is just the high
                  // order bits of the VPN.
                  // 0=xuseg, 1=sxxeg, 2=xkphys, 3=xkseg
    vpn2 : 27'b0, // Virtual Page Number.  Each Hi entry represents
                  // 2 Lo entries, so the last bit isn't matched.
    asid : 8'b0   // Address Space Identifier.
  };

  Context defaultContext = Context {
    pteBase : 41'b0, // The Base address of the table of virtual
                     // address mappings.
    badVPN2 : 19'b0, // The page address after a TLB exception
                     // (high-order bits of BadVAddr
    zeros   : 4'b0   // Offset by 4 so that this can structure can be
                     // used as a pointer into a table of virtual
                     // address mappings.
  };
  
  // The MIPS specification requires access to registers via rdhwr to be
  // disabled by default.
  HWREna defaultHWREna = HWREna{
    cpunum: False,
    synci_step: False,
    cc: False,
    ccres: False,
    tls: False
  };
  
  

  // 0 : Index into the TLB
  Reg#(Maybe#(Bit#(LogTLBSizePlusOne))) tlbIndex      <- mkReg(tagged Valid 0);
  // 1 : Constantly decrementing pointer into the TLB.
  Reg#(Bit#(LogAssosTLBSize)) tlbRandom <- mkConfigReg(fromInteger(assosTLBSize-1));
  // 2 : Entry Lo of even virtual address of a pair.
  Reg#(TlbEntryLo)      tlbEntryLo0   <- mkConfigReg(defaulttlbEntryLo);
  // 3 : Entry Hi of odd virtual address of a pair.
  Reg#(TlbEntryLo)      tlbEntryLo1   <- mkConfigReg(defaulttlbEntryLo);
  // 4.0 : Low order bits = VPN of failed lookup.
  Reg#(Context)         tlbContext    <- mkReg(defaultContext);
  // 4.1 : 
  Reg#(Address)         tlsPointer    <- mkReg(64'b0);
  // 5 : Used to create bigger-than-4k pages.
  Reg#(Bit#(12))        tlbPageMask   <- mkConfigReg(12'b0);
  Reg#(HWREna)          hwrena        <- mkReg(defaultHWREna);
  // 6 : The TLB location below which all entries are static and not
  //     replacable by random replacement.
  Reg#(Bit#(8))         tlbWired      <- mkConfigReg(0);
  // 8.0 : Virtual Address that Caused Exception
  Reg#(Bit#(64))        badVAddr      <- mkConfigReg(64'b0);
  // 8.1 : Virtual Address that Caused Exception
  Reg#(Bit#(32))        badInst       <- mkConfigReg(32'b0);
  // 9 : Counts up all the time.  R/W but rarely written.
  Reg#(Bit#(32))        count         <- mkConfigReg(32'b0);
  Reg#(Bit#(32))        instCount     <- mkConfigReg(32'b0);
  // 9 sel 6 : Whether tracing is enabled.
  Reg#(Bool)            doTrace       <- mkConfigReg(False);
  // 10: Entry Hi contains the virtual address and space ID for a pair of
  //     virtual addresses.
  Reg#(TlbEntryHi)      tlbEntryHi    <- mkConfigReg(defaultTlbEntryHi);
  // 11: When Compare is written, then when Count==Compare, an interrupt
  //     is raised.  Interrupt cleared when Compare is written again.
  Reg#(Bit#(32))        compare       <- mkConfigReg(32'b0);
  // 12: Status register
  Reg#(StatusRegister)  sr            <- mkConfigReg(defaultSR);
  RWire#(StatusRegister)srWrite       <- mkRWire();
  RWire#(Bool)          srException   <- mkRWire();
  // 13: Cause register
  Reg#(CauseRegister)   cause         <- mkConfigReg(unpack(32'b0));
  // Just the ip field of the cause register broken out to avoid conflicts.
  Reg#(Bit#(8))         causeip       <- mkConfigReg(0);
  RWire#(Bit#(8))       causeipWire   <- mkRWire();
  // 14: Exception Program Counter.  The place to restart after returning
  //     from an exception.
  Reg#(Bit#(64))        epc           <- mkConfigReg(64'b0);
  // 15: Processor ID.
  Reg#(PRId)            procid        <- mkReg(defaultProcID);
  // 15(Shadow Register)
  COREId coreid = COREId {
        coreCount : fromInteger(valueOf(CORE_COUNT) - 1),
        coreID    : coreId
      };

  // 16: Config Register.  See MIPS.bsv for the fields.
  Reg#(Config0)         configReg0    <- mkReg(defaultConfig0);
  Reg#(Config1)         configReg1    <- mkReg(defaultConfig1);
  Reg#(Config2)         configReg2    <- mkReg(defaultConfig2);
  Reg#(Config3)         configReg3    <- mkReg(defaultConfig3);
  Reg#(Config6)         configReg6    <- mkReg(defaultConfig6);
  // 17: Address of the last-run load-linked operation.
  Reg#(Maybe#(Address)) llScReg       <- mkConfigReg(tagged Valid 64'b0);
  // 18: Memory reference trap address low bits
  Reg#(Bit#(32))        watchLo       <- mkReg(32'b0);
  // 19: Memory reference trap address high bits
  Reg#(Bit#(4))         watchHi       <- mkReg(4'b0);
  // 20: Context convenience register for > 32bit address spaces.
  Reg#(XContext)        tlbXContext   <- mkReg(unpack(64'b0));
  // 21-25 are reserved in R4000.
  // 28: TagLo and DataLo registers read from the L1 and L2 caches.
  // DataLo is not implemented as our data lines are 256 and they would not fit. 
  Reg#(Bit#(32))        tagLo         <- mkReg(32'hdeaddead);
  Reg#(Bit#(32))        dataLo        <- mkReg(32'hdeaddead);
  // 29: TagHi and DataHi registers read from the L1 and L2 caches.
  // Both TagHi and DataHi are not implemented as the entire Tag fits in TagLo and
  // the datalines are too large to fit in this field.
  Reg#(Bit#(32))        tagHi         <- mkReg(32'hdeaddead);
  Reg#(Bit#(32))        dataHi        <- mkReg(32'hdeaddead);
  // 30: Error exception program counter
  Reg#(Bit#(64))        errorEPC      <- mkConfigReg(64'b0);

  Reg#(Bit#(5))         exInterrupts  <- mkReg(5'b0);
  Reg#(Bool)       countInstructions  <- mkConfigRegU;

  `ifndef MICRO
    TLBIfc tlb <- mkTLB(coreid.coreID);
  `else
    Vector#(NumTLBLookups, FIFOF#(TlbResponse)) smt_fifos <- replicateM(mkFIFOF);
  `endif

  Bool kernelMode     = sr.ksu == 0 || sr.exl;
  Bool supervisorMode = sr.ksu == 1;

  `ifndef MICRO
    (* descending_urgency = "readTlb, probeCatch, updateCP0Registers, dequeueExpectWrites" *)
    rule readTlb;
      TLBEntryT te <- tlb.readWrite.response.get();
      tlbPageMask <= te.assosEntry.pageMask;
      tlbEntryHi  <= te.assosEntry.entryHi;
      tlbEntryLo0 <= te.entryLo0;
      tlbEntryLo1 <= te.entryLo1;
      tlbReads.deq;
      `ifndef MULTI
        tlbtrace($display("TLB Read of index %d", fromMaybe(0,tlbIndex)));
        tlbtrace($display("     PageMask <- %x", te.assosEntry.pageMask));
        tlbtrace($display("     EntryHi <-  priv:%d vpn:%x asid:%d",
          te.assosEntry.entryHi.r, te.assosEntry.entryHi.vpn2, te.assosEntry.entryHi.asid));
        tlbtrace($display("     EntryLo0 <- pfn:%x cache:%d dirty:%d valid:%d global:%d",
          te.entryLo0.pfn, te.entryLo0.c, te.entryLo0.d, te.entryLo0.v, te.entryLo0.g));
        tlbtrace($display("     EntryLo1 <- pfn:%x cache:%d dirty:%d valid:%d global:%d",
          te.entryLo1.pfn, te.entryLo1.c, te.entryLo1.d, te.entryLo1.v, te.entryLo1.g));
        expectWrites.deq;
      `else
        tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: TLB Read of index %d", $time, coreid.coreID, fromMaybe(0,tlbIndex)));
        tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: PageMask <- %x", $time, coreid.coreID, te.assosEntry.pageMask));
        tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryHi <-  priv:%d vpn:%x asid:%d", $time, coreid.coreID, te.assosEntry.entryHi.r, te.assosEntry.entryHi.vpn2, te.assosEntry.entryHi.asid));
        tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryLo0 <- pfn:%x cache:%d dirty:%d valid:%d global:%d", $time, coreid.coreID, te.entryLo0.pfn, te.entryLo0.c, te.entryLo0.d, te.entryLo0.v, te.entryLo0.g));
        tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryLo1 <- pfn:%x cache:%d dirty:%d valid:%d global:%d", $time, coreid.coreID, te.entryLo1.pfn, te.entryLo1.c, te.entryLo1.d, te.entryLo1.v, te.entryLo1.g));
        expectWrites.deq;
      `endif
    endrule
    
    rule dequeueExpectWrites;
      deqExpectWrites.deq;
      expectWrites.deq;
    endrule
  
    rule reportWiredToTLB;
      tlb.putConfig(tlbRandom, configReg6.enableLargeTlb, tlbEntryHi.asid);
    endrule
  
    rule probeStart;
      tlb.lookup[0].request.put(TlbRequest{
        addr: tlbProbes.first,
        write: False,
        ll: False,
        exception: None,
        fromDebug: False,
        instId: 0
      });
      tlbProbes.deq;
      tlbProbeResponses.enq(True);
      debug($display("TLB Probe Start."));
    endrule
  
    rule probeCatch(tlbProbeResponses.notEmpty);
      TlbResponse tr <- tlb.lookup[0].response.get;
      if (tr.exception != DTLBL) begin
        tlbIndex <= tagged Valid tr.addr[logTLBSize:0];
        `ifndef MULTI
          tlbtrace($display("TLB Probe, Index <- %x", tr.addr));
        `else
          tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: TLB Probe, Index <- %x", $time, coreid.coreID, tr.addr));
        `endif
      end else begin
        tlbIndex <= tagged Invalid;
        `ifndef MULTI
          tlbtrace($display("TLB Probe, Index <- %x0 (Invalid)", {1'b1, 27'h0}));
        `else
          tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: TLB Probe, Index <- %x0 (Invalid)", $time, coreid.coreID, {1'b1, 27'h0}));
        `endif
      end
      tlbProbeResponses.deq;
      expectWrites.deq;
      debug($display("TLB Probe Catch."));
    endrule
  `endif

  // This rule must fire every cycle to ensure we do not drop
  // writes to some registers.
  (*no_implicit_conditions*)
  rule updateContextRegisters_And_Count;
    Bit#(41) pte = fromMaybe(tlbContext.pteBase,pteWire.wget);
    Bit#(31) xpte = fromMaybe(tlbXContext.pteBase,xpteWire.wget);
    // Unconditional updates.
    tlbContext <= Context{
      pteBase: pte,
      badVPN2: badVAddr[31:13],
      zeros:   4'b0
    };
    tlbXContext <= XContext{
      pteBase: xpte,
      r:     badVAddr[63:62],
      badVPN2: badVAddr[39:13],
      zeros: 4'b0
    };
    Bit#(8) newcauseip = fromMaybe(causeip, causeipWire.wget);
    if (count == compare) newcauseip[7] = 1;
    newcauseip[6:2] = exInterrupts;
    causeip <= newcauseip;
    
    StatusRegister srn = sr;
    srn = fromMaybe(srn, srWrite.wget);
    srn.exl = fromMaybe(srn.exl, srException.wget);
    sr <= srn;
  endrule

  rule updateCP0Registers(!tlbReads.notEmpty && !tlbProbeResponses.notEmpty);
    RegNum rn = rnUpdate.first.regNum;
    Bit#(3) sel = rnUpdate.first.sel; rnUpdate.deq;
    Word data = dataUpdate.first; dataUpdate.deq;
    Bool forceKernel = forceUpdate.first; forceUpdate.deq;
    Bool writeIsDone = True;
    debug($display("CP0 register update, register %d, select %d, value 0x%x", rn, sel, data));
    Bit#(8) newcauseip = causeip;
    // Setup values for unconditional updates that may be changed.
    if (kernelMode || forceKernel || sr.cpEn.cu0) begin
      case (rn)
         0: tlbIndex <= tagged Valid data[logTLBSize:0];
         // tlbRandom not writeable?
         2: tlbEntryLo0 <= unpack(truncate({data[63:62],data[33:0]}));
         3: tlbEntryLo1 <= unpack(truncate({data[63:62],data[33:0]}));
         4: begin
          case (sel)
            0: begin
              Context updt = unpack(data);
              //pte = updt.pteBase;
              pteWire.wset(updt.pteBase);
            end
            2: tlsPointer <= data;
          endcase
         end
         5: tlbPageMask <= data[24:13];
         6: begin
            tlbWired <= data[7:0];
         end
         7: begin
            hwrena <= HWREna{
              cpunum: data[0]==1'b1,
              // don't allow synci_step to be enabled, because it isn't
              // implemented.
              synci_step: False, // data[1]==1'b1,
              cc: data[2]==1'b1,
              ccres: data[3]==1'b1,
              tls: data[29]==1'b1
            };
         end
         //8: badVAddr;        badVAddr is read only
         9: begin// count, which is read only and trace
             if (sel == 6)
                 doTrace <= unpack(data[0]);
         end
        10: begin
          tlbEntryHi <= TlbEntryHi{
            r: data[63:62],
            vpn2: data[39:13],
            asid: data[7:0]
          };
        end
        11: begin
          compare <= data[31:0];
          //Bit#(8) updt = cause.ip;
          //updt[7] = 0; // Clear the counter interrupt.
          //causeUpdate2.enq(updt);
          newcauseip[7] = 0;
        end
        12: begin
          StatusRegister updt = unpack(data[31:0]);
          StatusRegister srn = sr;
          srn.bev = updt.bev;  // Changes the default exception entry point to uncached space!  Need to make this work!
          if (updt.ux == False || updt.sx == False || updt.kx == False) begin
            debug($display("Clearing sr.ux, sr.sx and sr.kx are not implemented. Throwing exception."));
            newcauseip[0] = 1;
          end
          //srn.ux = updt.ux;
          //srn.sx = updt.sx;
          //srn.kx = updt.kx;
          srn.sr = updt.sr;
          srn.im = updt.im;
          srn.ksu = updt.ksu;
          srn.ie = updt.ie;
          srn.exl = updt.exl;
          srn.cpEn = updt.cpEn;
          srWrite.wset(srn);
        end
        13: begin
          CauseRegister orig = cause;
          CauseRegister updt = unpack(data[31:0]);
          newcauseip[1:0] = updt.ipDummy[1:0]; // Clear any interrupts that the writer is trying to clear.
          orig.dc = updt.dc; // Stop the count register! (Not implemented.  Only for newer MIPS64s)
          orig.iv = updt.iv; // Write True to get a special exception entry point for interrupts.
          orig.wp = updt.wp; // Write True to get a special exception entry point for interrupts. Not sure the relationship here.
          cause <= orig;
        end
        14: begin
          epc <= data;
        end
        //15: procid;      procid is read only.
        16: begin
          case (sel)
            6: begin
              $display("Set large TLB to %d", data[2]==1'b1);
              configReg6.enableLargeTlb <= data[2]==1'b1;
            end
          endcase
        end
        //17: llAddr;      llAddr is read only.
        18: watchLo <= {data[31:3],1'b0,data[1:0]};
        19: watchHi <= data[3:0];
        20: begin
          XContext updt = unpack(data);
          //xcntxtUpdate.enq(updt.pteBase);
          xpteWire.wset(updt.pteBase);
        end
        23: begin
          $finish;
        end
        25: begin // TLB report.  Custom instruction for dumping TLB state.
          `ifndef MICRO
            debugInst(tlb.debugDump());
          `endif
        end
        27: begin // CP0 register report.  Custom instruction for dumping CP0 state.
          debugInst($display("======   CP0 Registers   ======"));
          Bit#(31) tlbIndexBase = zeroExtend(fromMaybe(?, tlbIndex));
          Bit#(64) idx = signExtend({pack(!isValid(tlbIndex)), tlbIndexBase});
          debugInst($display("[00] Index: 0x%x", idx));
          debugInst($display("[01] Random: 0x%x", tlbRandom));
          debugInst($display("[02] EntryLo0: 0x%x", tlbEntryLo0));
          debugInst($display("[03] EntryLo1: 0x%x", tlbEntryLo1));
          //debugInst($display("[04] Context: 0x%x", tlbContext));
          debugInst($display("[05] PageMask: 0x%x", {tlbPageMask,13'b0}));
          debugInst($display("[06] Wired: 0x%x", tlbWired));
          debugInst($display("[08] BadVAddr: 0x%x", badVAddr));
          debugInst($display("[08.1] BadInst: 0x%x", badInst));
          //debugInst($display("[09] Count: %x", count));
          debugInst($display("[10] EntryHi: 0x%x", tlbEntryHi));
          debugInst($display("[11] Compare: 0x%x", compare));
          debugInst($display("[12] SR (Status): 0x%x", sr));
          CauseRegister causeReturn = cause;
          causeReturn.ipDummy = causeip;
          debugInst($display("[13] Cause: 0x%x", causeReturn));
          debugInst($display("[14] EPC: 0x%x", epc));
          debugInst($display("[15] PRId: 0x%x", procid));
          debugInst($display("[16] Config: 0x%x", configReg0));
          //debugInst($display("[17] LLAddr: 0x%x", llScReg));
          debugInst($display("[18] WatchLo: 0x%x", watchLo));
          debugInst($display("[19] WatchHi: 0x%x", watchHi));
          //debugInst($display("[20] XContext: 0x%x", tlbXContext));
          debugInst($display("[30] ErrorEPC: 0x%x", errorEPC));
        end
        28: begin
          case (sel)
            0: tagLo <= data[31:0];
            1: dataLo <= data[31:0]; // Not Implemented
          endcase
        end
        29: begin
          case (sel)
            0: tagHi <= data[31:0];  // Not Implemented
            1: dataHi <= data[31:0]; // Not Implemented 
          endcase
        end
        30: errorEPC <= data;
        31: begin
          CP0Inst cp0Inst = unpack(data[5:0]);
          case (cp0Inst)
            `ifndef MICRO
              RDE: begin// Read indexed entry
                TLBEntryT te = TLBEntryT{
                  write: False,
                  random: False,
                  tlbAddr: fromMaybe(?, tlbIndex),
                  assosEntry: ?,
                  entryLo0: ?,
                  entryLo1: ?
                };
                tlb.readWrite.request.put(te);
                debug($display("CP0 tlb read"));
                tlbReads.enq(True);
                // Tell the pipeline we're waiting for an update.
                writeIsDone = False;
              end
              WIE: begin // Write indexed entry
                TLBEntryT te = TLBEntryT{
                  write: True,
                  random: False,
                  tlbAddr: fromMaybe(?, tlbIndex),
                  assosEntry: TlbAssosEntry{
                    entryHi: tlbEntryHi,
                    whichLoBit: 12-pack(countZerosMSB(tlbPageMask)),
                    valid: True,      // Always valid for a stored entry.  Will be returned invalid if there is no entry.
                    pageMask: tlbPageMask,      // The page mask register determines the page size
                    g: (tlbEntryLo0.g && tlbEntryLo1.g)  // Global.  This virtual address maps in all spaces.
                  },
                  entryLo0: tlbEntryLo0,
                  entryLo1: tlbEntryLo1
                };
                `ifndef MULTI
                  tlbtrace($display("TLB Write Indexed to index %d", fromMaybe(0,tlbIndex)));
                  tlbtrace($display("     PageMask: %x", tlbPageMask));
                  tlbtrace($display("     EntryHi:  priv:%d vpn:%x asid:%d", tlbEntryHi.r, tlbEntryHi.vpn2, tlbEntryHi.asid));
                  tlbtrace($display("     EntryLo0: pfn:%x cache:%d dirty:%d valid:%d global:%d", tlbEntryLo0.pfn, tlbEntryLo0.c, tlbEntryLo0.d, tlbEntryLo0.v, tlbEntryLo0.g));
                  tlbtrace($display("     EntryLo1: pfn:%x cache:%d dirty:%d valid:%d global:%d", tlbEntryLo1.pfn, tlbEntryLo1.c, tlbEntryLo1.d, tlbEntryLo1.v, tlbEntryLo1.g));
                `else
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: TLB Write Indexed to index %d", $time, coreid.coreID, fromMaybe(0,tlbIndex)));
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: PageMask: %x", $time, coreid.coreID, tlbPageMask));
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryHi:  priv:%d vpn:%x asid:%d", $time, coreid.coreID, tlbEntryHi.r, tlbEntryHi.vpn2, tlbEntryHi.asid));
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryLo0: pfn:%x cache:%d dirty:%d valid:%d global:%d", $time, coreid.coreID, tlbEntryLo0.pfn, tlbEntryLo0.c, tlbEntryLo0.d, tlbEntryLo0.v, tlbEntryLo0.g));
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryLo1: pfn:%x cache:%d dirty:%d valid:%d global:%d", $time, coreid.coreID, tlbEntryLo1.pfn, tlbEntryLo1.c, tlbEntryLo1.d, tlbEntryLo1.v, tlbEntryLo1.g));
                `endif
                if (isValid(tlbIndex)) tlb.readWrite.request.put(te);
              end
              WRE: begin // Write random entry
                Bit#(LogTLBSize) hashKey = tlbEntryHi.vpn2[logTLBSize-1:0]-fromInteger(assosTLBSize);
                Bit#(LogTLBSizePlusOne) tlbAddr = zeroExtend(hashKey)+fromInteger(assosTLBSize);
                if (!configReg6.enableLargeTlb || tlbPageMask!=0) tlbAddr = zeroExtend(tlbRandom);
                TLBEntryT te = TLBEntryT{
                  write: True,
                  random: True,
                  tlbAddr: tlbAddr,
                  assosEntry: TlbAssosEntry{
                    entryHi: tlbEntryHi,
                    whichLoBit: 12-pack(countZerosMSB(tlbPageMask)),
                    valid: True,      // Always valid for a stored entry.  Will be returned invalid if there is no entry.
                    pageMask: tlbPageMask,      // The page mask register determines the page size
                    g: (tlbEntryLo0.g && tlbEntryLo1.g)      // Global.  This virtual address maps in all spaces.
                  },
                  entryLo0: tlbEntryLo0,
                  entryLo1: tlbEntryLo1
                };
                `ifndef MULTI 
                  tlbtrace($display("TLB Write Random to index %d", te.tlbAddr));
                  tlbtrace($display("     PageMask: %x", 0));
                  tlbtrace($display("     EntryHi:  priv:%d vpn:%x asid:%d", tlbEntryHi.r, tlbEntryHi.vpn2, tlbEntryHi.asid));
                  tlbtrace($display("     EntryLo0: pfn:%x cache:%d dirty:%d valid:%d global:%d", tlbEntryLo0.pfn, tlbEntryLo0.c, tlbEntryLo0.d, tlbEntryLo0.v, tlbEntryLo0.g));
                  tlbtrace($display("     EntryLo1: pfn:%x cache:%d dirty:%d valid:%d global:%d", tlbEntryLo1.pfn, tlbEntryLo1.c, tlbEntryLo1.d, tlbEntryLo1.v, tlbEntryLo1.g));
                `else
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: TLB Write Random to index %d", $time, coreid.coreID, te.tlbAddr));
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: PageMask: %x", $time, coreid.coreID, 0));
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryHi:  priv:%d vpn:%x asid:%d", $time, coreid.coreID, tlbEntryHi.r, tlbEntryHi.vpn2, tlbEntryHi.asid));
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryLo0: pfn:%x cache:%d dirty:%d valid:%d global:%d", $time, coreid.coreID, tlbEntryLo0.pfn, tlbEntryLo0.c, tlbEntryLo0.d, tlbEntryLo0.v, tlbEntryLo0.g));
                  tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: EntryLo1: pfn:%x cache:%d dirty:%d valid:%d global:%d", $time, coreid.coreID, tlbEntryLo1.pfn, tlbEntryLo1.c, tlbEntryLo1.d, tlbEntryLo1.v, tlbEntryLo1.g));
                `endif
                tlb.readWrite.request.put(te);
                // Update the random register.  It's not that random, it just decrements once
                // for every write.  Incrementing continually allows patterns that cause bad cycles and no progress.
                if (tlbRandom != tlbWired[logAssosTLBSize-1:0]) tlbRandom <= tlbRandom - 1;
                else tlbRandom <= fromInteger(assosTLBSize-1); // The top entry in the tlb.
              end
              PME: begin // Probe matching entry
                tlbProbes.enq({tlbEntryHi.r,22'b0,tlbEntryHi.vpn2, 13'b0});
                // Tell the pipeline we're waiting for an update.
                writeIsDone = False;
              end
            `endif
            ERET: begin // Exception Return
              if (!sr.erl) begin // er.erl should always be False...
                StatusRegister srn = sr;
                srn.exl = False; // Clear sr.exl, the exception level flag.
                srWrite.wset(srn);
                if (!eretHappened.notEmpty) eretHappened.enq(True);  // signal llSc to clear.
                //debug($display("eret Happened!"));
              end
            end
          endcase
        end
        //default:        no default action.
      endcase
      if (writeIsDone) expectWrites.deq;
    end
    causeipWire.wset(newcauseip);
  endrule

  method Action readReq(RegNum rn, Bit#(3) sel);
    readReqs.enq(C0ProReg{regNum: rn, sel: sel});
    debug($display("CP0 read in"));
  endmethod

  method Bool writePending;
    return (expectWrites.notEmpty || tlbProbeResponses.notEmpty || tlbReads.notEmpty);
  endmethod

  // readGet gets the result of a read.
  // We block when we are waiting for a probe response since it can take longer than the standard TLB operation.
  method ActionValue#(Word) readGet(Bool goingToWrite);// if (!tlbProbeResponses.notEmpty);
    if (goingToWrite) expectWrites.enq(?);
    RegNum regNum = readReqs.first.regNum();
    Bit#(3) sel = readReqs.first.sel();
    readReqs.deq;
    Bit#(64) rv = ?;
    debug($display("CP0 read out"));
    Bit#(31) tlbIndexBase = zeroExtend(fromMaybe(0,tlbIndex));
    case (regNum)
      0: rv = signExtend({pack(!isValid(tlbIndex)), tlbIndexBase});
      1: rv = zeroExtend(tlbRandom);
      `ifdef CAP
        2: rv = {pack(tlbEntryLo0)[35:34],28'b0,pack(tlbEntryLo0)[33:0]};
        3: rv = {pack(tlbEntryLo1)[35:34],28'b0,pack(tlbEntryLo1)[33:0]};
      `else
        2: rv = zeroExtend(pack(tlbEntryLo0)[33:0]);
        3: rv = zeroExtend(pack(tlbEntryLo1)[33:0]);
      `endif
      4: begin
        case (sel)
          0: rv = pack(tlbContext);
          2: rv = tlsPointer;
          default: rv = 0;
        endcase
      end
      5: rv = zeroExtend({tlbPageMask,13'b0});
      6: rv = zeroExtend(tlbWired);
      7: begin
        rv = 0;
        rv[0] = pack(hwrena.cpunum);
        rv[1] = pack(hwrena.synci_step);
        rv[2] = pack(hwrena.cc);
        rv[3] = pack(hwrena.ccres);
        rv[29] = pack(hwrena.tls);
      end
      8: begin
        case (sel)
          0: rv = badVAddr;
          1: rv = zeroExtend(badInst);
          default: rv = 0;
        endcase
      end
      9: rv = zeroExtend(count);
      10: begin
        rv = {tlbEntryHi.r,22'b0,tlbEntryHi.vpn2,5'b0,tlbEntryHi.asid};
      end
      11: rv = zeroExtend(compare);
      12: rv = zeroExtend(pack(sr));
      13: begin
        CauseRegister causeReturn = cause;
        causeReturn.ipDummy = causeip;
        rv = zeroExtend(pack(causeReturn));
      end
      14: rv = epc;
      15: begin
        case (sel)
          0: rv = zeroExtend(pack(procid));
// ADDED BACK IN FOR BACKWARDS COMPATABILITY WITH OLD FREEBSD KERNELS >>>
          1: rv = zeroExtend(pack(coreid));
          2: rv = 0; // thread ID
// NEEDS TO BE REMOVED LATER<<<
          6: rv = zeroExtend(pack(coreid));
          7: rv = 0; // thread ID
          default: rv = zeroExtend(pack(procid));
        endcase
      end
      16: begin
        case (sel)
          0: rv = zeroExtend(pack(configReg0));
          1: rv = zeroExtend(pack(configReg1));
          2: rv = zeroExtend(pack(configReg2));
          3: rv = zeroExtend(pack(configReg3));
          4: rv = 1;
          5: rv = 1;
          6: rv = zeroExtend(pack(configReg6));
          default: rv = 64'b0;
        endcase
      end
      17: rv = fromMaybe(?,llScReg);
      18: rv = zeroExtend(watchLo);
      19: rv = zeroExtend(watchHi);
      20: rv = pack(tlbXContext);
      28: begin
        case (sel)
          0: rv = zeroExtend(tagLo);
          1: rv = zeroExtend(dataLo); // Not Implemented
          default: rv = 64'b0;
        endcase
      end
      29: begin
        case (sel)
          0: rv = zeroExtend(tagHi);  // Not Implemented
          1: rv = zeroExtend(dataHi); // Not Implemented
          default: rv = 64'b0;
        endcase
      end
      30: rv = errorEPC;
      default: rv = 64'b0;
    endcase
    return (rv);
  endmethod

  method Action writeReg(RegNum rn, Bit#(3) sel, Word data, Bool forceKernelMode, Bool writeBack) if (rnUpdate.notFull && dataUpdate.notFull);
    if (writeBack) begin
      rnUpdate.enq(C0ProReg{regNum:rn, sel: sel});
      dataUpdate.enq(data);
      forceUpdate.enq(forceKernelMode);
      debug($display("CP0 write"));
    end else begin
      deqExpectWrites.enq(?);
      debug($display("CP0 didn't write"));
    end
  endmethod

  method Cp0ExceptionReport getException();
    Cp0ExceptionReport expRpt = Cp0ExceptionReport{
      exception:None,
      bev: sr.bev,
      exl: sr.exl
    };

    // If we didn't get an exception yet but an interrupt is triggered and
    // we're listening to interrupts and we're not in interrupt mode already.
    //debug($display("Interrupt check. cause.ip=%x(&)sr.im=%x(!=0), sr.ie=%x(1), sr.exl=%x(0)", cause.ip, sr.im, sr.ie, sr.exl));
    if ((causeip & sr.im) != 0 && sr.ie == True && sr.exl == False)
      expRpt.exception = Int;
    if (sr.sr && sr.exl == False) expRpt.exception = NMI; // This is probably a software reset!  Highest priority!
    return (expRpt);
  endmethod

  method Action putException(ExceptionWriteback exp, Address ivaddr, MIPSReg dvaddr);
    Address badVaddr = 64'b0;
    if (exp.exception == ITLB || exp.exception == ITLBI || exp.exception == IADEL) begin
      badVaddr = ivaddr;
    end
    if (exp.exception == DTLBL || exp.exception == DTLBLI || 
            exp.exception == DTLBS || exp.exception == DTLBSI || 
            exp.exception == CTLBS || 
            exp.exception == Mod || exp.exception == DADEL || 
            exp.exception == DADES) begin
      badVaddr = dvaddr;
    end
    if (exp.exception != None && !exp.dead) begin
      CauseRegister cr = cause;
      cr.excCode = getExceptionCode(exp.exception);
      cr.bd = exp.branchDelay;
      case (exp.exception)
        CP0: cr.ce = 0;
        CP1: cr.ce = 1;
        CP2: cr.ce = 2;
        CP3: cr.ce = 3;
        default: cr.ce = 0;
      endcase
      //causeUpdate1.enq(cr);
      cause <= cr;
      badInst <= exp.instruction;
      srException.wset(True);
      // Error exceptions, NMI, (Soft) Reset, and Cache error (unused),
      // expect the VAddr in errorEPC, not EPC as everything else.
      if (exp.exception == NMI /* || cacheErr */)
        errorEPC <= exp.victim;
      else
        epc <= exp.victim;
      case(exp.exception)
        ITLB, ITLBI, DTLBL, DTLBS, DTLBLI, DTLBSI, CTLBS, 
                Mod, IADEL, DADEL, DADES: begin
          `ifdef MULTI
            trace($display("Time:%0d, Core:%0d, Thread:0 :: Bad virtual address: %x", $time, coreid.coreID, badVaddr));
          `else
            trace($display("Bad virtual address: %x", badVaddr));
          `endif
          badVAddr <= badVaddr;
          tlbEntryHi <= TlbEntryHi{
            r: badVaddr[63:62],
            vpn2: badVaddr[39:13],
            asid: tlbEntryHi.asid
          };
        end
      endcase
    end
    if (exp.exception == None && !exp.dead) instCount <= instCount + 1;
  endmethod

  method Action interrupts(Bit#(5) interruptLines);
    exInterrupts <= interruptLines;
  endmethod

  `ifndef MICRO
    interface Server tlbLookupInstruction;
      interface Put request;
        method Action put(reqIn);
          tlb.lookup[1].request.put(reqIn);
          debug($display("Instruction TLB Request %x. At time %d", reqIn.addr, $time));
        endmethod
      endinterface
      interface Get response;
        method get();
          actionvalue
            TlbResponse retVal <- tlb.lookup[1].response.get();
            debug($display("Instruction TLB Testing Watch. Address=%x. Watch=%x. Read Flag=%d", retVal.addr[35:0], {watchHi,watchLo[31:3],3'b0}, watchLo[1]==1'b1));
            if (!kernelMode) begin
              if (retVal.priv==Kernel) retVal.exception = IADEL;
              else if (retVal.priv == Supervisor && !supervisorMode) retVal.exception = IADEL;
            end
            if (retVal.addr[35:0] == {watchHi,watchLo[31:3],3'b0} && watchLo[1]==1'b1) begin
              if (retVal.exception == None) retVal.exception = Watch;
            end
            debug($display("Instruction TLB Response. Exception=%d. At time %d", retVal.exception!=None, $time));
            return retVal;
          endactionvalue
        endmethod
      endinterface
    endinterface
  
    interface Server tlbLookupData;
      interface Put request;
        method Action put(reqIn);
          tlb.lookup[2].request.put(reqIn);
        endmethod
      endinterface
      interface Get response;
        method get();
          actionvalue
            TlbResponse retVal <- tlb.lookup[2].response.get();
            if (!kernelMode && !retVal.fromDebug) begin// && retVal.exception==None) begin
              if (retVal.priv==Kernel) retVal.exception = (retVal.write) ? DADES : DADEL;
              else if (retVal.priv == Supervisor && !supervisorMode) retVal.exception = (retVal.write) ? DADES : DADEL;
            end
  
            if (retVal.addr[35:0] == {watchHi,watchLo[31:3],3'b0} &&     // If there has not been an exception and the address matches
              ((watchLo[1]==1'b1 && !retVal.write) || (watchLo[0]==1'b1 && retVal.write))) begin  // and the address is watching for a read or a write and the operation matches.
              if (retVal.exception == None) retVal.exception = Watch;
            end
            return retVal;
          endactionvalue
        endmethod
      endinterface
    endinterface
  `else                        
    interface Server tlbLookupInstruction;
      interface Put request;
        method Action put(reqIn);
          TlbResponse simpleResponse = TlbResponse{
            addr: ?,
            exception: None,
            write:reqIn.write,
            ll:reqIn.ll,
            cached:True,
            fromDebug:reqIn.fromDebug,
            priv:Kernel,
            instId:reqIn.instId
          };
          if (reqIn.addr[63:56] == 8'h90 || (reqIn.addr[63:32] == 32'hFFFFFFFF && reqIn.addr[31:29] == 3'b101)) begin
            simpleResponse.cached = False;
          end
          if (reqIn.addr[63:32] == 32'hFFFFFFFF && (reqIn.addr[31:29] == 3'b100 || reqIn.addr[31:29] == 3'b101)) begin // Simple translation for the kseg1 & kseg0 regions which map into 512MB of physical memory.
            simpleResponse.addr = {11'b0,reqIn.addr[28:0]};
            smt_fifos[0].enq(simpleResponse); // Shave off the top 35 bits...
          end else begin // Simple translation for the xkphys regions which map into physical memory.
            simpleResponse.addr = reqIn.addr[39:0];
            smt_fifos[0].enq(simpleResponse); // Just shave off the top bits...
          end
          debug($display("Instruction TLB Request %x. At time %d", reqIn.addr, $time));
        endmethod
      endinterface
      interface Get response;
        method ActionValue#(TlbResponse) get();
          TlbResponse retVal = smt_fifos[0].first();
          smt_fifos[0].deq;
          debug($display("Instruction TLB Response. Exception=%d. At time %d", retVal.exception != None, $time));
          return retVal;
        endmethod
      endinterface
    endinterface
  
    interface Server tlbLookupData;
      interface Put request;
        method Action put(reqIn);
          TlbResponse simpleResponse = TlbResponse{
            addr: ?,
            exception: None,
            write:reqIn.write,
            ll:reqIn.ll,
            cached:True,
            fromDebug:reqIn.fromDebug,
            priv:Kernel,
            instId:reqIn.instId
          };
          if (reqIn.addr[63:56] == 8'h90 || (reqIn.addr[63:32] == 32'hFFFFFFFF && reqIn.addr[31:29] == 3'b101)) begin
            simpleResponse.cached = False;
          end
          if (reqIn.addr[63:32] == 32'hFFFFFFFF && (reqIn.addr[31:29] == 3'b100 || reqIn.addr[31:29] == 3'b101)) begin // Simple translation for the kseg1 & kseg0 regions which map into 512MB of physical memory.
            simpleResponse.addr = {11'b0,reqIn.addr[28:0]};
            smt_fifos[1].enq(simpleResponse); // Shave off the top 35 bits...
          end else begin // Simple translation for the xkphys regions which map into physical memory.
            simpleResponse.addr = reqIn.addr[39:0];
            smt_fifos[1].enq(simpleResponse); // Just shave off the top bits...
          end
        endmethod
      endinterface
      interface Get response;
        method ActionValue#(TlbResponse) get();
          TlbResponse retVal = smt_fifos[1].first();
          smt_fifos[1].deq;
          return retVal;
        endmethod
      endinterface
    endinterface
  `endif

  method ActionValue#(Bool) setLlScReg(Address matchAddress, Bool link, Bool store);
    Maybe#(Address) newLlSc = llScReg;
    if (link) begin
      newLlSc = tagged Valid zeroExtend(matchAddress[56:0]);
      debug($display("%d: Setting Load Linked register to:%x", $time, matchAddress));
    end
    if ((isValid(llScReg) && (matchAddress[11:0] == fromMaybe(?,llScReg)[11:0]) &&
            store) || eretHappened.notEmpty) begin
      newLlSc = tagged Invalid;
      if (eretHappened.notEmpty) eretHappened.deq;
      debug($display("%d: Invalidating Load Linked Register:%x==%x", $time, matchAddress, fromMaybe(64'h9999999999999999,llScReg)));
    end
    llScReg <= newLlSc;
    if (isValid(llScReg) && fromMaybe(?,llScReg)[11:0] == matchAddress[11:0] && !eretHappened.notEmpty) return True;
    else return False;
  endmethod

  method CoProEn getCoprocessorEnables();
    CoProEn cpEn = sr.cpEn;
    cpEn.cu0 = kernelMode || sr.cpEn.cu0;
    `ifdef COP1
      // If the floating point unit is here, tie cp3 enable to cp1 enable.
      cpEn.cu3 = cpEn.cu1;
    `endif
    return cpEn;
  endmethod
  
  method HWREna getHardwareRegisterEnables();
    return hwrena;
  endmethod

  method Bit#(8) getAsid();
    return tlbEntryHi.asid;
  endmethod

  method Action putCacheConfiguration(L1ChCfg iCacheConfig, L1ChCfg dCacheConfig);
    Config1 newCfg1 = configReg1;
    newCfg1.iCache = iCacheConfig;
    newCfg1.dCache = dCacheConfig;
    configReg1 <= newCfg1;
  endmethod

  method Action putDeterministicCycleCount(Bool shouldCountInstructions);
    // The plusarg takes precendence
    let plusArg <- $test$plusargs("instructionBasedCycleCounter");
    countInstructions <= shouldCountInstructions || plusArg;
  endmethod

  method Bool shouldTrace();
    return doTrace;
  endmethod
  
  method Action putCount(Bit#(32) commonCount);
    count <= (countInstructions) ? instCount:commonCount;
  endmethod

  `ifdef DMA_VIRT
      interface tlbs = takeAt(3, tlb.lookup);
  `endif

endmodule
