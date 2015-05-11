/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
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

import Vector  :: *;
import FIFO    :: *;
import BRAM    :: *;
import Library :: *;

interface BRAM3#(type addr, type data);
   method Action               reqA(addr a);
   method ActionValue#(data)  respA();
   method Action               reqB(addr a);
   method ActionValue#(data)  respB();
   method Action              write(addr a, data x);
endinterface

module mkBRAM3#(Integer memSize, Bool hasOutputRegister)(BRAM3#(addr, data))
   provisos(Bits#(addr, addr_sz),
            Bits#(data, data_sz));
    
  function BRAMRequest#(addr, data) makeRequest(Bool isW, addr a, data x);
    return BRAMRequest{
             write:           isW,
             responseOnWrite: False,
             address:         a,
             datain:          x
           };
  endfunction
    
  let cfg = BRAM_Configure {
		          memorySize   : memSize,
		          latency      : (hasOutputRegister) ? 1 : 2, // No output reg
          		outFIFODepth : 3,
              loadFormat   : None,
              allowWriteResponseBypass : False
            };
	
  Vector#(2, BRAM2Port#(addr, data)) brams <- replicateM(mkBRAM2Server(cfg));
  
  method Action reqA(addr a) = brams[0].portA.request.put(makeRequest(False,a,?));
  method ActionValue#(data) respA() = brams[0].portA.response.get();
  method Action reqB(addr a) = brams[1].portA.request.put(makeRequest(False,a,?));
  method ActionValue#(data) respB() = brams[1].portA.response.get();

  method Action write(addr a, data x);
    let req = makeRequest(True,a,x);
    brams[0].portB.request.put(req);
    brams[1].portB.request.put(req);
  endmethod
endmodule

module mkBRAM3_WriteFirst#(Integer memSize, Bool hasOutputRegister)(BRAM3#(addr, data))
   provisos(Bits#(addr, addr_sz), Eq#(addr),
            Bits#(data, data_sz));
    
  function BRAMRequest#(addr, data) makeRequest(Bool isW, addr a, data x);
    return BRAMRequest{
             write:           isW,
             responseOnWrite: False,
             address:         a,
             datain:          x
           };
  endfunction

  let cfg = BRAM_Configure {
		          memorySize   : memSize,
		          latency      : (hasOutputRegister) ? 1 : 2, // No output reg
          		outFIFODepth : 3,
              loadFormat   : None,
              allowWriteResponseBypass : False
            };
	
  Vector#(2, FIFO#(addr))           readQs <- replicateM(mkLFIFO);  
  Vector#(2, BRAM2Port#(addr, data)) brams <- replicateM(mkBRAM2Server(cfg));
  RWire#(Tuple2#(addr, data)) writeW <- mkRWire();
  
  method Action reqA(addr a);
    brams[0].portA.request.put(makeRequest(False,a,?));
	readQs[0].enq(a);
  endmethod

  method ActionValue#(data) respA();
    let addr <- popFIFO(readQs[0]);
    let vp <- brams[0].portA.response.get();
    case (writeW.wget()) matches
      tagged Invalid:       return vp;
      tagged Valid {.a,.v}: return (addr == a) ? v : vp;
    endcase
  endmethod
  
  method Action reqB(addr a);
    brams[1].portA.request.put(makeRequest(False,a,?));
	readQs[1].enq(a);
  endmethod

  method ActionValue#(data) respB();
    let addr <- popFIFO(readQs[1]);
    let vp <- brams[1].portA.response.get();
    case (writeW.wget()) matches
      tagged Invalid:       return vp;
      tagged Valid {.a,.v}: return (addr == a) ? v : vp;
    endcase
  endmethod  
      	
  method Action write(addr a, data x);
    let req = makeRequest(True,a,x);
    brams[0].portB.request.put(req);
    brams[1].portB.request.put(req);
    writeW.wset(tuple2(a,x));
  endmethod
endmodule

