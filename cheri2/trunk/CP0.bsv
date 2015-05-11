/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2014 Robert M. Norton
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
 *   Robert M. Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: MIPS CP0 implementation
 *
 ******************************************************************************/

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import FShow::*;

import MIPS::*;
import CHERITypes::*;
import Debug::*;
import Library::*;
import TLB::*;
import MemoryCompute::*;
import Bram::*;
import EHR::*;

typedef struct {
  Maybe#(Address)   cp0_mexceptionPC;  //maybe exception jump addr
  Maybe#(Value)     cp0_mvalue; //maybe Resulting value to store
  ThreadState               ts;
} CP0Result deriving(Bits, Eq, FShow);

interface CP0RegisterFile;
    method Action                  req(ThreadID thread, ThreadState ts, CP0Operation op, Bit#(8) extIrqs); // lookup or ins
    method ActionValue#(Exception) checkException(); // check for an exception (including interrupt)
    method ActionValue#(CP0Result) resp(Bool commit, Address exception_pc, Exception exception, Bool inDelaySlot, Value v, Bit#(32) instr);
    interface Vector#(NumThreads, Reg#(ThreadState)) threadStates;
endinterface

interface CP0;
  interface CP0RegisterFile regs;
  interface TLB tlb;
endinterface

typedef struct {
  //Timer
  Bit#(32)                     compareReg;
  Bit#(32)                      lastCount; // value of count register last time an instruction from this thread was executed. used to check for comparison timer hits.
  Bool                      timerAsserted;
  Vector#(2, Bool)               softIrqs;

  // TLB
  Bit#(2)                 entryHiRegion;
  Bit#(VPN2BITS)            entryHiVPN2;
  Bool                  tlbProbeFailReg;
  TLBIndex                  tlbIndexReg;
  TLBIndex                 tlbRandomReg;
  TLBIndex                  tlbWiredReg;
  Vector#(2, TLBEntryLoReg) tlbEntryLoRegs;
  PageMask               tlbPageMaskReg;

  //Exception
  Address                   exceptionPC;
  MIPSException           lastException;
  Bool                 exceptionInDelay;
  Bit#(2)           coprocessorUnusable;
  Address                      badVaddr;
  Bit#(32)                       eInstr;


  // Context Register (4)
  Bit#(41)               contextPTEBase;

  // XContext Register (20)
  Bit#(TSub#(64, TAdd#(VPN2BITS, 6))) xContextPTEBase;
  Bit#(TAdd#(VPN2BITS, 2))           xContextRBadVPN2;

  //Status Register (12)
  Bit#(4)                     cpNEnable;
  //RP/FR/RE/MX/PX not implemented
  Bool                              bev;
  //TS/SR/NMI not implemented
  Vector#(8,Bool)         interruptMask;
  //KX/SX/UX not implemented (always one)
  //KSU/ERL/EXL/IE live in other ThreadState struct
  Bool                  interruptEnable;

  // LL/SC State
  Address                     llAddrReg;
  Value                       userLocal;
  Bit#(32)                       hwrEna; // 32 bits although only regs 0-3 and 29 are implemented
} CP0PerThreadState deriving(Bits, FShow);

ThreadState initialThreadState = ThreadState {
   modeBits			:KSU_K,
   errorLevel			:False,
   exceptionLevel		:False,
   cacheAlgorithm		:CA_CACHED,
   asid                         :0,
`ifndef NOWATCH
   watchVaddr			:0,
   watchI			:False,
   watchR			:False,
   watchW			:False,
   watchG			:False,
   watchASID			:0,
   watchMask			:0,
`endif
   llBit                        :False
};

CP0PerThreadState initialCP0ThreadState = CP0PerThreadState {
   compareReg			:0,
   lastCount                    :0,
   timerAsserted                :False,
   softIrqs                     :replicate(False),
   entryHiRegion                :0,
   entryHiVPN2                  :0,
   tlbProbeFailReg              :False,
   tlbIndexReg                  :0,
   tlbRandomReg                 :maxBound,
   tlbWiredReg                  :0,
   tlbEntryLoRegs               :?,
   tlbPageMaskReg               :0,
   exceptionPC			:0,
   lastException		:MIPS_Ex_None,
   exceptionInDelay		:False,
   coprocessorUnusable		:0,
   badVaddr			:0,
   contextPTEBase		:0,
   xContextPTEBase		:0,
   xContextRBadVPN2		:0,
   cpNEnable			:4'b0000,
   bev				:True,
   interruptMask		:replicate(False),
   interruptEnable		:False,
   llAddrReg			:0,
   userLocal                    :0,
   hwrEna                       :0,
   eInstr                       :?
   };

module mkCP0(CP0);
  TLB                                   theTLB <- mkTLB;

   // Small per thread state. Uses an EHR to avoid scheduling problems in main pipeline.
   // (Note: threadState is not used internally by this module, but only via the CP0 interface.)
   Vector#(NumThreads, EHR#(2, ThreadState)) threadState <- replicateM(mkEHR(initialThreadState));

   // Function to produce threadStates interface.  _write is used by
   // writeBack, so must be scheduled before _read, which is used by fetch.
   function Reg#(ThreadState) tsIfcFn(EHR#(2, ThreadState) ehr) =
      (interface Reg;
	  method _read  = ehr[1]._read;
	  method _write = ehr[0]._write;
       endinterface );

  function getInitialCP0ThreadState (idx)            =  initialCP0ThreadState;
  // Larger CP0 state is stored in bram.
  let                                    initCP0bram <- mkInitialisedBram(getInitialCP0ThreadState);
  let                                    initialised =  initCP0bram.isInitialised;
  Bram#(ThreadID, CP0PerThreadState)  cp0ThreadState =  initCP0bram.bram;
  // State shared between all threads
  Vector#(8,Reg#(Bool))      interruptsPending <- replicateM(mkReg(False));
   EHR#(2, Bit#(32))                      countReg <- mkEHR(0);

  FIFO#(Tuple4#(ThreadID, ThreadState, CP0Operation, Bit#(8)))                    readQ <- mkPipeFIFO;
  FIFO#(Tuple5#(ThreadID, ThreadState, CP0Operation, Bit#(8), CP0PerThreadState))  midQ <- mkPipeFIFO;
  FIFO#(Tuple6#(ThreadID, ThreadState, CP0Operation, Bit#(8), CP0PerThreadState, Maybe#(Bit#(2)))) respQ <- mkPipeFIFO;


  // Combine the global interruptsPending register with thread state to get final pending interrupt values (currently just oring in the comparision timer)
  function Vector#(8, Bool) threadInterruptsPending(CP0PerThreadState ts, Bit#(5) extIrqs) = unpack({pack(ts.timerAsserted), extIrqs, pack(ts.softIrqs)});

  function Value readIndexReg(CP0PerThreadState cp0ts) = {32'b0, pack(cp0ts.tlbProbeFailReg), zeroExtend(cp0ts.tlbIndexReg)};
  function Value readEntryLo(TLBEntryLoReg e);
    return {
`ifdef CAP
     // CHERI extends the TLB entry with extra flags in top two bits
     pack(e.lo.nostorecap),
     pack(e.lo.noloadcap),
`endif
     zeroExtend({ // fill bits between noloadcap and pfn with zero
         e.lo.pfn,
         pack(e.lo.cacheAlgorithm),
         pack(e.lo.dirty),
         pack(e.lo.valid),
         pack(e.global)})
     };
  endfunction

  function Value cp0read(ThreadID thread, ThreadState ts, CP0PerThreadState cp0ts, Bit#(8) extIrqs, Bool size32, Bit#(3) sel, CP0RegName n);
    Value ret = case (n)
      00:
      begin
        return readIndexReg(cp0ts);
      end
      01:
      begin
        return zeroExtend(cp0ts.tlbRandomReg);
      end
      02:
      begin
        return readEntryLo(cp0ts.tlbEntryLoRegs[0]);
      end
      03:
      begin
        return readEntryLo(cp0ts.tlbEntryLoRegs[1]);
      end
      04: return {cp0ts.contextPTEBase, cp0ts.xContextRBadVPN2[18:0], 4'b0};  // TLB Context
      05: return {0,pack(cp0ts.tlbPageMaskReg)}; // XXX Multiple page sizes not supported
      06: return {0,pack(cp0ts.tlbWiredReg)};
      07: return {32'b0, cp0ts.hwrEna}; // Hardware read enable
      08: return case(sel) matches
		   0:       return cp0ts.badVaddr; // Bad Virtual Address
		   1:       return zeroExtend(cp0ts.eInstr);
		   default: return 0;
		 endcase;
      09: return {32'b0,countReg[0]};
      10: return {cp0ts.entryHiRegion, zeroExtend(cp0ts.entryHiVPN2), 5'b0, ts.asid};
      11: return {32'b0,cp0ts.compareReg};
      12: return {32'b0 // status register
                      ,pack(cp0ts.cpNEnable) // CU3..CU0
                      // unsupported things
                      ,1'b0               // RP reduced power
                      ,1'b0               // FR additional floating point
                      ,1'b0               // RE reverse endian
                      ,1'b0               // MX mdmx
                      ,1'b0               // PX 64-bit user instructions, 32-bit address
                      ,pack(cp0ts.bev)    // BEV
                      // more unsupported
                      ,1'b0               // TS tlb shutdown
                      ,1'b0               // SR soft reset
                      ,1'b0               // NMI non-maskable interrupts
                      ,3'b0               // undefined
                      ,pack(cp0ts.interruptMask) // IM7..IM0 interrupt mask
                      // The following three bits are supposed to be R/W, but we don't support 32-bit mode
                      ,1'b1               // KX 64-bit kernel mode
                      ,1'b1               // SX 64-bit supervisor mode
                      ,1'b1               // UX 64-bit user mode
                      ,pack(ts.modeBits)           // KSU
                      ,pack(ts.errorLevel)         // ERL
                      ,pack(ts.exceptionLevel)     // EXL
                      ,pack(cp0ts.interruptEnable) // IE
                      };
      13: return {32'b0, //cause register
                      pack(cp0ts.exceptionInDelay),
                      1'b0,
                      pack(cp0ts.coprocessorUnusable),
                      12'd0, // rmn30 XXX WP for deferred watch point not implemented
                      pack(threadInterruptsPending(cp0ts, extIrqs[4:0])),
                      1'd0,
                      pack(cp0ts.lastException),
                      2'd0};
      14: return cp0ts.exceptionPC;
      15: begin
                    Bit#(16) maxCoreID = 16'b0; // single core for now
                    Bit#(16) coreID    = 16'b0;
                    ThreadID maxThreadID = maxBound;
                    Bit#(16) threadID    = zeroExtend(thread);
                    let coreIDReg = {zeroExtend(maxCoreID), coreID};
                    let threadIDReg = {zeroExtend(maxThreadID), threadID};
                    return case (sel)
                      0: return {zeroExtend(thread), 8'h0, 8'h04, 8'h00}; // PRId: note use of top byte for thread ID
                      1: return coreIDReg;   // Selects 1 and 2 are for compatibility with a previous version. 
                      2: return threadIDReg; // They may change in future to comply with MIPS spec.
                      6: return coreIDReg;
                      7: return threadIDReg;
                    endcase;
                  end
      16: return case (sel) //configRegs
                   0: return {32'b0,
                      1'b1,          // M Yes, config1
                      15'b0,         // impl
                      1'b1,          // isBigEndian
                      2'b10,         // addressingType 0=MIPS32, 1=MIPS64 inst with MIPS32 address MAP, 2=MIPS64 inst & address map.
                      3'b0,          // archRelease
                      pack(MMU_TLB), // MMU type
                      4'b0,
                      pack(ts.cacheAlgorithm)
                                  };
                   1:
                   begin
                     Bit#(6) configMMU=fromInteger(valueof(TLBSize)-1);
                     Bit#(3) dWays=fromInteger(valueof(DWays));
                     Bit#(3) iWays=fromInteger(valueof(IWays));
                     return {32'b0,
                                  1'b1,                 // M Yes config2
                                  configMMU,            // MMU Size
                             // Description of Caches. Note that we
                             // set the line size to 16 instead of 8
                             // because FreeBSD does not support
                             // 8. That's OK because this information
                             // is only used for cache invalidation
                             // and cheri2 does that in hardware.
                                  3'b011,               // 512 Icache sets per way
                                  3'b011,               // 16 Icache line size
                                  iWays,                // number of Icache ways
                                  3'b011,               // 512 Dcache sets per way
                                  3'b011,               // 16 Dcache line size
                                  dWays,                // number of Dcache ways
`ifdef CAP
                                  1'b1,                 // yes CP2
`else
                                  1'b0,                 // no  CP2
`endif
                                  1'b0,                 // No MDMX
                                  1'b0,                 // No performance counters
`ifndef NOWATCH
                                  1'b1,                 // Yes watch regs
`else
                                  1'b0,                 // No watch regs
`endif
                                  1'b0,                 // No code compression
                                  1'b0,                 // No EJTAG
                                  1'b0                  // No FPU
                                 };
                   end
                   2: return {32'b0,1'b1,31'b0}; // Yes, config3 exists. That is all.
                   3: return {32'b0,18'b0,1'b1,13'b0}; // No config4, URLI implemented
                   default: return 0;
                 endcase;
      17: return cp0ts.llAddrReg; // Load Linked Address
`ifndef NOWATCH
      18: return {ts.watchVaddr, pack(ts.watchI), pack(ts.watchR), pack(ts.watchW)}; // Watch Lo Bits
`else
      18: return 0;
`endif
      20: return {cp0ts.xContextPTEBase, cp0ts.xContextRBadVPN2, 4'b0}; // XContext Pointer to Kernel VTE Table
      21: return 0; // Reserved
      22: return 0; // Reserved
      23: return 0; // Reserved
      24: return 0; // Reserved
      25: return 0; // Reserved
      26: return 0; // ECC
      27: return 0; // Cache Error
      28: return 0; // Cache Tag LO
      29: return 0; // Cache Tag HI
      30: return 0; // * Error Program Counter
    endcase;
    return size32 ? signExtend(ret[31:0]) : ret;
  endfunction

  function TLBEntryLoReg writeTLBEntryLoReg(Value v);
    return TLBEntryLoReg {
       lo: TLBEntryLo {
`ifdef CAP
          nostorecap: unpack(v[63]),
          noloadcap:  unpack(v[62]),
`endif
          pfn: truncate(v[61:6]),
          cacheAlgorithm: unpack(v[5:3]),
          dirty: unpack(v[2]),
          valid: unpack(v[1])
       },
       global: unpack(v[0])
       };
  endfunction

  function ActionValue#(Tuple2#(ThreadState, CP0PerThreadState)) cp0write(ThreadID thread, ThreadState ts,  CP0PerThreadState cp0ts, CP0RegName x, Bit#(3) sel, Value v);
    actionvalue
      case (x)
        0:
        begin
          cp0ts.tlbProbeFailReg = unpack(v[31:31]);
          cp0ts.tlbIndexReg     = unpack(truncate(v[30:0]));
          debug_cp0($display("CP0\tT%d: Index <- %x", thread, readIndexReg(cp0ts)));
        end
        1:
        begin
          debug_cp0($display("CP0\tT%d: ERROR updating TLB Random register", thread));
        end
        2:
        begin
          cp0ts.tlbEntryLoRegs[0] = writeTLBEntryLoReg(v);
          debug_cp0($display("CP0\tT%d: EntryLo0 <- ", thread, fshow(cp0ts.tlbEntryLoRegs[0])));
        end
        3:
        begin
          cp0ts.tlbEntryLoRegs[1] = writeTLBEntryLoReg(v);
          debug_cp0($display("CP0\tT%d: EntryLo1 <- ", thread, fshow(cp0ts.tlbEntryLoRegs[1])));
        end
        4:
        case (sel)
          0:
          begin
            cp0ts.contextPTEBase    = unpack(v[63:23]);
            debug_cp0($display("CP0\tT%d: Context <- %x", thread, v));
          end
          2:
          begin
            cp0ts.userLocal         = v;
            debug_cp0($display("CP0\tT%d: UserLocal <- %x", thread, v));
          end
        endcase
        5:
        begin
          cp0ts.tlbPageMaskReg    = unpack(truncate(v));
          debug_cp0($display("CP0\tT%d: PageMask <- %x", thread, v));
        end
        6:
        begin
          cp0ts.tlbWiredReg       = unpack(truncate(v));
          cp0ts.tlbRandomReg      = maxBound;
          debug_cp0($display("CP0\tT%d: Wired <- %x, Random <- Max)", thread, v));
        end
        7: // HWREna
        begin
          debug_cp0($display("CP0\tT%d: hwrEna <- %x)", thread, v));
          cp0ts.hwrEna            = truncate(v) & 32'h2000000f; // Only regs 0-3 and 29 implemented
        end
        9:
        begin
          `ifndef DETERMINISTIC_TIMER
          countReg[0]                <= unpack(v[31:0]);
          debug_cp0($display("CP0\tT%d: Count <- %x",thread, v));
          `else
          debug_cp0($display("CP0\tT%d: Ignored write to Count.", thread));
          `endif
        end
        10:
        begin
          VAddr vaddr = unpack(v);
          cp0ts.entryHiRegion           = vaddr.r;
          cp0ts.entryHiVPN2             = vaddr.vpn2;
          ts.asid                       = v[7:0];
          debug_cp0($display("CP0\tT%d: EntryHi <- priv:%x, vpn:%x, asid:%d",thread, pack(cp0ts.entryHiRegion), {cp0ts.entryHiVPN2, 1'b0}, ts.asid));
        end
        11:
        begin
          cp0ts.compareReg              = unpack(v[31: 0]);
          cp0ts.timerAsserted           = False;
          debug_cp0($display("CP0\tT%d: Compare <- %x", thread,v));
        end
        12: // Status Register
        begin
          cp0ts.cpNEnable               = unpack(v[31:28]);
          // 27:23 RP/FR/RE/MX/PX not implemented
          cp0ts.bev                     = unpack(v[22:22]);
          //21:16
          cp0ts.interruptMask           = unpack(v[15:8]);
          //7:5
          ts.modeBits        = unpack(v[ 4: 3]);
          ts.errorLevel      = unpack(v[ 2: 2]);
          ts.exceptionLevel  = unpack(v[ 1: 1]);
          cp0ts.interruptEnable = unpack(v[ 0: 0]);
          debug_cp0($display("CP0\tT%d: Status <- CUX: %x BEV: %x IM: %x KSU: %x ERL: %x EXL: %x IE: %x",thread, cp0ts.cpNEnable, cp0ts.bev, cp0ts.interruptMask, ts.modeBits, ts.errorLevel, ts.exceptionLevel, cp0ts.interruptEnable));
        end
        13: // cause register
        begin
          //v[31:10]
          cp0ts.softIrqs = unpack(v[9:8]);
          //v[ 7: 0]
          debug_cp0($display("CP0\tT%d: Cause <- Soft IRQS: %x",thread, cp0ts.softIrqs));
        end
        14:
        begin
          cp0ts.exceptionPC = v;
          debug_cp0($display("CP0\tT%d: ExceptionPC <- 0x%x",thread, v));
        end
        15: noAction; // processor ID / ThreadID
        16: noAction; // Configuration Reg
        17: noAction; // LL Addr
`ifndef NOWATCH
        18:
        begin
          ts.watchVaddr = unpack(v[63:3]);
          ts.watchI     = unpack(v[2]);
          ts.watchR     = unpack(v[1]);
          ts.watchW     = unpack(v[0]);
        end
        19:
        begin
          ts.watchG     = unpack(v[30]);
          ts.watchASID  = unpack(v[23:16]);
          ts.watchMask  = unpack(v[11:3]);
        end
`endif
        20: cp0ts.xContextPTEBase = v[63:valueOf(TSub#(SEGBITS, 7))];
        default: debug($display("XXX haven't handled this register [0x%h] <= %h", x, v));
      endcase
      return tuple2(ts, cp0ts);
    endactionvalue
  endfunction

  function TLBEntry makeTLBEntry(ThreadState ts, CP0PerThreadState cp0ts);
    function Bool loEntryGlobal(TLBEntryLoReg x) = x.global;
    let global = Vector::all(loEntryGlobal, cp0ts.tlbEntryLoRegs);
    function TLBEntryLo loFromLoReg(TLBEntryLoReg e) = e.lo;
    return TLBEntry {
                assoc : TLBAssociativeEntry {
                  entryHi: TLBEntryHi {
                     r: cp0ts.entryHiRegion,
                     vpn2: cp0ts.entryHiVPN2 ,
                     asid: ts.asid
                  },
                  valid: True,
                  pageMask: cp0ts.tlbPageMaskReg,
                  global: global
                },
                lo : Vector::map(loFromLoReg, cp0ts.tlbEntryLoRegs)
              };
  endfunction

  `ifndef DETERMINISTIC_TIMER
  `ifndef VERIFY2
	(* fire_when_enabled *)
  `endif
	(* no_implicit_conditions *)
  rule timerOperation; // This rule must fire each cycle or our timer is off.
    //debug($display("COUNT: %h, COMPARE: %h", countReg, compareReg));
    countReg[1] <= countReg[1] + 1; //YYY: This may be 2x the correct speed
  endrule
  `endif

  interface CP0RegisterFile regs;
    method Action req(ThreadID thread, ThreadState ts, CP0Operation op, Bit#(8) extIrqs) if (initialised);
      readQ.enq(tuple4(thread,ts,op, extIrqs));
      cp0ThreadState.readReq(thread);
    endmethod

    method ActionValue#(Exception) checkException() if (initialised);
      match{.thread, .ts, .op, .extIrqs} <- popFIFO(readQ);
      let cp0ts <- cp0ThreadState.readResp();

      case(op.cp0_inst) matches
        CP0_RDE: // Read indexed TLB entry (TLBR)
        begin
          //move indexed tlb to CP0 Regs
          theTLB.update.read_req(thread, cp0ts.tlbIndexReg);
        end
        CP0_PME: // Probe matching TLB entry
        begin
          VAddress probeVA = {cp0ts.entryHiRegion, zeroExtend(cp0ts.entryHiVPN2), 13'b0};
          theTLB.update.probe_req(thread, ts.asid, probeVA);
        end
      endcase

      // Check access to co-processors

      Bool kernelMode = currentMode(ts.modeBits, ts.exceptionLevel, ts.errorLevel) == KSU_K;
      Bool cp0_move   =  op.cp0_hasResult || isValid(op.cp0_dest);
      Maybe#(Bit#(2)) cpUnusable =
      case(op.cp0_inst) matches
        CP0_NONE: return (!kernelMode && cp0_move && cp0ts.cpNEnable[0] != 1) ? tagged Valid(0) : Invalid;
        CP0_XCP1: return (cp0ts.cpNEnable[1] != 1) ? tagged Valid(1) : Invalid;
        CP0_XCP2: return (cp0ts.cpNEnable[2] != 1) ? tagged Valid(2) : Invalid;
        CP0_RDHWR: return Invalid;
        default:  return (!kernelMode && cp0ts.cpNEnable[0] != 1) ? tagged Valid(0) : Invalid;
      endcase;
      let accessEx = isValid(cpUnusable) ? Ex_CoProcess1 : Ex_None;

      // For RDHWR check to see whether relevant bit of hwrEna is set.
      let hwrEnaEx = (!kernelMode && (op.cp0_inst == CP0_RDHWR) && (cp0ts.hwrEna[validValue(op.cp0_opA)] != 1)) ? Ex_RI : Ex_None;

      let interruptEx = (any(id, zipWith(andBools, threadInterruptsPending(cp0ts, extIrqs[4:0]), cp0ts.interruptMask)) && cp0ts.interruptEnable && !(ts.exceptionLevel || ts.errorLevel)) ? Ex_Interrupt :  Ex_None;

      respQ.enq(tuple6(thread, ts, op, extIrqs, cp0ts, cpUnusable));
      return joinException(hwrEnaEx, joinException(accessEx, interruptEx));
    endmethod

    method ActionValue#(CP0Result) resp(Bool commit, Address exception_pc, Exception exception, Bool inDelaySlot, Value v, Bit#(32) instr) if (initialised);
      match{.thread, .ts, .op, .extIrqs, .cp0ts, .cpUnusable} <- popFIFO(respQ);
      Bool cheri1_trace                          <- $test$plusargs("cheri1_trace");

      // Check for timer interrupt. I assert that this handles wrapping just fine.
      if ((countReg[0] - cp0ts.lastCount) > (cp0ts.compareReg - cp0ts.lastCount))
          cp0ts.timerAsserted = True; // this will actually take effect on the next committed instruction.
      cp0ts.lastCount = countReg[0];

      //===============================================
      //Determine return values to main pipeline
      Maybe#(Value) mretVal = (op.cp0_hasResult) ? liftM(cp0read(thread, ts, cp0ts, extIrqs, op.cp0_size32,op.cp0_sel), op.cp0_opA) : Invalid; //reg read

      debug($display("DEBUG T%1d: CP0 Op:", {1'b0, thread}, fshow(op), " exception:", fshow(exception), " pc: 0x%x", exception_pc, commit ? "" : " DROP"));

      Bool isException = (exception != Ex_None);
      Bool commitNotEx = commit && !isException;

      Maybe#(Address) maddr = (isException)
    ? (Valid((cp0ts.bev) ? getExceptionEntryROM(exception)
               : getExceptionEntryRAM(exception)))
       : (op.cp0_inst == CP0_ERET) ? tagged Valid(cp0ts.exceptionPC) : Invalid;

      if(commit && isException)
        begin //take exception
          cp0ts.exceptionPC      = (inDelaySlot) ? exception_pc - 4 : exception_pc;
          cp0ts.lastException    = exceptionToMIPS(exception);
          ts.exceptionLevel      = True;
          cp0ts.exceptionInDelay = inDelaySlot;
	  cp0ts.eInstr           = instr;
          if (cpUnusable matches tagged Valid .cp)
            cp0ts.coprocessorUnusable = cp;
          debug($display("DEBUG T%1d: WB [%x] CP0: Take ", {1'b0, thread}, exception_pc, fshow(exception), " exception"));
          if(cheri1_trace)
            $write("    Exception! Code=%x ", cp0ts.lastException, fshow(exception));
          if (isAddressException(exception))
            begin
	      // The address for memory ops is passed as the operand. Instruction fetch exceptions
	      // also set this to the bad PC.
	      let badAddr    = v;
              VAddr badVAddr = unpack(badAddr);
              cp0ts.badVaddr = badAddr;
              trace($display("CP0\tT%1d: [%x] BadAddr: 0x%x", thread, exception_pc, badAddr));
              if(cheri1_trace)
                $write(" BadAddr=%x", badAddr);
              if (isTLBException(exception))
                begin
                  // rmn30 ZZZ could calculate these on read instead of storing them
                  let vpn2 = badVAddr.vpn2;
                  let r    = badVAddr.r;
                  cp0ts.xContextRBadVPN2 = {r, vpn2};
                  cp0ts.entryHiRegion    = r;
                  cp0ts.entryHiVPN2      = vpn2;
                end
            end
          if(cheri1_trace)
            $write("\n\n");
          ts.llBit = False; // not strictly required by spec
        end

      if (op.cp0_setLL && commitNotEx)
        ts.llBit = True;
      case(op.cp0_inst) matches
        CP0_ERET: // Exception return
        if (commitNotEx)
          begin
            ts.exceptionLevel = False;
            ts.llBit = False;
            debug_cp0($display("CP0\tT%d: ERET to 0x%x ", thread,cp0ts.exceptionPC));
          end
        CP0_RDE: // Read indexed TLB entry (TLBR)
        begin
          //move indexed tlb to CP0 Regs
          let entry <- theTLB.update.read_resp();
          if (commitNotEx)
            begin
              function TLBEntryLoReg loRegFromLo(TLBEntryLo lo) = TLBEntryLoReg{lo: lo, global:entry.assoc.global};
              ts.asid              = entry.assoc.entryHi.asid;
              cp0ts.entryHiRegion  = entry.assoc.entryHi.r;
              cp0ts.entryHiVPN2    = entry.assoc.entryHi.vpn2;
              cp0ts.tlbEntryLoRegs = Vector::map(loRegFromLo, entry.lo);
              cp0ts.tlbPageMaskReg = entry.assoc.pageMask;
              debug_cp0($display("CP0\tT%d: Read TLB entry idx=%d ", thread,cp0ts.tlbIndexReg, fshow(entry)));
            end
        end
        CP0_PME: // Probe matching TLB entry
        begin
          VAddress probeVA = {cp0ts.entryHiRegion, zeroExtend(cp0ts.entryHiVPN2), 13'b0};
          let mIdx <- theTLB.update.probe_resp;
          if (commitNotEx)
            begin
              cp0ts.tlbProbeFailReg = !isValid(mIdx);
              cp0ts.tlbIndexReg     = fromMaybe(cp0ts.tlbIndexReg, mIdx);
              debug_cp0($display("CP0\tT%d: Probe TLB for 0x%x %s, idx=%x\n", thread,probeVA, isValid(mIdx) ? "matched" :  "didn't match", readIndexReg(cp0ts)));
            end
        end
        CP0_WIE: // Write indexed TLB entry
        begin
          let index = cp0ts.tlbIndexReg;
          let entry = makeTLBEntry(ts, cp0ts);
          if (commitNotEx)
            begin
              theTLB.update.write(thread, index, entry);
              debug_cp0($display("CP0\tT%d: Write indexed TLB entry idx=%d ",thread, index, fshow(entry)));
            end
        end
        CP0_WRE: // Write random TLB entry
        begin
          let index = cp0ts.tlbRandomReg;
          let entry = makeTLBEntry(ts, cp0ts);
          if (commitNotEx)
            begin
              theTLB.update.write(thread, index, entry);
              debug_cp0($display("CP0\tT%d: Write random TLB entry idx=%d ", thread,index, fshow(entry)));
            end
        end
        CP0_WAIT:
        begin
          // nop
        end
        CP0_RDHWR:
        begin
          mretVal = Valid (case (validValue(op.cp0_opA))
                            00: return 64'b0;             // CPUNum - XXX thread or core? we already have this in PRID
                            01: return 8;                 // Step for SYNCI, which is not implemented
                            02: return signExtend(countReg[0]); // CC high resolution counter
                            03: return 64'b1;             // CCRes - counter increments every cycle
                            29: return cp0ts.userLocal;
                            default: return ?;
                           endcase);
        end
        CP0_NONE: // No operation so consider writing
        begin
          case(op.cp0_dest) matches
            tagged Valid .d:
              if (commitNotEx)
                begin
                  match{.newTS, .newCP0ts} <- cp0write(thread, ts, cp0ts, d, op.cp0_sel, v);
                  ts = newTS;
                  cp0ts = newCP0ts;
                end
          endcase
        end
      endcase

      if (commit)
        begin
          `ifdef DETERMINISTIC_TIMER
          // increment the counter on every commited instruction, giving predictable timer interrupts.
          countReg[0] <= countReg[0] + 1;
          `endif
          // rmn30 YYY Increment tlb random every instruction. This might be a little too deterministic.
          cp0ts.tlbRandomReg = max(cp0ts.tlbRandomReg + 1, cp0ts.tlbWiredReg);

          cp0ThreadState.write(thread, cp0ts);
        end

      debug($display("CP0 Resp: op: ", fshow(op) ," mval:  (%b,0x%h)", isValid(mretVal), validValue(mretVal)
                                             ," maddr: (%b/0x%h)", isValid(maddr)  , validValue(maddr)
                                                 ," => ePC: %h", cp0ts.exceptionPC));

      return (CP0Result{cp0_mvalue:       mretVal,
                        cp0_mexceptionPC: maddr,
                        ts:               ts});

    endmethod

    interface  threadStates = map(tsIfcFn, threadState);
  endinterface

  interface TLB    tlb        = theTLB;
endmodule
