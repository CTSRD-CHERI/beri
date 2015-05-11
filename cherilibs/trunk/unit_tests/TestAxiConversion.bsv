/*-
* Copyright (c) 2014 Colin Rothwell
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
*
*/

import Testing::*;
import Variadic::*;
import List::*;
import CheriAxi::*;
import TLM3::*;
import StmtFSM::*;

module [TestModule] mkTestOffsetAndSize(Empty);
    List#(Bit#(32)) inputs = list(
       'b1,
       'b10,
       'b100,
       'b11,
       'b1100,
       'b1111,
       'hff,
       'hffff,
       'hffffffff,
       'hf0
   );

   List#(Tuple2#(Bit#(32), TLMBSize)) expectedValid = list(
       tuple2(0, BITS8),
       tuple2(1, BITS8),
       tuple2(2, BITS8),
       tuple2(0, BITS16),
       tuple2(2, BITS16),
       tuple2(0, BITS32),
       tuple2(0, BITS64),
       tuple2(0, BITS128),
       tuple2(0, BITS256),
       tuple2(4, BITS32)
    );

    function toValid(in);
        return tagged Valid in;
    endfunction

    let expected = map(toValid, expectedValid);

    function applyAndCheck(in, expec);
        return (seq
            return offsetAndSize(in) == expec;
        endseq);
    endfunction
    
    let results = zipWith(applyAndCheck, inputs, expected);

    let names = list(
        "Byte",
        "Byte, offset 1",
        "Byte, offset 2",
        "Two bytes",
        "Two bytes, offset 2",
        "Four bytes",
        "Eight bytes",
        "Sixteen bytes",
        "32 bytes",
        "Four bytes, offset 4"
    );

    zipWithM(addTest, names, results);

endmodule

(* synthesize *)
module [Module] mkTestOffsetAndSizeRunner(Empty);
    runTests(mkTestOffsetAndSize);
endmodule
