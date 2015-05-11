/*-
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Colin Rothwell as part of his final year
 * undergraduate project.
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
import CoProFPTypes::*;
import PopFIFO::*;

import MIPS::*;

import GetPut::*;
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import FloatingPoint::*;

function DiadFPRequest#(Float) getLowRequest(DiadFPRequest#(PairedSingle) args);
    let left = tpl_1(args);
    let right = tpl_2(args);
    return tuple3(tpl_1(left), tpl_1(right), tpl_3(args));
endfunction

function DiadFPRequest#(Float) getHighRequest(DiadFPRequest#(PairedSingle) args);
    let left = tpl_1(args);
    let right = tpl_2(args);
    return tuple3(tpl_2(left), tpl_2(right), tpl_3(args));
endfunction

module [Module] mkCombinedDiadicServers
    #(Module#(DiadicFloatServer) mkServer, Integer fifoLength)
    (CombinedDiadicServers);

    FIFO#(AbstractFormat) requestTypes <- mkSizedFIFO(6);
    FIFO#(Tuple2#(Float, FloatingPoint::Exception)) floatOutput <-
        mkSizedFIFO(fifoLength);
    FIFO#(Tuple2#(PairedSingle, FloatingPoint::Exception)) pairedSingleOutput <-
        mkSizedFIFO(fifoLength);

    let lowSrv <- mkServer();
    let highSrv <- mkServer();

    (* fire_when_enabled *)
    rule processResult;
        let response <- lowSrv.response.get();
        let responseType <- popFIFO(requestTypes);
        case (responseType)
            SINGLE: begin
                floatOutput.enq(response);
            end
            PAIREDSINGLE: begin
                //TODO: Exceptions properly!
                let resultHigh <- highSrv.response.get();
                let val = tuple2(tpl_1(response), tpl_1(resultHigh));
                pairedSingleOutput.enq(tuple2(val, tpl_2(response)));
            end
        endcase
    endrule

    interface DiadicFloatServer float;
        interface Put request;
            method Action put(DiadFPRequest#(Float) req);
                requestTypes.enq(SINGLE);
                lowSrv.request.put(req);
            endmethod
        endinterface
        interface Get response = toGet(floatOutput);
    endinterface

    interface DiadicPairedSingleServer pairedSingle;
        interface Put request;
            method Action put(DiadFPRequest#(PairedSingle) req);
                requestTypes.enq(PAIREDSINGLE);
                lowSrv.request.put(getLowRequest(req));
                highSrv.request.put(getHighRequest(req));
            endmethod
        endinterface
        interface Get response = toGet(pairedSingleOutput);
    endinterface
endmodule
