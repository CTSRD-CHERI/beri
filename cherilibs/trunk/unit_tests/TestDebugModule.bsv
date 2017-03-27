/*-
 * Copyright (c) 2014 Alexandre Joannou
 * Copyright (c) 2016 A. Theodore Markettos
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
 */

import UnitTesting::*;
import Variadic::*;
import StmtFSM::*;
import DebugModule::*;

interface DebugTestIfc;
    method UInt#(8) counter;
endinterface

module [DebugModule] mkDebugTest(DebugTestIfc);
    Reg#(UInt#(8)) count1 <- mkReg(0);
    addDebugEntry("count1", count1);
    Reg#(UInt#(8)) count2 <- mkDebugReg("count2", 0);

    rule inc;
        count1 <= count1 + 1;
        count2 <= count2 + 1;
    endrule

    method counter = count1;
endmodule

module [DebugModule] mkTest0 (Test);


    Reg#(UInt#(8))  count   <- mkCounter;
    DebugTestIfc debug <- mkDebugTest;
    UInt#(8) probeName <- getDebugEntry("count1");
    UInt#(8) probeDebugReg <- getDebugEntry("count2");

    method String testName = "DebugModule counter test";

    method Stmt runTest = seq
        action
            $display("probe by name = %d, probe DebugReg = %d, output counter = %d", probeName, probeDebugReg, debug.counter);
        endaction
        testAssert(probeName == debug.counter);
        testAssert(probeDebugReg == debug.counter);
        action
            $display("probe by name = %d, probe DebugReg = %d, output counter = %d", probeName, probeDebugReg, debug.counter);
        endaction
        testAssert(probeName == debug.counter);
        testAssert(probeDebugReg == debug.counter);
        action
            $display("probe by name = %d, probe DebugReg = %d, output counter = %d", probeName, probeDebugReg, debug.counter);
        endaction
        testAssert(probeName == debug.counter);
        testAssert(probeDebugReg == debug.counter);
        action
            $display("probe by name = %d, probe DebugReg = %d, output counter = %d", probeName, probeDebugReg, debug.counter);
        endaction
        testAssert(probeName == debug.counter);
        testAssert(probeDebugReg == debug.counter);
    endseq;

endmodule

module [DebugModule] mkTestDebugModuleInner (Empty);
    Test test0 <- mkTest0;

    runTests(list(
        test0));

endmodule

Module#(Empty) mkTestDebugModule = runDebug(mkTestDebugModuleInner);
