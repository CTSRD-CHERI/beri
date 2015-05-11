/*-
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014 Alexandre Joannou
 * Copyright (C) 2014 Colin Rothwell
 * Copyright (C) 2015 Paul J. Fox
 * All rights reserved.
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
 *
 ******************************************************************************
 *
 * Author: Alan A. Mujumdar <alan.mujumdar@cl.cam.ac.uk>
 * 
 ******************************************************************************
 * Description
 * 
 * This module sits in between TopSimulation and MIPSTop. Its purpose is to 
 * create beris and link them. 
 * The module contains an interface that allows the CP0 register to acquire
 * a unique ID.
 ************************************************************************/

import MIPS::*;
import MemTypes::*;
import Memory::*;
import FIFO::*;
import FIFOF::*;
import Debug::*;
import GetPut::*;
import ClientServer::*;
import MasterSlave::*;
import Connectable::*;
import Interconnect::*;
import MIPSTop::*;
`ifndef MICRO
  import L2Cache::*;
`endif
import AvalonStreaming::*;
import Vector::*;
import PIC::*;
import Peripheral::*;
`ifdef CAP
  import CapCop :: *;
  import TagCache::*;
  import Connectable::*;
  `define USECAP
`elsif CAP128
  import CapCop128 :: *;
  import TagCache::*;
  import Connectable::*;
  `define USECAP
`endif
`ifdef RMA
  import RemoteMemoryAccessorCheri::*;
`endif

// For testing the memory sub-system
`ifdef TEST_MEM
  import MIPSTop_TestMem::*;
`endif

interface MulticoreIfc;
  interface Master#(CheriMemRequest, CheriMemResponse) memoryStage;  
  (* always_ready, always_enabled *)
  method Action putIrqs(Bit#(32) irqs);
  interface Vector#(CORE_COUNT, Server#(Bit#(8), Bit#(8))) debugStream; 
  interface Vector#(CORE_COUNT, Peripheral#(0)) pic;
  `ifdef RMA
  interface AvalonStreamSourcePhysicalIfc#(Bit#(76)) networkRx;
  interface AvalonStreamSinkPhysicalIfc#(Bit#(76)) networkTx;
  `endif
  method Bool reset_n();

  // For testing the memory sub-system
  interface Vector#(CORE_COUNT, MIPSMemory) mipsMemories;
endinterface

  (*synthesize*)
  module mkMulticore(MulticoreIfc);

    // For testing the memory sub-system
    `ifdef TEST_MEM
      function mkMIPSTop = mkMIPSTop_TestMem;
    `endif

    // Instantiating a number processor cores as stated by CORE_COUNT
    Vector#(CORE_COUNT, MIPSTopIfc)	beri		<- mapM(mkMIPSTop, map(fromInteger, genVector));
    function Vector#(TMul#(2,CORE_COUNT), Master#(CheriMemRequest,CheriMemResponse))
        getBeriMasters(Vector#(CORE_COUNT, MIPSTopIfc) b);
        Vector#(TMul#(2,CORE_COUNT), Master#(CheriMemRequest,CheriMemResponse)) masters;
        for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin
            masters[2*i] = b[i].imemory;
            masters[2*i+1] = b[i].dmemory;
        end
        return masters;
    endfunction

    Vector#(TMul#(2,CORE_COUNT), Master#(CheriMemRequest,CheriMemResponse)) 
            beriMasters = getBeriMasters(beri);
    
    Vector#(1, Slave#(CheriMemRequest,CheriMemResponse)) topSlave;
   `ifndef MICRO
      // L2Cache instantiation has been moved from Memory.bsv to this location
      L2CacheIfc l2cache <- mkL2Cache;
      topSlave[0] = l2cache.cache;
      
      // A single port L2Cache can not communicate directly with the L1's due to the nature
      // of the merge module. A different merge module is used with the multiport L2, it 
      // Allows direct L1Cache invalidation

      rule invalidateL1Caches;
        Maybe#(InvalidateCache) inv <- l2cache.getInvalidate;
        if (inv matches tagged Valid .invalidate) begin
          for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin
            if (invalidate.sharers[2*i]) begin 
              beri[i].invalidateICache(unpack(pack(invalidate.addr)));
            end
            if (invalidate.sharers[2*i+1]) begin
              beri[i].invalidateDCache(unpack(pack(invalidate.addr)));
            end
            debug2("multicore", $display("<time %0t Multicore> Invalidate L1 Shared Block Core:%d, BitMap:%b, Addr:%x", $time, fromInteger(i), invalidate.sharers, invalidate.addr));
          end
        end
      endrule

      Master#(CheriMemRequest,CheriMemResponse) lastMaster = l2cache.memory;
    `else
      Forward#(CheriMemRequest,CheriMemResponse) forwarder <- mkForward;
      topSlave[0] = forwarder.slave;
      Master#(CheriMemRequest,CheriMemResponse) lastMaster = forwarder.master;
    `endif
 
    // I do this sleazy forceReqType trickery because I can't be bothered to
    // work out the complicated return type.
    function truncateMasterID(resp);
        CheriMemResponse forceRespType = resp;
        return tagged Valid unpack(truncate(pack(resp.masterID)));
    endfunction

    mkBus(beriMasters,constFn(tagged Valid unpack(0)),topSlave,truncateMasterID);

    // Connect the Remote Memory Accessor.  This is very likely to have to move up or down the stack
    `ifdef RMA
      RemoteMemoryAccessorCheriIfc rma <- mkRemoteMemoryAccessorCheri(0); // Argument is the board id, needs to be different for every board 
      mkConnection(lastMaster, rma.slave);
      lastMaster = rma.master;
    `endif

    // Connecting the L2Cache to the TagCache. TagCache is then connected to DRAM
    `ifdef USECAP
      TagCacheIfc tagCache <- mkTagCache(); 
      mkConnection(lastMaster, tagCache.cache);
      lastMaster = tagCache.memory;
    `endif
    
    // Synchronised count and pause registers for all cores.
    Reg#(Bit#(48))                      count           <- mkReg(48'b0);
    Reg#(Bool)                          pause           <- mkReg(False);
    
    (* fire_when_enabled, no_implicit_conditions *)
    rule putStates;
      if (!pause) count <= count + 1;
      for (Integer i=0; i<valueof(CORE_COUNT); i=i+1)
        beri[i].putState(count, pause);
    endrule
    
    for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin
      rule getPause;
        Bool getPause = beri[i].getPause();
        pause <= getPause;
      endrule
    end
    
    // Creating one PIC per core
    Vector#(CORE_COUNT,PIC#(32,Bit#(0))) pics <- replicateM(mkPIC);

    // PIC interfacing
    (* fire_when_enabled, no_implicit_conditions *)  
    rule irqForward;
      for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin   
        Bit#(0) tid = unpack(0); 
        beri[i].putIrqs(truncate(pics[i].irqMapper.getMIPSIrqs(tid)));
      end  
    endrule 

    // For testing the memory sub-system
    function MIPSMemory getMipsMemory(MIPSTopIfc core) = core.mipsMemory;

    Vector#(CORE_COUNT, Server#(Bit#(8), Bit#(8))) debug;
    Vector#(CORE_COUNT, Peripheral#(0)) picVector;
  
    for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin	
      debug[i] = beri[i].debugStream;
      picVector[i] = pics[i].regs;
    end 

    method Action putIrqs(Bit#(32) irqs); 
      for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin
        pics[i].irqMapper.putExtIrqs(zeroExtend(irqs));
      end  
    endmethod 

    interface PIC pic = picVector;
    interface debugStream = debug;
    method reset_n = beri[0].reset_n;
    interface memoryStage = lastMaster;

    // For testing the memory sub-system
    interface mipsMemories = map(getMipsMemory, beri);

    `ifdef RMA
    interface networkRx = rma.networkRx;
    interface networkTx = rma.networkTx;
    `endif

  endmodule

