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

import MEM::*;
import UnitTesting::*;
import Variadic::*;
import StmtFSM::*;

module mkTest0 (Test);

    MEM#(UInt#(8), UInt#(16))  dut <- mkMEM;

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(16)) val     <- mkRegU;

    method String testName = "MEM test simple write then read";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(8, 16'hf00d);
        endaction
        testAssert(count == 0);
        action
            dut.read.put(8);
        endaction
        testAssert(count == 1);
        action
            val <= dut.read.peek();
        endaction
        testAssert(count == 2);
        testAssert(val == 16'hf00d);
        action
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 3);
        testAssert(val == 16'hf00d);
    endseq;

endmodule

module mkTest1 (Test);

    MEM#(UInt#(8), UInt#(16))  dut <- mkMEM;

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(16)) val     <- mkRegU;

    method String testName = "MEM test write and put read same cycle";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(6, 16'hbeef);
            dut.read.put(6);
        endaction
        testAssert(count == 0);
        action
            val <= dut.read.peek();
        endaction
        testAssert(count == 1);
        testAssert(val == 16'hbeef);
        action
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 2);
        testAssert(val == 16'hbeef);
    endseq;

endmodule

module mkTest2 (Test);

    MEM#(UInt#(8), UInt#(16))  dut <- mkMEM;

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(16)) val     <- mkRegU;

    method String testName = "MEM test several writes and peeks";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.read.put(42);
        endaction
        testAssert(count == 0);
        action
            dut.write(42, 16'hbabe);
        endaction
        testAssert(count == 1);
        action
            dut.write(42, 16'hffff);
            val <= dut.read.peek();
        endaction
        testAssert(count == 2);
        testAssert(val == 16'hbabe);
        action
            dut.write(42, 16'h0000);
            val <= dut.read.peek();
        endaction
        testAssert(count == 3);
        testAssert(val == 16'hffff);
        action
            val <= dut.read.peek();
        endaction
        testAssert(count == 4);
        testAssert(val == 16'h0000);
    endseq;

endmodule

module mkTest3 (Test);

    MEM#(UInt#(8), UInt#(16))  dut <- mkMEM;

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(16)) val     <- mkRegU;

    method String testName = "MEM test several writes with delay and peeks";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.read.put(42);
        endaction
        testAssert(count == 0);
        repeat (20) noAction;
        action
            dut.write(42, 16'hbabe);
        endaction
        testAssert(count == 21);
        repeat (20) noAction;
        action
            dut.write(42, 16'hffff);
            val <= dut.read.peek();
        endaction
        testAssert(count == 42);
        testAssert(val == 16'hbabe);
        repeat (20) noAction;
        action
            dut.write(42, 16'h0000);
            val <= dut.read.peek();
        endaction
        testAssert(count == 63);
        testAssert(val == 16'hffff);
        repeat (20) noAction;
        action
            val <= dut.read.peek();
        endaction
        testAssert(count == 84);
        testAssert(val == 16'h0000);
    endseq;

endmodule

module mkTest4 (Test);

    MEM#(UInt#(8), UInt#(16))  dut <- mkMEM;

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(16)) val     <- mkRegU;

    method String testName = "MEM test pipelined reads and writes";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(100, 16'h1234);
            dut.read.put(100);
        endaction
        testAssert(count == 0);
        action
            dut.write(101, 16'h2345);
            dut.read.put(101);
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 1);
        testAssert(val == 16'h1234);
        action
            dut.write(102, 16'h3456);
            dut.read.put(102);
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 2);
        testAssert(val == 16'h2345);
        action
            dut.write(103, 16'h4567);
            dut.read.put(103);
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 3);
        testAssert(val == 16'h3456);
        action
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 4);
        testAssert(val == 16'h4567);
    endseq;

endmodule

module mkTest5 (Test);

    MEM#(UInt#(8), UInt#(16))  dut <- mkMEM;

    Reg#(UInt#(8))  count   <- mkCounter;
    Reg#(UInt#(16)) val     <- mkRegU;

    method String testName = "MEM test pipelined reads and writes with delay";

    method Stmt runTest = seq
        action
            count <= 0;
            dut.write(100, 16'h1234);
            dut.read.put(100);
        endaction
        testAssert(count == 0);
        repeat (20) noAction;
        action
            dut.write(101, 16'h2345);
            dut.read.put(101);
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 21);
        testAssert(val == 16'h1234);
        repeat (20) noAction;
        action
            dut.write(102, 16'h3456);
            dut.read.put(102);
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 42);
        testAssert(val == 16'h2345);
        repeat (20) noAction;
        action
            dut.write(103, 16'h4567);
            dut.read.put(103);
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 63);
        testAssert(val == 16'h3456);
        repeat (20) noAction;
        action
            let tmp <- dut.read.get();
            val <= tmp;
        endaction
        testAssert(count == 84);
        testAssert(val == 16'h4567);
    endseq;

endmodule

module mkTestMEM (Empty);

    Test test0 <- mkTest0;
    Test test1 <- mkTest1;
    Test test2 <- mkTest2;
    Test test3 <- mkTest3;
    Test test4 <- mkTest4;
    Test test5 <- mkTest5;

    runTests(list(
        test0,
        test1,
        test2,
        test3,
        test4,
        test5));

endmodule
