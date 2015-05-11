/*-
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014 Alexandre Joannou
 * Copyright (C) 2014 Colin Rothwell
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
import FIFO::*;
import FIFOF::*;
//import SpecialFIFOs::*;
//import FIFOLevel::*;
import GetPut::*;
import ClientServer::*;
import MasterSlave::*;
import Interconnect::*;
import MIPSTop::*;
import Merge::*;
import L2Cache::*;
import AvalonStreaming::*;
import Vector::*;
import PIC::*;
import Peripheral::*;
`ifdef CAP
  import CapCop::*;
  import TagCache::*;
  import Connectable::*;
`endif 

interface MulticoreIfc;
  interface Master#(CheriMemRequest, CheriMemResponse) memoryStage;  
  method Action putIrqs(Bit#(32) irqs);
  interface Vector#(CORE_COUNT, Server#(Bit#(8), Bit#(8))) debugStream; 
  interface Vector#(CORE_COUNT, Peripheral#(0)) pic;
  method Bool reset_n();
endinterface

  (*synthesize*)
  module mkMulticore(MulticoreIfc);

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

    // L2Cache instantiation has been moved from Memory.bsv to this location
    L2CacheIfc				l2cache		<- mkL2Cache; 
    Vector#(1, Slave#(CheriMemRequest,CheriMemResponse)) l2slave;
    l2slave[0] = l2cache.cache;

    mkBus(beriMasters,constFn(tagged Valid unpack(0)),l2slave,routeFromField);

    // Creating one PIC per core
    Vector#(CORE_COUNT,PIC#(64,Bit#(0))) pics            <- replicateM(mkPIC);

    // Connecting the L2Cache to the TagCache. TagCache is then connected to DRAM
    `ifdef CAP
      TagCacheIfc                       tagCache        <- mkTagCache(); 
      mkConnection(l2cache.memory, tagCache.cache);
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

    // PIC interfacing
    (* fire_when_enabled, no_implicit_conditions *)  
    rule irqForward;
      for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin   
        Bit#(0) tid = unpack(0); 
        beri[i].putIrqs(truncate(pics[i].irqMapper.getMIPSIrqs(tid)));
      end  
    endrule 

    // A single port L2Cache can not communicate directly with the L1's due to the nature
    // of the merge module. A different merge module is used with the multiport L2, it 
    // Allows direct L1Cache invalidation
    rule invalidateL1Caches;
      InvalidateCache inv <- l2cache.invalidate.request.get();
      for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin
	if (inv.sharers[2*i]) begin 
          beri[i].invalidateICache(unpack(pack(inv.addr)));
        end
        if (inv.sharers[2*i+1]) begin
          beri[i].invalidateDCache(unpack(pack(inv.addr)));
        end
        debug($display("Multicore Invalidate L1 Shared Block Core:%d, BitMap:%b, Addr:%x", fromInteger(i), inv.sharers, inv.addr));
      end
    endrule

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
    `ifdef CAP
      interface memoryStage = tagCache.memory;
    `else
      interface memoryStage = l2cache.memory;
    `endif

  endmodule

