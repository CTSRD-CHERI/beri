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

import ClientServer::*;
import FIFO::*;
import GetPut::*;
import TLM3::*;
import Axi::*;
import DefaultValue::*;
import Assert::*;

import PutMerge::*;
import Library::*;
import CheriAxi::*;
import Peripheral::*;

`include "parameters.bsv"

typedef Bit#(23) BlueBusAddr;

interface TLMBlueBusPeripheral#(numeric type numIrqs);
    interface CheriTLMReadWriteRecv peripheral;
    (* always_ready, always_enabled *) // Doesn't depend on module state.
    method Bool matchAddress(CheriTLMAddr addr);
    (* always_ready, always_enabled *)
    method Bit#(numIrqs) getIrqs();
endinterface

// BlueBus uses byte addresses
// This only translates; doesn't check that the address is in the BlueBus area.
function BlueBusAddr tlmAddrToBlueBusAddr(CheriTLMAddr tlmAddr);
    return truncate(tlmAddr);
endfunction

// Base is base relative to bluebus.
// Width is byte address width.
// The address match function expects byte addresses aligned to 256 byte
// boundaries.
module mkBlueBusPeripheralToTLM
    #(Peripheral#(numIrqs) toWrap, Bit#(23) base, Bit#(23) width)
    (TLMBlueBusPeripheral#(numIrqs));

    // General purpose conversion functions.

    BlueBusAddr addressMask = ~('1 << width);

    function byteEnableToDWordIndex(byteEnable);
        // BlueBus wants 1/4 of a full line. This translates a byte enable to
        // part of an address.
        return (case (byteEnable)
            32'h000000ff: tagged Valid 2'd0;
            32'h0000ff00: tagged Valid 2'd1;
            32'h00ff0000: tagged Valid 2'd2;
            32'hff000000: tagged Valid 2'd3;
            default: tagged Invalid; //undefined if not double word
        endcase);
    endfunction

    function Maybe#(UInt#(8)) shiftAmountForRequest(CheriRequestDescriptor req);
        case (req.byte_enable) matches
            tagged Specify .be: begin
                case (byteEnableToDWordIndex(be)) matches
                    tagged Valid .dwi: return tagged Valid (zeroExtend(dwi) * 64);
                    tagged Invalid: return tagged Invalid;
                endcase
            end
            tagged Calculate: return tagged Valid (truncate(unpack(req.addr)) * 8);
        endcase
    endfunction

    function BlueBusAddr indexDWord(BlueBusAddr addr, Bit#(2) dWordIndex);
        addr[4:0] = {dWordIndex, 3'h0};
        return addr;
    endfunction

    function tlmDataToBlueBusData(tlmData, dWordIndex);
        // reverse bytes so we don't have to think in big endian
        return reverseBytes(case (dWordIndex) 
            2'd0: tlmData[63:0];
            2'd1: tlmData[127:64];
            2'd2: tlmData[191:128];
            2'd3: tlmData[255:192];
        endcase);
    endfunction

    // Technically a request descriptor
    function Maybe#(PerifReq) tlmReqToBlueBusReq(CheriRequestDescriptor req);
        let bbData = ?;
        BlueBusAddr bbAddr = tlmAddrToBlueBusAddr(req.addr);
        let fail = False;
        // Bluebus looks more like AXI, as it has a byte enable, so if it's a
        // calculate read, we should be fine.
        case (req.byte_enable) matches
            tagged Specify .be: begin
                case (byteEnableToDWordIndex(be)) matches
                    tagged Valid .dWordIndex: begin
                        bbAddr = indexDWord(bbAddr, dWordIndex);
                        bbData = tlmDataToBlueBusData(req.data, dWordIndex);
                    end
                    tagged Invalid: begin
                        fail = True;
                    end
                endcase
            end
            tagged Calculate: begin // This should only be reads
                if (req.addr[2:0] != 0) // Not 64-bit aligned
                    fail = True;
            end
        endcase
        // And address with mask to address relative to peripheral.
        if (fail)
            return tagged Invalid;
        else
            return tagged Valid (PerifReq {
                offset: bbAddr & addressMask,
                read: req.command == READ,
                data: bbData
            });
    endfunction

    // Actual state
    FIFO#(Tuple2#(CheriTLMResp, UInt#(8))) outstandingResponses <- mkFIFO();

    let nextRespCmd = tpl_1(outstandingResponses.first).command;

    function Action putRequest(CheriTLMReq tlmReq);
        action
            if (tlmReq matches tagged Descriptor .req) begin
                let fail = False;
                let perifReq = ?;
                let shiftAmount = ?;
                let resp = tlmResponseFromRequestDescriptor(req);
                case (tlmReqToBlueBusReq(req)) matches
                    tagged Valid .pReq:
                        perifReq = pReq;
                    tagged Invalid:
                        fail = True;
                endcase
                case (shiftAmountForRequest(req)) matches
                    tagged Valid .amount:
                        shiftAmount = amount;
                    tagged Invalid:
                        fail = True;
                endcase
                if (fail) begin
                    $write("!!! UNSUPPORTED TLM REQ FOR BLUEBUS: ");
                    $display(fshow(tlmReq));
                end
                else begin
                    outstandingResponses.enq(tuple2(resp, shiftAmount));
                    toWrap.regs.request.put(perifReq);
                end
            end
            else begin
                $display("!!! ATTEMPTING TO SEND BLUEBUS A BURST! UNSUPPORTED!");
                dynamicAssert(False, "Attempted to send Bluebus a burst.");
            end
        endaction
    endfunction

    PutMerge#(CheriTLMReq) putMerge <- mkPutMerge(toPut(putRequest));

    interface CheriTLMReadWriteRecv peripheral;
        interface CheriTLMRecv read;
            interface Put rx = putMerge.left;

            interface Get tx;
                method ActionValue#(CheriTLMResp) get() if (nextRespCmd == READ);
                    /*let respAndShiftAmount <- popFIFO(outstandingResponses);*/
                    match {.resp, .shiftAmount} <- popFIFO(outstandingResponses);
                    let respData <- toWrap.regs.response.get();
                    // Reverse Bytes to correct endianness.
                    respData = zeroExtend(pack(reverseBytes(respData)));
                    // Shift left to put result in correct lane.
                    resp.data = respData << shiftAmount;
                    return resp;
                endmethod
            endinterface
        endinterface

        interface CheriTLMRecv write;
            interface Put rx = putMerge.right;

            interface Get tx;
                method ActionValue#(CheriTLMResp) get() if (nextRespCmd == WRITE);
                    match {.resp, .shiftAmount} <- popFIFO(outstandingResponses);
                    resp.data = 'hBEDBEDBEDBED << shiftAmount;
                    return resp;
                endmethod
            endinterface
        endinterface
    endinterface

    method Bool matchAddress(CheriTLMAddr addr);
        return ((addr & `BLUE_BUS_MASK) == `BLUE_BUS_BASE) &&
               (tlmAddrToBlueBusAddr(addr) & ~addressMask) == base;
    endmethod

    method Bit#(numIrqs) getIrqs = toWrap.getIrqs;

endmodule
