/*-
* Copyright (c) 2014 Colin Rothwell
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
*
*/

import TLM3::*;
import GetPut::*;
import FIFOF::*;
import SpecialFIFOs::*;

interface TLMBridge#(
    type slaveReq, type slaveResp, type masterReq, type masterResp
);

    interface TLMRecvIFC#(slaveReq, slaveResp) slave;
    interface TLMSendIFC#(masterReq, masterResp) master;
endinterface

module mkTLMBridge
        #(function masterReq slaveToMasterReq(slaveReq sr),
          function slaveResp masterToSlaveResp(masterResp mr))
        (TLMBridge#(slaveReq, slaveResp, masterReq, masterResp))
        provisos (Bits#(slaveResp, a__), Bits#(masterReq, b__)); // From BSC

    FIFOF#(masterReq) reqFifo <- mkBypassFIFOF();
    FIFOF#(slaveResp) respFifo <- mkBypassFIFOF();

    interface TLMRecvIFC slave;
        interface Get tx = toGet(respFifo);
        interface Put rx;
            method Action put(slaveReq req);
                reqFifo.enq(slaveToMasterReq(req));
            endmethod
        endinterface
    endinterface

    interface TLMSendIFC master;
        interface Get tx = toGet(reqFifo);
        interface Put rx;
            method Action put(masterResp resp);
                respFifo.enq(masterToSlaveResp(resp));
            endmethod
        endinterface
    endinterface
endmodule

module mkNonTranslatingTLMBridge(TLMBridge#(req, resp, req, resp))
        provisos (Bits#(req, a__), Bits#(resp, b__));
    let bridge <- mkTLMBridge(id, id);
    return bridge;
endmodule
