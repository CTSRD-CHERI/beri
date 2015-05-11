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

import MegafunctionTestBench::*;
import CoProFPSynthesisableModules::*;
import CoProFPParallelCombinedServer::*;
import PopFIFO::*;
import CoProFPTypes::*;
import CoProFPServerCreation::*;
import MonadicMegafunctions::*;
import CoProFPMegafunctions::*;

import GetPut::*;
import ClientServer::*;
import List::*;
import StmtFSM::*;
import FloatingPoint::*;
import FIFO::*;

(* synthesize *)
module mkMegafunctionServerTests ();
    `ifndef BLUESIM
        WithInt#(30, MonadicDoubleServer) mfSqrtWrapped <- 
            mkMegafunctionServer(
                mkMonadicDoubleMegafunction(mkVerilogDoubleSqrtMegafunction)
            );
        let mfSqrt = getPayload(mfSqrtWrapped);
    `endif
    let bsvSqrt <- mkFloatingPointSquareRooter();
    
    function toDouble(Bit#(32) raw);
        Float float = unpack(raw);
        Double ret = tpl_1(convert(float, ?, True));
        return ret;
    endfunction

    let tests = map(toDouble, testData);

    Reg#(int) i <- mkRegU;
    Reg#(int) j <- mkRegU;
    Reg#(int) k <- mkRegU;
    mkAutoFSM(par
        for (i <= 0; i < testDataCount; i <= i + 1) seq
            action
                let test = tuple2(tests[i], ?);
                `ifndef BLUESIM
                    mfSqrt.request.put(test);
                `endif
                bsvSqrt.request.put(test);
            endaction
        endseq

        for (j <= 0; j < testDataCount; j <= j + 1) action
            let bsvRes <- bsvSqrt.response.get();
            $display("FROM BSV: %X", tpl_1(bsvRes));
        endaction

        `ifndef BLUESIM
            for (k <= 0; k < testDataCount; k <= k + 1) action
                let mfRes <- mfSqrt.response.get();
                $display("FROM MF: %X", tpl_1(mfRes));
            endaction
        `endif
    endpar);
endmodule
