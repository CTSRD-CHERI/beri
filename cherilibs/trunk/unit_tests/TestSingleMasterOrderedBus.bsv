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
import Connectable::*;
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

    PuppetMaster#(ReqT#(40), RspT#(40)) puppet_master <- mkPuppetMaster;
    Master#(ReqT#(40), RspT#(40)) master = fromPuppetMaster(puppet_master);
    FIFOF#(ReqT#(40)) m_req_fifo <- mkFIFOF1;
    FIFOF#(RspT#(40)) m_rsp_fifo <- mkFIFOF1;

    mkConnection(toCheckedPut(m_req_fifo),getMasterReqIfc(master));
    mkConnection(toCheckedGet(m_rsp_fifo),getMasterRspIfc(master));
    Master#(ReqT#(40), RspT#(40)) connect_master = mkMaster(toCheckedGet(m_req_fifo), toCheckedPut(m_rsp_fifo));

    Vector#(2, PuppetSlave#(ReqT#(40), RspT#(40))) puppet_slaves <- replicateM(mkPuppetSlave);
    Vector#(2, Slave#(ReqT#(40), RspT#(40))) slaves = map (fromPuppetSlave, puppet_slaves);

    Vector#(2, FIFOF#(RspT#(40))) rsp_fifo <- replicateM (mkFIFOF1);
    Vector#(2, FIFOF#(ReqT#(40))) req_fifo <- replicateM (mkFIFOF1);
    Vector#(2, FIFOF#(ReqT#(40))) internal_fifo <- replicateM (mkFIFOF1);

    zipWithM(mkConnection,map(toCheckedPut,rsp_fifo),map(getSlaveRspIfc,slaves));
    zipWithM(mkConnection,map(toCheckedGet,req_fifo),map(getSlaveReqIfc,slaves));
    Vector#(2, Slave#(ReqT#(40), RspT#(40))) connect_slaves = zipWith(mkSlave,map(toCheckedPut, req_fifo),map(toCheckedGet, rsp_fifo));

    MappingTable#(2,40) m2s_maptab;
    m2s_maptab[0] = Range{base:40'h0, span:40'h10};
    m2s_maptab[1] = Range{base:40'h50, span:40'h10};

    mkSingleMasterOrderedBus(connect_master, connect_slaves, routeFromMap(m2s_maptab), 8);

    method String testName = "SingleMasterOrderedBus 1 master - 2 slaves";

    method Stmt runTest = par
    seq
        action
            count <= 0;
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h51, data: 40'h1, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h51, data: 40'h1, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            $display("<%0t> - master done ", $time);
        endaction
    endseq
    seq
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            $display("<%0t> - slave0 done ", $time);
        endaction
    endseq
    seq
        action
            let req <- puppet_slaves[1].request.get;
            internal_fifo[1].enq(req);
            $display("<%0t> - slave1 receive ", $time, fshow(req));
        endaction
        action
            internal_fifo[1].deq;
            let rsp = RspT{src_id: 0, data: 40'h1, slave_id: 1, last: True};
            puppet_slaves[1].response.put(rsp);
            $display("<%0t> - slave1 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[1].request.get;
            internal_fifo[1].enq(req);
            $display("<%0t> - slave1 receive ", $time, fshow(req));
        endaction
        action
            internal_fifo[1].deq;
            let rsp = RspT{src_id: 0, data: 40'h1, slave_id: 1, last: True};
            puppet_slaves[1].response.put(rsp);
            $display("<%0t> - slave1 send ", $time, fshow(rsp));
        endaction
        action
            $display("<%0t> - slave1 done ", $time);
        endaction
    endseq
    endpar;

endmodule

module mkTest1 (Test);

    Reg#(UInt#(8))  count       <- mkCounter;

    PuppetMaster#(ReqT#(40), RspT#(40)) puppet_master <- mkPuppetMaster;
    Master#(ReqT#(40), RspT#(40)) master = fromPuppetMaster(puppet_master);
    FIFOF#(ReqT#(40)) m_req_fifo <- mkFIFOF1;
    FIFOF#(RspT#(40)) m_rsp_fifo <- mkFIFOF1;

    mkConnection(toCheckedPut(m_req_fifo),getMasterReqIfc(master));
    mkConnection(toCheckedGet(m_rsp_fifo),getMasterRspIfc(master));
    Master#(ReqT#(40), RspT#(40)) connect_master = mkMaster(toCheckedGet(m_req_fifo), toCheckedPut(m_rsp_fifo));

    Vector#(2, PuppetSlave#(ReqT#(40), RspT#(40))) puppet_slaves <- replicateM(mkPuppetSlave);
    Vector#(2, Slave#(ReqT#(40), RspT#(40))) slaves = map (fromPuppetSlave, puppet_slaves);

    Vector#(2, FIFOF#(RspT#(40))) rsp_fifo <- replicateM (mkFIFOF1);
    Vector#(2, FIFOF#(ReqT#(40))) req_fifo <- replicateM (mkFIFOF1);
    Vector#(2, FIFOF#(ReqT#(40))) internal_fifo <- replicateM (mkFIFOF1);

    zipWithM(mkConnection,map(toCheckedPut,rsp_fifo),map(getSlaveRspIfc,slaves));
    zipWithM(mkConnection,map(toCheckedGet,req_fifo),map(getSlaveReqIfc,slaves));
    Vector#(2, Slave#(ReqT#(40), RspT#(40))) connect_slaves = zipWith(mkSlave,map(toCheckedPut, req_fifo),map(toCheckedGet, rsp_fifo));

    MappingTable#(2,40) m2s_maptab;
    m2s_maptab[0] = Range{base:40'h0, span:40'h10};
    m2s_maptab[1] = Range{base:40'h50, span:40'h10};

    mkSingleMasterOrderedBus(connect_master, connect_slaves, routeFromMap(m2s_maptab), 8);

    method String testName = "SingleMasterOrderedBus 1 master - 2 slaves saturate fifo";

    method Stmt runTest = par
    seq
        action
            count <= 0;
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h51, data: 40'h1, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 1 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h51, data: 40'h1, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 1 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h51, data: 40'h1, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 1 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h51, data: 40'h1, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 1 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h51, data: 40'h1, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 1 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            let req = ReqT{addr: 40'h1, data: 40'h0, src_id: 0, last: True};
            puppet_master.request.put(req);
            $display("<%0t> - master send to slave 0 ", $time, fshow(req));
        endaction
        action
            $display("<%0t> - master done sending", $time);
        endaction
    endseq
    seq
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            let rsp <- puppet_master.response.get;
            $display("<%0t> - master rcv ", $time, fshow(rsp));
        endaction
        action
            $display("<%0t> - master done receiving", $time);
        endaction
    endseq
    seq
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            let req <- puppet_slaves[0].request.get;
            internal_fifo[0].enq(req);
            $display("<%0t> - slave0 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[0].deq;
            let rsp = RspT{src_id: 0, data: 40'h0, slave_id: 0, last: True};
            puppet_slaves[0].response.put(rsp);
            $display("<%0t> - slave0 send ", $time, fshow(rsp));
        endaction
        action
            $display("<%0t> - slave0 done ", $time);
        endaction
    endseq
    seq
        action
            let req <- puppet_slaves[1].request.get;
            internal_fifo[1].enq(req);
            $display("<%0t> - slave1 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[1].deq;
            let rsp = RspT{src_id: 0, data: 40'h1, slave_id: 1, last: True};
            puppet_slaves[1].response.put(rsp);
            $display("<%0t> - slave1 send ", $time, fshow(rsp));
        endaction
        repeat (20) noAction;
        action
            let req <- puppet_slaves[1].request.get;
            internal_fifo[1].enq(req);
            $display("<%0t> - slave1 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[1].deq;
            let rsp = RspT{src_id: 0, data: 40'h1, slave_id: 1, last: True};
            puppet_slaves[1].response.put(rsp);
            $display("<%0t> - slave1 send ", $time, fshow(rsp));
        endaction
        repeat (20) noAction;
        action
            let req <- puppet_slaves[1].request.get;
            internal_fifo[1].enq(req);
            $display("<%0t> - slave1 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[1].deq;
            let rsp = RspT{src_id: 0, data: 40'h1, slave_id: 1, last: True};
            puppet_slaves[1].response.put(rsp);
            $display("<%0t> - slave1 send ", $time, fshow(rsp));
        endaction
        repeat (20) noAction;
        action
            let req <- puppet_slaves[1].request.get;
            internal_fifo[1].enq(req);
            $display("<%0t> - slave1 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[1].deq;
            let rsp = RspT{src_id: 0, data: 40'h1, slave_id: 1, last: True};
            puppet_slaves[1].response.put(rsp);
            $display("<%0t> - slave1 send ", $time, fshow(rsp));
        endaction
        repeat (20) noAction;
        action
            let req <- puppet_slaves[1].request.get;
            internal_fifo[1].enq(req);
            $display("<%0t> - slave1 receive ", $time, fshow(req));
        endaction
        repeat (20) noAction;
        action
            internal_fifo[1].deq;
            let rsp = RspT{src_id: 0, data: 40'h1, slave_id: 1, last: True};
            puppet_slaves[1].response.put(rsp);
            $display("<%0t> - slave1 send ", $time, fshow(rsp));
        endaction
        action
            $display("<%0t> - slave1 done ", $time);
        endaction
    endseq
    endpar;

endmodule

module mkTestSingleMasterOrderedBus (Empty);

    Test test0 <- mkTest0;
    Test test1 <- mkTest1;

    runTests(list(
        test0,
        test1
        ));

endmodule
