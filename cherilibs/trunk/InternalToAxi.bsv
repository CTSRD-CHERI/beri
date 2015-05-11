/*-
* Copyright (c) 2014, 2015 Alexandre Joannou
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

import MasterSlave::*;
import Interconnect::*;
import MemTypes::*;
import FIFOF::*;
import SpecialFIFOs::*;
import DefaultValue::*;
import Axi::*;
import Debug::*;
import Assert::*;

`include "CheriTLM.defines"

interface InternalToAxi;
    interface Slave#(CheriMemRequest, CheriMemResponse) slave;
    interface AxiRdMaster#(`TLM_PRM_CHERI) read_master;
    interface AxiWrMaster#(`TLM_PRM_CHERI) write_master;
endinterface

interface InternalToAxiRead;
    interface Slave#(CheriMemRequest, CheriMemResponse) slave;
    interface AxiRdMaster#(`TLM_PRM_CHERI) master;
endinterface

interface InternalToAxiWrite;
    interface Slave#(CheriMemRequest, CheriMemResponse) slave;
    interface AxiWrMaster#(`TLM_PRM_CHERI) master;
endinterface

typedef AxiAddrCmd#(`TLM_PRM_CHERI) CheriAxiAddrCmd;
typedef AxiRdResp#(`TLM_PRM_CHERI)  CheriAxiRdResp;
typedef AxiWrData#(`TLM_PRM_CHERI)  CheriAxiWrData;
typedef AxiWrResp#(`TLM_PRM_CHERI)  CheriAxiWrResp;

typedef enum {READ, WRITE} TransactionT deriving (Bits, Eq, FShow);

(* synthesize *)
module mkInternalToAxi (InternalToAxi);

    InternalToAxiRead  convert_r  <- mkInternalToAxiRead();
    InternalToAxiWrite convert_w  <- mkInternalToAxiWrite();

    Reg#(Bool)         read_rsp_prio <- mkReg(False);
    Reg#(TransactionT) last_rsp      <- mkReg(WRITE);

    Wire#(CheriMemResponse) w_read_rsp  <- mkDWire(?);
    Wire#(CheriMemResponse) w_write_rsp <- mkDWire(?);
    Wire#(CheriMemResponse) w_response  <- mkWire();

    PulseWire               w_read_rsp_last      <- mkPulseWire();
    PulseWire               w_get_read_response  <- mkPulseWire();
    PulseWire               w_get_write_response <- mkPulseWire();
    PulseWire               w_get_response       <- mkPulseWire();

    Bool canPutRequest =
    (
        convert_r.slave.request.canPut() &&
        convert_w.slave.request.canPut()
    );

    Bool canGetResponse =
    (
        (read_rsp_prio && convert_r.slave.response.canGet()) ||
        (!read_rsp_prio &&
        (convert_r.slave.response.canGet() || convert_w.slave.response.canGet()))
    );

    ///////////
    // Rules //
    ///////////

    rule display_debug;
        debug2("axi", $display("<time %0t, InternalToAxi>", $time,
            " read_rsp_prio=", fshow(read_rsp_prio),
            " last_rsp=", fshow(last_rsp),
            " canPutReq=", fshow(canPutRequest),
            " canGetRsp=", fshow(canGetResponse)));
    endrule

    rule is_read_rsp_last (getLastField(convert_r.slave.response.peek()));
        w_read_rsp_last.send();
    endrule

    rule prepare_read_response;
        w_read_rsp <= convert_r.slave.response.peek();
    endrule

    rule prepare_write_response;
        w_write_rsp <= convert_w.slave.response.peek();
    endrule

    rule prepare_response;
        CheriMemResponse end_response = ?;
        if (read_rsp_prio && convert_r.slave.response.canGet()) end_response = w_read_rsp;
        else if (!read_rsp_prio && last_rsp == WRITE && convert_r.slave.response.canGet()) end_response = w_read_rsp;
        else if (!read_rsp_prio && last_rsp == READ  && convert_w.slave.response.canGet()) end_response = w_write_rsp;
        else if (!read_rsp_prio && last_rsp == WRITE && convert_w.slave.response.canGet()) end_response = w_write_rsp;
        else if (!read_rsp_prio && last_rsp == READ  && convert_r.slave.response.canGet()) end_response = w_read_rsp;
        w_response <= end_response;
    endrule

    rule get_response (w_get_response);
        function Action do_read_rsp () = action
            w_get_read_response.send();
            read_rsp_prio <= !w_read_rsp_last;
            last_rsp <= READ;
        endaction;
        function Action do_write_rsp () = action
            w_get_write_response.send();
            last_rsp <= WRITE;
        endaction;
        if (read_rsp_prio) do_read_rsp();
        else if (last_rsp == WRITE && convert_r.slave.response.canGet())
            do_read_rsp();
        else if (last_rsp == READ  && convert_w.slave.response.canGet())
            do_write_rsp();
        else if (last_rsp == WRITE && convert_w.slave.response.canGet())
            do_write_rsp();
        else if (last_rsp == READ  && convert_r.slave.response.canGet())
            do_read_rsp();
        else dynamicAssert(False, "There must be a Read or a Write response");
    endrule

    rule get_read_response (w_get_read_response);
        CheriMemResponse rsp <- convert_r.slave.response.get();
        debug2("axi", $display("<time %0t, InternalToAxi>", $time," get read response - ", fshow(rsp)));
    endrule

    rule get_write_response (w_get_write_response);
        CheriMemResponse rsp <- convert_w.slave.response.get();
        dynamicAssert(getLastField(rsp), "Write responses should be single flit");
        debug2("axi", $display("<time %0t, InternalToAxi>", $time," get write response - ", fshow(rsp)));
    endrule

    ////////////////
    // Interfaces //
    ////////////////

    interface AxiRdMaster read_master  = convert_r.master;
    interface AxiWrMaster write_master = convert_w.master;

    interface Slave slave;
        interface CheckedPut request;
            method Bool canPut() = canPutRequest;
            method Action put(CheriMemRequest req) if (canPutRequest);
                debug2("axi", $display("<time %0t, InternalToAxi>", $time," send request - ", fshow(req)));
                case (req.operation) matches
                    tagged Read .rop: begin
                        convert_r.slave.request.put(req);
                        dynamicAssert(getLastField(req), "Read requests must be a single FLIT");
                    end
                    tagged Write .wop: begin
                        convert_w.slave.request.put(req);
                    end
                    default: dynamicAssert(False, "Every packet should be either a Read or a Write request");
                endcase
            endmethod
        endinterface
        interface CheckedGet response;
            method Bool canGet() = canGetResponse;
            method CheriMemResponse peek() if (canGetResponse) = w_response;
            method ActionValue#(CheriMemResponse) get();
                debug2("axi", $display("<time %0t, InternalToAxi>", $time," trying to get a response "));
                w_get_response.send();
                return w_response;
            endmethod
        endinterface
    endinterface

endmodule

(* synthesize *)
module mkInternalToAxiRead (InternalToAxiRead);

    FIFOF#(CheriMemRequest)        req <- mkFIFOF;
    FIFOF#(CheriMemResponse)      resp <- mkFIFOF;

    Wire#(CheriAxiAddrCmd)  ar_channel <- mkDWire(defaultValue);
    Wire#(Bool)               ar_ready <- mkDWire(False);

    Wire#(AxiId#(`TLM_PRM_CHERI))     r_id <- mkDWire(defaultValue);
    Wire#(AxiData#(`TLM_PRM_CHERI)) r_data <- mkDWire(defaultValue);
    Wire#(AxiResp)                  r_resp <- mkDWire(SLVERR);
    Wire#(Bool)                     r_last <- mkDWire(False);
    Wire#(Bool)                    r_valid <- mkDWire(False);

    CheriAxiAddrCmd ar_chan = defaultValue;
    case (req.first.operation) matches
        tagged Read .rop: begin
            ar_chan.id    = {pack(req.first.masterID),pack(req.first.transactionID)};
            ar_chan.addr  = pack(req.first.addr);
            ar_chan.len   = unpack(zeroExtend(pack(rop.noOfFlits))); // same encoding of the field
            ar_chan.size  = unpack(pack(rop.bytesPerFlit)); // same encoding of the field
            ar_chan.burst = INCR;
            //TODO why does that not build ? ar_chan.lock  <= NORMAL;
            ar_chan.lock  = unpack(0);
            ar_chan.cache = unpack(4'b0010); // Normal Non-cacheable Non-Bufferable, see chap. A4.4 of AXI doc
            ar_chan.prot  = unpack(3'b010);  // Unpriviledged Non-secure Data access, see chap. A4.7 of AXI doc
        end
        /*
        default: begin
            dynamicAssert(False, "only read requests are handled");
        end
        */
    endcase

    rule ar_channel_wire_up;
        ar_channel <= ar_chan;
    endrule

    rule consume_request (ar_ready);
        req.deq;
        debug2("axiRead", $display("<time %0t, InternalToAxiRead> consume req ", $time,
            fshow(req.first)));
    endrule

    rule receive_response (r_valid);
        CheriMemResponse internalResp;
        internalResp.masterID = unpack(truncateLSB(r_id));
        internalResp.transactionID = unpack(truncate(r_id)); // XXX see AXI doc chap. A5.3.5 and A5.3.6
        internalResp.error = r_resp == OKAY ? NoError : SlaveError;
        internalResp.operation = tagged Read {
            data: Data{
                `ifdef CAP
                cap: unpack(0),
                `endif
                data: r_data
            },
            last: r_last
        };
        resp.enq(internalResp);
        debug2("axiRead", $display("<time %0t, InternalToAxiRead> enq rsp ", $time,
            fshow(internalResp)));
    endrule

    ////////////////
    // Interfaces //
    ////////////////

    interface AxiRdMaster master;
        // Address Outputs
        method AxiId#(`TLM_PRM_CHERI)   arID    = ar_channel.id;
        method AxiAddr#(`TLM_PRM_CHERI) arADDR  = ar_channel.addr;
        method AxiLen                   arLEN   = ar_channel.len;
        method AxiSize                  arSIZE  = ar_channel.size;
        method AxiBurst                 arBURST = ar_channel.burst;
        method AxiLock                  arLOCK  = ar_channel.lock;
        method AxiCache                 arCACHE = ar_channel.cache;
        method AxiProt                  arPROT  = ar_channel.prot;
        // control flow output
        method Bool arVALID = req.notEmpty;
        // control flow input
        method Action arREADY(Bool value) =
            action ar_ready <= value; endaction;

        // Response Inputs
        method Action rID(AxiId#(`TLM_PRM_CHERI) value) =
            action r_id <= value; endaction;
        method Action rDATA(AxiData#(`TLM_PRM_CHERI) value) =
            action r_data <= value; endaction;
        method Action rRESP(AxiResp value) =
            action r_resp <= value; endaction;
        method Action rLAST(Bool value) =
            action r_last <= value; endaction;
        // control flow input
        method Action rVALID(Bool value) =
            action r_valid <= value; endaction;
        // control flow output
        method Bool rREADY = resp.notFull;
    endinterface

    interface Slave slave;
        interface request  = toCheckedPut(req);
        interface response = toCheckedGet(resp);
    endinterface

endmodule

(* synthesize *)
module mkInternalToAxiWrite (InternalToAxiWrite);

    FIFOF#(CheriMemResponse)       resp <- mkFIFOF;

    FIFOF#(CheriAxiAddrCmd)     aw_fifo <- mkFIFOF;
    Reg#(Bool)                  aw_done <- mkReg(False);
    FIFOF#(CheriAxiWrData)       w_fifo <- mkFIFOF;

    Wire#(CheriAxiAddrCmd)   aw_channel <- mkDWire(defaultValue);
    Wire#(Bool)                aw_ready <- mkDWire(False);

    Wire#(CheriAxiWrData)     w_channel <- mkDWire(defaultValue);
    Wire#(Bool)                 w_ready <- mkDWire(False);

    Wire#(AxiId#(`TLM_PRM_CHERI))  b_id <- mkDWire(defaultValue);
    Wire#(AxiResp)               b_resp <- mkDWire(SLVERR);
    Wire#(Bool)                 b_valid <- mkDWire(False);

    rule forward_aw;
        aw_channel  <= aw_fifo.first;
    endrule

    rule forward_w;
        w_channel   <= w_fifo.first;
    endrule

    rule consume_request_aw (aw_ready);
        debug2("axiWrite", $display("<time %0t, InternalToAxiWrite> consume aw req ", $time,
            fshow(aw_fifo.first().id)));
        aw_fifo.deq;
    endrule

    rule consume_request_w (w_ready);
        debug2("axiWrite", $display("<time %0t, InternalToAxiWrite> consume w req ", $time,
            fshow(w_fifo.first().id)));
        w_fifo.deq;
    endrule

    rule receive_response (b_valid);
        CheriMemResponse internalResp;
        internalResp.masterID = unpack(truncateLSB(b_id));
        internalResp.transactionID = unpack(truncate(b_id)); // XXX see AXI doc chap. A5.3.5 and A5.3.6
        internalResp.error = b_resp == OKAY ? NoError : SlaveError;
        internalResp.operation = tagged Write;
        resp.enq(internalResp);
        debug2("axiWrite", $display("<time %0t, InternalToAxiWrite> receive rsp ", $time,
            fshow(internalResp)));
    endrule

    ////////////////
    // Interfaces //
    ////////////////

    interface AxiWrMaster master;
        // Address Outputs
        method AxiId#(`TLM_PRM_CHERI)   awID    = aw_channel.id;
        method AxiAddr#(`TLM_PRM_CHERI) awADDR  = aw_channel.addr;
        method AxiLen                   awLEN   = aw_channel.len;
        method AxiSize                  awSIZE  = aw_channel.size;
        method AxiBurst                 awBURST = aw_channel.burst;
        method AxiLock                  awLOCK  = aw_channel.lock;
        method AxiCache                 awCACHE = aw_channel.cache;
        method AxiProt                  awPROT  = aw_channel.prot;
        // control flow output
        method Bool awVALID = aw_fifo.notEmpty;
        // control flow input
        method Action awREADY(Bool value) =
            action aw_ready <= value; endaction;

        // Data Outputs
        method AxiId#(`TLM_PRM_CHERI)     wID   = w_channel.id;
        method AxiData#(`TLM_PRM_CHERI)   wDATA = w_channel.data;
        method AxiByteEn#(`TLM_PRM_CHERI) wSTRB = w_channel.strb;
        method Bool                       wLAST = w_channel.last;
        // control flow output
        method Bool wVALID = w_fifo.notEmpty;
        // control flow input
        method Action wREADY(Bool value) =
            action w_ready <= value; endaction;

        // Response Inputs
        method Action bID(AxiId#(`TLM_PRM_CHERI) value) =
            action b_id <= value; endaction;
        method Action bRESP(AxiResp value) =
            action b_resp <= value; endaction;
        // control flow input
        method Action bVALID(Bool value) =
            action b_valid <= value; endaction;
        // control flow output
        method Bool bREADY = resp.notFull;
    endinterface

    interface Slave slave;
        interface CheckedPut request;
            method Bool canPut() = (w_fifo.notFull && (aw_done || aw_fifo.notFull));
            method Action put(CheriMemRequest req) if (w_fifo.notFull && (aw_done || aw_fifo.notFull));
                CheriAxiAddrCmd aw_chan = defaultValue;
                CheriAxiWrData  w_chan  = defaultValue;
                case (req.operation) matches
                    tagged Write .wop: begin
                        aw_chan.id    = {pack(req.masterID),pack(req.transactionID)};
                        aw_chan.addr  = pack(req.addr);
                        //TODO update Internal format ? aw_chan.len   <= wop.noOfFlits;
                        //TODO --- ? aw_chan.size  <= rop.bytesPerFlit; // same encoding of the field
                        aw_chan.burst = INCR;
                        //TODO Why does that not build ? aw_chan.lock  <= NORMAL;
                        aw_chan.lock  = unpack(0);
                        aw_chan.cache = unpack(4'b0010); // Normal Non-cacheable Non-Bufferable, see chap. A4.4 of AXI doc
                        aw_chan.prot  = unpack(3'b010);  // Unpriviledged Non-secure Data access, see chap. A4.7 of AXI doc

                        w_chan.id     = zeroExtend(pack(req.masterID));
                        w_chan.data   = wop.data.data;
                        w_chan.strb   = pack(wop.byteEnable);
                        w_chan.last   = wop.last;

                        w_fifo.enq(w_chan);
                        if (!aw_done) aw_fifo.enq(aw_chan);
                        aw_done <= !wop.last;
                    end
                    default: begin
                        dynamicAssert(False, "only write requests are handled");
                    end
                endcase
            endmethod
        endinterface
        interface response = toCheckedGet(resp);
    endinterface

endmodule
