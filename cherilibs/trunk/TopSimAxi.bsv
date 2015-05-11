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

import TopAxi::*;
import PISM::*;
import CheriAxi::*;
import PutMerge::*;
import Debug::*;

import Assert::*;
import FIFOF::*;
import SpecialFIFOs::*;
import GetPut::*;
import Connectable::*;
import DefaultValue::*;
import Library::*; //Nirav's library
import TLM3::*;
import Axi::*;
import AvalonStreaming::*;
import MemTypes::*;
import Vector::*;

(* synthesize *)
module mkTopSimAxi(Empty);
    TopAxi topAxi <- mkTopAxi();
    CheriTLMReadWriteRecv pismMemory <- mkPISMTLM(PISM_BUS_MEMORY);

    function pismAddrMatch(bus, addr);
        PismData req = defaultValue();
        req.addr = zeroExtend(addr);
        return pism_addr_valid(bus, req);
    endfunction

    let matchMemAddr = pismAddrMatch(PISM_BUS_MEMORY);

    CheriRdSlaveXActor pismMemoryRdXActor <- mkAxiRdSlave(False, matchMemAddr);
    mkConnection(topAxi.read_master, pismMemoryRdXActor.fabric.bus);
    mkConnection(pismMemory.read, pismMemoryRdXActor.tlm);

    CheriWrSlaveXActor pismMemoryWrXActor <- mkAxiWrSlave(False, matchMemAddr);
    mkConnection(topAxi.write_master, pismMemoryWrXActor.fabric.bus);
    mkConnection(pismMemory.write, pismMemoryWrXActor.tlm);

    Reg#(Bool) pismMemorySetup <- mkReg(False);

    rule setupPISMMemory (!pismMemorySetup);
        Bool pismInitSuccess <- pism_init(PISM_BUS_MEMORY);
        pismMemorySetup <= pismInitSuccess;
    endrule

    // Vector of registers used for initialising the debug units
    Vector#(CORE_COUNT, Reg#(Bool)) pismDebugSetup <- replicateM(mkReg(False));
    
    // Initialising a single or dual debug unit. Maximum of 2 are currently supported
    let internal_core_count = valueOf(CORE_COUNT);
    if (internal_core_count > 2)
        internal_core_count = 2;

    for (Integer i=0; i<internal_core_count; i=i+1) begin
        let debug_current = ?;
	if (i == 0)
            debug_current = DEBUG_STREAM_0;
        else if (i == 1)
            debug_current = DEBUG_STREAM_1;
 
        rule setupPISMDebug (!pismDebugSetup[i]);
            Bool debugInitSuccess <- debug_stream_init(debug_current);
            pismDebugSetup[i] <= debugInitSuccess;
        endrule
    end

    (* fire_when_enabled, no_implicit_conditions *)
    rule tickPISM;
        pism_cycle_tick(PISM_BUS_MEMORY);
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule putIrqs;
        topAxi.irq(pism_interrupt_get(PISM_BUS_MEMORY));
    endrule

    Vector#(CORE_COUNT, AvalonStreamSinkIfc#(Bit#(8))) getFromBusDebug <- replicateM(mkAvalonStreamSink2Get());
    Vector#(CORE_COUNT, AvalonStreamSourceIfc#(Bit#(8))) putToBusDebug <- replicateM(mkPut2AvalonStreamSource());

    // Wiring a single or dual debug unit
    for (Integer i=0; i<internal_core_count; i=i+1) begin
        mkConnectionStreamPhysical(
            topAxi.debug_stream_sources[i],
            getFromBusDebug[i].physical
        );
  
        mkConnectionStreamPhysical(
            putToBusDebug[i].physical,
            topAxi.debug_stream_sinks[i]
        );

        let debug_current = ?;
        if (i == 0)
            debug_current = DEBUG_STREAM_0;
        else if (i == 1)
            debug_current = DEBUG_STREAM_1;
 
        rule debugIn (debug_stream_source_ready(debug_current));
            Bit#(8) char <- debug_stream_source_get(debug_current);
            putToBusDebug[i].tx.put(char);
        endrule
  
        rule debugOut (debug_stream_sink_ready(debug_current));
            Bit#(8) char <- getFromBusDebug[i].rx.get();
            debug_stream_sink_put(debug_current, char);
        endrule
    end

    `ifdef MULTI
        // Dummy module used to keep Bluespec happy for a processor with more than 2 cores
        // If we decide to attach more debug modules to PISM or in hardware, we will need
        // to remove this code and change the loop for rules debugIn and debugOut to a max
        // value of CORE_COUNT
        for (Integer i=internal_core_count; i<valueof(CORE_COUNT); i=i+1) begin
            mkConnectionStreamPhysical(
                topAxi.debug_stream_sources[i],
                getFromBusDebug[i].physical
            );
  
            mkConnectionStreamPhysical(
                putToBusDebug[i].physical,
                topAxi.debug_stream_sinks[i]
            );

            let debug_current = ?;
            Bool block_debug = True;
            rule dummyPutToBusDebug (!block_debug);
                Bit#(8) char = ?;
                putToBusDebug[i].tx.put(char);
            endrule

            rule dummyGetFromBusDebug (!block_debug);
                Bit#(8) char <- getFromBusDebug[i].rx.get();
            endrule
        end
    `endif
endmodule

typedef enum {
    Read,
    Write
} RequestType deriving (Bits, Eq, FShow);

typedef enum {
    Error,
    PISM
} ResponseSource deriving (Bits, Eq, FShow);

function Tuple2#(CheriTLMAddr, Bit#(32)) byteEnFromBurstSize(
        CheriTLMAddr inAddr, TLMBSize burstSize);

    let unshiftedBE = truncate(beForBurstSize(burstSize));
    let lineAddressMask = '1 << 5;
    let lineAddress = inAddr & lineAddressMask;
    let partOffset = inAddr & ~lineAddressMask;
    let shiftedBE = unshiftedBE << partOffset;
    return tuple2(lineAddress, shiftedBE);
endfunction

typedef union tagged {
    success Success;
    Action Fail;
} MightFail#(type success);

// PISM doesn't have split read/write busses, but TLM does. This uses FIFOs to
// give a limited ability for both methods to be called in the same cycle, but
// obviously can't provide the full throughput.
module mkPISMTLM#(PismBus bus)(CheriTLMReadWriteRecv);

    FIFOF#(CheriTLMReq) tlmRequests <- mkBypassFIFOF();
    PutMerge#(CheriTLMReq) requestMerge <- mkPutMerge(toPut(tlmRequests));
    FIFOF#(PismData) pismRequests <- mkBypassFIFOF();

    // Data from PISM not attached to RESP
    FIFOF#(CheriTLMResp) incompleteResps <- mkBypassFIFOF();
    // Ready to return
    FIFOF#(CheriTLMResp) completeResps <- mkBypassFIFOF();

    function MightFail#(PismData) translateReq(CheriTLMReq tlmReq);
        if (tlmReq matches tagged Descriptor .tlmDesc) begin
            if (tlmDesc.command == UNKNOWN) begin
                let msg = "TLM Command fed to PISM is unknown.";
                return tagged Fail debug2("cTrace", $display(msg));
            end
            else if (tlmDesc.b_size == BITS512 ||
                     tlmDesc.b_size == BITS1024) begin
                let msg = "Attempting to read more than a line from PISM.";
                return tagged Fail debug2("cTrace", $display(msg));
            end
            else begin
                match {.calcAddr, .calcBE} =
                    byteEnFromBurstSize(tlmDesc.addr, tlmDesc.b_size);
                let byteEnable = (case (tlmDesc.byte_enable) matches
                    tagged Specify .be: be;
                    tagged Calculate: calcBE;
                endcase);
                let isWrite = (tlmDesc.command == WRITE);
                return tagged Success (PismData {
                    addr: zeroExtend(calcAddr),
                    data: tlmDesc.data,
                    byteenable: byteEnable,
                    write: zeroExtend(pack(isWrite)),
                    pad1: ?
                });
            end
        end
        else begin // Not a descriptor
            let msg = "Can't burst read/write PISM";
            return tagged Fail debug2("cTrace", $display(msg));
        end
    endfunction

    rule translateReqAndPrepareResp;
        let req <- popFIFOF(tlmRequests);
        let resp = tlmResponseFromRequest(req);
        let fail = False;
        case (translateReq(req)) matches
            tagged Success .pr: begin
                if (pism_addr_valid(bus, pr)) begin
                    pismRequests.enq(pr);
                end
                else begin
                    debug2("cTrace", $write("Invalid PISM Address for "));
                    debug2("cTrace", $displayh(fshow(bus), pr.addr));
                    fail = True;
                end
            end
            tagged Fail .act: begin
                act();
                fail = True;
            end
        endcase
        if (fail) begin
            debug2("cTrace", $display("Bad request: ", fshow(req)));
            resp.status = ERROR;
        end
        incompleteResps.enq(resp);
    endrule

    rule putReq (pismRequests.notEmpty());
        if (pism_request_ready(bus, pismRequests.first)) begin
            let pr <- popFIFOF(pismRequests);
            debug2("tlm", $display("%t: Putting ", $time, fshow(pr)));
            pism_request_put(bus, pr);
        end
    endrule

    rule completeErrorResp (incompleteResps.first.status == ERROR);
        let resp <- popFIFOF(incompleteResps);
        debug2("tlm", $display("%t: Completing PISM error response: ", $time,
            fshow(resp)));
        completeResps.enq(resp);
    endrule

    rule completeWriteResp (
            incompleteResps.first.status == SUCCESS &&
            incompleteResps.first.command == WRITE
        );

        debug2("tlm", $display("%t: Completing PISM write response.", $time));
        let resp <- popFIFOF(incompleteResps);
        completeResps.enq(resp);
    endrule

    rule completeReadResp (
            incompleteResps.first.status == SUCCESS &&
            incompleteResps.first.command == READ &&
            pism_response_ready(bus)
        );

        Bit#(512) pismBitResp <- pism_response_get(bus);
        PismData pismResp = unpack(pismBitResp);
        let resp <- popFIFOF(incompleteResps);
        debug2("tlm", $display("%t: Completing PISM read response: ", $time,
            fshow(resp)));
        resp.data = pismResp.data;
        completeResps.enq(resp);
    endrule

    rule completeUnknownResp (
            (incompleteResps.first.status == SUCCESS &&
             incompleteResps.first.command == UNKNOWN) ||
            (incompleteResps.first.status != SUCCESS &&
             incompleteResps.first.status != ERROR)
        );

        let msg = "Trying to return unknown response! ";
        dynamicAssert(False, msg);
        let resp <- popFIFOF(incompleteResps);
        debug2("cTrace", $display("!!! ", msg, resp));
    endrule

    interface CheriTLMRecv read;
        interface Put rx = toPut(requestMerge.left);
        interface Get tx;
            method ActionValue#(CheriTLMResp) get
                    if (completeResps.first.command == READ);

                let resp <- popFIFOF(completeResps);
                debug2("tlm", $display("%t: Returning complete PISM read resp: ",
                    $time, fshow(resp)));
                return resp;
            endmethod
        endinterface
    endinterface

    interface CheriTLMRecv write;
        interface Put rx = toPut(requestMerge.right);
        interface Get tx;
            method ActionValue#(CheriTLMResp) get
                    if (completeResps.first.command == WRITE);

                let resp <- popFIFOF(completeResps);
                debug2("tlm", $display("%t: Returning complete PISM write resp: ",
                    $time, fshow(resp)));
                return resp;
            endmethod
        endinterface
    endinterface

endmodule
