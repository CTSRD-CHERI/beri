/*-
 * Copyright (c) 2011 Jonathan Woodruff
 * Copyright (c) 2011-2012 SRI International
 * Copyright (c) 2013 Robert M. Norton
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
 *
 ******************************************************************************
 *
 * Description: Capability Register File
 *
 ******************************************************************************/

import Vector :: *;
import FIFO :: *;
import FShow :: *;

import MIPS :: *;
import CHERITypes :: *;
import CapabilityTypes :: *;
import CapabilityMicroTypes :: *;
import Library::*;
import SearchFIFO :: *;
import Bram  :: *;
import Debug :: *;
import EHR   :: *;

//--------------------------------------------------------------------------------------------------------
// Capability RegisterFile
//--------------------------------------------------------------------------------------------------------

interface CapabilityRegisterFile;
  interface Vector#(NumThreads, EHR#(2, Capability)) pcc;
  method TaggedCapability               epcc (ThreadID tid);
  method TaggedCapability               kcc (ThreadID tid);
  method Action                         readReqA(ThreadID tid, CapRegName x);
  method ActionValue#(TaggedCapability) readRespA();
  method Action                         readReqB(ThreadID tid, CapRegName x);
  method ActionValue#(TaggedCapability) readRespB();
  method Action                         write(ThreadID tid, CapRegName x, Bool valid, Capability v);

  method Action                         readReqD(ThreadID tid, CapRegName x);  // for debug unit
  method ActionValue#(TaggedCapability) readRespD();
  method Action                         writeD(ThreadID tid, CapRegName x, Bool valid, Capability v);
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkCapabilityRegisterFile(CapabilityRegisterFile);
  Vector#(NumThreads, EHR#(2,Capability))     pccReg  <- replicateM(mkEHR(defaultCap));
  Vector#(NumThreads, Reg#(TaggedCapability)) epccReg <- replicateM(mkReg(tuple2(True, defaultCap)));
  Vector#(NumThreads, Reg#(TaggedCapability)) kccReg  <- replicateM(mkReg(tuple2(True, defaultCap)));
  Bram#(ThreadCapReg, TaggedCapability)       rfA     <- mkBram();
  Bram#(ThreadCapReg, TaggedCapability)       rfB     <- mkBram();

  //initialization mechanisms
  Reg#(CapRegName) cap    <- mkReg(minBound);
  Reg#(ThreadID)   thread <- mkReg(minBound);
  Reg#(Bool)       ready  <- mkReg(False);

  rule initialize (!ready);
    let tcr = ThreadCapReg {tid: thread, r: cap};
    rfA.write(tcr, tuple2(True, defaultCap));
    rfB.write(tcr, tuple2(True, defaultCap));
    if (cap == maxBound && thread == maxBound)
      ready <= True;
    else if (cap == maxBound)
      begin
        cap    <= minBound;
        thread <= thread + 1;
      end
    else
      cap <= cap + 1;
  endrule

  method Action readReqA(ThreadID t, CapRegName x) if (ready);
    let tcr = ThreadCapReg {tid: t, r: x};
    rfA.readReq(tcr);
  endmethod

  method ActionValue#(TaggedCapability) readRespA() if (ready);
    let rv <- rfA.readResp();
    return rv;
  endmethod

  method Action readReqB(ThreadID t, CapRegName x) if (ready);
    let tcr = ThreadCapReg {tid: t, r: x};
    rfB.readReq(tcr);
  endmethod

  method ActionValue#(TaggedCapability) readRespB() if (ready);
    let rv <- rfB.readResp();
    return rv;
  endmethod

  method Action write(ThreadID t, CapRegName a, Bool valid, Capability x) if (ready);
    let tcr = ThreadCapReg {tid: t, r: a};
    rfA.write(tcr, tuple2(valid, x));
    rfB.write(tcr, tuple2(valid, x));
    if(a == 29) kccReg[t]  <= tuple2(valid, x);
    if(a == 31) epccReg[t] <= tuple2(valid, x); //gives us a fast cached version to read
  endmethod

  method Action readReqD(ThreadID t, CapRegName x) if (ready);
    let tcr = ThreadCapReg {tid: t, r: x};
    rfB.readReqD(tcr);
  endmethod

  method ActionValue#(TaggedCapability) readRespD() if (ready);
    let rv <- rfB.readRespD();
    return rv;
  endmethod

  method Action writeD(ThreadID t, CapRegName a, Bool valid, Capability x) if (ready);
    let tcr = ThreadCapReg {tid: t, r: a};
    rfA.writeD(tcr, tuple2(valid, x));
    rfB.writeD(tcr, tuple2(valid, x));
    if(a == 29) kccReg[t]  <= tuple2(valid, x);
    if(a == 31) epccReg[t] <= tuple2(valid, x); //gives us a fast cached version to read
  endmethod

  method TaggedCapability epcc(ThreadID t) if (ready);
    return epccReg[t];
  endmethod

  method TaggedCapability kcc(ThreadID t) if (ready);
    return kccReg[t];
  endmethod

  interface pcc = when(ready, pccReg);
endmodule

module mkForwardingCapabilityRegisterFile
          #(CapabilityRegisterFile archRF,
            Vector#(n, Forwarder#(ThreadCapReg, TaggedCapability)) fwds)
                   (CapabilityRegisterFile)
            provisos(Add#(1, k__, n));

  //select left-most value in parallel

  FIFO#(ThreadCapReg) portA <- mkFIFO();
  FIFO#(ThreadCapReg) portB <- mkFIFO();

  Maybe#(Maybe#(TaggedCapability)) forwardResultA = foldValues(getValuesA(fwds, portA.first()));
  Maybe#(Maybe#(TaggedCapability)) forwardResultB = foldValues(getValuesB(fwds, portB.first()));

  method Action readReqA(tid, rn);
    archRF.readReqA(tid, rn); portA.enq(ThreadCapReg{tid: tid, r: rn});
  endmethod

  method Action readReqB(tid, rn);
    archRF.readReqB(tid, rn); portB.enq(ThreadCapReg{tid: tid, r: rn});
  endmethod

  //ndave: Stall if the value is to be forwarded but hasn't been generated
  method ActionValue#(TaggedCapability) readRespA() if (forwardResultA != Valid(Invalid)); // only V(V(x)) or I
    let v <- archRF.readRespA(); portA.deq();
    return fromMaybe(v, joinMaybe(forwardResultA));
  endmethod

  //ndave: Stall if the value is to be forwarded but hasn't been generated
  method ActionValue#(TaggedCapability) readRespB() if (forwardResultB != Valid(Invalid));
    let v <- archRF.readRespB(); portB.deq();
    return fromMaybe(v, joinMaybe(forwardResultB));
  endmethod

  method Action write(ThreadID tid, CapRegName x, Bool t, Capability v) = archRF.write(tid, x,t,v);

  //we have to do something about pcc speculation
  interface Reg pcc        = archRF.pcc;
  method TaggedCapability epcc(ThreadID t) = when(False, archRF.epcc(t)); //can't read forwarded value
  method TaggedCapability kcc(ThreadID t)  = when(False, archRF.kcc(t)); //can't read forwarded value
endmodule

module [m] mkCapabilityRegisterFile_Debug#(m#(CapabilityRegisterFile) mkRF)
                            (Debug#(CapabilityRegisterFile, Display#(ThreadID)))
  provisos(IsModule#(m, a__));

  CapabilityRegisterFile               rf <- mkRF();
  Vector#(NumThreads, Vector#(32, Reg#(Capability))) debugCaps <- replicateM(replicateM(mkReg(defaultCap)));

  interface CapabilityRegisterFile inf;
    method Action readReqA(t, rn)                        = rf.readReqA(t, rn);
    method ActionValue#(TaggedCapability) readRespA() = rf.readRespA();
    method Action readReqB(t, rn)                        = rf.readReqB(t, rn);
    method ActionValue#(TaggedCapability) readRespB() = rf.readRespB();
    method Action write(tid, rn, t, v);
      rf.write(tid, rn,t,v);
      debugCaps[tid][rn] <= v;
    endmethod
    interface Reg pcc = rf.pcc;
      method TaggedCapability epcc(ThreadID t) = rf.epcc(t);
      method TaggedCapability kcc(ThreadID t)  = rf.kcc(t);
    endinterface

  interface Display debugging;
    method Action debug_display(ThreadID t);
      $display("======  Thread %2d  ======", t);
      $display("======   RegFile   ======");
      let pcc = rf.pcc[t][0];
      $display("DEBUG CAP PCC u:%d perms:0x%x type:0x%x base:0x%x length:0x%x",
               pcc.unsealed, pcc.perms, pcc.oType_eaddr, pcc.base, pcc.length);
      for (Integer i = 0; i<32; i=i+1)
        $display("DEBUG CAP REG %d u:%d perms:0x%x type:0x%x base:0x%x length:0x%x",
           i,
           debugCaps[t][i].unsealed,
           debugCaps[t][i].perms,
           debugCaps[t][i].oType_eaddr,
           debugCaps[t][i].base,
           debugCaps[t][i].length);
    endmethod
  endinterface
endmodule
