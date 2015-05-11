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

import CheriAxi::*;
import MemTypes::*;
import Interconnect::*;
import MasterSlave::*;
import Variadic::*;
import UnitTesting::*;
import Debug::*;

import TLM3::*;
import Vector::*;
import ClientServer::*;
import GetPut::*;
import StmtFSM::*;
import DefaultValue::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

`include "CheriTLM.defines"

instance DefaultValue#(MemoryRequest#(word_address_width, data_width_bytes));
    function MemoryRequest#(word_address_width, data_width_bytes) defaultValue();
        return MemoryRequest {
            op: Read,
            addr: 0,
            data: 0,
            byteenable: '1,
            cached: False,
            cacheOp: CacheOperation { inst: Nop, cache: None }
        };
    endfunction
endinstance


module mkFakeRequester(Client#(MemoryRequest#(35, 32), MemoryResponse#(256)));
    Vector#(4, MemoryRequest#(35, 32)) reqs = replicate(defaultValue());
    reqs[1].op = Write;
    reqs[1].addr = 1;
    reqs[2].op = Write;
    reqs[2].addr = 2;
    reqs[3].op = Read;
    reqs[3].addr = 3;

    Reg#(UInt#(3)) toRequest <- mkReg(0);

    interface Get request;
        method ActionValue#(MemoryRequest#(35, 32)) get() if (toRequest < 4);
            toRequest <= toRequest + 1;
            debug($display("%t: Making request ", $time, toRequest));
            return reqs[toRequest]; // Uses old value: this is hardware.
        endmethod
    endinterface

    interface Put response;
        method Action put(MemoryResponse#(256) resp);
            debug($display("%t: Got response: ", $time, fshow(resp)));
        endmethod
    endinterface
endmodule

module mkReqTest(Test);

    let requester <- mkFakeRequester();
    let dut <- mkInternalMemoryToInterconnect(requester);

    function descWithCmdAndAddr(cmd, addr, req);
        case (req) matches
            tagged Descriptor .desc:
                return (desc.command == cmd && desc.addr == addr);
            default:
                return False;
        endcase

    endfunction

    let firstReqCorrect  = descWithCmdAndAddr(READ, 0);
    let secondReqCorrect = descWithCmdAndAddr(WRITE, 32);
    let thirdReqCorrect  = descWithCmdAndAddr(WRITE, 64);
    let fourthReqCorrect = descWithCmdAndAddr(READ, 96);

    let req = dut.request;
    let resp = dut.response;

    CheriTLMResp defReadResp = defaultValue();
    CheriTLMResp defWriteResp = defaultValue();
    defWriteResp.command = WRITE;

    method String testName = "Test Internal Memory to Interconnect";

    method Stmt runTest = seq
        debug($display("%t: Awaiting 1st req", $time));
        await(req.notEmpty());
        debug($display("%t: First 1st req ready", $time));
        testAssert(firstReqCorrect(req.first()));
        req.deq();
        resp.enq(defReadResp);

        debug($display("%t: Awaiting 2nd req", $time));
        await(req.notEmpty());
        debug($display("%t: 2nd req ready", $time));
        testAssert(secondReqCorrect(req.first()));
        req.deq();
        resp.enq(defWriteResp);

        debug($display("%t: Awaiting 3rd req", $time));
        await(req.notEmpty());
        debug($display("%t: 3rd req ready", $time));
        testAssert(thirdReqCorrect(req.first()));
        req.deq();
        resp.enq(defWriteResp);

        debug($display("%t: Awaiting 4th req", $time));
        await(req.notEmpty());
        debug($display("%t: 4th req ready", $time));
        testAssert(fourthReqCorrect(req.first()));
        req.deq();
        resp.enq(defReadResp);
    endseq;

endmodule

module mkTestSplitInterconnect(Test);
    let internalRequester <- mkFakeRequester();
    let tlmRequester <- mkInternalMemoryToInterconnect(internalRequester);
    let dut <- mkSplitInterconnect(tlmRequester);

    CheriTLMResp firstResp = defaultValue();
    firstResp.data = 1;

    CheriTLMResp secondResp = defaultValue();
    secondResp.command = WRITE;
    secondResp.data = 2;

    CheriTLMResp thirdResp = defaultValue();
    thirdResp.command = WRITE;
    thirdResp.data = 3;

    CheriTLMResp fourthResp = defaultValue();
    fourthResp.data = 4;

    method String testName = "Test Split Request into Read and Write";

    // No asserts here. The failure mode is essentially just that the
    // interconnect jams.
    method Stmt runTest = par
        seq
            dut.read.request.deq();
            par
                dut.read.response.enq(firstResp);
                debug($display("%t: Enqueued first resp", $time));
            endpar
            dut.read.request.deq();
            par
                dut.read.response.enq(fourthResp);
                debug($display("%t: Enqueued fourth resp", $time));
            endpar
        endseq

        seq
            dut.write.request.deq();
            par
                dut.write.response.enq(secondResp);
                debug($display("%t: Enqueued second resp", $time));
            endpar
            dut.write.request.deq();
            par
                dut.write.response.enq(thirdResp);
                debug($display("%t: Enqueued third resp", $time));
            endpar
        endseq
    endpar;
endmodule

module mkTestSplitTLMToInterconnectSlave(Test);

    function fifosToTLMRecv(reqFifo, respFifo) =
        (interface TLMRecvIFC;
            interface Put rx = toPut(reqFifo);
            interface Get tx = toGet(respFifo);
        endinterface);

    FIFO#(CheriTLMReq) rdReqFifo <- mkBypassFIFO();
    FIFO#(CheriTLMResp) rdRespFifo <- mkBypassFIFO();
    TLMRecvIFC#(`TLM_RR_CHERI) rdRecv = fifosToTLMRecv(rdReqFifo, rdRespFifo);

    FIFO#(CheriTLMReq) wrReqFifo <- mkBypassFIFO();
    FIFO#(CheriTLMResp) wrRespFifo <- mkBypassFIFO();
    TLMRecvIFC#(`TLM_RR_CHERI) wrRecv = fifosToTLMRecv(wrReqFifo, wrRespFifo);

    let dut <- mkSplitTLMToInterconnectSlave(rdRecv, wrRecv);

    CheriRequestDescriptor readReqDesc = defaultValue();
    CheriTLMReq readReq = tagged Descriptor readReqDesc;

    CheriRequestDescriptor writeReqDesc = defaultValue();
    writeReqDesc.command = WRITE;
    CheriTLMReq writeReq = tagged Descriptor writeReqDesc;


    CheriTLMResp firstResp = defaultValue();
    firstResp.data = 1;

    CheriTLMResp secondResp = defaultValue();
    secondResp.command = WRITE;
    secondResp.data = 2;

    CheriTLMResp thirdResp = defaultValue();
    thirdResp.command = WRITE;
    thirdResp.data = 3;

    CheriTLMResp fourthResp = defaultValue();
    fourthResp.data = 4;

    method String testName = "Test Split TLMRecv to one Interconnect Slave";

    method Stmt runTest = par
        seq
            dut.request.enq(readReq);
            dut.request.enq(writeReq);
            dut.request.enq(writeReq);
            dut.request.enq(readReq);
        endseq

        seq
            rdReqFifo.deq();
            rdRespFifo.enq(firstResp);
            rdReqFifo.deq();
            rdRespFifo.enq(fourthResp);
        endseq

        seq
            wrReqFifo.deq();
            wrRespFifo.enq(secondResp);
            wrReqFifo.deq();
            wrRespFifo.enq(thirdResp);
        endseq

        seq
            debug($display("First response: ", fshow(dut.response.first)));
            /*testAssert(dut.response.first.data == 1);*/
            dut.response.deq();
            debug($display("Second response: ", fshow(dut.response.first)));
            /*testAssert(dut.response.first.data == 1);*/
            dut.response.deq();
            debug($display("Third response: ", fshow(dut.response.first)));
            /*testAssert(dut.response.first.data == 3);*/
            dut.response.deq();
            debug($display("Fourth response: ", fshow(dut.response.first)));
            /*testAssert(dut.response.first.data == 4);*/
            dut.response.deq();
        endseq
    endpar;
endmodule

module mkTestInternalMemoryToInterconnect(Empty);
    let reqTest <- mkReqTest();
    let splitMasterTest <- mkTestSplitInterconnect();
    let splitSlaveTest <- mkTestSplitTLMToInterconnectSlave();

    runTests(list(reqTest, splitMasterTest, splitSlaveTest));
endmodule
