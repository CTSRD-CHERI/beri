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

import AsymmetricBRAM::*;
import UnitTesting::*;
import Variadic::*;
import StmtFSM::*;

module mkTest0 (Test);

    AsymmetricBRAM#(Bit#(1),UInt#(32),Bit#(1),UInt#(32))  dut <- mkAsymmetricBRAM(False, False);

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(32)) val     <- mkRegU;

    method String testName = "AsymmetricBRAM test symmetric port, not registered, not forwarded";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(0, 32'h0badf00d);
        endaction
        testAssert(count == 0);
        action
            dut.write(0, 32'hdeadbeef);
            dut.read(0);
        endaction
        testAssert(count == 1);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'h0badf00d);
        testAssert(count == 2);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 3);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.write(0, 32'hbabebabe);
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 4);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 5);
        action
            let tmp <- dut.getRead;
            val <= tmp;
        endaction
        testAssert(count == 6);
        testAssert(val == 32'hbabebabe);
    endseq;

endmodule

module mkTest1 (Test);

    AsymmetricBRAM#(Bit#(1),UInt#(32),Bit#(1),UInt#(32))  dut <- mkAsymmetricBRAM(True, False);

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(32)) val     <- mkRegU;

    method String testName = "AsymmetricBRAM test symmetric port, registered, not forwarded";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(0, 32'h0badf00d);
        endaction
        testAssert(count == 0);
        action
            dut.write(0, 32'hdeadbeef);
            dut.read(0);
        endaction
        testAssert(count == 1);
        action
            dut.read(0);
        endaction
        testAssert(count == 2);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'h0badf00d);
        testAssert(count == 3);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.write(0, 32'hbabebabe);
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 4);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 5);
        action
            let tmp <- dut.getRead;
            val <= tmp;
        endaction
        testAssert(count == 6);
        testAssert(val == 32'hdeadbeef);
        action
            let tmp <- dut.getRead;
            val <= tmp;
        endaction
        testAssert(count == 7);
        testAssert(val == 32'hbabebabe);
    endseq;

endmodule

module mkTest2 (Test);

    AsymmetricBRAM#(Bit#(1),UInt#(32),Bit#(1),UInt#(32))  dut <- mkAsymmetricBRAM(False, True);

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(32)) val     <- mkRegU;

    method String testName = "AsymmetricBRAM test symmetric port, not registered, forwarded";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(0, 32'h0badf00d);
            dut.read(0);
        endaction
        testAssert(count == 0);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.write(0, 32'hdeadbeef);
            dut.read(0);
        endaction
        testAssert(val == 32'h0badf00d);
        testAssert(count == 1);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 2);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 3);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.write(0, 32'hbabebabe);
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 4);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'hbabebabe);
        testAssert(count == 5);
        action
            let tmp <- dut.getRead;
            val <= tmp;
        endaction
        testAssert(count == 6);
        testAssert(val == 32'hbabebabe);
    endseq;

endmodule

module mkTest3 (Test);

    AsymmetricBRAM#(Bit#(1),UInt#(32),Bit#(1),UInt#(32))  dut <- mkAsymmetricBRAM(True, True);

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(32)) val     <- mkRegU;

    method String testName = "AsymmetricBRAM test symmetric port, registered, forwarded";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(0, 32'h0badf00d);
            dut.read(0);
        endaction
        testAssert(count == 0);
        action
            dut.write(0, 32'hdeadbeef);
            dut.read(0);
        endaction
        testAssert(count == 1);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'h0badf00d);
        testAssert(count == 2);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 3);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.write(0, 32'hbabebabe);
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 4);
        action
            let tmp <- dut.getRead;
            val <= tmp;
            dut.read(0);
        endaction
        testAssert(val == 32'hdeadbeef);
        testAssert(count == 5);
        action
            let tmp <- dut.getRead;
            val <= tmp;
        endaction
        testAssert(count == 6);
        testAssert(val == 32'hbabebabe);
    endseq;

endmodule

module mkTest4 (Test);

    AsymmetricBRAM#(Bit#(2),UInt#(32),Bit#(1),UInt#(64))  dut <- mkAsymmetricBRAM(False, False);

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(32)) val     <- mkRegU;

    method String testName = "AsymmetricBRAM test asymmetric write/read, not registered, not forwarded";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(0,64'h0123456789abcdef);
        endaction
        testAssert(count == 0);
        dut.read(0);
        testAssert(count == 1);
        action
            let tmp <- dut.getRead;
            val <= tmp;
        endaction
        testAssert(val == 32'h89abcdef);
        testAssert(count == 2);
        dut.read(1);
        testAssert(count == 3);
        action
            let tmp <- dut.getRead;
            val <= tmp;
        endaction
        testAssert(val == 32'h01234567);
        testAssert(count == 4);
        dut.write(1,64'hfeedbabedeadbabe);
        testAssert(count == 5);
        dut.read(3);
        testAssert(count == 6);
        action
            let tmp <- dut.getRead;
            val <= tmp;
        endaction
        testAssert(val == 32'hfeedbabe);
        testAssert(count == 7);
    endseq;

endmodule

module mkTestAsymmetricBRAM (Empty);

    Test test0 <- mkTest0;
    Test test1 <- mkTest1;
    Test test2 <- mkTest2;
    Test test3 <- mkTest3;
    Test test4 <- mkTest4;

    runTests(list(
        test0,
        test1,
        test2,
        test3,
        test4));

endmodule
