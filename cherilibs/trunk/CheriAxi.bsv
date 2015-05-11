/*-
* Copyright (c) 2014 Colin Rothwell
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
*
*/

import TLM3::*;
import Axi::*;
import MemTypes::*;
import DefaultValue::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import ClientServer::*;
import GetPut::*;
import Connectable::*;
import Debug::*;
import Assert::*;
import Vector::*;
import ReorderBuffer::*;

import MasterSlave::*;
import BeriUGBypassFIFOF::*;
import Interconnect::*;
import Library::*;

`include "CheriTLM.defines"
`include "TLM.defines"

typedef AxiRdSlaveXActorIFC#(`TLM_XTR_CHERI) CheriRdSlaveXActor;
typedef AxiWrSlaveXActorIFC#(`TLM_XTR_CHERI) CheriWrSlaveXActor;
typedef AxiRdMasterXActorIFC#(`TLM_XTR_CHERI) CheriRdMasterXActor;
typedef AxiWrMasterXActorIFC#(`TLM_XTR_CHERI) CheriWrMasterXActor;

typedef TLMAddr#(`TLM_PRM_CHERI) CheriTLMAddr;
typedef TLMRecvIFC#(`TLM_RR_CHERI) CheriTLMRecv;
typedef TLMSendIFC#(`TLM_RR_CHERI) CheriTLMSend;
typedef TLMReadWriteSendIFC#(`TLM_RR_CHERI) CheriTLMReadWriteSend;
typedef TLMReadWriteRecvIFC#(`TLM_RR_CHERI) CheriTLMReadWriteRecv;

typedef TLMRequest#(`TLM_PRM_CHERI) CheriTLMReq;
typedef TLMResponse#(`TLM_PRM_CHERI) CheriTLMResp;

typedef RequestDescriptor#(`TLM_PRM_CHERI) CheriRequestDescriptor;

typedef Master#(CheriTLMReq, CheriTLMResp) CheriInterconnectMaster;
typedef Slave#(CheriTLMReq, CheriTLMResp) CheriInterconnectSlave;

instance FShow#(TLMBEKind#(`TLM_PRM));
    function Fmt fshow(TLMBEKind#(`TLM_PRM) be);
        return $format("< TLM Byte Enable: ") + (case (be) matches
            tagged Specify .bep: $format("0x%X", bep);
            tagged Calculate: $format("Calculate");
        endcase) + $format(" >");
    endfunction
endinstance

function TLMResponse#(`TLM_PRM) tlmResponseFromRequestDescriptor(
        RequestDescriptor#(`TLM_PRM) req);
    return (TLMResponse {
        command: req.command,
        data: defaultValue(),
        status: SUCCESS,
        user: 0,
        prty: req.prty,
        transaction_id: req.transaction_id,
        is_last: True
    });
endfunction

function TLMResponse#(`TLM_PRM) tlmResponseFromRequest(
        TLMRequest#(`TLM_PRM) req);
    case (req) matches
        tagged Descriptor .desc:
            return tlmResponseFromRequestDescriptor(desc);
        tagged Data .data: begin
            TLMResponse#(`TLM_PRM) resp = defaultValue();
            resp.command = WRITE;
            resp.transaction_id = data.transaction_id;
            resp.is_last = True;
            return resp;
        end
    endcase
endfunction

function Bool tlmReqIsRead(TLMRequest#(`TLM_PRM) tlmReq);
    case (tlmReq) matches 
        tagged Descriptor .desc: 
            return desc.command == READ;
        default:
            return False;
    endcase
endfunction

function Bool tlmReqIsWrite(TLMRequest#(`TLM_PRM) tlmReq);
    case (tlmReq) matches
        tagged Descriptor .desc:
            return desc.command == WRITE;
        tagged Data .*:
            return True;
    endcase
endfunction

function TLMRequest#(`TLM_PRM) tlmReqWithTransactionId(
        TLMRequest#(`TLM_PRM) request, TLMId#(`TLM_PRM) id);
    case (request) matches
        tagged Descriptor .reqDesc: begin
            let rd = reqDesc;
            rd.transaction_id = id;
            return tagged Descriptor rd;
        end
        tagged Data .data: begin
            let d = data;
            d.transaction_id = id;
            return tagged Data d;
        end
    endcase
endfunction

function Maybe#(CheriTLMReq) memReqToTLM(CheriMemRequest memReq);
    Bool failed = False;
    CheriRequestDescriptor reqDesc = defaultValue();

    reqDesc.addr        = unpack(pack(memReq.addr));
    reqDesc.b_length    = 0;
    reqDesc.mark        = LAST;
    case (memReq.operation) matches
        tagged Read .r : begin
            reqDesc.command     = READ;
            reqDesc.b_size      = bpfToBurstSize(r.bytesPerFlit);
            reqDesc.byte_enable = tagged Specify pack('1);// should not be used
        end
        tagged Write .w : begin
            reqDesc.command     = WRITE;
            reqDesc.data        = w.data.data;
            reqDesc.byte_enable = tagged Specify pack(w.byteEnable);
            reqDesc.b_size      = BITS256;
        end
        default : begin
            //dynamicAssert(False, "only Read and Write Request are supported");
            failed = True;
        end
    endcase

    if (failed)
        return tagged Invalid;
    else
        return tagged Valid (tagged Descriptor reqDesc);
endfunction

Bit#(128) beFor8Bit    = 128'h1;
Bit#(128) beFor16Bit   = (beFor8Bit << 1) | beFor8Bit;
Bit#(128) beFor32Bit   = (beFor16Bit << 2) | beFor16Bit;
Bit#(128) beFor64Bit   = (beFor32Bit << 4) | beFor32Bit;
Bit#(128) beFor128Bit  = (beFor64Bit << 8) | beFor64Bit;
Bit#(128) beFor256Bit  = (beFor128Bit << 16) | beFor128Bit;
Bit#(128) beFor512Bit  = (beFor256Bit << 32) | beFor256Bit;
Bit#(128) beFor1024Bit = (beFor512Bit << 64) | beFor512Bit;

function Bit#(128) beForBurstSize(TLMBSize burstSize);
    return (case (burstSize)
        BITS8:    beFor8Bit;
        BITS16:   beFor16Bit;
        BITS32:   beFor32Bit;
        BITS64:   beFor64Bit;
        BITS128:  beFor128Bit;
        BITS256:  beFor256Bit;
        BITS512:  beFor512Bit;
        BITS1024: beFor1024Bit;
    endcase);
endfunction

function TLMBSize bpfToBurstSize(BytesPerFlit bpf);
    return (case (bpf)
        BYTE_1      : BITS8;
        BYTE_2      : BITS16;
        BYTE_4      : BITS32;
        BYTE_8      : BITS64;
        BYTE_16     : BITS128;
        BYTE_32     : BITS256;
        BYTE_64     : BITS512;
        BYTE_128    : BITS1024;
    endcase);
endfunction

function CheriMemResponse tlmToMemoryResponse(CheriTLMResp resp);
    Vector#(64, Bit#(4)) allAs = replicate(4'hA);
    CheriMemResponse memResp = defaultValue();

    case (resp.command)
        READ: begin
            let d = MemTypes::Data {
                `ifdef CAP
                cap: unpack(0), // cap bit not used at this level of the cache hierarchy
                `endif
                data:   (case (resp.status)
                            ERROR: return unpack(pack(allAs));
                            default: return unpack(pack(resp.data));
                        endcase)
            };
            memResp.operation = tagged Read {
                data: d,
                last: True
            };
        end
        WRITE: begin
            memResp.operation = tagged Write;
        end
    endcase

    return memResp;
endfunction

typedef enum {
    Read,
    Write
} RequestType deriving (Bits, Eq, FShow);

interface ReadWriteMaster#(type req, type resp);
    interface Master#(req, resp) read;
    interface Master#(req, resp) write;
endinterface



instance Reorderable#(CheriTLMResp, 256);
    function ReorderToken#(256) extractToken(CheriTLMResp element);
        return element.transaction_id;
    endfunction
endinstance

`ifndef VERIFY2
(* synthesize *)
`endif
module mkFourElementResponseBuffer(ReorderBuffer#(4, CheriTLMResp));
    ReorderBuffer#(4, CheriTLMResp) worker <- mkReorderBuffer;

    interface reserve = worker.reserve;
    interface complete = worker.complete;
    interface drain = worker.drain;
endmodule

module mkInternalMemoryToInterconnect
        #(Master#(CheriMemRequest, CheriMemResponse) internal)
        (Master#(`TLM_RR_CHERI));

    FIFOF#(CheriTLMReq) reqs <- mkBypassFIFOF();
    FIFOF#(CheriTLMResp) resps <- mkBypassFIFOF();

    rule fillRequestFIFOs;
        let internalReq <- internal.request.get();
        case (memReqToTLM(internalReq)) matches
            tagged Valid .tlmReq: begin
                debug2("tlm", $display("%t: Emitting request ", $time,
                    fshow(tlmReq)));
                reqs.enq(tlmReq);
            end
            tagged Invalid: begin
                $write("!!! Failing due to invalid request :");
                $display(fshow(internalReq));
                dynamicAssert(False, "Invalid Memory Request");
            end
        endcase
    endrule

    rule deqReadResp (resps.first.command == READ);
        let resp <- popFIFOF(resps);
        debug2("tlm", $display("%t: Passing read resp: ", $time,
            fshow(resp)));
        internal.response.put(tlmToMemoryResponse(resp));
    endrule

    rule deqWriteResp (resps.first.command == WRITE);
        let resp <- popFIFOF(resps);
        debug2("tlm", $display("%t: Passing write resp: ", $time, 
            fshow(resp)));
        internal.response.put(tlmToMemoryResponse(resp));
    endrule

    rule deqUnknownResp (resps.first.command == UNKNOWN);
        let resp <- popFIFOF(resps);
        debug2("tlm", $display("%t: !!! UNKNOWN RESP: ", $time, fshow(resp)));
        dynamicAssert(False, "Got unknown response...");
    endrule

    interface CheckedGet request = toCheckedGet(reqs);
    interface CheckedPut response = toCheckedPut(resps);
    
endmodule

module mkReorderInternalMemoryToInterconnect
        #(Client#(CheriMemRequest, CheriMemResponse) internal)
        (Master#(`TLM_RR_CHERI));

    FIFOF#(CheriTLMReq) reqs <- mkBypassFIFOF();
    ReorderBuffer#(4, CheriTLMResp) respBuffer <- mkFourElementResponseBuffer();

    rule fillRequestFIFOs;
        let internalReq <- internal.request.get();
        case (memReqToTLM(internalReq)) matches
            tagged Valid .tlmReq: begin
                ReorderToken#(4) tok <- respBuffer.reserve.get();
                let rawTok = zeroExtend(pack(tok));
                reqs.enq(tlmReqWithTransactionId(tlmReq, rawTok));
            end
            tagged Invalid: begin
                $write("!!! Failing due to invalid request :");
                $display(fshow(internalReq));
                dynamicAssert(False, "Invalid Memory Request");
            end
        endcase
    endrule

    rule deqReadResp (respBuffer.drain.peek.command == READ);
        let resp <- respBuffer.drain.get();
        debug2("tlm", $display("%t: Passing read resp to L2: ", $time,
            fshow(resp)));
        internal.response.put(tlmToMemoryResponse(resp));
    endrule

    rule deqWriteResp (respBuffer.drain.peek.command == WRITE);
        // Throw writes on the floor :(
        let resp <- respBuffer.drain.get();
        debug2("tlm", $display("%t: Throwing write resp on floor: ", $time, 
            fshow(resp)));
    endrule

    rule deqUnknownResp (respBuffer.drain.peek.command == UNKNOWN);
        let resp <- respBuffer.drain.get();
        debug2("tlm", $display("%t: !!! UNKNOWN RESP: ", $time, fshow(resp)));
        dynamicAssert(False, "Got unknown response...");
    endrule

    interface CheckedGet request = toCheckedGet(reqs);
    interface CheckedPut response = respBuffer.complete;
    
endmodule

// This strictly preserves order. Technical we only need to preserve order on a
// per transaction-id basis, but as we don't ever do re-ordering this doesn't
// matter for the moment.
module mkSplitInterconnect
        #(Master#(`TLM_RR_CHERI) toSplit)
        (ReadWriteMaster#(`TLM_RR_CHERI));

    FIFOF#(RequestType) responseSources <- mkUGSizedFIFOF(2);

    function splitOn(typ, pred);
        function notEmpty();
            return toSplit.request.canGet() && pred(toSplit.request.peek);
        endfunction

        function notFull();
            return responseSources.notFull() && responseSources.first == typ;
        endfunction

        return (interface Master;
            interface CheckedGet request;
                method Bool canGet = notEmpty;
                method peek = toSplit.request.peek;

                method ActionValue#(CheriTLMReq) get() if (notEmpty());
                    responseSources.enq(typ);
                    let val <- toSplit.request.get();
                    return val;
                endmethod
            endinterface

            interface CheckedPut response;
                method Bool canPut = notFull;

                method Action put(CheriTLMResp resp) if (notFull());
                    responseSources.deq();
                    toSplit.response.put(resp);
                endmethod
            endinterface
        endinterface);
    endfunction

    interface read = splitOn(Read, tlmReqIsRead);
    interface write = splitOn(Write, tlmReqIsWrite);
endmodule


module mkSplitInternalMemoryToInterconnect
        #(Client#(CheriMemRequest, CheriMemResponse) internal)
        (ReadWriteMaster#(`TLM_RR_CHERI));

    FIFOF#(CheriTLMReq) readReqs <- mkBypassFIFOF();
    FIFOF#(CheriTLMReq) writeReqs <- mkBypassFIFOF();
    FIFO#(RequestType) responseSources <- mkSizedFIFO(2);
    FIFOF#(CheriTLMResp) readResps <- mkBypassFIFOF();

    rule fillRequestFIFOs;
        let internalReq <- internal.request.get();
        case (memReqToTLM(internalReq)) matches
            tagged Valid .tlmReq: case(tlmReq) matches
                tagged Descriptor .desc: case (desc.command)
                    READ: begin
                        readReqs.enq(tlmReq);
                        responseSources.enq(Read);
                    end
                    WRITE: begin
                        writeReqs.enq(tlmReq);
                        responseSources.enq(Write);
                    end
                endcase
                tagged Data .*: begin
                    writeReqs.enq(tlmReq);
                    responseSources.enq(Write);
                end
            endcase
            tagged Invalid: begin
                $write("!!! Failing due to invalid request :");
                $display(fshow(internalReq));
                dynamicAssert(False, "Invalid Memory Request");
            end
        endcase
    endrule

    rule deqReadResp (responseSources.first == Read);
        responseSources.deq();
        let resp <- popFIFOF(readResps);
        internal.response.put(tlmToMemoryResponse(resp));
    endrule

    interface Master read;
        interface CheckedGet request = toCheckedGet(readReqs);
        interface CheckedPut response = toCheckedPut(readResps);
    endinterface
    
    interface Master write;
        interface CheckedGet request = toCheckedGet(writeReqs);
        interface CheckedPut response;
            method Bool canPut();
                return responseSources.first == Write;
            endmethod

            method Action put(CheriTLMResp resp);
                debug2("tlm", $write("%t Discarding write response ", $time));
                debug2("tlm", $display(fshow(resp)));
                responseSources.deq();
            endmethod
        endinterface
    endinterface

endmodule

interface CheriAxiReadWriteRecv;
    interface AxiRdFabricSlave#(`TLM_PRM_CHERI) read;
    interface AxiWrFabricSlave#(`TLM_PRM_CHERI) write;
endinterface

module mkTLMReadWriteRecvToAxi
        #(CheriTLMReadWriteRecv tlm, 
          function Bool matchAddr(CheriTLMAddr addr))
        (CheriAxiReadWriteRecv);

    CheriRdSlaveXActor rdXActor <- mkAxiRdSlave(False, matchAddr);
    CheriWrSlaveXActor wrXActor <- mkAxiWrSlave(False, matchAddr);
    // These are named to help with debugging.
    let readConn <- mkConnection(rdXActor.tlm, tlm.read);
    let writeConn <- mkConnection(wrXActor.tlm, tlm.write);

    interface read = rdXActor.fabric;
    interface write = wrXActor.fabric;
endmodule

instance Routable#(TLMRequest#(a,b,c,d,e), b);
    function UInt#(b) getRoutingField(TLMRequest#(a,b,c,d,e) req);
        case (req) matches
            tagged Descriptor .desc:
                return unpack(desc.addr);
            tagged Data .*:
                return ?;
        endcase
    endfunction

    function Bool getLastField(TLMRequest#(a,b,c,d,e) req);
        case (req) matches
            tagged Descriptor .desc:
                return (desc.mark != NOT_LAST);
            tagged Data .data:
                return data.is_last;
        endcase
    endfunction
endinstance

instance Routable#(TLMResponse#(a,b,c,d,e), a);
    function UInt#(a) getRoutingField(TLMResponse#(a,b,c,d,e) resp);
        return unpack(resp.transaction_id);
    endfunction

    function Bool getLastField(TLMResponse#(a,b,c,d,e) resp);
        return resp.is_last;
    endfunction
endinstance

module mkTLMToInterconnectMaster#(TLMSendIFC#(`TLM_RR) tlm)(Master#(`TLM_RR))
        provisos (Bits#(req_t, req_t_bits), Bits#(resp_t, resp_t_bits));

    let out <- mkGetToCheckedGet(tlm.tx);
    let in <- mkPutToCheckedPut(tlm.rx);

    interface CheckedGet request = out;
    interface CheckedPut response = in;
endmodule

module mkTLMToInterconnectRdWrMaster
        #(TLMReadWriteSendIFC#(`TLM_RR) tlm)
        (ReadWriteMaster#(`TLM_RR))
        provisos (Bits#(req_t, req_t_bits), Bits#(resp_t, resp_t_bits));

    let readMod <- mkTLMToInterconnectMaster(tlm.read);
    let writeMod <- mkTLMToInterconnectMaster(tlm.write);

    interface Master read = readMod;
    interface Master write = writeMod;
endmodule

module mkTLMToInterconnectSlave#(TLMRecvIFC#(`TLM_RR) tlm)(Slave#(`TLM_RR))
        provisos (Bits#(req_t, req_t_bits), Bits#(resp_t, resp_t_bits));

    let in <- mkPutToCheckedPut(tlm.rx);
    let out <- mkGetToCheckedGet(tlm.tx);

    interface CheckedPut request = in;
    interface CheckedGet response = out;
endmodule

module mkSplitTLMToInterconnectSlave
        #(CheriTLMRecv tlmRead, CheriTLMRecv tlmWrite)
        (CheriInterconnectSlave);

    FIFOF#(CheriTLMReq) reqs <- mkBypassFIFOF();
    FIFOF#(RequestType) responseSources <- mkSizedFIFOF(8);

    // We need these to be unguarded, otherwise the single "get response" will
    // need a value in both to be able to fire.
    FIFOF#(CheriTLMResp) readResps <- mkBeriUGBypassFIFOF();
    FIFOF#(CheriTLMResp) writeResps <- mkBeriUGBypassFIFOF();

    function Bool responseReady();
        return (responseSources.first == Read && readResps.notEmpty()) ||
               (responseSources.first == Write && writeResps.notEmpty());
    endfunction

    function currentResponseFIFO();
        if (responseSources.first == Read)
            return readResps;
        else // responseSource.first == Write
            return writeResps;
    endfunction


    rule dispatchReadReq (tlmReqIsRead(reqs.first()));
        let req <- popFIFOF(reqs);
        debug2("tlm", $display("%t: Dispatching read: ", $time, fshow(req)));
        responseSources.enq(Read);
        tlmRead.rx.put(req);  
    endrule

    rule dispatchWriteReq (tlmReqIsWrite(reqs.first()));
        let req <- popFIFOF(reqs);
        debug2("tlm", $display("%t: Dispatching write: ", $time, fshow(req)));
        responseSources.enq(Write);
        tlmWrite.rx.put(req);
    endrule

    rule extractReadResp (readResps.notFull());
        let resp <- tlmRead.tx.get();
        readResps.enq(resp);
    endrule

    rule extractWriteResp (writeResps.notFull());
        let resp <- tlmWrite.tx.get();
        writeResps.enq(resp);
    endrule

    interface CheckedPut request = toCheckedPut(reqs);
    
    interface CheckedGet response;
        method Bool canGet = responseReady;

        method CheriTLMResp peek();
            return currentResponseFIFO().first();
        endmethod

        method ActionValue#(CheriTLMResp) get();
            debug2("tlm", $display("%t: Slave responding: ", $time,
                fshow(currentResponseFIFO().first())));
            let resp <- popFIFOF(currentResponseFIFO());
            responseSources.deq();
            return resp;
        endmethod
    endinterface

endmodule
