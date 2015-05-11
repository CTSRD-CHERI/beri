#-
# Copyright (c) 2013 Colin Rothwell
# All rights reserved.
#
# This software was developed by Colin Rothwell as part of his final year
# undergraduate project.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for
# additional information regarding copyright ownership.  BERI licenses this
# file to you under the BERI Hardware-Software License, Version 1.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at:
#
#   http://www.beri-open-systems.org/legal/license-1-0.txt
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
# @BERI_LICENSE_HEADER_END@
#
import List::*;

import MIPS::*;

import MegafunctionTestBench::*;
import CoProFPCompositeServers::*;
import CoProFPTypes::*;

import GetPut::*;

List#(MIPSReg) testDoubles =
    cons('h3FF0000000000000, // 1
    cons('h3FC555555530AED6, // 0.1666666
    cons('hC06D5431F8A0902E, // -234.6311
    cons('h41E1808E6C666666, // some random big number
    nil))));

int testDoubleCount = fromInteger(length(testDoubles));

(* synthesize *)
module mkCompositeOpTests(Empty);
    let recipTest <- mkDualMonadicServerTest(mkRecipServers (1), "Recip");
    let recipSqrtTest <- mkDualMonadicServerTest(mkRecipSqrtServers (1), "RecipSqrt");

    rule finish (recipTest.done() && recipSqrtTest.done());
        $finish();
    endrule
endmodule

interface Test;
    method Bool done();
endinterface

module [Module] mkDualMonadicServerTest
    #(Module#(DualServers#(MonadicServer)) mkTestServers, String tag)
    (Test);

    let testServers <- mkTestServers;
    let singleServer = testServers.single;
    let doubleServer = testServers.double;

    Reg#(Bool) placingDoubles <- mkReg(False);
    Reg#(Bool) takingDoubles <- mkReg(False);
    Reg#(Bool) finished <- mkReg(False);
    Reg#(int) in <- mkReg(0);
    Reg#(int) out <- mkReg(0);

    rule placeSingle (!placingDoubles);
        singleServer.request.put(signExtend(testData[in]));
        let nextIn = in + 1;
        if (nextIn < testDataCount)
            in <= nextIn;
        else begin
            in <= 0;
            placingDoubles <= True;
        end
    endrule

    rule takeSingle (!takingDoubles);
        $display("%d: %sSingle Result %X", out, tag, singleServer.response.get());
        let nextOut = out + 1;
        if (nextOut < testDataCount)
            out <= nextOut;
        else begin
            out <= 0;
            takingDoubles <= True;
        end
    endrule

    rule placeDouble (placingDoubles && in < testDoubleCount);
        doubleServer.request.put(testDoubles[in]);
        in <= in + 1;
    endrule

    rule takeDouble (takingDoubles && !finished);
        $display("%d: %sDouble Result %X", out, tag, doubleServer.response.get());
        let nextOut = out + 1;
        if (nextOut < testDoubleCount)
            out <= nextOut;
        else
            finished <= True;
    endrule

    method Bool done();
        return finished;
    endmethod
endmodule
