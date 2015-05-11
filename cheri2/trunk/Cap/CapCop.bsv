/*-
 * Copyright (c) 2011-2013 Jonathan Woodruff
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
 * Copyright (c) 2013 Michael Roe
 * Copyright (c) 2014 Alexandre Joannou
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
 *   Jonathan Woodruff <jonathan.woodruff@cl.cam.ac.uk>
 *   Nirav Dave <ndave@csl.sri.com>
 *
 ******************************************************************************
 *
 * Description: Capability CoProcessor
 *
 ******************************************************************************/

import ClientServer :: *;
import GetPut :: *;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import BuildVector::*;
import FShow::*;

import Debug::*;
import MemTypes::*;
import DefaultValue::*;
import Assert::*;
import EHR::*;

import MIPS :: *;
import CHERITypes :: *;
import Memory :: *;

import CapabilityTypes::*;
import CapabilityMicroTypes::*;
import CapabilityRegisterFile::*;
import CapabilityExecute::*;

import Library::*;
import SearchFIFO::*;
import Debug::*;
import TraceTypes::*;

//=============================================================================
// Interface
//=============================================================================

typedef struct{
  Value        result;
  Exception exception;
  Bool          bCond;
  Address   fetchAddr;
  Maybe#(Address) mNewPC;
} CapResp deriving(Bits, Eq, FShow);


typedef struct{
  Bool          flush;
`ifdef DEBUG
  TraceEntry       te;
`endif
} CapWritebackResp deriving(Bits, Eq, FShow);

interface CapabilityCoprocessor;

  interface IMem capIMem; // fetch/decode
  interface DMem capDMem; // wraps dmem interface and inserts cap. checks

  // invalid op = do operation through
  method Action capReq(CapOperation op, Bit#(16) imm); //Dec
  method ActionValue#(CapResp) capResp(Bool kill, Address pc, Value a, Value b, Value result, Bool bCond);//Exec

  // these are always called from main pipeline. We use them to
  // perform cap. loads/stores and push data
  method ActionValue#(Exception) memoryStage();
  method ActionValue#(Exception) memoryStage2(Bool commit);
  // the return value signifies if we need to flush after commit.
  // XXX NDAVE: Can we remove the returning flush by pushing this information into decode?
  method ActionValue#(CapWritebackResp) commitWriteback(
     Bool commit, 
     `ifdef DEBUG
     TraceEntry te,
     `endif
     Address pc, 
     Exception exception, 
     Bool eret);

  method Bool isFlushed();
  method Action debugDisplay();

endinterface

//=============================================================================
// Capability Coprocessor
//=============================================================================

module mkCapabilityCoprocessor#(IMem imem, DMem dmem, DCache capMem, CapabilityRegisterFile caprf)(CapabilityCoprocessor);

  Vector#(NumThreads, EHR#(2, CapCause))           capCause <- replicateM(mkEHR(defaultCapCause));
  Vector#(NumThreads, Reg#(Maybe#(Capability))) mDelayedPCC <- replicateM(mkReg(Invalid));

  `ifndef VERIFY2
   let debug_crf <- mkCapabilityRegisterFile_Debug(toModule(caprf));
   CapabilityRegisterFile crf = debug_crf.inf;
  `else
   CapabilityRegisterFile crf = caprf;
  `endif

  CapExecute capExe <- mkCapExecute();

  let cfet2decQ_debug <- mkFIFOF_Debug(mkPipeFIFOF, 1);
  FIFOF#(Tuple4#(ThreadID, ThreadState, Bool, Address)) cfet2decQ = cfet2decQ_debug.inf;

  let cdec2exeQ_debug <- mkFIFOF_Debug(mkPipeFIFOF, 1);
  FIFOF#(DecCapInst) cdec2exeQ = cdec2exeQ_debug.inf;

  SFIFO#(ExeCapInst, ThreadCapReg, TaggedCapability)
                     scexe2memQ <- mkSFIFO1(0,1,1,2, searchCExe);
  FIFOF#(ExeCapInst) cexe2memQ = scexe2memQ.fifo;

  SFIFO#(MemCapInst, ThreadCapReg, TaggedCapability)
                     scmem2mem2Q <- mkSFIFO1(0,1,2,2, searchCMem);
  FIFOF#(MemCapInst) cmem2mem2Q = scmem2mem2Q.fifo;

  SFIFO#(MemCapInst, ThreadCapReg, TaggedCapability)
                     scmem2wbQ <- mkSFIFO1(0,1,2,2, searchCMem);
  FIFOF#(MemCapInst) cmem2wbQ = scmem2wbQ.fifo;

  Vector#(3, Forwarder#(ThreadCapReg, TaggedCapability)) forwarders =
      vec(scexe2memQ.search, scmem2mem2Q.search, scmem2wbQ.search);

  CapabilityRegisterFile forwardcrf <- mkForwardingCapabilityRegisterFile(crf,forwarders);

  interface IMem capIMem;
    method ActionValue#(Exception) req(ThreadID thread, ThreadState ts, Address off);
      let pcc     = forwardcrf.pcc[thread][1];
      let a       = pcc.base + off;
      let isValid = off + 4 <= pcc.length;
      debug2("fetch",$display("CP2: IMEM req to 0x%h", off, " x ", fshow(pcc), " => (0x%h) ", a, fshow(isValid)));

      let e <- (isValid) ? imem.req(thread, ts, a) : toAV(Ex_CoProcess2); // only req when necessary

      cfet2decQ.enq(tuple4(thread, ts, isValid, a));
      return e;
    endmethod

    method ActionValue#(Tuple2#(Exception, Bit#(32))) resp();
      let rv <- imem.resp();
      debug2("decode", $display("CP2: IMEM resp: 0x%h", fshow(rv)));
      return rv;
    endmethod
    interface invalidate = imem.invalidate;
 endinterface

  //XXX simplify Operands if possible
  method Action capReq(CapOperation op, Bit#(16) imm);
    match {.thread, .ts, .isValid, .fetchAddr} <- popFIFOF(cfet2decQ);
    //ndave: conditionally read Capability Registers
    case (op.cA) matches
      tagged Valid .r: forwardcrf.readReqA(thread, r);
    endcase
    case (op.cB) matches
      tagged Valid .r: forwardcrf.readReqB(thread, r);
    endcase

    debug2("decode", $display("CP2: capReq reading ", fshow(op.cA), " ", fshow(op.cA)));

    let dci = DecCapInst{thread: thread, ts: ts, op: op, imm: imm, fetEx: !isValid, fetchAddr: fetchAddr};
    cdec2exeQ.enq(dci);
  endmethod

  method ActionValue#(CapResp) capResp(Bool kill, Address pc, Value a, Value b, Value result, Bool bCond);//Exec
    let dci = cdec2exeQ.first();
    cdec2exeQ.deq();

    TaggedCapability pcA <- case (dci.op.cA) matches
			      tagged Valid .*: forwardcrf.readRespA();
			      default:         ?;
			    endcase;
    TaggedCapability pcB <- case (dci.op.cB) matches
			      tagged Valid .*: forwardcrf.readRespB();
			      default:         ?;
			    endcase;
    `ifdef VERIFY2
   $display(pcA,pcB);
   `endif
    match{.vA,.cA} = pcA;
    match{.vB,.cB} = pcB;

    let cResult <- (kill) ? toAV(?) // don't need result
                          : capExe.capExec(dci.op, crf.pcc[dci.thread][1], pc, a, vA, cA, b, vB, cB, result, bCond, dci.imm, capCause[dci.thread][1]);
    if (dci.fetEx)
      begin
        cResult.exception = Ex_CoProcess2;
        cResult.capCause  = capException(ExC_LengthViolation, Invalid);
      end
    let doMem = cResult.exception == Ex_None && (cResult.loadOp || cResult.storeOp);
    if (!kill) // mispredicted executions are dropped
      begin
	let capResult = cResult.capResult;
        let eci = ExeCapInst{thread: dci.thread, ts: dci.ts, op: dci.op, tag: cResult.capTag, cap: cResult.capResult, getMemResp: doMem, capException: cResult.capCause, memAddr: cResult.memAddr};
        cexe2memQ.enq(eci);
      end

    let capRespV = CapResp{
             exception: cResult.exception,
             result:    cResult.result,
             bCond:     cResult.bCond,
             fetchAddr: dci.fetchAddr,
             mNewPC:    cResult.mNewPC
           };

    if (!kill)
      begin
        debug2("cp2exec", $display("CP2: capResp Op: ", fshow (dci.op.op),
                       "\n reading A: ", fshow(dci.op.cA), " => %b ", vA, fshow(cA),
                       "\n reading B: ", fshow(dci.op.cB), " => %b ", vB, fshow(cB),
                       "\n Result: ", fshow(cResult.capResult),
                       " LoadStore (%d/%d)", cResult.loadOp, cResult.storeOp,
                       "\n CapCause :", fshow(cResult.capCause),
                       "\n CapResp: ", fshow(capRespV)));
      end

   return capRespV;
  endmethod

  // This interface wraps dmem. It used to perform the cap. offset and
  // bounds check but this now happens in execute so it doesn't have
  // very much to do. Now it suppresses the dmem access if we are
  // performing a cap load/store. This has no effect since capability
  // accesses and data accesses never happen together. The check just
  // informs bluespec of this so that they do not conflict in the
  // DCache.
  interface DMem capDMem;
    method ActionValue#(Exception) req(ThreadID tid, ThreadState ts, MemOperation op, Address off, Value val);
      let mci = cexe2memQ.first();
      let ex <- mci.getMemResp ? toAV(Ex_None) : dmem.req(tid, ts, op, off, val);
      return ex;
    endmethod

    method ActionValue#(Exception)  commit(Bool c);
      let wci = cmem2mem2Q.first();
      let e <- wci.getMemResp ?  toAV(Ex_None) : dmem.commit(c);
      return e;
    endmethod

    method ActionValue#(Value) resp();
      let wci = cmem2wbQ.first();
      let r <- wci.getMemResp ? toAV(0) : dmem.resp();
      return r;
    endmethod
  endinterface

  method ActionValue#(Exception) memoryStage();
    let mci = cexe2memQ.first();
    let  ex = Ex_None;
    cexe2memQ.deq();
    if(mci.getMemResp)
      begin
        // perform a clc/csc op if necessary
        let load = mci.op.op == CapOp_CLCR;
        VirtualMemRequest mreq = defaultValue;
        mreq.addr = unpack(pack(mci.memAddr & ~31));
        if (load) begin
        mreq.operation = tagged Read {
            uncached: ?,
            linked: False,
            noOfFlits: 0,
            bytesPerFlit: BYTE_32
        };
        end else begin
        mreq.operation = tagged Write {
            uncached: ?,
            conditional: False,
            byteEnable: unpack('hFFFFFFFF),
            data: Data {
                cap: unpack(pack(mci.tag)),
                data: pack(mci.cap)
            },
            last: True
        };
        end
        ex <- capMem.req (
           mci.thread,
           mci.ts,
           mreq);
        debug2("cp2mem", $display("CP2: capmem 0x%x %s %b ", mci.memAddr, load ? " -> " : " <- ", mci.tag, fshow(mci.cap)));
      end
    let wci = MemCapInst{thread: mci.thread, ts: mci.ts, op: mci.op, tag: mci.tag, cap: mci.cap, getMemResp: mci.getMemResp && ex == Ex_None, capException: mci.capException};
    cmem2mem2Q.enq(wci);
    return ex;
  endmethod

  method ActionValue#(Exception) memoryStage2(Bool commit);
    if (!commit)
      debug2("cp2mem", $display("CP2: mem2 abort!"));
    let wci <- popFIFOF(cmem2mem2Q);
    let ex <- wci.getMemResp ? capMem.commit(commit) :  toAV(Ex_None);
    cmem2wbQ.enq(wci);
    return ex;
  endmethod

  method ActionValue#(CapWritebackResp) commitWriteback(Bool commit, 
     `ifdef DEBUG 
     TraceEntry te, 
     `endif
     Address pc, 
     Exception exception, Bool eret); // writeback
    let wci = cmem2wbQ.first();
    cmem2wbQ.deq();
    let resp = CapWritebackResp {
      `ifdef DEBUG
      te: te,
      `endif
      flush: False
    };
    Maybe#(Capability) newDelayedPCC = mDelayedPCC[wci.thread];
    Capability oldPCC = crf.pcc[wci.thread][0];
    oldPCC.cursor = oldPCC.base + pc;
    Capability newPCC = oldPCC;
    function addBool(c) = tuple2(True, c);

    match {.ctag, .cap} <- wci.getMemResp ?
                            actionvalue
                              let r <- capMem.resp;
                              if (r.operation matches tagged Read .rop) begin
                                 return tuple2(pack(rop.data.cap) != 0 ? True: False , unpack(rop.data.data));
                              end else begin
                                 dynamicAssert(False, "Only read response expected");
                                 return tuple2(?,?);
                              end
                            endactionvalue
                          :
                            actionvalue
                              return tuple2(wci.tag, wci.cap);
                            endactionvalue;

    `ifdef DEBUG
    if (wci.getMemResp)
      if (isValid(wci.op.dest))
        begin
          let shortCap = capToShortCap(ctag, cap);
          resp.te.entry_type = TraceType_CapLoad;
          resp.te.regVal1    = pack(shortCap)[127:64];
          resp.te.pc         = pack(shortCap)[63:0];
        end
      else
        begin
          let shortCap = capToShortCap(wci.tag, wci.cap);
          resp.te.entry_type = TraceType_CapStore;
          resp.te.regVal1    = pack(shortCap)[127:64];
          resp.te.pc         = pack(shortCap)[63:0];
        end
    else if (isValid(wci.op.dest))
      begin
        let shortCap = capToShortCap(ctag, cap);
        resp.te.entry_type = TraceType_CapOp;
        resp.te.regVal1    = pack(shortCap)[127:64];
        resp.te.regVal2    = pack(shortCap)[63:0];
      end
    `endif

    if(commit)
      begin
        if (mDelayedPCC[wci.thread] matches tagged Valid .c)
          begin
            debug2("wb", $display("CP2: WB write delayed pcc: ", fshow(c)));
            newPCC = c;
            newDelayedPCC = Invalid;
            resp.flush = True; // rmn30 YYY could we avoid flushing on cap. jump?
          end
        if (exception != Ex_None && exception != Ex_Suspended) // exception
          begin
            debug2("trace", $display("CP2\tT%1d: EXCEPTION: ", wci.thread, fshow(wci.capException)));
            debug2("trace", $display("CP2\tT%1d: pcc  <= ", wci.thread, fshow(crf.kcc(wci.thread))));
            debug2("trace", $display("CP2\tT%1d: epcc <= ", wci.thread, fshow(oldPCC)));
            if (exception == Ex_CoProcess2 || exception == Ex_CP2Trap)
              capCause[wci.thread][0] <= wci.capException;
            match {.kt, .kcc} = crf.kcc(wci.thread);
            newPCC = (kt) ? kcc : invalidCap;
            crf.write(wci.thread, 31, True, oldPCC);
            resp.flush = True;
          end
        else if (eret) // eret
          begin
            debug2("trace", $display("CP2\tT%1d: ERET pcc <= ", wci.thread, fshow(crf.epcc(wci.thread))));
            match {.et, .epcc } = crf.epcc(wci.thread);
            newPCC = et ? epcc : invalidCap;
            resp.flush = True;
          end
        else if (wci.op.op == CapOp_SetCause) // special case -- set cause without exception
          begin
            debug2("trace", $display("CP2\tT%1d: SetCause <= ", wci.thread, fshow(wci.capException)));
            capCause[wci.thread][0] <= wci.capException;
            resp.flush = True;
          end
        else if (wci.op.op == CapOp_JR)  // capability jump
          begin
            debug2("trace", $display("CP2\tT%1d: JR pcc <= ", wci.thread, fshow(cap)));
            newDelayedPCC = tagged Valid cap;
            // write link cap
            if (wci.op.dest matches tagged Valid .c)
              begin
                let linkPCC = oldPCC;
                linkPCC.cursor = linkPCC.cursor + 8;
                debug2("trace", $display("CP2\tT%1d: c%1d <= ", wci.thread, c, fshow(linkPCC)));
                crf.write(wci.thread, c, True, linkPCC);
              end
            // don't flush until after branch delay
          end
        else if (wci.op.dest matches tagged Valid .c)  // ordinary commit
          begin
            debug2("trace",$display("CP2\tT%1d: c%1d <= ", wci.thread, c, show_tagged_cap(ctag, cap)));
            crf.write(wci.thread, c, ctag, cap);
          end
        else if(wci.op.displayRF)
          begin
 		    `ifndef VERIFY2
            debugDisplay(debug_crf.debugging, wci.thread);
			`endif
          end
      end
    crf.pcc[wci.thread][0]  <= newPCC;
    mDelayedPCC[wci.thread] <= newDelayedPCC;
    return resp;
  endmethod

  method Action debugDisplay();
    $write("CP2 Pipe status: WB: ");
    displayFIFO1(cmem2wbQ);
    $write(" MEM: ");
    displayFIFO1(cexe2memQ);
    $write(" EXE: ");
    cdec2exeQ_debug.debugging.debug_display(?);
    $write(" DEC: ");
    cfet2decQ_debug.debugging.debug_display(?);
    $display("");
  endmethod

  method Bool isFlushed();
    return True; // XXX rmn30 I think this is unnecessary since
                 // capability pipeline executes in lock-step with
                 // main pipeline.
  endmethod
endmodule
