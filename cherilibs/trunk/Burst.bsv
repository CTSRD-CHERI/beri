/*-
 * Copyright (c) 2013 Jonathan Woodruff
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

import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import MasterSlave::*;
import MemTypes::*;
import Debug::*;

/* =================================================================
mkBurst
 =================================================================*/

interface BurstIfc;
  interface Slave#(CheriMemRequest, CheriMemResponse)  slave;
  interface Master#(CheriMemRequest, CheriMemResponse) master;
endinterface: BurstIfc

(*synthesize*)
module mkBurst(BurstIfc ifc);
  FIFOF#(CheriMemRequest)                  req_fifo <- mkBypassFIFOF;
  FIFOF#(CheriMemResponse)                resp_fifo <- mkBypassFIFOF;
  FIFO#(Bool)                             last_fifo <- mkSizedFIFO(32);
  Reg#(UInt#(TLog#(MemTypes::MaxNoOfFlits)))   flit <- mkReg(0);
/*
  rule reportStuff;
    trace($display("req_fifo.notempty: %x, resp_fifo.notempty: %x", req_fifo.notEmpty(), resp_fifo.notEmpty()));
  endrule
*/  
  CheriMemRequest req = req_fifo.first();
  if (req.operation matches tagged Read .rop) begin
    req.addr.lineNumber = req.addr.lineNumber + zeroExtend(pack(flit));
    req.operation = tagged Read {
                      uncached: rop.uncached,
                      linked: rop.linked,
                      noOfFlits: 0,
                      bytesPerFlit: rop.bytesPerFlit
                  };
  end
  
  interface Slave slave;
    interface request  = toCheckedPut(req_fifo);
    interface response = toCheckedGet(resp_fifo);
  endinterface

  interface Master master;
    interface CheckedGet request;
      method Bool canGet();
        return req_fifo.notEmpty();
      endmethod
      method CheriMemRequest peek();
        return req;
      endmethod
      method ActionValue#(CheriMemRequest) get();
        CheriMemRequest reqIn = req_fifo.first();
        if (reqIn.operation matches tagged Read .rop) begin
          if (rop.noOfFlits == flit) begin
            flit <= 0;
            req_fifo.deq();
            last_fifo.enq(True);
          end else begin
            flit <= flit + 1;
            last_fifo.enq(False);
          end
        end else begin
          req_fifo.deq();
          last_fifo.enq(True);
        end
        return req;
      endmethod
    endinterface
    interface CheckedPut response;
      method Bool canPut();
        return resp_fifo.notFull();
      endmethod
      method Action put(CheriMemResponse resp);
        if (resp.operation matches tagged Read .rop)
          resp.operation = tagged Read{data: rop.data, last: last_fifo.first};
        last_fifo.deq();
        resp_fifo.enq(resp);
      endmethod
    endinterface
  endinterface
endmodule
