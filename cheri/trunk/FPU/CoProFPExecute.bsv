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
import CoProFPInst::*;
import PopFIFO::*;
import BufferServer::*;
import CoProFPOpModules::*;
import CoProFPCompositeServers::*;
import CoProFPConversionModules::*;
import CoProFPConversionFunctions::*;
import CoProFPSynthesisableModules::*;

import MIPS::*;

import ClientServer::*;
import GetPut::*;
import FIFO::*;
import FloatingPoint::*;

module [Module] mkCoProFPExecute(Server#(ExecuteRequest, MIPSReg));
    let floatAbsServer <- mkBufferOutputServer(mkFloatAbsServer, 1);
    let doubleAbsServer <- mkBufferOutputServer(mkDoubleAbsServer, 1);
    let pairedSingleAbsServer <- mkBufferOutputServer(mkPairedSingleAbsServer, 1);

    let addServers <- mkConcreteAddServers();

    let compareServers <- mkCompareServers(1);

    //Conversion servers
    FloatingPointServer#(MonadFPRequest#(Float), Double) floatToDoubleServer <-
        mkFPConversionServer(floatToDouble, 1);
    FloatingPointServer#(MonadFPRequest#(Double), Float) doubleToFloatServer <- 
        mkFPConversionServer(doubleToFloat, 1);
    let floatToLongServer <- mkFloatingPointToLongServer();
    let doubleToLongServer <- mkFloatingPointToLongServer();
    Server#(Int#(64), Float) longToFloatServer <- mkIntToFloatingPointServer();
    Server#(Int#(64), Double) longToDoubleServer <- mkIntToFloatingPointServer();

    let doubleDivServer <- mkConcreteDoubleDivServer();
    let floatDivServer <- mkUseDiadicDoubleForFloat(doubleDivServer);

    let mulServers <- mkConcreteMulServers();

    let floatNegServer <- mkBufferOutputServer(mkNegateServer, 1);
    let doubleNegServer <- mkBufferOutputServer(mkNegateServer, 1);
    let pairedSingleNegServer <-
        mkBufferOutputServer(mkNegatePairedSingleServer, 1);

    let doubleRecipServer <- mkUseDivForRecip(doubleDivServer);
    let floatRecipServer <- mkUseDivForRecip(floatDivServer);

    let doubleSqrtServers <- mkSqrtDoubleServers();
    let floatSqrtServer <- mkUseMonadicDoubleForFloat(doubleSqrtServers.sqrt);
    let floatRecipSqrtServer <-
        mkUseMonadicDoubleForFloat(doubleSqrtServers.recipSqrt);
    
    let floatSubServer <- mkUseAddForSub(addServers.float);
    let pairedSingleSubServer <-
        mkUsePSAddForPSSub(addServers.pairedSingle);
    let doubleSubServer <- mkUseAddForSub(addServers.double);

    // Dummy servers: should never be called, stops it whinging about defaults.
    MonadicFloatServer dummyMonadFloatServer <- mkDummyServer;
    MonadicDoubleServer dummyMonadDoubleServer <- mkDummyServer;
    MonadicPairedSingleServer dummyMonadPairedSingleServer <- mkDummyServer;
    DiadicFloatServer dummyDiadFloatServer <- mkDummyServer;
    DiadicDoubleServer dummyDiadDoubleServer <- mkDummyServer;
    DiadicPairedSingleServer dummyDiadPairedSingleServer <- mkDummyServer;

    function selectMonadFloatServer(op);
        case (op)
            Abs: return floatAbsServer;
            Neg: return floatNegServer;
            Recip: return floatRecipServer;
            RecipSqrt: return floatRecipSqrtServer;
            Sqrt: return floatSqrtServer;
            default: return dummyMonadFloatServer;
        endcase
    endfunction

    function selectMonadDoubleServer(op);
        case (op)
            Abs: return doubleAbsServer;
            Neg: return doubleNegServer;
            Sqrt: return doubleSqrtServers.sqrt;
            Recip: return doubleRecipServer;
            RecipSqrt: return doubleSqrtServers.recipSqrt;
            default: return dummyMonadDoubleServer;
        endcase
    endfunction

    function selectMonadPairedSingleServer(op);
        case (op)
            Abs: return pairedSingleAbsServer;
            Neg: return pairedSingleNegServer;
            default: return dummyMonadPairedSingleServer;
        endcase
    endfunction

    function selectDiadFloatServer(op);
        case (op) 
            CoProFPTypes::Add: return addServers.float;
            Div: return floatDivServer;
            Mul: return mulServers.float;
            Sub: return floatSubServer;
            default: return dummyDiadFloatServer;
        endcase
    endfunction

    function selectDiadDoubleServer(op);
        case (op)
            CoProFPTypes::Add: return addServers.double;
            Div: return doubleDivServer;
            Mul: return mulServers.double;
            Sub: return doubleSubServer;
            default: return dummyDiadDoubleServer;
        endcase
    endfunction

    function selectDiadPairedSingleServer(op);
        case (op)
            CoProFPTypes::Add: return addServers.pairedSingle;
            Mul: return mulServers.pairedSingle;
            Sub: return pairedSingleSubServer;
            default: return dummyDiadPairedSingleServer;
        endcase
    endfunction

    function extractMonadQNaN(fp, argType);
        if (isQNaN(fp))
            return tagged Value zeroExtend(pack(fp));
        else
            return tagged Execute argType;
    endfunction

    function extractMonadPSQNaN(ps, argType);
        let high = tpl_1(ps);
        let low = tpl_2(ps);
        if (isQNaN(high) && isQNaN(low))
            return tagged Value pack(tuple2(high, low));
        else if (isQNaN(low))
            return tagged ValueLow tuple2(argType, pack(low));
        else if (isQNaN(high))
              return tagged ValueHigh tuple2(argType, pack(high));
        else
            return tagged Execute argType;
    endfunction

    function extractDiadQNaN(left, right, argType);
        if (isQNaN(left))
            return tagged Value zeroExtend(pack(left));
        else if (isQNaN(right))
            return tagged Value zeroExtend(pack(right));
        else
            return tagged Execute argType;
    endfunction

    function floatDiadQNaN(left, right);
        if (isQNaN(left))
            return Valid(pack(left));
        else if (isQNaN(right))
            return Valid(pack(right));
        else
            return Invalid;
    endfunction

    function extractDiadPSQNaN(left, right, argType);
        let leftHigh = tpl_1(left);
        let leftLow = tpl_2(left);
        let rightHigh = tpl_1(right);
        let rightLow = tpl_2(right);
        let highQNaN = floatDiadQNaN(leftHigh, rightHigh);
        let lowQNaN = floatDiadQNaN(leftLow, rightLow);
        if (highQNaN matches tagged Valid .hqv &&&
                lowQNaN matches tagged Valid .lqv)
            return tagged Value pack(tuple2(hqv, lqv));
        else if (lowQNaN matches tagged Valid .lqv)
            return tagged ValueLow tuple2(argType, lqv);
        else if (highQNaN matches tagged Valid .hqv)
            return tagged ValueHigh tuple2(argType, hqv);
        else
            return tagged Execute argType;
    endfunction

    function ExecuteSource getExecuteSource(ExecuteRequest req);
        ExecuteArgType argType = getArgType(req.args);
        case (req.args) matches
            tagged MonadFloat .fpreq:
                return extractMonadQNaN(tpl_1(fpreq), argType);
            tagged MonadDouble .fpreq:
                return extractMonadQNaN(tpl_1(fpreq), argType);
            tagged MonadPairedSingle .fpreq:
                return extractMonadPSQNaN(tpl_1(fpreq), argType);
            tagged DiadFloat .fpreq:
                return extractDiadQNaN(tpl_1(fpreq), tpl_2(fpreq), argType);
            tagged DiadDouble .fpreq:
                return extractDiadQNaN(tpl_1(fpreq), tpl_2(fpreq), argType);
            tagged DiadPairedSingle .fpreq:
                return extractDiadPSQNaN(tpl_1(fpreq), tpl_2(fpreq), argType);
            default:
                return tagged Execute argType;
        endcase
    endfunction

    function Bool shouldDispatch(ExecuteSource src);
        if (src matches tagged Value .*)
            return False;
        else
            return True;
    endfunction

    function Action dispatchExecuteRequest(ExecuteRequest req);
        action
            case (req.args) matches
                tagged MonadWord .word: begin
                    let seWord = signExtend(word);
                    case (req.op)
                        ToFloat: longToFloatServer.request.put(seWord);
                        ToDouble: longToDoubleServer.request.put(seWord);
                    endcase
                end
                tagged MonadLong .long:
                    case (req.op)
                        ToFloat: longToFloatServer.request.put(long);
                        ToDouble: longToDoubleServer.request.put(long);
                    endcase
                tagged MonadFloat .fpreq: begin
                    case (req.op)
                        ToDouble: floatToDoubleServer.request.put(fpreq);
                        ToLong: floatToLongServer.request.put(fpreq);
                        ToWord: floatToLongServer.request.put(fpreq);
                        default: selectMonadFloatServer(req.op).request.put(fpreq);
                    endcase
                end
                tagged MonadDouble .fpreq:
                    case (req.op)
                        ToFloat: doubleToFloatServer.request.put(fpreq);
                        ToLong: doubleToLongServer.request.put(fpreq);
                        ToWord: doubleToLongServer.request.put(fpreq);
                        default: selectMonadDoubleServer(req.op).request.put(fpreq);
                    endcase
                tagged MonadPairedSingle .fpreq: 
                    selectMonadPairedSingleServer(req.op).request.put(fpreq);
                tagged DiadFloat .fpreq: 
                    selectDiadFloatServer(req.op).request.put(fpreq);
                tagged DiadDouble .fpreq:
                    selectDiadDoubleServer(req.op).request.put(fpreq);
                tagged DiadPairedSingle .fpreq:
                    selectDiadPairedSingleServer(req.op).request.put(fpreq);
                tagged Compare .compare:
                    case (compare.fmt)
                        S: compareServers.float.request.put(compare);
                        D: compareServers.double.request.put(compare);
                        PS: compareServers.pairedSingle.request.put(compare);
                        default: compareServers.float.request.put(compare);
                    endcase
            endcase
        endaction
    endfunction

    function retrieveExecuteResponse(op, argType, fd);
        actionvalue
            ExecuteArgType at = argType; //for typing!
            case (at) matches
                MonadWord: begin
                    case (op)
                        ToFloat: begin
                            let res <- longToFloatServer.response.get();
                            return zeroExtend(pack(res));
                        end
                        ToDouble: begin
                            let res <- longToDoubleServer.response.get();
                            return pack(res);
                        end
                    endcase
                end
                MonadLong: begin
                    case (op)
                        ToFloat: begin
                            let res <- longToFloatServer.response.get();
                            return zeroExtend(pack(res));
                        end
                        ToDouble: begin
                            let res <- longToDoubleServer.response.get();
                            return pack(res);
                        end
                    endcase
                end
                MonadFloat: begin
                    case (op)
                        ToDouble: begin
                            let res <- floatToDoubleServer.response.get();
                            return flushDoubleDenorm(tpl_1(res), fd);
                        end
                        ToLong: begin
                            let res <- floatToLongServer.response.get();
                            return pack(res);
                        end
                        ToWord: begin
                            let res <- floatToLongServer.response.get();
                            return signExtend(pack(res)[31:0]);
                        end
                        default: begin
                            let res <- selectMonadFloatServer(op).response.get();
                            return flushFloatDenorm(tpl_1(res), fd);
                        end
                    endcase
                end
                MonadDouble: begin
                    case (op)
                        ToFloat: begin
                            let res <- doubleToFloatServer.response.get();
                            return flushFloatDenorm(tpl_1(res), fd);
                        end
                        ToWord: begin
                            let res <- doubleToLongServer.response.get();
                            return signExtend(pack(res)[31:0]);
                        end
                        ToLong: begin
                            let res <- doubleToLongServer.response.get();
                            return pack(res);
                        end
                        default: begin
                            let res <- selectMonadDoubleServer(op).response.get();
                            return flushDoubleDenorm(tpl_1(res), fd);
                        end
                    endcase
                end
                MonadPairedSingle: begin
                    let res <- selectMonadPairedSingleServer(op).response.get();
                    return flushPairedSingleDenorm(tpl_1(res), fd);
                end
                DiadFloat: begin
                    let res <- selectDiadFloatServer(op).response.get();
                    return flushFloatDenorm(tpl_1(res), fd);
                end
                DiadDouble: begin
                    let res <- selectDiadDoubleServer(op).response.get();
                    return flushDoubleDenorm(tpl_1(res), fd);
                end
                DiadPairedSingle: begin
                    let res <- selectDiadPairedSingleServer(op).response.get();
                    return flushPairedSingleDenorm(tpl_1(res), fd);
                end
                CompareFloat: begin
                    let res <- compareServers.float.response.get();
                    return res;
                end
                CompareDouble: begin
                    let res <- compareServers.double.response.get();
                    return res;
                end
                ComparePairedSingle: begin
                    let res <- compareServers.pairedSingle.response.get();
                    return res;
                end
            endcase
        endactionvalue
    endfunction

    FIFO#(ExecuteToken) tokens <- mkSizedFIFO(35);

    interface Put request;
        method Action put(ExecuteRequest req);
            let src = getExecuteSource(req);
            tokens.enq(ExecuteToken { 
                op: req.op, 
                argType: getArgType(req.args), 
                source: src, 
                flushToZero: req.flushToZero
            });
            if (shouldDispatch(src))
                dispatchExecuteRequest(req);
        endmethod
    endinterface
    
    interface Get response;
        method ActionValue#(MIPSReg) get();
            let tok <- popFIFO(tokens);
            let op = tok.op;
            let argType = tok.argType;
            let fd = tok.flushToZero;
            case (tok.source) matches
                tagged Value .val: begin
                    return val;
                end
                tagged ValueLow {.req, .val}: begin
                    let res <- retrieveExecuteResponse(op, argType, fd);
                    // extracting the bits is a bit non-bluespec
                    return { res[63:32], val };
                end
                tagged ValueHigh {.req, .val}: begin
                    let res <- retrieveExecuteResponse(op, argType, fd);
                    return { val, res[31:0] };
                end
                tagged Execute .req: begin
                    let res <- retrieveExecuteResponse(op, argType, fd);
                    return res;
                end
            endcase
        endmethod
    endinterface

endmodule

function Bool isQNaN(FloatingPoint#(e, m) fp);
    return ((&fp.exp == 1) && (|fp.sfd == 1) && (msb(fp.sfd) == 0));
endfunction

function ExecuteArgType getArgType(ExecuteArgs args);
    case (args) matches
        tagged MonadWord .*: return MonadWord;
        tagged MonadLong .*: return MonadLong;
        tagged MonadFloat .*: return MonadFloat;
        tagged MonadDouble .*: return MonadDouble;
        tagged MonadPairedSingle .*: return MonadPairedSingle;
        tagged DiadFloat .*: return DiadFloat;
        tagged DiadDouble .*: return DiadDouble;
        tagged DiadPairedSingle .*: return DiadPairedSingle;
        tagged Compare .compArgs:
            case (compArgs.fmt) matches
                S: return CompareFloat;
                D: return CompareDouble;
                PS: return ComparePairedSingle;
                default: return CompareFloat;
            endcase
    endcase
endfunction

function MIPSReg flushFloatDenorm(Float fp, Bool fd);
    if (fd && isSubNormal(fp)) begin//bluespec wrongly counts zero as subnormal
        Float z = zero(fp.sign);
        return zeroExtend(pack(z));
    end
    else
        return zeroExtend(pack(fp));
endfunction

function MIPSReg flushDoubleDenorm(Double fp, Bool fd);
    if (fd && isSubNormal(fp)) begin
        Double z = zero(fp.sign);
        return pack(z);
    end
    else
        return pack(fp);
endfunction

function Float flushSingle(Float fp);
    if (isSubNormal(fp))
        return zero(fp.sign);
    else
        return fp;
endfunction

function MIPSReg flushPairedSingleDenorm(PairedSingle ps, Bool fd);
    if (fd) 
        return pack(tuple2(flushSingle(tpl_1(ps)), flushSingle(tpl_2(ps))));
    else
        return pack(ps);
endfunction
