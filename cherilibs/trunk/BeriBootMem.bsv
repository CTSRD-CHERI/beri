/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2014 Colin Rothwell
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

/*****************************************************************************
  BeriBootMem
  ==============================================================
  Jonathan Woodruff, October 2010, 2013
 *****************************************************************************/
package BeriBootMem;

import Vector::*;
import FIFO :: *;
import BRAM :: *;
import PutMerge :: *;
`ifdef VERIFY2

import Bram :: *;
`endif

interface BRAM1PortBE256Ifc#(type addr, type data, numeric type n);
   interface BRAMServerBE#(addr, data, n) portA;
endinterface
    
function BRAMRequestBE#(Bit#(11), Bit#(32), 4) makeRequestBE32(Bit#(4)write, Bit#(11) addr, Bit#(32) data);
      return BRAMRequestBE{
        writeen: write,
        responseOnWrite: False,
        address: addr,
        datain: data
      };
endfunction
    
typedef enum {Serving, Reading, Writing} MemState deriving (Bits, Eq);

// This is like a banked BRAM, except it uses one BRAM, and incurs a four cycle
// latency for each request.
(*synthesize*)
module mkBeriBootMem (BRAM1PortBE256Ifc #(Bit#(11), Bit#(256), 32));
  `ifndef VERIFY2
  BRAM_Configure cfg = defaultValue;
  cfg.memorySize = 65536/8; // full size
  cfg.loadFormat = tagged Hex "mem64.hex";
  BRAM2Port#(Bit#(13), Vector#(8, Bit#(8))) mem <- mkBRAM2Server(cfg);
  `else
  Bram#(Bit#(13), Vector#(8, Bit#(8))) mem <- mkBram();
  `endif
  FIFO#(Vector#(8, Bit#(8))) reads <- mkFIFO;
  
  Reg#(BRAMRequestBE#(Bit#(11), Vector#(32, Bit#(8)), 32)) request <- mkRegU;
  FIFO#(Bit#(256)) response <- mkFIFO1;
  Reg#(MemState) state <- mkReg(Serving);
  Reg#(UInt#(2)) count <- mkReg(0);
  
  rule readRam(state == Reading || state == Writing);
	`ifndef VERIFY2
    Vector#(8, Bit#(8)) readWord <- mem.portA.response.get();
    `else
    Vector#(8, Bit#(8)) readWord <- mem.readResp();
    `endif

    if (state == Writing)
	  begin
		Vector#(8, Bit#(8)) newWord;
		Vector#(8, Bit#(8)) writeWord = readWord;
		for (Integer i=0; i<8; i=i+1) begin
          Bit#(5) idx = {pack(count),fromInteger(i)};
          newWord[i] = request.datain[idx];
          if (request.writeen[idx] == 1'b1) writeWord[i] = newWord[i];
		end

		`ifndef VERIFY2 
		mem.portB.request.put(BRAMRequest{
		  write: True,
		  responseOnWrite: False,
		  address: {request.address,pack(count)},
		  datain: writeWord
		});
		`else
        mem.write({request.address, pack(count)}, writeWord);
		`endif		
      end
	else
	  begin
		Vector#(32, Bit#(8)) newData = request.datain;
		for (Integer i=0; i<8; i=i+1) begin
          Bit#(5) idx = {pack(count),fromInteger(i)};
          newData[idx] = readWord[i];
		end
		if (count == 3) response.enq(pack(newData));
		request.datain <= newData;
      end
    if (count < 3)
	  begin
        `ifndef VERIFY2
		  mem.portA.request.put(BRAMRequest{
		    write: False,
  		    responseOnWrite: False,
		    address: {request.address,pack(count+1)},
		    datain: ?
 			});
		`else
          mem.readReq({request.address,pack(count+1)});
		`endif		
      end
    if (count == 3)
	  state <= Serving;
    count <= count + 1;
  endrule
  
  interface Server portA;
    interface Put request;
      method Action put(bramReqBE) if (state == Serving);
        request <= unpack(pack(bramReqBE));
        state <= (bramReqBE.writeen == 0) ? Reading : Writing;
        `ifndef VERIFY2
        mem.portA.request.put(BRAMRequest{
                write: False,
                responseOnWrite: False,
                address: {bramReqBE.address,2'b0},
                datain: ?
              });
        `else 
		mem.readReq({bramReqBE.address,2'b0});
		`endif
      endmethod
    endinterface
    interface Get response = toGet(response);
  endinterface
endmodule

typedef enum {
    PortA,
    PortB
} Port deriving (Bits, Eq, FShow);

module mkSplitBootMem (BRAM2PortBE#(Bit#(11), Bit#(256), 32));
    let actualMem <- mkBeriBootMem();
    let merge <- mkPutMerge(actualMem.portA.request);
    
    // portA is read/write 
    interface Server portA;
        interface Put request = merge.left;
        interface Get response = actualMem.portA.response;
    endinterface

    // portB is write only
    interface Server portB;
        interface Put request = merge.right;
    endinterface
endmodule

endpackage

