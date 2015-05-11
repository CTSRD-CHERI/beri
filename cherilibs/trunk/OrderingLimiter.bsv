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
import Vector::*;
import MEM::*;
import MemTypes::*;
import Debug::*;

/* =================================================================
mkOrderingLimiter
 =================================================================*/

interface OrderingLimiterIfc;
  interface Slave#(CheriMemRequest, CheriMemResponse)  slave;
  interface Master#(CheriMemRequest, CheriMemResponse) master;
endinterface: OrderingLimiterIfc

(*synthesize*)
module mkOrderingLimiter(OrderingLimiterIfc ifc);
  FIFOF#(CheriMemRequest)                 req_fifo <- mkBypassFIFOF;
  FIFOF#(CheriMemResponse)               resp_fifo <- mkBypassFIFOF;
  OrderingCoreIfc                          orderer <- mkOrderingCore;

  interface Slave slave;
    interface request  = toCheckedPut(req_fifo);
    interface response = toCheckedGet(resp_fifo);
  endinterface

  interface Master master;
    interface CheckedGet request;
      method Bool canGet();
        return req_fifo.notEmpty();//orderer.allowRequest(req_fifo.first());
      endmethod
      method CheriMemRequest peek() if (orderer.allowRequest(req_fifo.first()));
        return req_fifo.first();
      endmethod
      method ActionValue#(CheriMemRequest) get() if (orderer.allowRequest(req_fifo.first()));
        orderer.putRequest(req_fifo.first());
        req_fifo.deq();
        debug2("orderer", $display("<time %0t, OrderingLimiter> SendExternalRequest - ", $time, fshow(req_fifo.first())));
        return req_fifo.first();
      endmethod
    endinterface
    interface CheckedPut response;
      method Bool canPut();
        return resp_fifo.notFull();
      endmethod
      method Action put(CheriMemResponse resp);
        orderer.putResponse(resp);
        debug2("orderer", $display("<time %0t, OrderingLimiter> ReceiveExternalResponse - ", $time, fshow(resp)));
        resp_fifo.enq(resp);
      endmethod
    endinterface
  endinterface
endmodule

// mkOrderingCore
// This module ensures that reads to the same line as an outstanding write
// are blocked until the write response is recieved.

interface OrderingCoreIfc;
  method Bool allowRequest(CheriMemRequest req);
  method Action putRequest(CheriMemRequest req);
  method Action putResponse(CheriMemResponse resp);
endinterface: OrderingCoreIfc

(*synthesize*)
module mkOrderingCore(OrderingCoreIfc);
  FIFOF#(Bit#(2))       writeTableLocation <- mkUGSizedFIFOF(8);
  Vector#(4, FIFOF#(Bit#(8)))   writeTable <- replicateM(mkUGSizedFIFOF(1));
  /*
  rule debugdisplay;
    trace($display("writeTableLocation.notFull=%d",
      writeTableLocation.notFull));
    for (Integer i=0; i<4; i=i+1) begin
      case (writeTable[i].notEmpty)
        True:  trace($display("    %d - %x", i, writeTable[i].first()));
        False: trace($display("    %d - Empty", i));
      endcase
    end
  endrule
  */
  method Bool allowRequest(CheriMemRequest req);
    // Make a hash that takes into account both upper bits and lower bits to prevent
    // blocking of reads to large, aligned offsets due to eviction and replacement.
    Bit#(8) addressHash = req.addr.lineNumber[7:0]^
                          req.addr.lineNumber[18:11];
    Bit#(2) key = addressHash[1:0];
    Bool blockNextRequest = (case (req.operation) matches
        tagged Read .rop:  return (writeTable[key].notEmpty) ? writeTable[key].first == addressHash : False;
        tagged Write .wop: return writeTable[key].notEmpty;
        default: return False;
      endcase);

    return !blockNextRequest;
  endmethod

  method Action putRequest(CheriMemRequest req);
    // Make a hash that takes into account both upper bits and lower bits to prevent
    // blocking of reads to large, aligned offsets due to eviction and replacement.
    Bit#(8) addressHash = req.addr.lineNumber[7:0]^
                          req.addr.lineNumber[18:11];
    Bit#(2) key = addressHash[1:0];
    if (req.operation matches tagged Write .unused) begin
      writeTable[key].enq(addressHash);
      writeTableLocation.enq(key);
    end
  endmethod

  method Action putResponse(CheriMemResponse resp);
    if (resp.operation matches tagged Write .wresp) begin
      writeTable[writeTableLocation.first()].deq();
      writeTableLocation.deq();
    end
  endmethod
endmodule
