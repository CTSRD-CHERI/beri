/*-
 * Copyright (c) 2016 Alexandre Joannou
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

import GetPut::*;
import MasterSlave::*;
import MemTypes::*;
import DefaultValue::*;
import StatCounters::*;

// interface types
///////////////////////////////////////////////////////////////////////////////

interface MasterStats;
  interface Master#(CheriMemRequest,CheriMemResponse) memory;
  interface Get#(ModuleEvents) events;
endinterface

// mkMasterStat module definition
///////////////////////////////////////////////////////////////////////////////

//(*synthesize*)
module mkMasterStats#(Master#(CheriMemRequest, CheriMemResponse) m)(MasterStats);

  Wire#(MasterEvents) masterEvnt <- mkDWire(defaultValue);
  Wire#(Maybe#(CheriMemRequest))  reqGet <- mkDWire(tagged Invalid);
  Wire#(Maybe#(CheriMemResponse)) rspPut <- mkDWire(tagged Invalid);

  rule countEvents;
    Bool reqRead      = False;
    Bool reqWrite     = False;
    Bool reqWriteLast = False;
    Bool rspRead      = False;
    Bool rspReadLast  = False;
    Bool rspWrite     = False;
    case (reqGet) matches
      tagged Valid .r: case (r.operation) matches
        tagged Read .rr: reqRead = True;
        tagged Write .wr: begin
          reqWrite = True;
          reqWriteLast = wr.last;
        end
      endcase
    endcase
    case (rspPut) matches
      tagged Valid .r: case (r.operation) matches
        tagged Read .rr: begin
          rspRead = True;
          rspReadLast = rr.last;
        end
        tagged Write .wr: rspWrite = True;
      endcase
    endcase
    masterEvnt <= MasterEvents {
      id: 0,
      incReadReq:      reqRead,
      incWriteReq:     reqWrite && reqWriteLast,
      incWriteReqFlit: reqWrite,
      incReadRsp:      rspRead && rspReadLast,
      incReadRspFlit:  rspRead,
      incWriteRsp:     rspWrite
    };
  endrule

  interface Master memory;
    interface CheckedGet request;
      method canGet = m.request.canGet;
      method CheriMemRequest peek = m.request.peek;
      method ActionValue#(CheriMemRequest) get;
        CheriMemRequest r <- m.request.get;
        reqGet <= tagged Valid r;
        return r;
      endmethod
    endinterface
    interface CheckedPut response;
      method Bool canPut = m.response.canPut;
      method Action put(CheriMemResponse r);
        rspPut <= tagged Valid r;
        m.response.put(r);
      endmethod
    endinterface
  endinterface
  interface Get events;
    method ActionValue#(ModuleEvents) get ();
      return tagged Master_E masterEvnt;
    endmethod
  endinterface
endmodule
