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
import CoProFPTypes::*;
import CoProFPSimulatedOps::*;
import CoProFPMegafunctionSimulation::*;
import MegafunctionTestBench::*;

import MIPS::*;

import List::*;

interface DiadicSimulatedMegafunctionTestBench#(numeric type delay);
    method Bool done();
endinterface

(* synthesize *)
module mkDiadicMegafunctionSimulationTests (Empty);
    DiadicSimulatedMegafunctionTestBench#(7) addTb <-
        mkSimulatedDiadicMegafunctionTestBench(add_fn, "Add");

    DiadicSimulatedMegafunctionTestBench#(5) mulTb <-
        mkSimulatedDiadicMegafunctionTestBench(mul_fn, "Multiply");

    DiadicSimulatedMegafunctionTestBench#(6) divTb <-
        mkSimulatedDiadicMegafunctionTestBench(div_fn, "Divide");

    DiadicSimulatedMegafunctionTestBench#(7) subTb <-
        mkSimulatedDiadicMegafunctionTestBench(sub_fn, "Subtract");

    rule finish(addTb.done() &&
                mulTb.done() && 
                divTb.done() && 
                subTb.done());
        $finish();
    endrule
endmodule

module [Module] mkSimulatedDiadicMegafunctionTestBench
    #(function Bit#(32) calculate(Bit#(32) left, Bit#(32) right),
      parameter String tag)
    (DiadicSimulatedMegafunctionTestBench#(delay))
    provisos(Add#(unused, 1, delay)); // delay <= 1 so piplining it works 

    SimulatedDiadicMegafunction#(delay) delayedFunction <- 
        mkSimulatedDiadicMegafunction(calculate);

    int delayInt = fromInteger(valueOf(delay));
    MegafunctionTestBench testBench <- 
        mkDiadicMegafunctionTestBench(delayedFunction.mf, delayInt, tag);

    method Bool done();
        return testBench.done();
    endmethod
endmodule
