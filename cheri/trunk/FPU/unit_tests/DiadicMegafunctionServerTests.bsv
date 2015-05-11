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

import MIPS::*;

import GetPut::*;
import ClientServer::*;
import List::*;
import StmtFSM::*;
import FloatingPoint::*;
import FIFO::*;

(* synthesize *)
module mkMegafunctionServerTests ();
    `ifdef MEGAFUNCTIONS
        let floatAddServers <-
            mkCombinedDiadicServers(mkMegafunctionServer(mkVerilogAddMegafunction));
    `else
        let floatAddServers <- mkConcreteFloatAddServers();
    `endif

    FIFO#(Tuple3#(Float, Float, RoundMode)) enteredTests <- mkFIFO();

    let tests = map(unpack, testData);

    Reg#(int) i <- mkRegU;
    Reg#(int) j <- mkRegU;
    mkAutoFSM(seq
        for (i <= 0; i < testDataCount; i <= i + 1) seq
            for (j <= 0; j < testDataCount; j <= j + 1) seq
                action
                    let test = tuple3(tests[i], tests[j], ?);
                    enteredTests.enq(test);
                    floatAddServers.float.request.put(test);
                endaction
            endseq
        endseq
    endseq);

    rule outputResults;
        let test <- popFIFO(enteredTests);
        let res <- floatAddServers.float.response.get();
        $display("%X + %X = %X", tpl_1(test), tpl_2(test), tpl_1(res));
    endrule

endmodule
