/*-
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
 */

import MasterSlave::*;
import Interconnect::*;
import UnitTesting::*;
import Variadic::*;
import StmtFSM::*;
import FIFOF::*;
import Vector::*;

typedef struct {
    UInt#(width) addr;
    UInt#(width) data;
    UInt#(width) src_id;
    Bool last;
} ReqT#(numeric type width) deriving (FShow, Bits);

instance Routable#(ReqT#(w), w);
    function UInt#(w) getRoutingField (ReqT#(w) req) = req.addr;
    function Bool getLastField (ReqT#(w) req) = req.last;
endinstance

typedef struct {
    UInt#(width) src_id;
    UInt#(width) data;
    UInt#(width) slave_id;
    Bool last;
} RspT#(numeric type width) deriving (FShow, Bits);

instance Routable#(RspT#(w), w);
    function UInt#(w) getRoutingField (RspT#(w) rsp) = rsp.src_id;
    function Bool getLastField (RspT#(w) rsp) = rsp.last;
endinstance

// interfaces to control an actual Master from the test sequence

interface PuppetMaster#(type req_t, type rsp_t);
    interface CheckedPut#(req_t) request;
    interface CheckedGet#(rsp_t) response;
    interface CheckedGet#(req_t) request_;
    interface CheckedPut#(rsp_t) response_;
endinterface

function Master#(req_t, rsp_t) fromPuppetMaster(PuppetMaster#(req_t, rsp_t) pm) =
    interface Master#(req_t, rsp_t);
        interface request = pm.request_;
        interface response = pm.response_;
    endinterface;

module mkPuppetMaster(PuppetMaster#(req_t, rsp_t))
    provisos(Bits#(req_t, req_sz), Bits#(rsp_t, rsp_sz));
    FIFOF#(req_t) req_fifo <- mkFIFOF1;
    FIFOF#(rsp_t) rsp_fifo <- mkFIFOF1;
    interface request   = toCheckedPut(req_fifo);
    interface response  = toCheckedGet(rsp_fifo);
    interface request_  = toCheckedGet(req_fifo);
    interface response_ = toCheckedPut(rsp_fifo);
endmodule

interface PuppetSlave#(type req_t, type rsp_t);
    interface CheckedGet#(req_t) request;
    interface CheckedPut#(rsp_t) response;
    interface CheckedPut#(req_t) request_;
    interface CheckedGet#(rsp_t) response_;
endinterface

function Slave#(req_t, rsp_t) fromPuppetSlave(PuppetSlave#(req_t, rsp_t) pm) =
    interface Slave#(req_t, rsp_t);
        interface request = pm.request_;
        interface response = pm.response_;
    endinterface;

module mkPuppetSlave (PuppetSlave#(req_t, rsp_t))
    provisos(Bits#(req_t, req_sz), Bits#(rsp_t, rsp_sz));
    FIFOF#(req_t) req_fifo <- mkFIFOF1;
    FIFOF#(rsp_t) rsp_fifo <- mkFIFOF1;
    interface request   = toCheckedGet(req_fifo);
    interface response  = toCheckedPut(rsp_fifo);
    interface request_  = toCheckedPut(req_fifo);
    interface response_ = toCheckedGet(rsp_fifo);
endmodule

//////////////////
// Actual Tests //
//////////////////

module mkTest0 (Test);

    Reg#(UInt#(8))  count       <- mkCounter;

    Vector#(1, PuppetMaster#(ReqT#(8), RspT#(8))) puppet_masters <- replicateM(mkPuppetMaster);
    Vector#(1, Master#(ReqT#(8), RspT#(8))) masters = map(fromPuppetMaster, puppet_masters);
    MappingTable#(1,8) s2m_maptab;
    s2m_maptab[0] = Range{base:8'h00, span:8'hff};

    Vector#(1, PuppetSlave#(ReqT#(8), RspT#(8))) puppet_slaves <- replicateM(mkPuppetSlave);
    Vector#(1, Slave#(ReqT#(8), RspT#(8))) slaves = map (fromPuppetSlave, puppet_slaves);
    MappingTable#(1,8) m2s_maptab;
    m2s_maptab[0] = Range{base:8'h00, span:8'hff};

    mkCrossBar( masters, routeFromMap(s2m_maptab),
                slaves, routeFromMap(m2s_maptab));

    method String testName = "CrossBar 1 master - 1 slave";

    method Stmt runTest = par
    seq
        action
            count <= 0;
            let req = ReqT{addr: 42, data: 8'hbb, src_id: 0, last: True};
            puppet_masters[0].request.put(req);
            //$display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            let rsp = puppet_masters[0].response.get;
            //$display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
    endseq
    seq
        action
            let req = puppet_slaves[0].request.get;
            //$display("<%0t> - slave receive ", $time, fshow(req));
        endaction
        action
            let rsp = RspT{src_id: 0, data: 8'hbb, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            //$display("<%0t> - slave send ", $time, fshow(rsp));
        endaction
    endseq
    endpar;

endmodule

module mkTestCrossBar (Empty);

    Test test0 <- mkTest0;

    runTests(list(
        test0
        ));

endmodule
