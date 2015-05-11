/*-
 * Copyright (c) 2014 Alex Horsman
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

package UnitTesting;


import GetPut::*;
import StmtFSM::*;

import List::*;
import ModuleCollect::*;


function Stmt abort() = seq
    return 0;
endseq;

function Stmt testAssert(Bool cond) = seq
    if (!cond) abort();
endseq;

function Stmt testAssertEqual(a expected, a actual) provisos(Eq#(a), FShow#(a)) = seq
    if (expected != actual) seq
        $displayh("Expected: ", fshow(expected), ". Got: ", fshow(actual));
        abort();
    endseq
endseq;

function Stmt seqStmts(Stmt first, Stmt second) = seq
    first;
    second;
endseq;

function Stmt concatStmts(List#(Stmt) stmts) =
    foldl(seqStmts,seq endseq,stmts);

module mkCounter (Reg#(dataT))
    provisos (Arith#(dataT), Bits#(dataT, data_size));

    Reg#(dataT) val <- mkRegU;
    PulseWire do_write <- mkPulseWire;

    rule do_count (!do_write);
        val <= val + 1;
    endrule

    method dataT _read = val;
    method Action _write (dataT v);
        do_write.send();
        val <= v;
    endmethod

endmodule

interface Test;
    method String testName;
    method Stmt runTest();
endinterface

module mkTestFSM#(Test test)(TestFSM);

    Reg#(Bool) passed <- mkReg(False);

    FSM fsm <- mkFSM(seq
        test.runTest();
        passed <= True;
    endseq);

    method name = test.testName();

    method Action start();
        fsm.start();
    endmethod

    method Bool result() if (fsm.done());
        return passed;
    endmethod

endmodule


interface TestFSM;
    method String name;
    method Action start();
    method Bool result();
endinterface

module runTests#(List#(Test) tests)(Empty);
    runTestsWithBookeeping(noAction, noAction, tests);
endmodule

module runTestsWithBookeeping
        #(Action setup, Action teardown, List#(Test) tests)(Empty);

    List#(TestFSM) resultGetters <- mapM(mkTestFSM,tests);

    function Stmt printResult(TestFSM test) = seq
        setup();
        $write("%s - ", test.name);
        test.start();
        action
            if (test.result) begin
                $display("Passed");
            end else begin
                $display("FAILED");
            end
        endaction
        teardown();
    endseq;

    Stmt testSequence = concatStmts(map(printResult,resultGetters));

    mkAutoFSM(seq
        $display("Starting tests");
        testSequence;
        $display("Tests finished.");
    endseq);

endmodule


endpackage
