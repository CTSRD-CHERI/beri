/*-
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Colin Rothwell as part of his final year
 * undergraduate project.
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
import CoProFPTypes::*;
import ShiftRegister::*;
import PopFIFO::*;

import MIPS::*;

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import ClientServer::*;
import FloatingPoint::*;

module [Module] mkMegafunctionServer
    #(Module#(Megafunction#(reqType, resultType)) mfModule)
    (WithInt#(delayLength, FloatingPointServer#(reqType, resultType)))
    provisos(Add#(resultTypeWidth, _, 64), Bits#(resultType, resultTypeWidth));

    let intDelayLength = valueOf(delayLength);

    // Should use type parameters
    Reg#(UInt#(1)) opPut <- mkDWire(0);
    Reg#(UInt#(1)) opGot <- mkDWire(0);
    Reg#(UInt#(5)) operationsInProgress <- mkReg(0);
    ShiftRegister#(delayLength, Bool) resultValid <- mkDefaultShiftRegister(False);
    FIFOF#(Tuple2#(resultType, FloatingPoint::Exception)) results 
        <- mkSizedBypassFIFOF(intDelayLength);

    let mfToWrap <- mfModule;

    rule updateOperationsInProgress;
        operationsInProgress <= operationsInProgress + 
            zeroExtend(opPut) - zeroExtend(opGot);
    endrule
    
    (* fire_when_enabled *)
    rule takeValidResult (resultValid.getTail());
        results.enq(mfToWrap.result());
    endrule

    interface FloatingPointServer payload;
        interface Put request;
            method Action put(reqType data) 
                    if (operationsInProgress < fromInteger(intDelayLength));

                opPut <= 1;
                resultValid.setHead(True);
                mfToWrap.place(data);
            endmethod
        endinterface

        interface Get response;
            method ActionValue#(Tuple2#(resultType, FloatingPoint::Exception)) get();
                opGot <= 1;
                let res <- popFIFOF(results);
                return res;
            endmethod
        endinterface
    endinterface
endmodule
