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

import Vector::*;
import MasterSlave::*;

import MIPS::*;
import MIPSTop::*;
import MIPSTop_TestMem ::*;
import MemTypes::*;

`ifdef MULTI
  import Multicore::*;
`endif

import Connectable :: * ;
import MemoryClient::*;
import TestEquiv::*;
import ModelDRAM :: *;
import Clocks::*;

(* synthesize *)
module mkTestMemTop (Empty);
  mkTestMemTopSingle;
endmodule

module [Module] mkTestMemTopSingle (Empty);
  // Make a reset signal for testing by iterative deepening
  Clock clk      <- exposeCurrentClock;
  MakeResetIfc r <- mkReset(0, True, clk);

  // Instantiate DRAM model
  // (max oustanding requests = 4, latency = 20, address width = 17)
  //ModelDRAM#(17) dram <- mkModelDRAMAssoc(4, 20, reset_by r.new_rst);
  ModelDRAM#(35) dram <- mkModelDRAMHash(4, 20, reset_by r.new_rst);

  `ifdef MULTI
      // Instantiate minimal core
      MulticoreIfc beri  <- mkMulticore(reset_by r.new_rst);

      // Connect core to DRAM
      mkConnection(beri.memoryStage, dram.slave, reset_by r.new_rst);

      // Make equivalence checker
      case (valueOf(CORE_COUNT))
        0,1:     mkTestMemSingle(beri.mipsMemories[0], r);
        2:       mkTestMemDualExclusive(beri.mipsMemories, r);
        default: mkTestMemoryModel(beri.mipsMemories, r);
      endcase      
  `else
      // Instantiate minimal core
      MIPSTopIfc beri <- mkMIPSTop_TestMem(0, reset_by r.new_rst);

      // Connect core to DRAM
      mkConnection(beri.memory, dram.slave, reset_by r.new_rst);

      // Make equivalence checker
      mkTestMemSingle(beri.mipsMemory, r);
  `endif

  // Needed to keep compiler happy
  rule irqs;
    beri.putIrqs(0);
  endrule
endmodule
