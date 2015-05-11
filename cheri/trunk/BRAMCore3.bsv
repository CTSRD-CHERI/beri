/*-
 * Copyright (c) 2013 Jonathan Woodruff
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
 */

package BRAMCore3;

import MIPS::*;
//import RegFile::*;
import FIFOF::*;
import BRAMCore::*;
import ConfigReg::*;

// Export the interfaces
export BRAMCore::*;
// Export 3 port version
export BRAM_TRIPLE_PORT(..);
export mkBRAMCore3;

interface BRAM_TRIPLE_PORT#(type addrT, type dataT);
   interface BRAM_PORT#(addrT, dataT) a;
   interface BRAM_PORT#(addrT, dataT) b;
   interface BRAM_PORT#(addrT, dataT) write;
endinterface

module mkBRAMCore3#(
  Integer memSize,
  Bool hasOutputRegister
)(BRAM_TRIPLE_PORT#(addrT, dataT))
provisos(
  Bits#(addrT, addrWidth),
  Bits#(dataT, dataWidth)
);

  BRAM_DUAL_PORT#(addrT, dataT) bramA <- mkBRAMCore2(memSize, hasOutputRegister);
  BRAM_DUAL_PORT#(addrT, dataT) bramB <- mkBRAMCore2(memSize, hasOutputRegister);

  interface BRAM_PORT a;
    method Action put(Bool write, addrT a, dataT d);
      if (!write) bramA.a.put(False, a, ?);
    endmethod
    method dataT read = bramA.a.read;
  endinterface
  interface BRAM_PORT b;
    method Action put(Bool write, addrT a, dataT d);
      if (!write) bramB.a.put(False, a, ?);
    endmethod
    method dataT read = bramB.a.read;
  endinterface
  interface BRAM_PORT write;
    method Action put(Bool write, addrT a, dataT d);
      if (write) begin
        bramA.b.put(True, a, d);
        bramB.b.put(True, a, d);
      end
    endmethod
    method dataT read = ?;
  endinterface
endmodule

endpackage
