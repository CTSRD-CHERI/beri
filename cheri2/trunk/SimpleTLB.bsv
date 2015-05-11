/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
 * Copyright (c) 2012 Jonathan Woodruff
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
 * Description: Simple version of CHERI2 Translation Lookaside Buffer. This 
 * version of the TLB is fully associative so does not have good properties
 * for synthesising but can be useful for testing/simulation.
 *
 * DOES NOT SUPPORT THREADS.
 *
 ******************************************************************************/

module mkTLB(TLB);
  Vector#(TLBSize, Reg#(TLBEntry)) entries <- replicateM(mkRegU);

  // For the update interface
  let                 probeQ <- mkFIFO1;
  let                  readQ <- mkFIFO1;
  let                 writeQ <- mkFIFO1;

  function Maybe#(TLBIndex) findMatch(ASID asid, VAddress va);
    function Bool hasMatch(Reg#(TLBEntry) reReg);
      return entryMatches(reReg, asid, va);
    endfunction
    return (findFirstMatchingIndex(hasMatch, entries));
  endfunction

  rule doWrite;
    match {.idx, .entry} <- popFIFO(writeQ);
    debug2("tlb", $display("write: idx=%d", idx, entry));
    entries[idx] <= entry;
  endrule

  module mkTLBLookup#(Integer i)(TLBLookup);
    FIFO#(TLBResponse) respQ <- mkPipeFIFO;
    method Action req(TLBRequest x);
      let m_index      = findMatch(x.ts.asid, x.addr);
      let m_entry      = liftM(select(readVReg(entries)), m_index);
      respQ.enq(getTLBResponse(x, m_entry));
    endmethod

    method ActionValue#(TLBResponse) resp;
      respQ.deq;
      return respQ.first;
    endmethod
  endmodule

  //-------------------------------------------------------------------------
  // Interface

  // construct vector of lookups
  let lookupMods <- mapM(mkTLBLookup, genVector);
  interface lookups = lookupMods;

  interface TLBUpdate update;
    method Action probe_req(ThreadID thread, ASID asid, VAddress va);
      probeQ.enq(tuple3(thread, asid, va));
    endmethod

    method ActionValue#(Maybe#(TLBIndex)) probe_resp;
      match {.thread, .asid, .va} <- popFIFO(probeQ);
      debug2("tlb", action
             $display("Probe asid=%x, va=%x", asid, va);
             for (int i=0; i<64; i = i + 1)
               begin
                 let hi=entries[i].assoc.entryHi;
                 let g =entries[i].assoc.global;
                 $display("Entry %d: r=%d vpn2=%x asid=%x g=%d", i, hi.r, {hi.vpn2, 13'b0}, hi.asid, g);
               end
         endaction);
      return findMatch(asid, va);
    endmethod

    method Action read_req(ThreadID thread, TLBIndex idx);
      readQ.enq(tuple2(thread, idx));
    endmethod

    method ActionValue#(TLBEntry) read_resp;
      match {.thread, .idx} <- popFIFO(readQ);
      return entries[idx];
    endmethod

    method Action write(ThreadID thread, TLBIndex idx, TLBEntry entry);
      writeQ.enq(tuple2(idx,entry));
    endmethod
  endinterface
endmodule
