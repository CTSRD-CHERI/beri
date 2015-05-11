/*-
 * Copyright (c) 2011-2014 SRI International
 * Copyright (c) 2012-2014 Robert Norton
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
 *   Robert Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: CHERI2 Debugging Unit
 *
 ******************************************************************************/

import ClientServer :: *;
import FIFO::*;
import FIFOF::*;
import FShow::*;
import GetPut :: *;
import Vector :: *;
import Assert :: *;
import DefaultValue :: *;

import MIPS :: *;
import CHERITypes::*;
import RegisterFile::*;
import BranchPredictor::*;
import CP0::*;
import Debug::*;
import Library::*;
import EHR::*;
import TLV::*;
import MemTypes::*;
import DebugCommands::*;
import TraceTypes::*;
import CircularBuffer::*;

import CapabilityRegisterFile::*;
`ifdef CAP
import CapabilityTypes::*;
`endif

`ifdef DEBUG
// Which thread to debug.
`ifndef DEBUGTHREAD
`define DEBUGTHREAD 0
`endif
typedef `DEBUGTHREAD DebugThread;

typedef 10 Log2StreamEntries;
typedef UInt#(Log2StreamEntries) StreamIndex;

//=======================================================================
// Tracing

interface TraceLogger;
  method Action addEntry(Exception e, Bit#(32) inst, Address pc, Value result, Value result2, ASID asid);
  method ActionValue#(Maybe#(TraceEntry)) popEntry();
  method Bool notEmpty();
  method Bool almostFull();
  interface Reg#(Bit#(256))  traceCmpMask;
  interface Reg#(TraceEntry) traceCmp;
endinterface

typedef 256 DebugInfoBitWidth;
typedef Bit#(DebugInfoBitWidth) DebugInfo;

module mkTraceLogger(TraceLogger);
  Reg#(Bit#(256))  traceCmpMaskReg  <- mkReg(0); //trace everything to start
  Reg#(TraceEntry) traceCmpReg      <- mkRegU();

  CircularBuffer#(Log2StreamEntries, TraceEntry) traceQ <- mkBRAMCircularBuffer;
  Reg#(Bit#(10))   count           <- mkReg(0);

  rule counter;
    count <= count + 1;
  endrule

  method Action addEntry(Exception e, Bit#(32) inst, Address pc, Value result, Value result2, ASID asid);
    let te = TraceEntry{
      valid:     True,
      version:   1,
      ex:        pack(e),
      inst:      inst,
      pc:        pc,
      regVal1:   result,
      regVal2:   result2,
      reserved:  0,
      asid:      asid,
      count:     count
    };
    if ((pack(te) & traceCmpMaskReg) == (pack(traceCmpReg) & traceCmpMaskReg))
      traceQ.enq(te);
  endmethod

  method ActionValue#(Maybe#(TraceEntry)) popEntry();
    if (traceQ.notEmpty)
      begin
	traceQ.deq();
	return Valid (traceQ.first);
      end
    else
      return Invalid;
    endmethod
  method almostFull = traceQ.almostFull;
  method notEmpty = traceQ.notEmpty;
  interface Reg traceCmpMask = traceCmpMaskReg;
  interface Reg traceCmp = traceCmpReg;
endmodule

//=======================================================================
// Debug Unit

interface DebugUnit;
  interface Server#(Bit#(8), Bit#(8)) stream;

  interface RegisterFile              rf;
  interface CP0RegisterFile        cp0rf;
  interface CapabilityRegisterFile caprf;

  method Action           canFetchInst();
  method ActionValue#(Bool) completeInst(Bit#(32) inst, Address pc, Address nextpc, Value result, Value result2, Exception e, ASID asid);
endinterface

module mkDebugUnit#(
  Bool pipelineFlushed,
  RegisterFile regfile,
  CP0RegisterFile cp0regfile,
  CapabilityRegisterFile capregfile,
  Vector#(NumThreads, BranchPredictor) bpreds,
  DMem dmemory)
(DebugUnit);

  ByteMarshaller#(DebugCommand) marshaller <- mkTLVByteMarshaller_DebugCommand();

  EHR#(2,PipelineState)       pipeState <- mkEHR(Pipe_RunningPipelined);
  Reg#(Bool)               sendingTrace <- mkReg(False);
  Reg#(Vector#(4, Address)) breakpoints <- mkReg(replicate(64'hFFFFFFFF)); //Threads
  Reg#(ThreadID)            debugThread <- mkReg(fromInteger(valueOf(DebugThread))); // current thread to debug.
  TraceLogger tracelogger               <- mkTraceLogger();

  Bool canDebug = (pipeState[1] == Pipe_Paused); // would ideally wait for pipeLineFlushed too but this causes awkward dependency cycles

  //
  FIFO#(void)               stepQ <- mkFIFO();
  FIFO#(DebugCommand) precommandQ <- mkFIFO();
  FIFO#(DebugCommand)    commandQ <- mkFIFO();
  FIFO#(Exception)        memExQ1 <- mkFIFO();
  FIFO#(Exception)        memExQ2 <- mkFIFO();

  let debug_rf    = when(canDebug, regfile);
  let debug_cp0rf = when(canDebug, cp0regfile);
  let debug_caprf = when(canDebug, capregfile);
  let debug_dmem  = when(canDebug, dmemory);

  rule loadCommand;
    let cmd <- marshaller.messageStream.request.get();
    precommandQ.enq(cmd);
  endrule

  function Bool touchesPipeline(DebugCommand c) = (c == D_PausePipelineReq) || (c == D_ResumePipelinedReq) || (c == D_ResumeUnpipelinedReq) || (c == D_ResumeStreamingReq);

  rule startDebugCommand_isolated;
    let cmd <- popFIFO(precommandQ);
    case (cmd) matches
      tagged D_PausePipelineReq:     noAction;
      tagged D_ResumePipelinedReq:   noAction;
      tagged D_ResumeUnpipelinedReq: noAction;
      tagged D_ResumeStreamingReq:   noAction;
      default: when(False, noAction);
    endcase
    commandQ.enq(cmd);
  endrule

  rule startDebugCommand_notIsolated (canDebug);
    let cmd <- popFIFO(precommandQ);
    Maybe#(Tuple3#(MemOp, Address, Value)) mmemreq = Invalid;
    case (cmd) matches
      tagged D_PausePipelineReq:     when(False, noAction);
      tagged D_ResumePipelinedReq:   when(False, noAction);
      tagged D_ResumeUnpipelinedReq: when(False, noAction);
      tagged D_ResumeStreamingReq:   when(False, noAction);
      tagged D_SetPCReq .pc:         noAction;
      tagged D_GetPCReq:             noAction;
      tagged D_SetByteReq {.addr,.val}:
        mmemreq = tagged Valid tuple3(MEM_SB, addr, zeroExtend(val));
      tagged D_GetByteReq .addr:
        mmemreq = tagged Valid tuple3(MEM_LB, addr, ?);
      tagged D_SetHalfWordReq {.addr,.val}:
        mmemreq = tagged Valid tuple3(MEM_SH, addr, zeroExtend(val));
      tagged D_GetHalfWordReq .addr:
        mmemreq = tagged Valid tuple3(MEM_LH, addr, ?);
      tagged D_SetWordReq {.addr,.val}:
        mmemreq = tagged Valid tuple3(MEM_SW, addr, zeroExtend(val));
      tagged D_GetWordReq .addr:
        mmemreq = tagged Valid tuple3(MEM_LW, addr, ?);
      tagged D_SetDoubleWordReq {.addr,.val}:
        mmemreq = tagged Valid tuple3(MEM_SD, addr, val);
      tagged D_GetDoubleWordReq .addr:
        mmemreq = tagged Valid tuple3(MEM_LD, addr, ?);
      tagged D_SetRegisterReq {.r,.v}:
        debug_rf.writeD(debugThread, r, v);
      tagged D_GetRegisterReq {.r}:
        debug_rf.readReqD(debugThread,r);
      tagged D_SetC0RegisterReq {.r,.v}: //XXX rmn30 CP0 operations not supported
        noAction;
        //debug_cp0rf.req(debugThread, ?, CP0Operation{
        //                     cp0_inst:   CP0_NONE,
        //                     cp0_size32: False,
        //                     cp0_hasResult: True,
        //                     cp0_opA: Invalid,
        //                     cp0_dest: tagged Valid r,
        //                     cp0_sel: 0
        //                  }, 8'b0); // rmn30 XXX get real ext irqs
      tagged D_GetC0RegisterReq .r:
        noAction;
        //debug_cp0rf.req(debugThread, ?, CP0Operation{
        //                     cp0_inst:   CP0_NONE,
        //                     cp0_size32: False,
        //                     cp0_hasResult: False,
        //                     cp0_opA: tagged Valid r,
        //                     cp0_dest: Invalid,
        //                     cp0_sel: 0
        //                   }, 8'b0);
      `ifdef CAP
      tagged D_SetC2RegisterReq {.r,.p,.v}:
	debug_caprf.writeD(debugThread, r,p,v);
      tagged D_GetC2RegisterReq {.r}:
        debug_caprf.readReqD(debugThread, r);
      `endif
      tagged D_ExecuteSingleInstReq:      noAction;
      tagged D_SetBreakPointReq {.name, .a}: noAction;
      tagged D_PopTraceReq: noAction;
      tagged D_SetTraceMaskReq .v: noAction;
      tagged D_SetTraceCmpReq .v: noAction;
      tagged D_SetThreadResp .v: noAction;
      default: noAction; // Responses
    endcase
    // do mem operations which we set up in the previous case block
    case (mmemreq) matches
      tagged Valid {.op, .a, .v}:
	begin
          let memop = MemOperation {
             op_memtype: op,
             op_isMemLinked: False,
             op_signed: False
          };
          let ts = debug_cp0rf.threadStates[debugThread];
          // allow debug unit to access all memory by pretending this
          // thread is executing in kernel mode
          ts.errorLevel = True;
          Exception e <- debug_dmem.req(debugThread, ts, memop, a, v);
          memExQ1.enq(e);
        end
    endcase
    commandQ.enq(cmd);
  endrule

  rule commitMem;
    Exception e    <- popFIFO(memExQ1);
    Exception newE <- (e == Ex_None) ? debug_dmem.commit(True) : toAV(e);
    memExQ2.enq(newE);
  endrule

  rule endCommand_isolated;
    let cmd <- popFIFO(commandQ);
    case (cmd) matches
      tagged D_PausePipelineReq:
        action
          marshaller.messageStream.response.put(tagged D_PausePipelineResp pipeState[0]);
          pipeState[0] <= Pipe_Paused;
        endaction
      tagged D_ResumePipelinedReq:
        action
          marshaller.messageStream.response.put(tagged D_ResumePipelinedResp pipeState[0]);
          pipeState[0] <= Pipe_RunningPipelined;
        endaction
      tagged D_ResumeUnpipelinedReq:
        action
          marshaller.messageStream.response.put(tagged D_ResumeUnpipelinedResp pipeState[0]);
          pipeState[0] <= Pipe_RunningUnpipelined;
        endaction
      tagged D_ResumeStreamingReq:
        action
          marshaller.messageStream.response.put(tagged D_ResumeStreamingResp pipeState[0]);
          pipeState[0] <= Pipe_Streaming;
          sendingTrace <= True;
        endaction
      default: when(False, noAction);
    endcase
  endrule

  rule endCommand_notIsolated;
    let cmd <- popFIFO(commandQ);

    Exception memEx = ?;
    Value   memResp = ?;
    if (isMemCommandReq(cmd))
      begin
        memEx   <- popFIFO(memExQ2);
        memResp <- debug_dmem.resp();
        if (memEx != Ex_None)
          marshaller.messageStream.response.put(tagged D_ExceptionOccurred(zeroExtend(pack(memEx))));
      end
      
    case (cmd) matches
      tagged D_PausePipelineReq:     when(False, noAction);
      tagged D_ResumePipelinedReq:   when(False, noAction);
      tagged D_ResumeUnpipelinedReq: when(False, noAction);
      tagged D_ResumeStreamingReq:   when(False, noAction);
      tagged D_SetPCReq .pc:
	action
          //$display("setPC! 0x%h", pc);
          bpreds[debugThread].debug_setPC(pc);
          debug_rf.pc[debugThread] <= pc;
	  marshaller.messageStream.response.put(tagged D_SetPCResp);
        endaction
      tagged D_GetPCReq:     marshaller.messageStream.response.put(tagged D_GetPCResp debug_rf.pc[debugThread]);
      tagged D_SetByteReq {.addr,.val}:
        action
          if (memEx == Ex_None)
              marshaller.messageStream.response.put(tagged D_SetByteResp);
        endaction
      tagged D_GetByteReq .addr:
        action
          if (memEx == Ex_None)
            marshaller.messageStream.response.put(tagged D_GetByteResp (truncate(memResp)));
        endaction
      tagged D_SetHalfWordReq {.addr,.val}:
        action
          if (memEx == Ex_None)
            marshaller.messageStream.response.put(tagged D_SetHalfWordResp);
        endaction
      tagged D_GetHalfWordReq .addr:
        action
          if (memEx == Ex_None)
             marshaller.messageStream.response.put(tagged D_GetHalfWordResp (truncate(memResp)));
        endaction
      tagged D_SetWordReq {.addr,.val}:
        action
          if (memEx == Ex_None)
            marshaller.messageStream.response.put(tagged D_SetWordResp);
        endaction
      tagged D_GetWordReq .addr:
        action
          if (memEx == Ex_None)
            marshaller.messageStream.response.put(tagged D_GetWordResp (truncate(memResp)));
        endaction
      tagged D_SetDoubleWordReq {.addr,.val}:
        action
          if (memEx == Ex_None)
            marshaller.messageStream.response.put(tagged D_SetDoubleWordResp);
        endaction
      tagged D_GetDoubleWordReq .addr:
        action
          if (memEx == Ex_None)
            marshaller.messageStream.response.put(tagged D_GetDoubleWordResp (memResp));
        endaction
      tagged D_SetRegisterReq {.r,.v}: marshaller.messageStream.response.put(tagged D_SetRegisterResp);
      tagged D_GetRegisterReq {.r}:
        action
          let x <- debug_rf.readRespD();
          marshaller.messageStream.response.put(tagged D_GetRegisterResp x);
        endaction
      tagged D_SetC0RegisterReq {.r,.v}:
        action
          //let result <- debug_cp0rf.resp(True, ?, Ex_None, False, v);
          marshaller.messageStream.response.put(tagged D_SetC0RegisterResp);
        endaction
      tagged D_GetC0RegisterReq {.r}:
        action
          //let result <- debug_cp0rf.resp(True, ?, Ex_None, False, ?);
          //marshaller.messageStream.response.put(tagged D_GetC0RegisterResp fromMaybe(?, result.cp0_mvalue));
          marshaller.messageStream.response.put(tagged D_GetC0RegisterResp fromMaybe(?, ?));
        endaction
      `ifdef CAP
      tagged D_SetC2RegisterReq {.r,.mv}: marshaller.messageStream.response.put(tagged D_SetC2RegisterResp);
      tagged D_GetC2RegisterReq {.r}:
        action
          let tup <- debug_caprf.readRespD();
          marshaller.messageStream.response.put(tagged D_GetC2RegisterResp tup);
        endaction
      `endif
      tagged D_ExecuteSingleInstReq:
        action
          stepQ.enq(?);
          marshaller.messageStream.response.put(tagged D_ExecuteSingleInstResp);
        endaction
      tagged D_SetBreakPointReq {.name, .a}:
        action
          breakpoints[name] <= a;
          marshaller.messageStream.response.put(tagged D_SetBreakPointResp);
        endaction
      tagged D_PopTraceReq:
        action
          let mv <- tracelogger.popEntry();
          let rv = case (mv) matches
	    tagged Valid .x: return pack(x);
	    tagged Invalid:  return 0;
	  endcase;
          marshaller.messageStream.response.put(tagged D_PopTraceResp rv);
        endaction
      tagged D_SetTraceMaskReq .v:
        action
          tracelogger.traceCmpMask <= v;
          marshaller.messageStream.response.put(tagged D_SetTraceMaskResp);
        endaction
      tagged D_SetTraceCmpReq .v:
        action
          tracelogger.traceCmp <= unpack(v);
          marshaller.messageStream.response.put(tagged D_SetTraceCmpResp);
        endaction
      tagged D_SetThreadReq .v:
        action
          debugThread <= unpack(truncate(v));
          marshaller.messageStream.response.put(tagged D_SetThreadResp);
        endaction
      default:
        action
	  marshaller.messageStream.response.put(tagged D_ExceptionOccurred 8'hff);
	endaction
    endcase
  endrule

  (* preempts="streamtrace, (endCommand_notIsolated, endCommand_isolated)" *)
  rule streamtrace (pipeState[0] == Pipe_Streaming && sendingTrace);
    if (!tracelogger.notEmpty())
      begin
	// This indicates the end of the stream trace.
	marshaller.messageStream.response.put(tagged D_PopTraceResp 0);
	sendingTrace <= False;
      end
    else
      begin
	let mv <- tracelogger.popEntry();
	if (mv matches tagged Valid .x)
	  begin
	    marshaller.messageStream.response.put(tagged D_PopTraceResp pack(x));
	  end
      end
  endrule

  interface Server stream                = marshaller.byteStream;

  //XXX ndave: adding canDebug should not apply to writeback
  interface RegisterFile              rf =    regfile;//when(!canDebug, regfile);
  interface CP0RegisterFile        cp0rf = cp0regfile;//when(!canDebug, cp0regfile);
  interface CapabilityRegisterFile caprf = capregfile;//when(!canDebug, capregfile);

  method Action canFetchInst; // this controls 
    case (pipeState[1])
      Pipe_Paused:              when(pipelineFlushed, stepQ.deq()); // only if we have a step
      Pipe_RunningPipelined:    noAction;                           // We can always fetch
      Pipe_RunningUnpipelined:  when(pipelineFlushed, noAction);    // Only one instruction in pipeline (fetch only when flushed)
      Pipe_Streaming:           when(!tracelogger.almostFull() && !sendingTrace, noAction); // Pause pipeline when buffer fills up and whilst emptying the buffer (in order to get instruction cycle times correct) 
    endcase
  endmethod

  method ActionValue#(Bool) completeInst(Bit#(32) i, Address pc, Address nextpc,Value v1, Value v2, Exception e, ASID asid);
    tracelogger.addEntry(e,i,pc,v1,v2,asid);
    function Bool matchAddr(Address a); return (a == nextpc); endfunction
    Maybe#(UInt#(2)) breakpointMatch = Vector::findIndex(matchAddr, breakpoints);
    if(breakpointMatch matches tagged Valid .name )
      begin
	pipeState[1] <= Pipe_Paused;
	//marshaller.messageStream.response.put(tagged D_BreakPointFired tuple2(pack(name), nextpc));
      end
    return isValid(breakpointMatch);
  endmethod

endmodule
`endif
