/*-
 * Copyright (c) 2016 Jonathan Woodruff
 * Copyright (c) 2015 Colin Rothwell
 * Copyright (c) 2014 Alan A. Mujumdar
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

import ClientServer::*;
import MasterSlave::*;
import GetPut::*;
import MemTypes::*;
import Vector::*;
import MIPS::*;
//import Debug::*;
// Memory.bsv describes the memory hierarchy.
import Memory::*;

// MIPSTopIfc is the interface for the processor top level, exporting the memory
// interface as well as interrupts and a debug interface.
interface MIPSTopIfc;
  `ifdef MULTI
    // Instruction cache invalidate interface
    method Action invalidateICache(PhyAddress addr);
    // Data cache invalidate interface
    method Action invalidateDCache(PhyAddress addr);
    method ActionValue#(Bool) getInvalidateDone;
    interface Master#(CheriMemRequest, CheriMemResponse) imemory;
    interface Master#(CheriMemRequest, CheriMemResponse) dmemory;
  `else
    // Memory client interface (which initializes transactions), 256 bit data
    // width, 35-bit WORD address width. As there are 2^5 = 32 bytes per word,
    // this is equivalent to a 35 + 5 = 40-bit byte address.
    interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `endif
  // interface below is required for the multiport L2Cache
  //interface Client#(MemoryRequest#(35, 32), BigMemoryResponse#(256)) memory;
  // 5 interrupt lines, matching the standard MIPS spec.
  (* always_ready, always_enabled *)
  // Deliver common state to this core.
  method Action putState(Bit#(48) count, Bool pause, Bit#(5) interruptLines);
  // Tell the system to pause.  This should pause all cores.
  method Bool getPause();
  // The debug interface is a byte stream interface, a channel of bytes in and a
  // channel of bytes out.
  interface Server#(Bit#(8), Bit#(8)) debugStream;
    // Also a reset out interface. This allows us to reset the system and also
    // ourselves (if it is fed back in).
  method Bool reset_n();
  // Whether we want the trace unit to be recording at each cycle.

  // For testing the memory sub-system
  interface MIPSMemory mipsMemory;
  
  `ifdef DMA_VIRT
      interface Vector#(2, Server#(TlbRequest, TlbResponse)) tlbs;
  `endif
endinterface
