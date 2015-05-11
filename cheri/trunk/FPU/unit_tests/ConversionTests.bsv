/*-
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Colin Rothwell as part of his final year
 * undergraduate project
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

import CoProFPConversionModules::*;
import PopFIFO::*;

import StmtFSM::*;
import FloatingPoint::*;
import FIFO::*;
import List::*;
import GetPut::*;
import ClientServer::*;

(* synthesize *)
module mkConversionTests();
    let dut <- mkWordToFloatServer();
    FIFO#(Float) enteredTests <- mkFIFO();

    let tests = cons(33558633, 
                cons(-23, nil));
    int testCount = fromInteger(length(tests));
    
    Reg#(int) count <- mkReg(0);
    mkAutoFSM(seq
        for (count <= 0; count < testCount; count <= count + 1) seq
            action
                enteredTests.enq(tests[count]);
                dut.request.put(tests[count]);
            endaction
        endseq
    endseq);

    rule outputResults;
        let test <- popFIFO(enteredTests);
        let res <- dut.response.get();
        $display("Converted %d to %x", test, res);
    endrule
endmodule
