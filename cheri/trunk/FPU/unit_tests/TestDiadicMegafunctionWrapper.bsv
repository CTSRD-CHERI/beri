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

/*
 * This is currently not working.
 * It needs to be updated to use the server creation stuff, which never quite
 * happened.
 */

import CoProFPServerCreation::*;
import CoProFPMegafunctionSimulation::*;
import CoProFPSimulatedOps::*;
import CoProFPTypes::*;

import MIPS::*;

import List::*;

(* synthesize *)
module mkDiadicMegafunctionWrapperTestBench (Empty);
    List#(MIPSReg) testData =
        cons('h3F800000, //1
        cons('h3F800000,
        cons('h47C35000, //1e5
        cons('h40000000, //2
        cons('h43670000, //231
        cons('h3E2AAA7E, //0.166666
        cons('h41BE8D50, //23.819
        cons('h794F233B, //~6.722e34
        cons('h4C465D40, //5.2e7
        cons('h40000000,
        nil))))))))));
    int testDataCount = fromInteger(length(testData));

    Reg#(Bool) loadingIntoWrapped <- mkReg(False);
    Reg#(int) datumIndex <- mkReg(0);

    SimulatedDiadicMegafunction#(7) addMegafunction 
        <- mkSimulatedDiadicMegafunction(add_fn);
    WrappedMegafunctionALUOpDiad#(7) addWrapper <-
        mkALUOpDiad(addMegafunction.mf);
    CoProFPALUOpDiad wrappedAdd = addWrapper.op;

    rule loadDataIntoRaw (!loadingIntoWrapped);
        let datum = testData[datumIndex];
        rawAdd.load(datum, datum, S, RN);
        if (datumIndex != (testDataCount - 1)) begin
            datumIndex <= datumIndex + 1;
        end
        else begin
            datumIndex <= 0;
            loadingIntoWrapped <= True;
        end
        $display("Loaded Raw result %X", rawAdd.result());
    endrule

    rule loadResultFromRaw;
        $display("Raw result %X", rawAdd.result());
    endrule

    rule loadDataIntoWrapped (loadingIntoWrapped && datumIndex < testDataCount);
        let datum = testData[datumIndex];
        wrappedAdd.load(datum, datum, S, RN);
        datumIndex <= datumIndex + 1;
    endrule

    rule loadResultFromWrapped(loadingIntoWrapped);
        $display("Wrapped result %X", wrappedAdd.result());
    endrule

    rule finish (loadingIntoWrapped && datumIndex == testDataCount);
        $finish();
    endrule
endmodule
