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
import PopFIFO::*;

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import ClientServer::*;
import FloatingPoint::*;
import Vector::*;

module mkFPConversionServer
    #(function FloatingPoint#(e2, m2) doConversion(FloatingPoint#(e, m) in),
      Integer fifoLength)
    (FloatingPointServer#(MonadFPRequest#(FloatingPoint#(e, m)),
                          FloatingPoint#(e2, m2)));
    
    FIFO#(Tuple2#(FloatingPoint#(e, m), RoundMode)) requests <- mkFIFO();
    FIFO#(Tuple2#(FloatingPoint#(e2, m2), Exception)) responses <-
        mkSizedFIFO(fifoLength);

    rule convert;
        let req <- popFIFO(requests);
        responses.enq(tuple2(doConversion(tpl_1(req)), ?));
    endrule

    interface Put request = toPut(requests);
    interface Get response = toGet(responses);
endmodule

typedef struct {
    Bool negative;
    Bit#(size) bits;
} SignAndBits#(numeric type size) deriving(Bits);

// Only works on normalised types.
module mkFloatingPointToLongServer
    (Server#(MonadFPRequest#(FloatingPoint#(e, m)), Int#(64)))
    provisos (
        Bits#(FloatingPoint#(e, m), width),
        Add#(e, 1, shamtWidth),
        Add#(a__, width, 64),
        Add#(b__, TAdd#(1, m), width), // from bsc
        Add#(m, c__, 63)
    );
    
    function floatRequestToSignAndBits(floatReq);

        FloatingPoint#(e, m) float = tpl_1(floatReq);
        RoundMode rm = tpl_2(floatReq);
        Bit#(64) resultTemp = zeroExtend({1'b1, float.sfd});
        // Because of the implicit position of the binary point, this is
        // already right shifted by m.
        Int#(shamtWidth) shiftCorrection = fromInteger(valueOf(m) + biasOf(float));
        Int#(shamtWidth) shift = unpack(zeroExtend(float.exp)) - shiftCorrection;
        if (shift >= 0)
            resultTemp = resultTemp << shift;
        else begin
            // can lose precision, so I need to round
            let rshift = -shift;
            // to put bit rt[rs - 2] in the top bit, 
            // we left shift by 64 - 1 - (rs - 2)
            let deciderBits = resultTemp << (65 - rshift);
            Bool decider = (|deciderBits == 1);
            // rshift - 1 must be >= 0
            Bool half = (resultTemp[rshift - 1] == 1);
            // we have shifted away any non-zero bit
            Bool inexact = half || decider;
            resultTemp = resultTemp >> rshift;
            case (rm)
                Rnd_Nearest_Even: 
                    if (half && (resultTemp[0] == 1 || decider))
                        resultTemp = resultTemp + 1;
                Rnd_Minus_Inf:
                    if (float.sign && inexact)
                        resultTemp = resultTemp + 1;
                Rnd_Plus_Inf:
                    if (!float.sign && inexact)
                        resultTemp = resultTemp + 1;
                // Truncate happens naturally!
            endcase
        end
        return SignAndBits { negative: float.sign, bits: resultTemp };
    endfunction

    function Bit#(64) evalSignAndBits(SignAndBits#(64) sab);
        return signExtend(sab.negative ? -sab.bits : sab.bits);
    endfunction

    FIFO#(SignAndBits#(64)) results <- mkFIFO();

    interface Put request;
        method Action put(MonadFPRequest#(FloatingPoint#(e, m)) data);
            results.enq(floatRequestToSignAndBits(data));
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Int#(64)) get();
            let res <- popFIFO(results);
            return unpack(evalSignAndBits(results.first()));
        endmethod
    endinterface

endmodule

module mkIntToFloatingPointServer(Server#(Int#(intSize), FloatingPoint#(e, m)))
    provisos (
        Log#(intSize, positionTypeSize),
        Add#(a_, positionTypeSize, e), // from bsc
        Add#(b_, m, intSize)
    );

    let topBitPosition = valueOf(intSize) - 1;
    let bias = fromInteger((2 ** (valueof(e) - 1)) - 1);
    let mBits = fromInteger(valueOf(m));

    function UInt#(positionTypeSize) indexOfTopOne(Bit#(intSize) word);
        // Reverse so we can find from the most signficant bit
        Vector#(intSize, Bit#(1)) vector = reverse(unpack(word));
        case (findElem(1'b1, vector)) matches
            // 31 is because we had to reverse
            tagged Valid .pos: return fromInteger(topBitPosition) - pos; 
            default: return 0;
        endcase
    endfunction

    function FloatingPoint#(e,m) wordToFloat(Int#(intSize) word);
        if (word == 0) 
            return zero(False); //unsigned zero
        else begin
            Bool sign = unpack(pack(word)[topBitPosition]);
            Bit#(intSize) usWord = pack(abs(word));
            // Floating point implictly has the first one, so that's where we take the
            // mantissa from. If it's more than 23, and we can't mantain precision,
            // we have to cut off some of the bottom, otherwise we shift upwards.
            let msoIndex = indexOfTopOne(usWord);
            Bit#(m) sfd;
            if (msoIndex > mBits) 
                sfd = truncate(usWord >> (msoIndex - mBits));
            else
                sfd = truncate(usWord << (mBits - msoIndex));
            Bit#(e) exp = pack(zeroExtend(msoIndex) + bias); 
            return FloatingPoint { sign: sign, exp: exp, sfd: sfd };
        end
    endfunction

    FIFO#(FloatingPoint#(e, m)) resultFIFO <- mkFIFO;

    interface Put request;
        method Action put(Int#(intSize) word);
            resultFIFO.enq(wordToFloat(word));
        endmethod
    endinterface

    interface Get response = toGet(resultFIFO);
endmodule

// Copied from the floating point library: they don't export it for some reason.
function Integer biasOf(FloatingPoint#(e, m) fp);
    return (2 ** (valueof(e) - 1)) - 1;
endfunction
