/*-
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
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
 *
 ******************************************************************************
 *
 * Author: Asif Khan <asif.khan@sri.com>
 *         Robert Norton <robert.norton@cl.cam.ac.uk>
 * 
 ******************************************************************************
 *
 * Description: Definition of the external memory interface for cheri 
 * processors. Also simulated version of BRAM rom.
 * 
 ******************************************************************************/

import Vector::*;
import RegFile::*;
import FIFO::*;
import BRAM::*;
import BeriBootMem::*;
import MemTypes::*;

typedef enum {EMR_Read, EMR_Write} ExtMemReqType deriving(Bits,Eq,FShow);
typedef struct {
  ExtMemReqType                     op;
  Bit#(word_address_width)          addr; // word address
  Bit#(TMul#(8, data_width_bytes))  data;
  Bit#(data_width_bytes)            byteEnable;
  Bool                              cached;
} ExtMemReq#(numeric type word_address_width, numeric type data_width_bytes) deriving(Bits,Eq, FShow);
  
typedef t ExtMemResp#(type t);
typedef Client#(ExtMemReq#(35,32),ExtMemResp#(Bit#(256))) ExtMemClient;

function ExtMemReq#(a,b) memReqToExtMemReq(MemoryRequest#(a,b) req);
  return ExtMemReq {
           op: case(req.op) matches
                 Read:  return EMR_Read;
                 Write: return EMR_Write;
               endcase,
           addr: req.addr,
           byteEnable: req.byteenable,
           data: req.data,
           cached: req.cached
         };
endfunction

function MemoryResponse#(a) extMemRespToMemResp(ExtMemResp#(Bit#(a)) resp);
  return MemoryResponse{
     `ifdef CAP
                     capability: False,
     `endif
                     data: resp
     };
endfunction

interface ExtMem;
  method Action req(ExtMemReq#(35, 32) r);
  method ActionValue#(ExtMemResp#(Bit#(256))) resp;
endinterface

(* synthesize *)
module mkExtMem(ExtMem);
  BRAM_Configure cfg = defaultValue;
  cfg.memorySize = 32768/32;
  BRAM1PortBE256Ifc#(Bit#(11), Vector#(32, Bit#(8)), 32)           mem <- mkBeriBootMem;
  FIFO#(BRAMRequestBE#(Bit#(11),Vector::Vector#(32, Bit#(8)),32)) reqs <- mkFIFO;
  
  rule putRequest;
    mem.portA.request.put(reqs.first);
    reqs.deq();
  endrule

  method Action req(ExtMemReq#(35, 32) r);
   Vector#(32, Bit#(8)) dataBytes;
   for (Integer i=0; i<32; i=i+1)
	  dataBytes[i] = r.data[8*i+7:8*i];
   reqs.enq(BRAMRequestBE{
                responseOnWrite: False,
                address: r.addr[10:0],
                datain: dataBytes,
                writeen: (r.op==EMR_Write) ? r.byteEnable: 32'b0 
            });
  endmethod

  method ActionValue#(Bit#(256)) resp;
    Vector#(32, Bit#(8)) vecResp <- mem.portA.response.get();
    ExtMemResp#(Bit#(256)) response = pack(vecResp);
    return response;
  endmethod
endmodule

// Simple shim module for converting between the two memory
// interfaces.
module  mkExtMemClient#(MemoryClient memClient)(ExtMemClient);
  interface Get request;
    method get;
      actionvalue
        let r <- memClient.request.get;
        return memReqToExtMemReq(r);
      endactionvalue
    endmethod
  endinterface
  interface Put response;
    method Action put(resp);
      memClient.response.put(extMemRespToMemResp(resp));
    endmethod
  endinterface
endmodule
