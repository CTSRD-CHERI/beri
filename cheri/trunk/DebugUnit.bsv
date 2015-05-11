/*-
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Simon W. Moore
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

import MIPS :: *;

import ClientServer :: *;
import GetPut :: *;
import FIFO::*;
import FIFOF :: *;
import SpecialFIFOs::*;
import ConfigReg :: *;
import Vector :: *;
import FShow::*;

import CircularBuffer::*;
import TraceTypes::*;

typedef enum {Polling,
              ExecuteInstruction,
              Step,
              StreamTrace
} DebugState deriving (Bits, Eq, FShow);

typedef enum{
  Type, Length, Data
} MsgBuildState deriving (Bits, Eq);

TraceEntry defaultTraceEntry = TraceEntry {
         version: 0,
         pc: 0,
         inst: 0,
         regVal1: 0,
         regVal2: 0,
         ex: 0,
         count: 0,
         asid: 0,
         reserved: 0,
         valid: True
      };

typedef enum {
  Null              = 8'h0,
  LoadInstruction   = 8'h69,            // "i"
  LoadOpA           = 8'h61,            // "a"
  LoadOpB           = 8'h62,            // "b"
  LoadBreakPoint0   = 8'h30,            // "0"
  LoadBreakPoint1   = 8'h31,            // "1"
  LoadBreakPoint2   = 8'h32,            // "2"
  LoadBreakPoint3   = 8'h33,            // "3"
  LoadTraceFltr     = 8'h43,            // "C"
  LoadTraceFltrMask = 8'h4D,            // "M"
  ExecuteInstruction= 8'h65,           // "e"
  ReportDest        = 8'h64,            // "d"
  PauseExecution    = 8'h70,            // "p"
  ResumeExecution   = 8'h72,            // "r"
  Reset             = 8'h52,            // "R"
  StepExecution     = 8'h73,            // "s"
  MovePCtoDest      = 8'h63,            // "c"
  ResumeUnpipelined = 8'h75,            // "u"
  PopTraceEntry     = 8'h74,            // "t"
  StreamTrace       = 8'h53,            // "S"
  
  LoadInstructionResponse   = 8'hE9,
  LoadOpAResponse           = 8'hE1,
  LoadOpBResponse           = 8'hE2,
  LoadBreakPoint0Response   = 8'hB0,
  LoadBreakPoint1Response   = 8'hB1,
  LoadBreakPoint2Response   = 8'hB2,
  LoadBreakPoint3Response   = 8'hB3,
  LoadTraceFltrResponse     = 8'hC3,
  LoadTraceFltrMaskResponse = 8'hCD,
  ExecuteInstructionResponse= 8'hE5,
  ExecuteExeptionResponse   = 8'hC5,
  ReportDestResponse        = 8'hE4,
  PauseExecutionResponse    = 8'hF0,
  ResumeExecutionResponse   = 8'hF2,
  ResetResponse             = 8'hD2,
  StepExecutionResponse     = 8'hF3,
  PopTraceResponse          = 8'hF4,            
  MovePCtoDestResponse      = 8'hE3,
  ResumeUnpipelinedResponse = 8'hF5,
  StreamTraceResponse       = 8'hD3,
  BreakpointFired           = 8'hFF,
  
  InvalidInstruction = 8'h20          // " "
} DebugCommand deriving (Bits, Eq, FShow);

function DebugCommand responseCode(DebugCommand dc);
  case (dc)
    LoadInstruction:    return LoadInstructionResponse;
    LoadOpA:            return LoadOpAResponse;
    LoadOpB:            return LoadOpBResponse;
    LoadBreakPoint0:    return LoadBreakPoint0Response;
    LoadBreakPoint1:    return LoadBreakPoint1Response;
    LoadBreakPoint2:    return LoadBreakPoint2Response;
    LoadBreakPoint3:    return LoadBreakPoint3Response;
    LoadTraceFltr:      return LoadTraceFltrResponse;
    LoadTraceFltrMask:  return LoadTraceFltrMaskResponse;
    ExecuteInstruction: return ExecuteInstructionResponse;
    ReportDest:         return ReportDestResponse;
    PauseExecution:     return PauseExecutionResponse;
    ResumeExecution:    return ResumeExecutionResponse;
    StepExecution:      return StepExecutionResponse;
    StreamTrace:        return StreamTraceResponse;
    MovePCtoDest:       return MovePCtoDestResponse;
    ResumeUnpipelined:  return ResumeUnpipelinedResponse;
    Reset:              return ResetResponse;
    PopTraceEntry:      return PopTraceResponse;
    default:           return ?;
  endcase
endfunction 

typedef struct {
  DebugCommand          op;     // Type of message
  UInt#(8)              length; // Length of message in bytes
  Vector#(32, Bit#(8))   data;   // Content of message
} MessagePacket deriving(Bits, Eq); // 80 bits

instance FShow#(MessagePacket);
  function Fmt fshow(MessagePacket m);
    return $format("MessagePacket{op: ", fshow(m.op),
                           " length: ", fshow(m.length),
                           " data: ", fshow(m.data), "}");
  endfunction
endinstance
  
typedef struct {
  Maybe#(MIPSReg) writeback;      // Register value of writeback
  ExpCode         expType;        // Exception type, hopefully "None"
} DebugReport deriving(Bits, Eq); // 69 bits

interface DebugConvert;
  interface Server#(Bit#(8), Bit#(8)) stream; // char-level interface  
  interface Client#(MessagePacket, MessagePacket) messages; // MessagePacket Interface
endinterface

(* synthesize *)
module mkDebugConvert(DebugConvert);
  //Input translation State
  `ifdef BLUESIM
    FIFO#(Bit#(8))        inChar        <- mkSizedFIFO(32768); // Hopefully large enough not to drop chars.
  `else
    FIFO#(Bit#(8))        inChar        <- mkSizedFIFO(1024); // Size to fit M9K BRAMs
  `endif
  Reg#(MsgBuildState)   commandState  <- mkReg(Type);
  Reg#(UInt#(8))        commandCount  <- mkReg(0);
  Reg#(MessagePacket)   command       <- mkRegU;
  FIFO#(MessagePacket)  commands      <- mkFIFO1; // Commands from the UART
  
  //Output translation State
  FIFO#(Bit#(8))        outChar       <- mkSizedFIFO(1024); // Size to fit M9K BRAMs
  Reg#(MsgBuildState)   responseState <- mkReg(Type);
  Reg#(UInt#(8))        responseCount <- mkReg(0);
  FIFO#(MessagePacket)  responses     <- mkFIFO1;

  rule getCommand;
    MessagePacket newCmd = command;
    Bit#(8) char = inChar.first();
    inChar.deq();
    case (commandState)
      Type:
      begin // Set myCmd to a clean, new command.
        newCmd = MessagePacket{op: unpack(char), length: 8'b0, data: ?};
        commandState <= Length;
      end
      Length:
      begin
        UInt#(8) length = unpack(char);
        if (length != 0 && length <= 32)
        begin
          newCmd.length = length;
          commandState <= Data;
          commandCount <= 0;
        end
      else
        begin
          newCmd.length = 0;
          commandState <= Type;
          commands.enq(newCmd);
        end
      end
      Data: 
      begin
        newCmd.data[commandCount] = char;
        if (commandCount >= command.length - 1)
	      begin
          commandState <= Type;
          commands.enq(newCmd);
        end
        commandCount <= commandCount + 1;
      end
    endcase
    debug($display("Debug got new byte: %x, newCmd: %x", char, newCmd));
    command <= newCmd;
  endrule

  rule deliverResponse;
    MessagePacket myRsp = responses.first();
    case (responseState)
      Type: begin
        outChar.enq(pack(myRsp.op));
        responseState <= Length;
      end
      Length: begin
        UInt#(8) length = myRsp.length;
        outChar.enq(pack(length));
        if (length != 0) begin
          responseState <= Data;
          responseCount <= 0;
        end else begin
	        responseState <= Type;
	        debug($display("DEBUG RESPONSE: ", fshow(myRsp)));
          responses.deq();
        end
      end
      Data: begin
        outChar.enq(myRsp.data[responseCount]);
        if (responseCount >= myRsp.length - 1) begin
          responseState <= Type;
          debug($display("DEBUG RESPONSE: ", fshow(myRsp)));
          responses.deq();
        end
        responseCount <= responseCount + 1;
      end
    endcase
  endrule
   
  interface Server stream   = fifosToServer(inChar, outChar);
  interface Client messages = fifosToClient(commands, responses);
endmodule

//=======================================================================

interface DebugIfc;
  method Action pause(Bool commonPause);
  method Word getOpA();
  method Word getOpB();
  method Bool iReady();
  method Bool getPause();
  method ActionValue#(Bool) checkPC(MIPSReg pc);
  method Action putPC(MIPSReg pc);
  method Action putTraceEntry(TraceEntry te);    
  interface Client#(Bit#(32),DebugReport) client;
  interface Server#(Bit#(8), Bit#(8)) stream;
  method Bool reset_n();
  method Bool getDeterministicCycleCount();
endinterface

(* synthesize *)
module mkDebug(DebugIfc);

  DebugConvert debugConvert <- mkDebugConvert();

  Reg#(MIPSReg)         opA           <- mkRegU;
  Reg#(MIPSReg)         opB           <- mkRegU;
  Vector#(4, Reg#(Maybe#(MIPSReg))) bp<- replicateM(mkConfigReg(Invalid));
  FIFOF#(MessagePacket) bpReport      <- mkUGFIFOF;

  Reg#(MIPSReg)                dest   <- mkRegU;
  Reg#(Bit#(32))        instruction   <- mkRegU;
  Reg#(Bool)             unPipeline   <- mkConfigReg(False);
  Wire#(Bool)             pausePipe   <- mkWire;
  Wire#(Bool)             pauseWire   <- mkWire;
  Reg#(Bool)               resetReg   <- mkReg(False);
  Reg#(Bool)      previousPausePipe   <- mkConfigReg(False);
  Reg#(UInt#(28))         idleCount   <- mkReg(0);

  Reg#(Bool)           pauseForInst   <- mkReg(False);
  Reg#(DebugState)            state   <- mkConfigReg(Polling);
  FIFOF#(DebugReport)    writebacks   <- mkFIFOF1;
  FIFOF#(Bit#(32))            instQ   <- mkFIFOF1;
  Reg#(Bool)          instQnotEmpty   <- mkConfigReg(False);

  FIFOF#(Bool)             doneInst   <- mkUGFIFOF; // Debug instruction completed pipeline.

  Reg#(UInt#(3))          pipeCount   <- mkConfigReg(0);
  Reg#(MIPSReg)              mipsPC   <- mkConfigReg(0); // Last PC fetched in pipeline.
  
  Reg#(TraceEntry)         traceCmp   <- mkReg(defaultTraceEntry);
  Reg#(Bit#(256))      traceCmpMask   <- mkReg(pack(defaultTraceEntry));
  
  FIFO#(MessagePacket)   curCommand   <- mkFIFO1;
  CircularBuffer#(12, TraceEntry) trace_buf <- mkBRAMCircularBuffer(); // 4095 entry circular buffer
  Reg#(Bool)  deterministicCycleCount <- mkReg(False);

  (* descending_urgency = "reportBreakPoint, doCommands" *)
  rule doCommands(state == Polling && (!unPipeline || pipeCount!=0));
    MessagePacket com <- debugConvert.messages.request.get();
    debug($display("DEBUG REQ: ", fshow(com)));
    //debug($display("debug command: %c", com.op));
    case (com.op)
      LoadInstruction, LoadOpA, LoadOpB, LoadBreakPoint0, LoadBreakPoint1, LoadBreakPoint2, LoadBreakPoint3: begin
        MIPSReg newVal = {com.data[0],com.data[1],com.data[2],com.data[3],com.data[4],com.data[5],com.data[6],com.data[7]};//XXX pack(com.data)
        case (com.op)
          LoadInstruction: instruction <= {com.data[0],com.data[1],com.data[2],com.data[3]};
          LoadOpA: opA <= newVal;
          LoadOpB: opB <= newVal;
          LoadBreakPoint0: bp[0] <= (newVal == 64'hFFFFFFFFFFFFFFFF) ? Invalid: Valid (newVal);
          LoadBreakPoint1: bp[1] <= (newVal == 64'hFFFFFFFFFFFFFFFF) ? Invalid: Valid (newVal);
          LoadBreakPoint2: bp[2] <= (newVal == 64'hFFFFFFFFFFFFFFFF) ? Invalid: Valid (newVal);
          LoadBreakPoint3: bp[3] <= (newVal == 64'hFFFFFFFFFFFFFFFF) ? Invalid: Valid (newVal);
        endcase
        Bool error = (com.op == LoadInstruction) ? (com.length != 4) : (com.length != 8);
        if (!error) debugConvert.messages.response.put(MessagePacket{op: responseCode(com.op), length: 8'b0, data: ?});
               else debugConvert.messages.response.put(MessagePacket{op: InvalidInstruction  , length: 8'b0, data: ?});
      end
      LoadTraceFltr, LoadTraceFltrMask: begin
        Bit#(256) newVal = {com.data[0],com.data[1],com.data[2],com.data[3],com.data[4],com.data[5],com.data[6],com.data[7],
                            com.data[8],com.data[9],com.data[10],com.data[11],com.data[12],com.data[13],com.data[14],com.data[15],
                            com.data[16],com.data[17],com.data[18],com.data[19],com.data[20],com.data[21],com.data[22],com.data[23],
                            com.data[24],com.data[25],com.data[26],com.data[27],com.data[28],com.data[29],com.data[30],com.data[31]};
        case (com.op)
          LoadTraceFltr: traceCmp <= unpack(newVal);
          LoadTraceFltrMask: traceCmpMask <= newVal;
        endcase
        $display("DEBUG PACKET: ", fshow(com));
        TraceEntry te = unpack(newVal);
        $display("valid=%d, version=%d, ex=%d, reserved=%x, inst=%x, pc=%x, regVal1=%x, regVal2=%x",
          te.valid, te.version, te.ex, te.reserved, te.inst, te.pc, te.regVal1, te.regVal2); 
        $display("DEBUG RESPONSE: ", fshow(MessagePacket{op: responseCode(com.op), length: 8'b0, data: ?}));
        Bool error = (com.length != 32);
        if (!error) debugConvert.messages.response.put(MessagePacket{op: responseCode(com.op), length: 8'b0, data: ?});
               else debugConvert.messages.response.put(MessagePacket{op: InvalidInstruction  , length: 8'b0, data: ?});
      end
      ExecuteInstruction: begin
        pauseWire <= True;
        previousPausePipe <= pausePipe;
        state <= ExecuteInstruction;
        instQ.enq(instruction);
        curCommand.enq(com);
      end
      ReportDest: begin
        com.length = 8'h8;
        com.op = responseCode(com.op);
        for (Integer i=0; i<8; i=i+1) com.data[7-i] = dest[i*8+7:i*8];
        debugConvert.messages.response.put(com);
      end
      MovePCtoDest: begin
        dest <= mipsPC;
        debugConvert.messages.response.put(MessagePacket{op: responseCode(com.op), length: 8'b0, data: replicate(0)});
      end
      PauseExecution: begin
        debug($display("pausing pipeline?"));
        pauseWire <= True;
        unPipeline <= False;
        MessagePacket response = MessagePacket{op: responseCode(com.op), length: 8'b1, data: replicate(0)};
        response.data[7] = zeroExtend(pack(pausePipe));
        debugConvert.messages.response.put(response);
      end
      ResumeExecution: begin
        debug($display("resuming execution?"));
        pauseWire <= False;
        unPipeline <= False;
        deterministicCycleCount <= False;
        debugConvert.messages.response.put(MessagePacket{op: responseCode(com.op), length: 8'b0, data: replicate(0)});
      end
      Reset: begin
        resetReg <= True;
        //debugConvert.messages.response.put(MessagePacket{op: responseCode(com.op), length: 8'b0, data: replicate(0)});
      end
      ResumeUnpipelined: begin
        pauseWire <= True;
        unPipeline <= True;
        MessagePacket response = MessagePacket{op: responseCode(com.op), length: 8'b1, data: replicate(0)};
        response.data[7] = zeroExtend(pack(unPipeline));
        debugConvert.messages.response.put(response);
      end
      StepExecution: begin
        state <= (pausePipe) ? Step : Polling;
        pauseWire <= False;
        curCommand.enq(com);
      end
      StreamTrace: begin
        pauseWire <= False;
        unPipeline <= False;
        deterministicCycleCount <= True;
        state <= StreamTrace;
      end
      default: begin
        debugConvert.messages.response.put(MessagePacket{op: InvalidInstruction, length: 8'b0, data: replicate(0)});
      end
    endcase
    idleCount <= 0;
  endrule

  rule stopTracePipe(state==StreamTrace && trace_buf.almostFull);
    // If the trace buffer is full, pause the pipeline.
    pauseWire <= True;
    unPipeline <= False;
  endrule
  
  rule popTrace(state==StreamTrace && trace_buf.notEmpty);
    TraceEntry t = trace_buf.first();
    trace_buf.deq();
    MessagePacket response = MessagePacket {
      op:     PopTraceResponse, 
      length: fromInteger(valueOf(SizeOf#(TraceEntry))/8),
      data:   unpack(pack(t))
    };
    debugConvert.messages.response.put(response);
    idleCount <= 0;
  endrule
  
  rule countIdleCyclesStreamTrace(state==StreamTrace && !trace_buf.notEmpty 
                                  && !trace_buf.almostFull);
    // Last condition to make this rule mutually exclusive with stopTracePipe...
    idleCount <= idleCount + 1;
    // Return to Polling if we are idle for 67M cycles (most of a second).
    if (idleCount == 28'h2000000 || pausePipe == True) begin
      MessagePacket response = MessagePacket{
        op: responseCode(StreamTrace),
        length: 8'b0,
        data: replicate(0)
      };
      debugConvert.messages.response.put(response);
      state <= Polling;
      pauseWire <= True;
      unPipeline <= False;
    end
  endrule

  rule reportBreakPoint(state == Polling && bpReport.notEmpty);
    debugConvert.messages.response.put(bpReport.first);
    bpReport.deq();
    pauseWire <= True;
    unPipeline <= False;
  endrule
  
  (* fire_when_enabled, no_implicit_conditions *)
  rule incPipeCount; // Increment counter used if we are running "unpipelined".
    pipeCount <= pipeCount + 1;
  endrule
  
  rule unpipelinedStep(unPipeline && pipeCount==0 && state == Polling && !bpReport.notEmpty);
    state <=  Step;
    pauseWire <= False;
    curCommand.enq(MessagePacket{op: Null, length: 8'b0, data: replicate(0)});
  endrule
  
  (* descending_urgency = "step, countIdleCycles" *)
  rule step(state == Step);
    state <= Polling;
    pauseWire <= True;
    if (curCommand.first.op != Null)
      debugConvert.messages.response.put(MessagePacket{op: responseCode(curCommand.first.op), length: 8'b0, data: ?});
    curCommand.deq();
  endrule
  
  rule feedInstQnotEmpty;
    instQnotEmpty <= (instQ.notEmpty);
  endrule
  
  (* descending_urgency = "finishExecute, countIdleCycles" *)
  rule finishExecute(state==ExecuteInstruction);
    DebugReport retVal = writebacks.first;
    writebacks.deq();
    if (retVal.writeback matches tagged Valid .wbValue) begin
      dest <= wbValue;
    end
    state <= Polling;
    pauseWire <= previousPausePipe;
    doneInst.deq;
    MessagePacket response = MessagePacket{op: responseCode(curCommand.first.op), length: 8'h0, data: ?};
    if (retVal.expType != None) begin
      response = MessagePacket{op: ExecuteExeptionResponse, length: 8'h1, data: ?};
      response.data[0] = zeroExtend(pack(retVal.expType));
    end
    debugConvert.messages.response.put(response);
    curCommand.deq();
  endrule
  
  rule finishExecuteFailsafe(state==Polling);
    DebugReport retVal = writebacks.first;
    writebacks.deq();
    doneInst.deq;
  endrule
  
  rule countIdleCycles(state==ExecuteInstruction);
    idleCount <= idleCount + 1;
    // Return to Polling if we are idle for 65k cycles.
    if (idleCount >= 28'h10000) begin
      MessagePacket response = MessagePacket{
        op: ExecuteExeptionResponse,
        length: 8'h1,
        data: replicate(0)
      };
      // Magic number to indicate timeout exception. 
      // This is not a MIPS architectural exception type.
      response.data[0] = 8'd31;
      debugConvert.messages.response.put(response);
      curCommand.deq();
      state <= Polling;
      pauseWire <= False;
      unPipeline <= False;
    end
  endrule

  method Action pause(Bool commonPause);
    pausePipe <= commonPause;
  endmethod
  method Bool getPause();
    return pauseWire;
  endmethod
  method Word getOpA() = opA;
  method Word getOpB() = opB;
  method Bool iReady() = instQnotEmpty;
  method Bool getDeterministicCycleCount() = deterministicCycleCount||pausePipe;

  method ActionValue#(Bool) checkPC(MIPSReg pc) if (!bpReport.notEmpty());
    function matchMaybePC(mpc) = mpc == Valid(pc);
    Bool newBpFired = any(matchMaybePC, readVReg(bp));
    if (newBpFired)
      begin
        MessagePacket com = MessagePacket{op: BreakpointFired, length: 8'h8, data: ?};
        for (Integer i=0; i<8; i=i+1) com.data[7-i] = pc[i*8+7:i*8];
        bpReport.enq(com);
      end
    return newBpFired;
  endmethod
  
  method Action putPC(MIPSReg pc);
    mipsPC <= pc;
  endmethod

  method Action putTraceEntry(TraceEntry te) if (trace_buf.notFull() || state!=StreamTrace);
    // Only enq the trace record if it matches the pattern and mask.
    // If the mask is 0, all records will be enqed.
    Bit#(256) tentB = pack(te) & traceCmpMask;
    tentB = pack(traceCmp) & traceCmpMask;
    if ((pack(te) & traceCmpMask) == (pack(traceCmp) & traceCmpMask)) begin
      trace_buf.enq(te);
    end
  endmethod
  
  interface Client client;
    interface Get request;
      method ActionValue#(Bit#(32)) get();
        let inst = instQ.first();
        instQ.deq();
        doneInst.enq(True);
        return inst;
      endmethod
    endinterface
    interface Put response;
      method Action put(DebugReport retVal);
        writebacks.enq(retVal);
      endmethod
    endinterface
  endinterface
  
  interface Server stream = debugConvert.stream;

  method Bool reset_n() = !resetReg;
endmodule
