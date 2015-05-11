/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
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
 * Author: Nirav Dave <ndave@csl.sri.com>
 *         Robert M. Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Architectural MIPS Register File
 *
 ******************************************************************************/

import RegFile::*;
import FIFO::*;
import ConfigReg::*;
import Vector::*;

import MIPS :: * ;
import CHERITypes :: * ;
import Bram::*;

import Library::*;
import Debug::*;

import SearchFIFO::*;

interface RegisterFile;
  interface Vector#(NumThreads, Reg#(Address))      pc;
  interface Vector#(NumThreads, Reg#(Value))        hi;
  interface Vector#(NumThreads, Reg#(Value))        lo;
  method Action               readReqA(ThreadID threadId, RegName x);
  method ActionValue#(Value) readRespA();
  method Action               readReqB(ThreadID threadId, RegName x);
  method ActionValue#(Value) readRespB();
  method Action                  write(ThreadID threadId, RegName x, Value v);

  method Action               readReqD(ThreadID threadId, RegName x);  // for debug unit
  method ActionValue#(Value) readRespD();
  method Action                 writeD(ThreadID threadId, RegName x, Value v);
endinterface

module mkRegisterFile(RegisterFile);
  Vector#(NumThreads, Reg#(Value)) pcRegs <- replicateM(mkReg_WriteFirst(tagged Valid 64'h9000000040000000));
  Vector#(NumThreads, Reg#(Value)) hiRegs <- replicateM(mkReg_WriteFirst(tagged Valid 0));
  Vector#(NumThreads, Reg#(Value)) loRegs <- replicateM(mkReg_WriteFirst(tagged Valid 0));

  Bram#(Tuple2#(ThreadID,RegName), Value) regFileA <- mkBram;
  Bram#(Tuple2#(ThreadID,RegName), Value) regFileB <- mkBram;
  FIFO#(Bool)                             isZeroA  <- mkFIFO();
  FIFO#(Bool)                             isZeroB  <- mkFIFO();

  method Action readReqA(id, rn);
    regFileA.readReq(tuple2(id, rn));
	isZeroA.enq(rn == 0);
  endmethod

  method ActionValue#(Value) readRespA;
    let isZero <- popFIFO(isZeroA);
    let resp <- regFileA.readResp;
    return (isZero) ? 0 : resp;
  endmethod

  method Action readReqB(id, rn);
    regFileB.readReq(tuple2(id, rn));
	isZeroB.enq(rn == 0);
  endmethod

  method ActionValue#(Value) readRespB;
    let isZero <- popFIFO(isZeroB);
    let resp <- regFileB.readResp;
    return (isZero) ? 0 : resp;
  endmethod

  method Action write(ThreadID id, RegName rn, Value v);
    if(rn != 0)
	  begin
		regFileA.write(tuple2(id, rn), v);
		regFileB.write(tuple2(id, rn), v);
	  end
  endmethod

  method Action readReqD(id, rn);
    regFileB.readReqD(tuple2(id, rn));
	isZeroB.enq(rn == 0);
  endmethod

  method ActionValue#(Value) readRespD;
    let isZero <- popFIFO(isZeroB);
    let resp <- regFileB.readRespD;
    return (isZero) ? 0 : resp;
  endmethod

  method Action writeD(ThreadID id, RegName rn, Value v);
    if(rn != 0)
	  begin
		regFileA.writeD(tuple2(id, rn), v);
		regFileB.writeD(tuple2(id, rn), v);
	  end
  endmethod

  interface Reg pc = pcRegs;
  interface Reg hi = hiRegs;
  interface Reg lo = loRegs;
endmodule

//=============================================================================
// Debugging Wrapper for Register File
//=============================================================================

module mkForwardingRegisterFile#(RegisterFile archRF, Vector#(n, Forwarder#(ThreadRegName, Value)) fwds)
                   (RegisterFile)
            provisos(Add#(1, k__, n));

  FIFO#(Maybe#(ThreadRegName)) regNameA <- mkFIFO();
  FIFO#(Maybe#(ThreadRegName)) regNameB <- mkFIFO();

  //select left-most value in parallel
  Maybe#(Maybe#(Value)) forwardResultA =
    case (regNameA.first()) matches
      tagged Valid .tr: return foldValues(getValuesA(fwds, tr));
      default:          return Invalid;
    endcase;

  Maybe#(Maybe#(Value)) forwardResultB =
      case (regNameB.first()) matches
      tagged Valid .tr: return foldValues(getValuesB(fwds, tr));
      default:          return Invalid;
    endcase;

  method Action readReqA(id, rn);
    debug2("regfile", $display("REGFILE: readReqA %d", rn));
    archRF.readReqA(id,rn);
    regNameA.enq((rn != 0) ? tagged Valid ThreadRegName{thread:id, r:rn} : Invalid);
  endmethod

  //ndave: Stall if the value is to be forwarded but hasn't been generated
  //We don't need to worry about Valid(Invalid) case
  method ActionValue#(Value) readRespA() if (forwardResultA != Valid(Invalid));
    let v <- archRF.readRespA();
    regNameA.deq();
    let val = validValue(fromMaybe(tagged Valid v, forwardResultA));
    if (isValid(regNameA.first()))
      debug2("regfile", $display(fshow(getValuesA(fwds, fromMaybe(?, regNameA.first())))));
    debug2("regfile", $display("REGFILE: readRespA = 0x%x from %s", val, isValid(forwardResultA) ? "forwarder":"regfile"));
    return val;
  endmethod

  method Action readReqB(id, rn);
    debug2("regfile", $display("REGFILE: readReqB %d", rn));
    archRF.readReqB(id,rn);
    regNameB.enq((rn != 0) ? tagged Valid ThreadRegName{thread:id, r:rn} : Invalid);
  endmethod

  //Stall if the value is to be forwarded but hasn't been generated
  method ActionValue#(Value) readRespB() if (forwardResultB != Valid(Invalid));
    let v <- archRF.readRespB();
    regNameB.deq();
    let val = validValue(fromMaybe(tagged Valid v, forwardResultB));
    if (isValid(regNameB.first()))
      debug2("regfile", $display(fshow(getValuesB(fwds, fromMaybe(?, regNameB.first())))));
    debug2("regfile", $display("REGFILE: readRespB = 0x%x from %s", val, isValid(forwardResultB) ? "forwarder":"regfile"));
    return val;
  endmethod

  method Action write(ThreadID id, RegName x, Value v);
    debug2("regfile", $display("REGFILE: write r%d = 0x%x", x,v));
    archRF.write(id, x,v);
  endmethod

   method readReqD  = archRF.readReqD;
   method readRespD = archRF.readRespD;
   method writeD    = archRF.writeD;

  // XXX We can have HI/LO speculation added here.
  interface Vector hi = archRF.hi;
  interface Vector lo = archRF.lo;
  interface Vector pc = archRF.pc;
endmodule

//=============================================================================
// Debugging Wrapper for Register File
//=============================================================================

module [m] mkRegisterFile_Debug#(m#(RegisterFile) mkRF)
                                   (Debug#(RegisterFile, Display#(Tuple2#(ThreadID, Address))))
  provisos(IsModule#(m, a__));

  RegisterFile                                          rf <- mkRF();
  Vector#(NumThreads, Vector#(32, Reg#(Value))) debugRegFile <- replicateM(replicateM(mkReg(0)));

  interface RegisterFile inf;
    method Action readReqA(id, rn)         = rf.readReqA(id, rn);
    method ActionValue#(Value) readRespA() = rf.readRespA();
    method Action readReqB(id, rn)          = rf.readReqB(id, rn);
    method ActionValue#(Value) readRespB() = rf.readRespB();
    method Action write(id, rn, v);
      rf.write(id, rn,v);
      if(rn != 0) debugRegFile[id][rn] <= v;
    endmethod

    method Action readReqD(id, rn)          = rf.readReqD(id, rn);
    method ActionValue#(Value) readRespD() = rf.readRespD();
    method Action writeD(id, rn, v);
      rf.writeD(id, rn,v);
      if(rn != 0) debugRegFile[id][rn] <= v;
    endmethod

    interface Reg pc = rf.pc;
    interface Reg hi = rf.hi;
    interface Reg lo = rf.lo;
  endinterface

  interface Display debugging;
    method Action debug_display(Tuple2#(ThreadID, Address) args);
      match{.t, .pc} = args;
      $display("======  Thread %2d  ======", t);
      $display("======   RegFile   ======");
      $display("DEBUG MIPS PC 0x%x", pc);
      $display("DEBUG MIPS REG %2d 0x%x", 0, 64'h0);
      for (Integer i = 1; i<32; i=i+1)
	$display("DEBUG MIPS REG %2d 0x%x", i, debugRegFile[t][i]);
    endmethod
  endinterface
endmodule
