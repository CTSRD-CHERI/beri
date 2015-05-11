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
import MegafunctionTestBench::*;
import SingleToMIPSReg::*;
import CoProFPConversionModules::*;
import CoProFPTypes::*;

import MIPS::*;

import List::*;
import GetPut::*;

(* synthesize *)
module mkFloatingPointConversionTest(Empty);

    let data = map(singleToMIPSReg, testData);
    
    Reg#(int) nextDatumToLoad <- mkReg(0);
    Reg#(int) nextDatumToRead <- mkReg(0);

    let singleToDoubleServer <- mkSingleToDoubleServer(1);
    let doubleToSingleServer <- mkDoubleToSingleServer(1);

    rule loadSingleToDouble (nextDatumToLoad < testDataCount);
        let datum = data[nextDatumToLoad];
        singleToDoubleServer.request.put(data[nextDatumToLoad]);
        nextDatumToLoad <= nextDatumToLoad + 1;
    endrule

    rule loadDoubleToSingle;
        let resp <- singleToDoubleServer.response.get();
        doubleToSingleServer.request.put(resp);
    endrule

    rule readDatum;
        let result <- doubleToSingleServer.response.get();
        let expected = data[nextDatumToRead];
        String isMatch;
        if (result == expected)
            isMatch = "Match! :)";
        else
            isMatch = "!! MISMATCH !! :(";
        $display("%d: Expected %X, Got %X. %s", nextDatumToRead, expected, result, isMatch);
        nextDatumToRead <= nextDatumToRead + 1;
    endrule

    rule finish (nextDatumToRead == testDataCount);
        $finish();
    endrule
endmodule
