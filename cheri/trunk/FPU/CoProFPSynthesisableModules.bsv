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
import CoProFPOpModules::*;
import BufferServer::*;
import CoProFPParallelCombinedServer::*;
import CoProFPTypes::*;
import CoProFPConversionFunctions::*;
import MonadicMegafunctions::*;
import DiadicMegafunctions::*;
import CoProFPMegafunctions::*;
import CoProFPServerCreation::*;

import NonPipelinedMath::*;
import FloatingPoint::*;
import ClientServer::*;
import GetPut::*;
import FIFOF::*;
import SpecialFIFOs::*;

(* synthesize, options="-aggressive-conditions" *)
module mkConcreteAddServers(MultipleFormatDiadicServers);
    `ifdef BLUESIM
        let floatAdder <- mkFloatingPointAdder();
        let doubleAdder <- mkFloatingPointAdder();
    `else
        let floatAdder <- mkUnbufferedFloatAddServer();
        let doubleAdder <- mkUnbufferedDoubleAddServer();
    `endif
    let worker <- mkCombinedServers(floatAdder, doubleAdder, 7);
    return worker;
endmodule

(* synthesize, options="-aggressive-conditions" *)
module mkConcreteMulServers(MultipleFormatDiadicServers);
    `ifdef BLUESIM
        let floatMultiplier <- mkFloatingPointMultiplier();
        let doubleMultiplier <- mkFloatingPointMultiplier();
    `else
        let floatMultiplier <- mkUnbufferedFloatMulServer();
        let doubleMultiplier <- mkUnbufferedDoubleMulServer();
    `endif
    let worker <- mkCombinedServers(floatMultiplier, doubleMultiplier, 5);
    return worker;
endmodule

module mkCombinedServers
        #(DiadicFloatServer float, DiadicDoubleServer double, 
          Integer pipelineDepth)
        (MultipleFormatDiadicServers);

    FIFOF#(Tuple2#(Float, Exception)) floatResults <- mkSizedBypassFIFOF(2);
    FIFOF#(Tuple2#(PairedSingle, Exception)) pairedSingleResults <- mkSizedBypassFIFOF(2);
    FIFOF#(Tuple2#(Double, Exception)) doubleResults <- mkSizedBypassFIFOF(2);

    FIFOF#(AbstractFormat) requestTypes <- mkSizedFIFOF(pipelineDepth + 1);

    rule extractFloatResult (requestTypes.first == SINGLE);
        requestTypes.deq();
        let res <- float.response.get();
        floatResults.enq(res);
    endrule

    rule extractPairedSingleResult (requestTypes.first == PAIREDSINGLE);
        requestTypes.deq();
        let lowRes <- float.response.get();
        let highDoubleRes <- double.response.get();
        let highRes = doubleToFloat(tpl_1(highDoubleRes));
        let ps = tuple2(tpl_1(lowRes), highRes);
        pairedSingleResults.enq(tuple2(ps, tpl_2(lowRes)));
    endrule

    rule extractDoubleResult (requestTypes.first == DOUBLE);
        requestTypes.deq();
        let res <- double.response.get();
        doubleResults.enq(res);
    endrule

    interface DiadicFloatServer float;
        interface Put request;
            method Action put(DiadFPRequest#(Float) req);
                requestTypes.enq(SINGLE);
                float.request.put(req);
            endmethod
        endinterface

        interface Get response = toGet(floatResults);
    endinterface

    interface DiadicPairedSingleServer pairedSingle;
        interface Put request;
            method Action put(DiadFPRequest#(PairedSingle) req);
                requestTypes.enq(PAIREDSINGLE);
                float.request.put(getLowRequest(req));
                double.request.put(floatToDoubleRequest(getHighRequest(req)));
            endmethod
        endinterface

        interface Get response = toGet(pairedSingleResults);
    endinterface

    interface DiadicDoubleServer double;
        interface Put request;
            method Action put(DiadFPRequest#(Double) req);
                requestTypes.enq(DOUBLE);
                double.request.put(req);
            endmethod
        endinterface

        interface Get response = toGet(doubleResults);
    endinterface
endmodule

(* synthesize, options="-aggressive-conditions" *)
module mkConcreteDoubleDivServer(DiadicDoubleServer);
    let intDivider <- mkNonPipelinedDivider(1);
    let worker <- mkBufferOutputServer(mkFloatingPointDivider(intDivider), 2);
    return worker;
endmodule

module [Module] mkUnbufferedFloatAddServer(DiadicFloatServer);
    WithInt#(7, DiadicFloatServer) mkAddWrapped <- mkMegafunctionServer(
        mkDiadicFloatMegafunction(mkVerilogFloatAddMegafunction)
    );
    return getPayload(mkAddWrapped);
endmodule

module [Module] mkUnbufferedDoubleAddServer(DiadicDoubleServer);
    WithInt#(7, DiadicDoubleServer) mfAddWrapped <- mkMegafunctionServer(
        mkDiadicDoubleMegafunction(mkVerilogDoubleAddMegafunction)
    );
    return getPayload(mfAddWrapped);
endmodule

module [Module] mkUnbufferedFloatMulServer(DiadicFloatServer);
    WithInt#(5, DiadicFloatServer) mkMulWrapped <- mkMegafunctionServer(
        mkDiadicFloatMegafunction(mkVerilogFloatMulMegafunction)
    );
    return getPayload(mkMulWrapped);
endmodule

module [Module] mkUnbufferedDoubleMulServer(DiadicDoubleServer);
    WithInt#(5, DiadicDoubleServer) mkMulWrapped <- mkMegafunctionServer(
        mkDiadicDoubleMegafunction(mkVerilogDoubleMulMegafunction)
    );
    return getPayload(mkMulWrapped);
endmodule
