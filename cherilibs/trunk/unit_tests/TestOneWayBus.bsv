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
    UInt#(TLog#(nb_dest)) dest;
    UInt#(width) data;
    Bool last;
} PacketT#(numeric type nb_dest, numeric type width) deriving (FShow, Bits);

instance Routable#(PacketT#(n,w), TLog#(n));
    function UInt#(TLog#(n)) getRoutingField (PacketT#(n,w) req) = req.dest;
    function Bool getLastField (PacketT#(n,w) req) = req.last;
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

    Vector#(1, PuppetMaster#(PacketT#(1,8), PacketT#(1,8))) puppet_masters <- replicateM(mkPuppetMaster);
    Vector#(1, Master#(PacketT#(1,8), PacketT#(1,8))) masters = map(fromPuppetMaster, puppet_masters);

    Vector#(1, PuppetSlave#(PacketT#(1,8), PacketT#(1,8))) puppet_slaves <- replicateM(mkPuppetSlave);
    Vector#(1, Slave#(PacketT#(1,8), PacketT#(1,8))) slaves = map (fromPuppetSlave, puppet_slaves);

    mkOneWayBus( map(getMasterReqIfc,masters), map(getSlaveReqIfc,slaves), constFn(tagged Valid 0));

    method String testName = "OneWayBus 1 master - 1 slave";

    method Stmt runTest = par
    count <= 0;
    seq
        action
            PacketT#(1,8) req = PacketT{dest: 0, data: 8'hbb, last: True};
            puppet_masters[0].request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
    endseq
    seq
        action
            PacketT#(1,8) req = puppet_slaves[0].request.peek;
            $display("<%0t> - slave receive ", $time, fshow(req));
        endaction
    endseq
    endpar;

endmodule

module mkTest1 (Test);

    Reg#(UInt#(8))  count       <- mkCounter;

    Vector#(2, PuppetMaster#(PacketT#(2,8), PacketT#(2,8))) puppet_masters <- replicateM(mkPuppetMaster);
    Vector#(2, Master#(PacketT#(2,8), PacketT#(2,8))) masters = map(fromPuppetMaster, puppet_masters);

    Vector#(1, PuppetSlave#(PacketT#(2,8), PacketT#(2,8))) puppet_slaves <- replicateM(mkPuppetSlave);
    Vector#(1, Slave#(PacketT#(2,8), PacketT#(2,8))) slaves = map (fromPuppetSlave, puppet_slaves);

    mkOneWayBus( map(getMasterReqIfc,masters), map(getSlaveReqIfc,slaves), constFn(tagged Valid 0));
    //mkOneWayCrossBar( map(getMasterReqIfc,masters), map(getSlaveReqIfc,slaves), constFn(tagged Valid 0));

    method String testName = "OneWayBus 2 masters - 1 slave";

    method Stmt runTest = par
    count <= 0;
    seq
        action
            PacketT#(2,8) req = PacketT{dest: 0, data: 8'hbb, last: True};
            puppet_masters[0].request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
    endseq
    seq
        action
            PacketT#(2,8) req = PacketT{dest: 0, data: 8'hdd, last: True};
            puppet_masters[1].request.put(req);
            $display("<%0t> - master send ", $time, fshow(req));
        endaction
    endseq
    seq
        action
            PacketT#(2,8) req <- puppet_slaves[0].request.get;
            $display("<%0t> - slave receive ", $time, fshow(req));
        endaction
        action
            PacketT#(2,8) req <- puppet_slaves[0].request.get;
            $display("<%0t> - slave receive ", $time, fshow(req));
        endaction
    endseq
    endpar;

endmodule

module mkTestOneWayBus (Empty);

    Test test0 <- mkTest0;
    Test test1 <- mkTest1;

    runTests(list(
        test0,
        test1
        ));

endmodule
