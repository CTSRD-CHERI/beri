/*-
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Robert N. M. Watson
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
import Vector::*;

typedef struct {
  Word   data;
  InstId instId;
} IdWord deriving (Bits, Eq);

typedef struct {
  Exception exception;
  InstId    instId;
} IdExp deriving (Bits, Eq);

typedef struct {
  RegNum  regNum;
  Bit#(3) sel;
} C0ProReg deriving (Bits, Eq);

PRId defaultProcID = PRId{
  revsn:  8'h0, // CPU Revision. Not used.
  cpuID:  8'h4, // CPU ID. Use 4=R4000?
  compID: 8'h0, // Company ID. Not important.
  compOp: 8'h0  // Company Options. Not important.
};

COREId defaultCoreID = COREId{
  coreCount : 16'b0, // Zero value is interpreted as one core
  coreID    : 16'b0  // Set core to zero by default
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

`ifdef COP1
  Bool coPro1 = True;
`else
  Bool coPro1 = False;
`endif

`ifdef CAP
  Bool coPro2 = True;
`else
  Bool coPro2 = False;
`endif

  Config1 defaultConfig1 = Config1{
    fp : coPro1, // True if Floating Point unit is available.
    ep : False,  // True if EJTAG unit is available.
    ca : False,  // True if MIPS16e is available.
    wr : True,   // True if there is at least one watchpoint register.
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

  LxChCfg l2ChCfg = LxChCfg{
    ta : 0, // Associativity = A+1.  (A=0 for direct mapped)
    tl : 4, // Cache line size = 2*2^L.  L=0 if there is no cache. (32)
    ts : 8, // Number of Cache index positions is 64 * 2^S. Mult by
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
    m     : False  // Continuation bit. 1 if there is another configuration
                   // register.
  };

StatusRegister defaultSR = StatusRegister{
  ie  : False, // Global interrupt enable.
  exl : False, // Set by proc on an exception, forces kernel mode & disables
               // interrupts until software sets new privilege level and interrupt
               // mask.
  erl : False, // Set by proc when it gets bad data. Not used.
  ksu : 2'b0,  // Current cpu privilege level. 0 = kernel, 1 = supervisor, 2 = user.
  ux  : True,  // User-mode uses 64-bit addressing and instructions (different TLB
               // miss entry point). If ad32in64m is set, you can use 64-bit
               // instructions but only 32-bit addressing.
  sx  : True,  // Supervisor uses 64-bit addressing (different TLB miss entry point)
  kx  : True,  // Kernel uses 64-bit addressing (different TLB miss entry point)
  im  : 8'h00, // Determines which sources can cause exceptions.
  z0  : 3'b0,  // Set to zero.
  nmi : False, // Set by proc if a non-maskable interrupt occurred.
  sr  : False, // Set by proc if a soft reset or a non-maskable interrupt occurred.
  ts  : False, // Set by proc if two TLB entries match to prevent proc damage.
               // This is not necessary for us.
  bev : True,  // Use ROM (kseg1) for exception entry points. Normally set to 0
               // when running.
  px  : False, // Use 32-bit addressing with 64-bit instructions in user mode.
  mx  : False, // 0, we don't have an MDMX unit.
  re  : False, // Currently does nothing!
  fr  : True,  // FPU has 64 bit registers.
  rp  : False, // Does nothing!
  cpEn: CoProEn{
    cu0 : False,  // Allows user-mode to access CP0 instructions! It is assumed that
                  // coprocessor 0 is present.
    cu1 : coPro1, // FPU
    cu2 : False,  // ? Might use for Capabilities ?
    cu3 : coPro1  // FPU overflow
  }
};

`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkCP0Micro(CP0Ifc);
  FIFO#(C0ProReg)       readReqs      <- mkLFIFO;
  FIFOF#(Exception)     counterInt    <- mkUGFIFOF; // Counter interrupt

  FIFOF#(Bool)          eretHappened  <- mkUGFIFOF1;

  Vector#(NumTLBLookups, FIFOF#(TlbResponse))
                        smt_fifos     <- replicateM(mkFIFOF);
  
  
  FIFOF#(C0ProReg)      rnUpdate      <- mkFIFOF;
  FIFOF#(Word)          dataUpdate    <- mkFIFOF;
  FIFOF#(Bool)          forceUpdate   <- mkFIFOF;
  FIFOF#(Bool)          expectWrites  <- mkUGFIFOF;
  FIFO#(void)           deqExpectWrites <- mkFIFO;

  Reg#(Bit#(64))        badVAddr      <- mkConfigRegU; // 8 : Virtual Address that Caused Exception
  Reg#(Bit#(32))        count         <- mkConfigReg(32'b0); // 9 : Counts up all the time. R/W but rarely written.
  Reg#(Bit#(32))        compare       <- mkReg(?); // 11: When Compare is written, then when Count==Compare, an interrupt is raised. Interrupt cleared when Compare is written again.
  Reg#(StatusRegister)  sr            <- mkConfigReg(defaultSR); // 12: Status register
  Reg#(CauseRegister)   cause         <- mkConfigReg(unpack(32'b0)); // 13: Cause register
  Reg#(Bit#(8))         causeip       <- mkConfigReg(0); // Just the ip field of the cause register broken out to avoid conflicts.
  Reg#(Bit#(64))        epc           <- mkConfigRegU; // 14: Exception Program Counter. The place to restart after returning from an exception.
  Reg#(PRId)            procid        <- mkReg(defaultProcID); // 15: Processor ID.
  Reg#(COREId)          coreid        <- mkReg(defaultCoreID);
  Reg#(Config0)         configReg0    <- mkReg(defaultConfig0);
  Reg#(Config1)         configReg1    <- mkReg(defaultConfig1);
  Reg#(Config2)         configReg2    <- mkReg(defaultConfig2);
  Reg#(Config3)         configReg3    <- mkReg(defaultConfig3);
  // Reg#(Config6)         configReg6    <- mkReg(defaultConfig6);
  Reg#(Maybe#(Address)) llScReg       <- mkConfigReg(tagged Valid 64'b0); // 17: Address of the last-run load-linked operation.
  Reg#(Bit#(64))        errorEPC      <- mkReg(64'b0); // 30: Error exception program counter

  Reg#(Bit#(5))         exInterrupts  <- mkReg(5'b0);
  Reg#(Bool) deterministicCycleCount  <- mkConfigRegU;

  Bool kernelMode     = sr.ksu == 0 || sr.exl;
  Bool supervisorMode = sr.ksu == 1;

  rule updateContextRegisters_And_Count;
    if (cause.dc == False && !deterministicCycleCount) begin
      count <= count + 1;
    end
    if (count == compare) begin
      causeip[7] <= 1;
    end
  endrule

  rule updateCP0Registers;
    RegNum rn = rnUpdate.first.regNum;
    Bit#(3) sel = rnUpdate.first.sel; rnUpdate.deq;
    Word data = dataUpdate.first; dataUpdate.deq;
    Bool forceKernel = forceUpdate.first; forceUpdate.deq;
    Bit#(8) newcauseip = causeip;
    debug($display("CP0 register update"));
    case (rn)
      11: begin
        compare <= data[31:0];
        newcauseip[7] = 0;
      end
      12: begin
        StatusRegister updt = unpack(data[31:0]);
        StatusRegister srn = sr;
        srn.bev = updt.bev; // Changes the default exception entry point to uncached space! Need to make this work!
        if (updt.ux == False || updt.sx == False || updt.kx == False) begin
          debug($display("Clearing sr.ux, sr.sx and sr.kx are not implemented. Throwing exception."));
          newcauseip[0] = 1;
        end
        //srn.ux = updt.ux;
        //srn.sx = updt.sx;
        //srn.kx = updt.kx;
        srn.sr = updt.sr; //XXX ndave
        srn.im = updt.im;
        srn.ksu = updt.ksu;
        srn.ie = updt.ie;
        srn.exl = updt.exl;
        srn.cpEn = updt.cpEn;
        sr <= srn;
      end
      13: begin
          CauseRegister orig = cause;
          CauseRegister updt = unpack(data[31:0]);
          newcauseip[1:0] = updt.ipDummy[1:0]; // Clear any interrupts that the writer is trying to clear.
          orig.dc = updt.dc; // Stop the count register! (Not implemented. Only for newer MIPS64s)
          orig.iv = updt.iv; // Write True to get a special exception entry point for interrupts.
          orig.wp = updt.wp; // Write True to get a special exception entry point for interrupts. Not sure the relationship here.
          cause <= orig;
        end
      14: begin
        epc <= data;
      end
      23: begin
        $finish;
      end
      27: begin // CP0 register report. Custom instruction for dumping CP0 state.
        debugInst($display("======   CP0 Registers   ======"));
        debugInst($display("[08] BadVAddr: 0x%x", badVAddr));
        debugInst($display("[09] Count: %x", count));
        debugInst($display("[11] Compare: 0x%x", compare));
        debugInst($display("[12] SR (Status): 0x%x", sr));
        CauseRegister causeReturn = cause;
        causeReturn.ipDummy = causeip;
        debugInst($display("[13] Cause: 0x%x", causeReturn));
        debugInst($display("[14] EPC: 0x%x", epc));
        debugInst($display("[15] PRId: 0x%x", procid));
        debugInst($display("[30] ErrorEPC: 0x%x", errorEPC));
      end
      31: begin
        CP0Inst cp0Inst = unpack(data[5:0]);
        case (cp0Inst)
          ERET: begin // Exception Return
            if (!sr.erl) begin // er.erl should always be False...
              StatusRegister srn = sr;
              srn.exl = False; // Clear sr.exl, the exception level flag.
              sr <= srn;
              if (!eretHappened.notEmpty) begin
                eretHappened.enq(True); // signal llSc to clear.
              end
              //debug($display("eret Happened!"));
            end
          end
        endcase
      end
      default: debug($display("Unsupported CP0 register write!"));
    endcase
    newcauseip[6:2] = exInterrupts;
    causeip <= newcauseip;
  endrule

  method Action readReq(RegNum rn, Bit#(3) sel);
    readReqs.enq(C0ProReg{regNum: rn, sel: sel});
    debug($display("CP0 read in"));
  endmethod

  // readGet gets the result of a read.
  // We block when we are waiting for a probe response since it can take longer
  // than the standard TLB operation.
  method ActionValue#(Word) readGet(Bool goingToWrite) if (!expectWrites.notEmpty);
    if (goingToWrite) begin
      expectWrites.enq(True);
    end
    RegNum regNum = readReqs.first.regNum();
    Bit#(3) sel = readReqs.first.sel();
    readReqs.deq;
    Bit#(64) rv;
    debug($display("CP0 read out"));
    case (regNum)
       8: rv = badVAddr;
       9: rv = zeroExtend(count);
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
          1: rv = zeroExtend(pack(coreid));
          2: rv = 0; // thread ID
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
          // 6: rv = zeroExtend(pack(configReg6));
          default: rv = 64'b0;
        endcase
      end

      17: rv = fromMaybe(?,llScReg);
      30: rv = errorEPC;
      default: rv = 64'b0;
    endcase
    return (rv);
  endmethod

  method Action writeReg(RegNum rn, Bit#(3) sel, Word data, Bool forceKernelMode, Bool writeBack) if (rnUpdate.notFull && dataUpdate.notFull);
    expectWrites.deq;
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
    if ((causeip & sr.im) != 0 && sr.ie == True && sr.exl == False) begin
      expRpt.exception = Int;
    end
    return (expRpt);
  endmethod

  method Action putException(ExceptionWriteback exp, Address ivaddr, MIPSReg dvaddr);
    Address badVaddr = 64'b0;
    if (exp.exception == ITLB || exp.exception == ITLBI || exp.exception == IADEL) begin
      badVaddr = ivaddr;
    end
    if (exp.exception == DTLBL || exp.exception == DTLBLI || 
            exp.exception == DTLBS || exp.exception == DTLBSI || 
            exp.exception == CTLBL || exp.exception == CTLBS || 
            exp.exception == Mod || exp.exception == DADEL || 
            exp.exception == DADES) begin
      badVaddr = dvaddr;
    end
    if (exp.exception != None && !exp.dead) begin
      CauseRegister cr = unpack(32'b0);
      cr.excCode = getExceptionCode(exp.exception);
      cr.bd = exp.branchDelay;
      case (exp.exception)
        CP0: cr.ce = 0;
        CP1: cr.ce = 1;
        CP2: cr.ce = 2;
        CP3: cr.ce = 3;
        default: cr.ce = 0;
      endcase
      cause <= cr;
      StatusRegister srn = sr;
      srn.exl = True;
      sr <= srn;
      epc <= exp.victim;
      case(exp.exception)
        IADEL, DADEL, DADES: begin
          trace($display("Bad virtual address: %x", badVaddr));
          badVAddr <= badVaddr;
        end
      endcase
    end else if (!exp.dead) begin
      if (cause.dc == False && deterministicCycleCount) begin
        count <= count + 1;
      end
    end
  endmethod

  method Action interrupts(Bit#(5) interruptLines);
    exInterrupts <= interruptLines;
  endmethod

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

  method ActionValue#(Bool) setLlScReg(Address matchAddress, Bool link, Bool store);
    Maybe#(Address) newLlSc = llScReg;
    if (link) begin
      newLlSc = tagged Valid zeroExtend(matchAddress[56:0]);
      debug($display("%d: Setting Load Linked register to:%x", $time, matchAddress));
    end
    if ((isValid(llScReg) && (matchAddress[11:0] == fromMaybe(?,llScReg)[11:0]) &&
            store) || eretHappened.notEmpty) begin
      newLlSc = tagged Invalid;
      if (eretHappened.notEmpty) begin
        eretHappened.deq;
      end
      debug($display("%d: Invalidating Load Linked Register:%x==%x", $time, matchAddress, fromMaybe(64'h9999999999999999,llScReg)));
    end
    llScReg <= newLlSc;
    if (isValid(llScReg) && fromMaybe(?,llScReg)[11:0] == matchAddress[11:0] && !eretHappened.notEmpty) begin
      return True;
    end else begin
      return False;
    end
  endmethod

  method CoProEn getCoprocessorEnables();
    CoProEn cpEn = sr.cpEn;
    cpEn.cu0 = kernelMode || sr.cpEn.cu0;
    return cpEn;
  endmethod

  method Action putCacheConfiguration(L1ChCfg iCacheConfig, L1ChCfg dCacheConfig);
    debug($display("%d: Not putting cache configuration.", $time));
  endmethod

  method Bool shouldTrace();
    return False; //Because there won't be the DRAM channel?
    // XXX cr437: do we just a BRAM in QSys? Needs more thought...
  endmethod

  method Action putDeterministicCycleCount(Bool cycleCount);
    deterministicCycleCount <= cycleCount;
  endmethod
endmodule
