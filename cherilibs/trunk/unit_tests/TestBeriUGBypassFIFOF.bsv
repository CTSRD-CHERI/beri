/*-
 * Copyright (c) 2014 Alexandre Joannou
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

import BeriUGBypassFIFOF::*;
import FIFOF::*;
import UnitTesting::*;
import Variadic::*;
import StmtFSM::*;

// notEmpty Conflict enq when in the same rule

module mkTest0 (Test);

    FIFOF#(UInt#(8)) dut <- mkBeriUGBypassFIFOF;

    Reg#(UInt#(8)) count <- mkCounter;

    method String testName = "BeriUGBypassFIFOF test simple enqueue - dequeue";

    method Stmt runTest = seq
        count <= 0;
        testAssert(dut.notFull);
        testAssert(count == 0);
        dut.enq(42);
        testAssert(!dut.notFull);
        testAssert(dut.notEmpty);
        testAssert(42 == dut.first);
        testAssert(count == 1);
        dut.deq;
        testAssert(!dut.notEmpty);
        testAssert(dut.notFull);
        testAssert(count == 2);
    endseq;

endmodule

module mkTest1 (Test);

    FIFOF#(UInt#(8)) dut <- mkBeriUGBypassFIFOF;

    Reg#(UInt#(8)) val <- mkRegU;

    Reg#(UInt#(8)) count <- mkCounter;

    method String testName = "BeriUGBypassFIFOF test single cycle enqueue - dequeue";

    method Stmt runTest = seq
        count <= 0;
        testAssert(dut.notFull);
        par
            seq
                dut.enq(42);
            endseq
            seq
                action
                    val <= dut.first;
                    dut.deq;
                endaction
            endseq
            testAssert(count == 0);
        endpar
        testAssert(val == 42);
        testAssert(dut.notFull);
        testAssert(!dut.notEmpty);
        testAssert(count == 1);
    endseq;

endmodule

module mkTestBeriUGBypassFIFOF (Empty);

    Test test0 <- mkTest0;
    Test test1 <- mkTest1;

    runTests(list(
        test0,
        test1));

endmodule
