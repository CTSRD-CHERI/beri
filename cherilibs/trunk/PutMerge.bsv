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
    Right,
    None
} DataSource deriving (Bits, Eq, FShow);

interface PutMerge#(type data);
    interface Put#(data) left;
    interface Put#(data) right;
endinterface

// This provides two put interfaces, and selects between them to write to its
// out interface. It's fair for some reasonable definition of fair: the source
// which didn't write last is allowed to go first.
module mkPutMerge#(Put#(data) out)(PutMerge#(data)) provisos (Bits#(data, a__));
    let _worker <- mkSizedPutMerge(2, out);
    return _worker;
endmodule

module mkSizedPutMerge#(Integer bufferLengths, Put#(data) out)(PutMerge#(data))
        provisos(Bits#(data, a__));
    FIFOF#(data) leftData <- mkSizedFIFOF(bufferLengths);
    FIFOF#(data) rightData <- mkSizedFIFOF(bufferLengths);
    Reg#(DataSource) lastData <- mkReg(Right);

    Bool rightReady = rightData.notEmpty();
    Bool leftReady = leftData.notEmpty();
    DataSource source = None;
    if (leftReady && rightReady) begin
      if (lastData == Right)
        source = Left;
      else // lastData == Left
        source = Right;
    end 
    else if (leftReady)  source = Left;
    else if (rightReady) source = Right;
    
    rule outputFromLeft(source == Left);
      out.put(leftData.first);
      leftData.deq;
      lastData <= source;
    endrule
    
    rule outputFromRight(source == Right);
      out.put(rightData.first);
      rightData.deq;
      lastData <= source;
    endrule

    interface left = toPut(leftData);
    interface right = toPut(rightData);
endmodule
