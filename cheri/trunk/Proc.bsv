/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014 Colin Rothwell
 * Copyright (c) 2014 Alexandre Joannou
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
 *
 ******************************************************************************
 *
 * Author: Robert Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Top-Level Cheri Processor
 *
 ******************************************************************************/

import GetPut::*;
import ClientServer::*;
import Vector::*;
import MasterSlave::*;

import MIPS::*;
import MIPSTop::*;

import MemTypes::*;
import CheriAxi::*;
import Processor::*;
import PIC::*;
import Peripheral::*;

`ifdef MULTI
  import Multicore::*;
`else
  (* synthesize *)
  module mkMyPIC(PIC#(32, Bit#(0)));
    PIC#(32, Bit#(0)) myPIC <- mkPIC();
    return myPIC;
  endmodule
`endif

(* synthesize *)
module mkCheri(Processor);
  `ifdef MULTI
    MulticoreIfc beri <- mkMulticore;
  `else
    MIPSTopIfc beri <- mkMIPSTop(0);
    PIC#(32, Bit#(0)) myPIC <- mkMyPIC();
    
    // Synchronised count and pause registers for all cores.
    Reg#(Bit#(48))  count   <- mkReg(48'b0);
    Reg#(Bool)      pause   <- mkReg(False);
  
    (* fire_when_enabled, no_implicit_conditions *)
    rule irqForward;
      Bit#(0) tid = unpack(0);
      beri.putIrqs(truncate(myPIC.irqMapper.getMIPSIrqs(tid))); // rmn30 XXX don't support irq 5-7 
      if (!pause) count <= count + 1;
      beri.putState(count, pause);
    endrule
    
    rule getPause;
      pause <= beri.getPause();
    endrule

    Vector#(1, Server#(Bit#(8), Bit#(8))) debugVector = newVector();
    debugVector[0] = beri.debugStream;

    Vector#(1, Peripheral#(0)) periphVector = newVector();
    periphVector[0] = myPIC.regs;

    method Action putIrqs(Bit#(32) irqs);
      myPIC.irqMapper.putExtIrqs(irqs);
    endmethod
  `endif
   
  `ifdef MULTI
    interface Master extMemory = beri.memoryStage;
    interface pic = beri.pic;
    interface putIrqs = beri.putIrqs;
    interface Server debugStream = beri.debugStream;
  `else
    interface Master extMemory = beri.memory;
    interface PIC pic = periphVector;
    interface Server debugStream = debugVector;
  `endif
  `ifdef RMA
    interface networkRx = beri.networkRx;
    interface networkTx = beri.networkTx;
  `endif
  `ifdef DMA_VIRT
    interface tlbs = beri.tlbs;
  `endif
  interface reset_n = beri.reset_n;
endmodule
