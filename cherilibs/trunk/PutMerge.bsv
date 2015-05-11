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

import GetPut::*;
import Connectable::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Library::*;

typedef enum {
    Left,
    Right
} DataSource deriving (Bits, Eq, FShow);

interface PutMerge#(type data);
    interface Put#(data) left;
    interface Put#(data) right;
endinterface

// This provides two put interfaces, and selects between them to write to its
// out interface. It's fair for some reasonable definition of fair: the source
// which didn't write last is allowed to go first.
module mkPutMerge#(Put#(data) out)(PutMerge#(data))
        provisos(Bits#(data, a__));

    function alwaysTrue(item);
        return True;
    endfunction

    let worker <- mkGuardedPutMerge(out, alwaysTrue);
    return worker;

endmodule

// This only dispatches the request if it satisfies some preidcate.
module mkGuardedPutMerge
        #(Put#(data) out,
          function Bool canPut(data item))
        (PutMerge#(data))
        provisos (Bits#(data, a__));

    FIFOF#(data) leftData <- mkBypassFIFOF();
    FIFOF#(data) rightData <- mkBypassFIFOF();
    Reg#(DataSource) lastData <- mkReg(Right);

    function Action outputFrom(DataSource source);
        action
            let fifo = (case (source)
                Left: leftData;
                Right: rightData;
            endcase);
            let data = fifo.first;
            if (canPut(data)) begin
                fifo.deq;
                out.put(data);
                lastData <= source;
            end
        endaction
    endfunction

    rule outputFromEither (leftData.notEmpty() && rightData.notEmpty());
        if (lastData == Right)
            outputFrom(Left);
        else // lastData == Left
            outputFrom(Right);
    endrule

    rule outputFromLeft (leftData.notEmpty() && !rightData.notEmpty());
        outputFrom(Left);
    endrule

    rule outputFromRight (rightData.notEmpty() && !leftData.notEmpty());
        outputFrom(Right);
    endrule

    interface left = toPut(leftData);
    interface right = toPut(rightData);

endmodule
