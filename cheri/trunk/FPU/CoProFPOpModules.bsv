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
import CoProFPConversionFunctions::*;
import PopFIFO::*;

import MIPS::*;

import GetPut::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import FloatingPoint::*;
import ClientServer::*;

module mkDummyServer(FloatingPointServer#(reqType, fpType));
    interface Put request;
        method Action put(reqType data);
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(Tuple2#(fpType, FloatingPoint::Exception)) get();
            return ?;
        endmethod
    endinterface
endmodule

module mkFloatAbsServer(MonadicFloatServer);
    let srv <- mkApplyFunctionServer(applyMask('h7fffffff));
    return srv;
endmodule

module mkDoubleAbsServer(MonadicDoubleServer);
    let srv <- mkApplyFunctionServer(applyMask('h7fffffffffffffff));
    return srv;
endmodule

module mkPairedSingleAbsServer(MonadicPairedSingleServer);
    let srv <- mkApplyFunctionServer(applyMask('h7fffffff7fffffff));
    return srv;
endmodule

module mkApplyFunctionServer
        #(function fpType mutate(fpType target))
        (FloatingPointServer#(MonadFPRequest#(fpType), fpType))
        provisos (Bits#(fpType, _));

    FIFO#(Tuple2#(fpType, FloatingPoint::Exception)) results <- mkFIFO();

    interface Put request;
        method Action put(MonadFPRequest#(fpType) data);
            results.enq(tuple2(mutate(tpl_1(data)), ?));
        endmethod
    endinterface
    
    interface Get response = toGet(results);
endmodule

function typ applyMask(Integer mask, typ target) provisos (Bits#(typ, _));
    return unpack(pack(target) & fromInteger(mask));
endfunction

// This uses the add server's output, so make sure you get your calls in the
// right order!
module mkUseAddForSub
    #(FloatingPointServer#(DiadFPRequest#(FloatingPoint#(e, m)),
                           FloatingPoint#(e, m)) addServer)
    (FloatingPointServer#(DiadFPRequest#(FloatingPoint#(e, m)),
                          FloatingPoint#(e, m)));

    interface Put request;
        method Action put(DiadFPRequest#(FloatingPoint#(e, m)) req);
            let negatedArg = negateFloatingPoint(tpl_2(req));
            addServer.request.put(tuple3(tpl_1(req), negatedArg, tpl_3(req)));
        endmethod
    endinterface

    interface Get response = addServer.response; 
endmodule

module mkUsePSAddForPSSub
    #(DiadicPairedSingleServer addServer)
    (DiadicPairedSingleServer);

    interface Put request;
        method Action put(DiadFPRequest#(PairedSingle) req);
            let negatedArg = negatePairedSingle(tpl_2(req));
            addServer.request.put(tuple3(tpl_1(req), negatedArg, tpl_3(req)));
        endmethod
    endinterface

    interface Get response = addServer.response;
endmodule

module mkUseDivForRecip
    #(FloatingPointServer#(DiadFPRequest#(FloatingPoint#(e, m)),
                           FloatingPoint#(e, m)) divServer)
    (FloatingPointServer#(MonadFPRequest#(FloatingPoint#(e, m)),
                           FloatingPoint#(e, m)));

    interface Put request;
        method Action put(MonadFPRequest#(FloatingPoint#(e, m)) req);
            let positiveOne = FloatingPoint::one(False);
            divServer.request.put(tuple3(positiveOne, tpl_1(req), tpl_2(req)));
        endmethod
    endinterface

    interface Get response = divServer.response;
endmodule

function DiadFPRequest#(Double)
        floatToDoubleRequest (DiadFPRequest#(Float) floatReq);

    Float floatLeft = tpl_1(floatReq);
    Float floatRight = tpl_2(floatReq);
    Double dblLeft = floatToDouble(floatLeft);
    Double dblRight = floatToDouble(floatRight);
    return tuple3(dblLeft, dblRight, tpl_3(floatReq));
endfunction

module [Module] mkUseDiadicDoubleForFloat
    #(DiadicDoubleServer doubleServer) 
    (DiadicFloatServer);

    interface Put request;
        method Action put(DiadFPRequest#(Float) req);
            doubleServer.request.put(floatToDoubleRequest(req));
        endmethod
    endinterface

    interface Get response = getDoubleToFloat(doubleServer.response);
endmodule

module [Module] mkUseMonadicDoubleForFloat
    #(MonadicDoubleServer doubleServer)
    (MonadicFloatServer);

    interface Put request;
        method Action put(MonadFPRequest#(Float) req);
            let double = floatToDouble(tpl_1(req));
            doubleServer.request.put(tuple2(double, tpl_2(req)));
        endmethod
    endinterface

    interface Get response = getDoubleToFloat(doubleServer.response);
endmodule

function Get#(Tuple2#(Float, Exception)) getDoubleToFloat
    (Get#(Tuple2#(Double, Exception)) getDouble);

    return (interface Get
        method ActionValue#(Tuple2#(Float, Exception)) get();
            Tuple2#(Double, Exception) res <- getDouble.get();
            Double dblRes = tpl_1(res); 
            return tuple2(doubleToFloat(dblRes), tpl_2(res));
        endmethod
    endinterface);
endfunction

module mkNegateServer(
    FloatingPointServer#(MonadFPRequest#(FloatingPoint#(e, m)),
                         FloatingPoint#(e, m)));

    let worker <- mkApplyFunctionServer(negateFloatingPoint);
    return worker;
endmodule

module mkNegatePairedSingleServer(MonadicPairedSingleServer);
    let worker <- mkApplyFunctionServer(negatePairedSingle);
    return worker;
endmodule

function PairedSingle negatePairedSingle(PairedSingle ps);
    let negLeft = negateFloatingPoint(tpl_1(ps));
    let negRight = negateFloatingPoint(tpl_2(ps));
    return tuple2(negLeft, negRight);
endfunction

function FloatingPoint#(e, m) negateFloatingPoint(FloatingPoint#(e, m) fp);
    return FloatingPoint { sign: !fp.sign, exp: fp.exp, sfd: fp.sfd };
endfunction

typedef struct {
    Bool less;
    Bool equal;
} LessEqual;

function LessEqual compareNumberFloats(
        Bool fsSign, td fsData, Bool ftSign, td ftData)
        provisos(Eq#(td), Ord#(td), Literal#(td));
    Bool less, equal;

    if (fsData == 0 && ftData == 0) begin
        less = False;
        equal = True;
    end
    else begin
        if (fsSign != ftSign) begin
            equal = False;
            less = fsSign;
        end
        else begin
            less = (fsSign && (fsData > ftData)) || ((!fsSign) && (fsData < ftData));
            equal = fsData == ftData;
        end
    end

    return LessEqual { less: less, equal: equal };
endfunction

typedef struct {
    Bool less;
    Bool equal;
    Bool unordered;
} ComparisonResult deriving (Bits);

function ComparisonResult compareSingles(Bit#(32) fs, Bit#(32) ft);
    Bool less, equal, unordered;
    Float floatFs = unpack(fs); 
    Float floatFt = unpack(ft);
    if (isNaN(floatFs) || isNaN(floatFt)) begin
        less = False;
        equal = False;
        unordered = True;
    end
    else begin
        unordered = False;
        let res = compareNumberFloats(floatFs.sign, fs[30:0], floatFt.sign, ft[30:0]);
        less = res.less;
        equal = res.equal;
    end
    return ComparisonResult { less: less, equal: equal, unordered: unordered };
endfunction

function ComparisonResult compareDoubles(Bit#(64) fs, Bit#(64) ft);
    Bool less, equal, unordered;
    Double floatFs = unpack(pack(fs)); 
    Double floatFt = unpack(pack(ft));
    if (isNaN(floatFs) || isNaN(floatFt)) begin
        less = False;
        equal = False;
        unordered = True;
    end
    else begin
        unordered = False;
        let res = compareNumberFloats(floatFs.sign, fs[62:0], floatFt.sign, ft[62:0]);
        less = res.less;
        equal = res.equal;
    end
    return ComparisonResult { less: less, equal: equal, unordered: unordered };
endfunction

function Bool evaluateCondition(Bit#(4) cond, ComparisonResult comparison);
    return (unpack(cond[2]) && comparison.less) ||
           (unpack(cond[1]) && comparison.equal) || 
           (unpack(cond[0]) && comparison.unordered);
endfunction

interface MultipleFormatComparisonServer;
    interface ComparisonServer float;
    interface ComparisonServer double;
    interface ComparisonServer pairedSingle;
endinterface

typedef struct {
    Bit#(4) condition;
    ComparisonResult resultLow;
    ComparisonResult resultHigh;
} FormattedComparison deriving (Bits);

module mkCompareServers#(Integer fifoLength)(MultipleFormatComparisonServer);
    //For information on the behaviour of condition and cond, consult the MIPS
    //Instruction Set manual!
    FIFO#(FormattedComparison) results <- mkSizedFIFO(fifoLength);

    Wire#(MIPSReg) left <- mkWire;
    Wire#(MIPSReg) right <- mkWire;
    Wire#(Bit#(4)) condition <- mkWire;
    Wire#(Format) fmt <- mkWire;
   
    rule loadResults;
        let cmp = FormattedComparison { condition: condition, 
                                        resultLow: ?,
                                        resultHigh: ? };

        if (fmt == S || fmt == PS)
            cmp.resultLow = compareSingles(left[31:0], right[31:0]);
        if (fmt == PS)
            cmp.resultHigh = compareSingles(left[63:32], right[63:32]);
        if (fmt == D)
            cmp.resultLow = compareDoubles(left, right);

        results.enq(cmp);
    endrule

    function Action setWires(Format format, ComparisonArgs args);
        action
            fmt <= format;
            left <= args.left;
            right <= args.right;
            condition <= args.cond;
        endaction
    endfunction

    function ActionValue#(MIPSReg) result();
        actionvalue
            let cmp <- popFIFO(results);
            return { 62'b0, // Compare should probably be a seperate unit... 
                     pack(evaluateCondition(cmp.condition, cmp.resultHigh)), 
                     pack(evaluateCondition(cmp.condition, cmp.resultLow)) };
        endactionvalue
    endfunction

    interface ComparisonServer float;
        interface Put request = toPut(setWires(S));
        interface Get response = toGet(result);
    endinterface

    interface ComparisonServer double;
        interface Put request = toPut(setWires(D));
        interface Get response = toGet(result);
    endinterface

    interface ComparisonServer pairedSingle;
        interface Put request = toPut(setWires(PS));
        interface Get response = toGet(result);
    endinterface
endmodule
