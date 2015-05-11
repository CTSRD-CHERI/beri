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
    UInt#(TLog#(nb_master)) src_id;
    Bool last;
} ReqT#(numeric type nb_master, numeric type width) deriving (FShow, Bits);

instance Routable#(ReqT#(n,w), w);
    function UInt#(w) getRoutingField (ReqT#(n,w) req) = req.addr;
    function Bool getLastField (ReqT#(n,w) req) = req.last;
endinstance

typedef struct {
    UInt#(TLog#(nb_master)) src_id;
    UInt#(width) data;
    UInt#(width) slave_id;
    Bool last;
} RspT#(numeric type nb_master, numeric type width) deriving (FShow, Bits);

instance Routable#(RspT#(n,w), TLog#(n));
    function UInt#(TLog#(n)) getRoutingField (RspT#(n,w) rsp) = rsp.src_id;
    function Bool getLastField (RspT#(n,w) rsp) = rsp.last;
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

    Vector#(1, PuppetMaster#(ReqT#(1,8), RspT#(1,8))) puppet_masters <- replicateM(mkPuppetMaster);
    Vector#(1, Master#(ReqT#(1,8), RspT#(1,8))) masters = map(fromPuppetMaster, puppet_masters);

    Vector#(1, PuppetSlave#(ReqT#(1,8), RspT#(1,8))) puppet_slaves <- replicateM(mkPuppetSlave);
    Vector#(1, Slave#(ReqT#(1,8), RspT#(1,8))) slaves = map (fromPuppetSlave, puppet_slaves);

    mkBus( masters, constFn(tagged Valid 0),
           slaves, constFn(tagged Valid 0));

    method String testName = "Bus 1 master - 1 slave";

    method Stmt runTest = par
    count <= 0;
    seq
        action
            ReqT#(1,8) req = ReqT{addr: 42, data: 8'hbb, src_id: 0, last: True};
            puppet_masters[0].request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            RspT#(1,8) rsp <- puppet_masters[0].response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
    endseq
    seq
        action
            ReqT#(1,8) req <- puppet_slaves[0].request.get;
            $display("<%0t> - slave receive ", $time, fshow(req));
        endaction
        action
            RspT#(1,8) rsp = RspT{src_id: 0, data: 8'hbb, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave send ", $time, fshow(rsp));
        endaction
    endseq
    endpar;

endmodule

module mkTest1 (Test);

    Reg#(UInt#(8))  count       <- mkCounter;

    Vector#(2, PuppetMaster#(ReqT#(2,8), RspT#(2,8))) puppet_masters <- replicateM(mkPuppetMaster);
    Vector#(2, Master#(ReqT#(2,8), RspT#(2,8))) masters = map(fromPuppetMaster, puppet_masters);

    Vector#(1, PuppetSlave#(ReqT#(2,8), RspT#(2,8))) puppet_slaves <- replicateM(mkPuppetSlave);
    Vector#(1, Slave#(ReqT#(2,8), RspT#(2,8))) slaves = map (fromPuppetSlave, puppet_slaves);
    FIFOF#(UInt#(TLog#(2))) pending_master <- mkFIFOF1;

    mkBus( masters, constFn(tagged Valid 0),
           slaves, routeFromField);

    method String testName = "Bus 2 masters - 1 slave";

    method Stmt runTest = par
    count <= 0;
    seq
        action
            ReqT#(2,8) req = ReqT{addr: 42, data: 8'hbb, src_id: 0, last: True};
            puppet_masters[0].request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            RspT#(2,8) rsp <- puppet_masters[0].response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
    endseq
    seq
        action
            ReqT#(2,8) req = ReqT{addr: 84, data: 8'hdd, src_id: 1, last: True};
            puppet_masters[1].request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            RspT#(2,8) rsp <- puppet_masters[1].response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
    endseq
    seq
        action
            ReqT#(2,8) req <- puppet_slaves[0].request.get;
            pending_master.enq(req.src_id);
            $display("<%0t> - slave receive ", $time, fshow(req));
        endaction
        action
            pending_master.deq;
            RspT#(2,8) rsp = RspT{src_id: pending_master.first, data: 8'h00, slave_id: 8'h0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave send ", $time, fshow(rsp));
        endaction
        action
            ReqT#(2,8) req <- puppet_slaves[0].request.get;
            pending_master.enq(req.src_id);
            $display("<%0t> - slave receive ", $time, fshow(req));
        endaction
        action
            pending_master.deq;
            RspT#(2,8) rsp = RspT{src_id: pending_master.first, data: 8'h00, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave send ", $time, fshow(rsp));
        endaction
    endseq
    endpar;

endmodule

module mkTestBus (Empty);

    Test test0 <- mkTest0;
    Test test1 <- mkTest1;

    runTests(list(
        test0,
        test1
        ));

endmodule
