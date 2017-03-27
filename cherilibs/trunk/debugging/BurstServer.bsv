/*-
 * Copyright (c) 2013 Alex Horsman
 * All rights reserved.
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

import ClientServer::*;
import GetPut::*;
import FIFO::*;

// Utility servers for building a burst. The build server collects words
// together to form a burst, the feed server outputs the words in a burst.
// This ensures the burst transfers can occur on successive cycles.
module mkBurstBuildServer(Server#(inType, outType))
    provisos (
        Bits#(inType, inSize), Bits#(outType, outSize),
        Div#(outSize, inSize, burstSize),
        Mul#(inSize, burstSize, outSize), // Divides properly
        Log#(TAdd#(burstSize, 1), burstCountRegSize),
        Add#(a__, inSize, outSize) // from bsc
    ); 

    UInt#(burstCountRegSize) burstSizeInt = fromInteger(valueOf(burstSize));

    Reg#(UInt#(burstCountRegSize)) wordsInBurst <- mkReg(0);
    Reg#(Bit#(outSize)) buildingBurst <- mkRegU;
    FIFO#(outType) finishedBurst <- mkFIFO();

    interface Put request;
        method Action put(inType in) if (wordsInBurst != burstSizeInt);
            let newBurst = { pack(in), truncateLSB(buildingBurst) };
            if (wordsInBurst == burstSizeInt - 1) begin
                wordsInBurst <= 0;
                finishedBurst.enq(unpack(newBurst));
            end
            else begin
                wordsInBurst <= wordsInBurst + 1;
                buildingBurst <= newBurst;
            end
        endmethod
    endinterface

    interface Get response = toGet(finishedBurst);
endmodule

module mkBurstFeedServer(Server#(inType, outType))
    provisos (
        Bits#(inType, inSize), Bits#(outType, outSize),
        Div#(inSize, outSize, burstSize),
        Mul#(outSize, burstSize, inSize),
        Log#(TAdd#(burstSize, 1), burstCountRegSize)
    );

    UInt#(burstCountRegSize) burstSizeInt = fromInteger(valueOf(burstSize));

    Reg#(UInt#(burstCountRegSize)) wordsInBurst <- mkReg(0);
    Reg#(Bit#(inSize)) burst <- mkRegU;

    interface Put request;
        method Action put(inType in) if (wordsInBurst == 0);
            wordsInBurst <= burstSizeInt;
            burst <= pack(in);
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(outType) get() if (wordsInBurst != 0);
            wordsInBurst <= wordsInBurst - 1;
            let bottomBurstWord = burst[valueOf(outSize) - 1:0];
            burst <= burst >> valueOf(outSize);
            return unpack(bottomBurstWord);
        endmethod
    endinterface

endmodule
