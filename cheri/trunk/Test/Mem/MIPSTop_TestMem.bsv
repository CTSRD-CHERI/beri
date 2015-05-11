/*-
 * Copyright (c) 2015 Matthew Naylor
 * All rights reserved.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
 * project, funded by EPSRC grant EP/K008528/1.
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

import MemTypes :: *;
import ClientServer :: *;
import MasterSlave :: *;
import MIPS :: *;
import Memory::*;
import CP0::*;
import DebugUnit::*;
import GetPut::*;
import MIPSTop::*;

(* synthesize *)
module mkMIPSTop_TestMem#(Bit#(16) coreId)(MIPSTopIfc);
  CP0Ifc theCP0 <- mkCP0(coreId);
  MIPSMemory theMem <- mkMIPSMemory(coreId,theCP0);
  DebugIfc theDebug <- mkDebug();

  interface putIrqs = theCP0.interrupts;
  `ifndef MULTI
  interface memory = theMem.memory;
  `else
  interface imemory = theMem.imemory;
  interface dmemory = theMem.dmemory;
  `endif
  interface debugStream = theDebug.stream;

  interface mipsMemory = theMem;

  `ifdef MULTI
    interface invalidateICache = theMem.invalidateICache;
    interface invalidateDCache = theMem.invalidateDCache;
  `endif
  method reset_n() = False;
  method getPause() = False;
  method Action putState(Bit#(48) count, Bool commonPause);
  endmethod
endmodule
