/*-
 * Copyright (c) 2013, 2014 Jonathan Woodruff
 * Copyright (c) 2013 Alex Horsman
 * Copyright (c) 2013, 2014, 2015 Alexandre Joannou
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

import Debug::*;
import MemTypes::*;
import DefaultValue::*;
import MIPS::*;
import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import FF::*;
import GetPut::*;
import MasterSlave::*;
import MEM::*;
import CacheCore::*;
import BeriUGBypassFIFOF::*;
import Vector::*;
import ConfigReg::*;
`ifdef NOCACHE
  import PISM::*;
`endif
`ifdef STATCOUNTERS
import StatCounters::*;
`endif

/* =================================================================
 ICache
 =================================================================*/

`ifdef MEM256
  typedef 8 BusInsts;
`elsif MEM128
  typedef 4 BusInsts;
`elsif MEM64
  typedef 2 BusInsts;
`endif

typedef SizeOf#(CheriPhyByteOffset) ByteOffsetSize;

`ifdef NOT_FLAT
  (*synthesize*)
`endif
module mkICache#(Bit#(16) cacheId)(CacheInstIfc);
  FIFO#(CacheResponseInstT)          preRsp_fifo <- mkLFIFO;
  FIFO#(CheriPhyByteOffset)                addrs <- mkLFIFO;
  Reg#(CacheRequestInstT)              reqInWire <- mkWire;
  FIFOF#(Bool)                      nextFromCore <- mkLFIFOF;
  //FIFOF#(Bool)                        returnNext <- mkUGSizedFIFOF(4); // Lots of room due to being unguarded.
  FF#(CheriMemRequest, 2)                memReqs <- mkUGFF();
  FF#(CheriMemResponse, 2)               memRsps <- mkUGFF(); // If this FIFO has capacity for less than 4 (the size of one burst response) the system can wedge on a SYNC when the data interface stalls waiting for all responses.
  CacheCore#(2, Indices, 1)                 core <- mkCacheCore(cacheId, WriteThrough, OnlyReadResponses, InOrder, ICache, 
                                                                zeroExtend(memReqs.remaining()), 
                                                                ff2fifof(memReqs), ff2fifof(memRsps));
  Reg#(CheriTransactionID)        transactionNum <- mkReg(0);
  Reg#(PhyAddress)                lastInvalidate <- mkRegU;

  rule packCommits;
    core.nextWillCommit(True);
  endrule
  
  Bool putReady = (core.canPut() && nextFromCore.notFull());
  
  rule doPut(putReady);
    CacheRequestInstT reqIn = reqInWire;
    debug2("icache", $display("<time %0t, cache %0d, ICache> putting ICache request ", $time, cacheId, fshow(reqIn)));
    Bool cached = reqIn.tr.cached;
    CheriMemRequest mem_req = defaultValue;
    mem_req.addr = unpack(reqIn.tr.addr);
    mem_req.masterID = unpack(truncate(cacheId));
    mem_req.transactionID = transactionNum;
    mem_req.operation = tagged CacheOp CacheOperation{
                            inst: CacheNop,
                            cache: ICache,
                            indexed: True
                          };
    CacheOperation cop = reqIn.cop;
    Bool expectResponse = False;
    Bool returnInst = False;
    
    CacheResponseInstT resp = CacheResponseInstT{inst: reqIn.defaultInst, exception: reqIn.tr.exception};

    case (cop.inst)
      CacheNop: begin
      end
      Read: begin
        if (resp.exception == None) begin
          mem_req.operation = tagged Read {
                            uncached: !cached,
                            linked: reqIn.tr.ll,
                            noOfFlits: 0,
                            bytesPerFlit: BYTE_4
                          };
          expectResponse = True;
        end
        returnInst = True;
      end
      default: begin
        resp.exception = None; // Not really necissary since we don't respond.
        mem_req.operation = tagged CacheOp cop;
      end
    endcase
    
    debug2("icache", $display("<time %0t, cache %0d, ICache> putting to core ", $time, cacheId, fshow(mem_req)));
    core.put(mem_req);
    // Ensure that the core never sees the same transaction ID twice.
    transactionNum <= transactionNum + 1;
      
    if (returnInst) begin
      preRsp_fifo.enq(resp);
      nextFromCore.enq(expectResponse);
      addrs.enq(truncate(reqIn.tr.addr));
    end
  endrule
  
  method Action put(CacheRequestInstT reqIn) if (putReady);
    reqInWire <= reqIn;
  endmethod
  
  method ActionValue#(CacheResponseInstT) getRead() if (!nextFromCore.first || core.response.canGet());
    CacheResponseInstT resp <- toGet(preRsp_fifo).get;
    CheriPhyByteOffset addr <- toGet(addrs).get;
    Bool    fromCore <- toGet(nextFromCore).get;
    if (fromCore) begin
      CheriMemResponse mr <- core.response.get();
      Vector#(8,Bit#(8)) byteArray = unpack(truncate(mr.data.data));
      byteArray = reverse(byteArray);
      Vector#(2,Bit#(32)) instArray = unpack(pack(byteArray)); 
      Bit#(1) index = ~addr[2];
      resp.inst = classifyMIPSInstruction(instArray[index]);
      //if (mr.operation matches tagged Read .rr) begin
        // Verilog synthesis chokes on this series of array ops.  Lame.
        //Vector#(TMul#(BusInsts,4),Bit#(8)) byteArray = unpack(rr.data.data);
        //byteArray = reverse(byteArray);
        //Vector#(BusInsts,Bit#(32)) instArray = unpack(pack(byteArray)); 
        //Bit#(TLog#(BusInsts)) index = (0-1)-truncate(addr>>2);
        //resp.inst = classifyMIPSInstruction(instArray[index]);
        /*Vector#(BusInsts,Bit#(32)) instArray = unpack(rr.data.data);
        Bit#(TLog#(BusInsts)) index = truncate(addr>>2);
        Vector#(4,Bit#(8)) instBits = unpack(instArray[index]);
        resp.inst = classifyMIPSInstruction({instBits[0],instBits[1],instBits[2],instBits[3]});*/
      //end
    end //else resp.inst = classifyMIPSInstruction(32'b0);
    debug2("icache", $display("<time %0t, cache %0d, ICache> returning ICache response ", $time, cacheId, fshow(resp)));
    return resp;
  endmethod

  `ifndef TIMEBASED
    method Action invalidate(Bit#(40) addr);
      // Filter out multiple invalidates to the same line.
      if (addr != lastInvalidate) begin
        debug2("icache", $display("<time %0t, cache %0d, ICache> put Invalidate! addr:%x", $time, cacheId, addr));
        core.invalidate(unpack(addr));
      end
      lastInvalidate <= addr;
    endmethod
  `endif

  method L1ChCfg getConfig();
    /*L1ChCfg{
      a:0,  //  Associativity = A+1.  (A=0 for direct mapped)
      l:6,  //  Cache line size = 2*2^L.  L=0 if there is no cache. (32)
      s:1   //  Number of Cache index positions is 64 * 2^S. Mult by Associativity for total number of cache lines. (128)
    };*/
    `ifdef MEM128
      L1ChCfg ret = L1ChCfg{ a:1, l:5, s:indicesMinus6};
    `elsif MEM64
      L1ChCfg ret = L1ChCfg{ a:1, l:4, s:indicesMinus6};
    `else
      L1ChCfg ret = L1ChCfg{ a:1, l:6, s:indicesMinus6};
    `endif
    return ret;
  endmethod
  
  interface Master memory;
    interface request  = toCheckedGet(ff2fifof(memReqs));
    interface response = toCheckedPut(ff2fifof(memRsps));
  endinterface
  `ifdef STATCOUNTERS
  interface Get cacheEvents;
    method ActionValue#(ModuleEvents) get () = core.cacheEvents.get();
  endinterface
  `endif
endmodule
