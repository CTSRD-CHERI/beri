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

import RegFile   :: *;
//import List      :: *;
import Vector    :: *;
import ConfigReg :: *;

// An associative register file.  We're not aiming for efficient
// hardware here, just something that works in simulation.

// Parameters
typedef 32 RegFileSize;
Integer regFileDefault = 0;

module mkRegFileAssoc (RegFile#(addrT, dataT))
       provisos ( Bits#(addrT, aw)
                , Bits#(dataT, dw)
                , Eq#(addrT)
                , Literal#(dataT)
                );

  // Keys
  Vector#(RegFileSize, Reg#(Maybe#(addrT))) keys <-
    replicateM(mkConfigReg(tagged Invalid));

  // Values
  Vector#(RegFileSize, Reg#(dataT)) vals <-
    replicateM(mkConfigRegU);

  // Obtain a register value
  method dataT sub(addrT addr);
    let found = findElem(tagged Valid addr, readVReg(keys));
    case (found) matches
      tagged Invalid: return fromInteger(regFileDefault);
      tagged Valid .i: return vals[i];
    endcase
  endmethod

  // Write a register value
  method Action upd(addrT addr, dataT data);
    function slot(entry);
      case (entry) matches
        tagged Invalid: return True;
        tagged Valid .key: return key==addr;
      endcase
    endfunction
    let found = findIndex(slot, readVReg(keys));
    case (found) matches
      tagged Invalid: $display("WARNING: mkRegFileAssoc is full");
      tagged Valid .i:
        begin
          keys[i] <= tagged Valid addr;
          vals[i] <= data;
        end
    endcase
  endmethod

endmodule
