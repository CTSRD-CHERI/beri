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

package BRAMForwardingCore2 ;

import MIPS :: *;
//import RegFile :: *;
import FIFOF::*;
import BRAMCore :: * ;
import ConfigReg :: *;

export BRAMCore :: *;
export mkBRAMForwardingCore2;

module mkBRAMForwardingCore2#(Integer memSize,
          Bool hasOutputRegister
          ) (BRAM_DUAL_PORT#(addr, data))
   provisos(
    Bits#(addr, addr_sz),
    Bits#(data, data_sz),
    Eq#(addr)
    );
    
  BRAM_DUAL_PORT#(addr, data) bram <- mkBRAMCore2(memSize, hasOutputRegister);
  Reg#(data)                  lastWriteDataA <- mkConfigReg(?);
  Reg#(data)                  lastWriteDataB <- mkConfigReg(?);
  Reg#(addr)                  lastReadAddrA  <- mkConfigReg(?);
  Reg#(addr)                  lastReadAddrB  <- mkConfigReg(?);
  Reg#(addr)                  lastWriteAddrA <- mkConfigReg(?);
  Reg#(addr)                  lastWriteAddrB <- mkConfigReg(?);

  interface BRAM_PORT a;
    method Action put(Bool write, addr a, data d);
      bram.a.put(write, a, d);
      if (write) begin
        lastWriteAddrA <= a;
        lastWriteDataA <= d;
      end else lastReadAddrA <= a;
    endmethod
    method data read;
      data returnVal = ?;
      if (lastReadAddrA == lastWriteAddrB)
        returnVal = lastWriteDataB;
      else returnVal = bram.a.read;
      return returnVal;
    endmethod
  endinterface
  interface BRAM_PORT b;
    method Action put(Bool write, addr a, data d);
      bram.b.put(write, a, d);
      if (write) begin
        lastWriteAddrB <= a;
        lastWriteDataB <= d;
      end else lastReadAddrB <= a;
    endmethod
    method data read;
      data returnVal = ?;
      if (lastReadAddrB == lastWriteAddrA)
        returnVal = lastWriteDataA;
      else returnVal = bram.b.read;
      return returnVal;
    endmethod
  endinterface
endmodule

endpackage
