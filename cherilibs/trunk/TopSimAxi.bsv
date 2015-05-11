/*-
* Copyright (c) 2014 Colin Rothwell
* Copyright (c) 2014 Alexandre Joannou
* Copyright (c) 2015 Paul J. Fox
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

    CheriRdSlaveXActor pismMemoryRdXActor <- mkAxiRdSlave(True, matchMemAddr);
    mkConnection(topAxi.read_master, pismMemoryRdXActor.fabric.bus);
    mkConnection(pismMemory.read, pismMemoryRdXActor.tlm);

    CheriWrSlaveXActor pismMemoryWrXActor <- mkAxiWrSlave(True, matchMemAddr);
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

    `ifdef RMA
	// These aren't connected yet, but need to be there to avoid errors related to the lower-level interfaces
        // not being connected
        AvalonStreamSourceIfc#(Bit#(76)) source <- mkPut2AvalonStreamSource;
        AvalonStreamSinkIfc#(Bit#(76)) sink <- mkAvalonStreamSink2Get;
        
        mkConnectionStreamPhysical(topAxi.networkRx, sink.physical);
        mkConnectionStreamPhysical(source.physical, topAxi.networkTx);
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

function Tuple3#(CheriTLMAddr, Bit#(32), Bit#(5)) byteEnFromBurstSize(
        CheriTLMAddr inAddr, TLMBSize burstSize);

    Bit#(32) unshiftedBE = truncate(beForBurstSize(burstSize));
    CheriTLMAddr lineAddressMask = '1 << 5;
    CheriTLMAddr lineAddress = inAddr & lineAddressMask;
    Bit#(5) partOffset = truncate(inAddr & ~lineAddressMask);
    Bit#(32) shiftedBE = unshiftedBE << partOffset;
    // Force alignment of offset which will be used for write data and byte enables.
    `ifdef MEM64
      partOffset[2:0] = 0;
    `elsif MEM128
      partOffset[3:0] = 0;
    `else
      partOffset = 0;
    `endif
    return tuple3(lineAddress, shiftedBE, partOffset);
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
    FIFOF#(CheriTLMResp) completeResps <- mkSizedFIFOF(16);
    
    Reg#(UInt#(TLog#(MemTypes::MaxNoOfFlits)))   flit <- mkReg(0);

    function MightFail#(PismData) translateReq(CheriTLMReq tlmReq);
        if (tlmReq matches tagged Descriptor .tlmDesc) begin
            if (tlmDesc.command == UNKNOWN) begin
                let msg = "TLM Command fed to PISM is unknown.";
                return tagged Fail debug2("simaxi", $display(msg));
            end
            else if (tlmDesc.b_size == BITS512 ||
                     tlmDesc.b_size == BITS1024) begin
                let msg = "Attempting to read more than a line from PISM.";
                return tagged Fail debug2("simaxi", $display(msg));
            end
            else begin
                match {.calcAddr, .calcBE, .byteShift} =
                    byteEnFromBurstSize(tlmDesc.addr, tlmDesc.b_size);
                Bit#(32) byteEnable = (case (tlmDesc.byte_enable) matches
                    tagged Specify .be: return zeroExtend(be)<<byteShift;
                    tagged Calculate:   return calcBE;
                endcase);
                let isWrite = (tlmDesc.command == WRITE);
                PismData ret = PismData {
                        addr: zeroExtend(calcAddr),
                        data: zeroExtend(tlmDesc.data),
                        byteenable: zeroExtend(byteEnable),
                        write: zeroExtend(pack(isWrite)),
                        pad1: ?
                    };
                ret.data = ret.data << {byteShift, 3'b0};
                return tagged Success ret;
            end
        end
        else begin // Not a descriptor
            let msg = "Can't burst read/write PISM";
            return tagged Fail debug2("simaxi", $display(msg));
        end
    endfunction

    rule translateReqAndPrepareResp;
        let req  = tlmRequests.first();
        debug2("simaxi", $display("Input request: ", fshow(req)));
        let resp = tlmResponseFromRequest(req);
        if (req matches tagged Descriptor .td) begin
          debug2("simaxi", $display("burst length:%x", td.b_length));
          let newTd = td;
          CheriPhyByteOffset space = 0;
          newTd.addr = td.addr + zeroExtend({pack(flit),space});
           // Stash shift amount for read response.
          `ifdef MEM64
            resp.data = zeroExtend(newTd.addr[4:3]);
          `elsif MEM128
            resp.data = zeroExtend({newTd.addr[4],1'b0});
          `else
            resp.data = 0;
          `endif
          req = tagged Descriptor newTd;
        end
        let fail = True;
        case (translateReq(req)) matches
            tagged Success .pr: begin
                if (pism_addr_valid(bus, pr)) begin
                    PismData prs = pr;
                    debug2("simaxi", $displayh(fshow(prs), prs.addr));
                    /*
                    Bit#(5) byteOffset = truncate(prs.addr);
                    prs.addr = prs.addr & signExtend(6'h20); // Force alignment for PISM.
                    // Calculate rotate amount for request or response data and stash it in data field.
                    Bit#(2) doubleWordOffset = truncateLSB(byteOffset);
                    
                    // Shift Data
                    Vector#(4, Bit#(64)) dataVec = unpack(prs.data);
                    Vector#(4, Bit#(64)) newDataVec = ?;
                    for (Integer i=0; i<4; i=i+1) newDataVec[doubleWordOffset+fromInteger(i)] = dataVec[i];
                    prs.data = pack(newDataVec);
                    // Shift ByteEnable
                    Vector#(4, Bit#(8)) beVec = unpack(prs.byteenable);
                    Vector#(4, Bit#(8)) newBeVec = ?;
                    for (Integer i=0; i<4; i=i+1) newBeVec[doubleWordOffset+fromInteger(i)] = beVec[i];
                    prs.byteenable = pack(newBeVec);*/
                    pismRequests.enq(prs);
                    //debug2("simaxi", $display("doubleWordOffset=%d ", doubleWordOffset, fshow(prs), prs.addr));
                    Bit#(3) burstSize = 0;
                    if (req matches tagged Descriptor .td)
                      burstSize = truncate(pack(td.b_length));
                    if (pack(flit) == burstSize) begin
                      debug2("simaxi", $display("last flit==%x burstSize==%x", flit, burstSize));
                      tlmRequests.deq();
                      flit <= 0;
                      resp.is_last = True;
                    end else begin
                      debug2("simaxi", $display("next flit==%x burstSize==%x", flit, burstSize));
                      flit <= flit + 1;
                      resp.is_last = False;
                    end
                    fail = False;
                end
                else begin
                    debug2("simaxi", $write("Invalid PISM Address for "));
                    debug2("simaxi", $displayh(fshow(bus), pr.addr));
                    fail = True;
                    tlmRequests.deq();
                end
            end
            tagged Fail .act: begin
                act();
                fail = True;
                tlmRequests.deq();
            end
            default: begin
              tlmRequests.deq();
            end
        endcase
        if (fail) begin
            debug2("simaxi", $display("Bad request: ", fshow(req)));
            resp.status = ERROR;
        end
        incompleteResps.enq(resp);
    endrule

    rule putReq (pismRequests.notEmpty());
        if (pism_request_ready(bus, pismRequests.first)) begin
            let pr <- popFIFOF(pismRequests);
            debug2("simaxi", $display("%t: Putting to PISM", $time, fshow(pr)));
            pism_request_put(bus, pr);
        end
    endrule

    rule completeErrorResp (incompleteResps.first.status == ERROR);
        let resp <- popFIFOF(incompleteResps);
        completeResps.enq(resp);
    endrule

    rule completeWriteResp (
            incompleteResps.first.status == SUCCESS &&
            incompleteResps.first.command == WRITE
        );

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
        Vector#(4, Bit#(64)) dataVec = unpack(pismResp.data);
        // Rotate the array so that the target words are at the bottom.
        Bit#(2) idx = unpack(truncate(resp.data));
        for (Integer i=0; i<4; i=i+1) dataVec[i] = dataVec[idx+fromInteger(i)];
        resp.data = truncate(pack(dataVec));
        debug2("simaxi", $display("%t: Completing PISM read response: Rotate amount = %x ", $time,
            idx, fshow(dataVec), fshow(pismResp)));
        debug2("simaxi", $display("%t: Completing PISM read response: ", $time,
            fshow(resp)));
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
        debug2("simaxi", $display("!!! ", msg, resp));
    endrule

    interface CheriTLMRecv read;
        interface Put rx = toPut(requestMerge.left);
        interface Get tx;
            method ActionValue#(CheriTLMResp) get
                    if (completeResps.first.command == READ);

                let resp <- popFIFOF(completeResps);
                debug2("simaxi", $display("%t: Returning complete PISM read resp: ",
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
                debug2("simaxi", $display("%t: Returning complete PISM write resp: ",
                    $time, fshow(resp)));
                return resp;
            endmethod
        endinterface
    endinterface

endmodule
