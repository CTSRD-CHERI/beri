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

/*
 * Unit tests for the ordered bus.
 *
 * These tend to be a bit weird. The forward modules are essentially dumb
 * bridges, so I use them to be able to fully manipulate what the bus sees. They
 * are named after their role on the bus, hence all the master.slave nonsense in
 * the actual test itself.
 *
 */

import StmtFSM::*;
import Variadic::*;
import Vector::*;

import Interconnect::*;
import MasterSlave::*;
import MemTypes::*;
import UnitTesting::*;

typedef Forward#(CheriMemRequest, CheriMemResponse) CheriForward;
typedef Master#(CheriMemRequest, CheriMemResponse)  CheriMaster;
typedef Slave#(CheriMemRequest, CheriMemResponse)   CheriSlave;

module mkTestSimple(Test);
    CheriForward master  <- mkForward();
    CheriForward slave   <- mkForward();
    Vector#(1, CheriMaster) masters = vector(master.master);
    Vector#(1, CheriSlave)  slaves  = vector(slave.slave);
    function routeReq(req) = tagged Valid 0;
    mkOrderedBus(masters, slaves, routeReq, 1);

    CheriMemRequest req = MemoryRequest {
        addr: unpack('hBEEF),
        masterID: 0,
        transactionID: 0,
        operation: tagged Read {
            uncached: False,
            linked: True,
            noOfFlits: 0,
            bytesPerFlit: BYTE_32
        }
    };

    CheriMemResponse resp = MemoryResponse {
        masterID: 0,
        transactionID: 0,
        error: NoError,
        operation: tagged Read {
            data: Data { data: 'hBEAD },
            last: True
        }
    };

    Reg#(Bool) correct <- mkRegU;

    method String testName = "Test that one request can go through the bus.";

    method Stmt runTest = seq
        master.slave.request.put(req);
        action
            let gotReq <- slave.master.request.get();
            correct <= (pack(gotReq) == pack(req));
        endaction
        testAssert(correct);
        slave.master.response.put(resp);
        action
            let gotResp <- master.slave.response.get();
            correct <= (pack(gotResp) == pack(resp));
        endaction
        testAssert(correct);
    endseq;
endmodule

function CheriMemRequest readReq(Bit#(40) addr, CheriMasterID masterID);
    return (MemoryRequest {
        addr: unpack(addr),
        masterID: masterID,
        transactionID: 0,
        operation: tagged Read {
            uncached: False,
            linked: True,
            noOfFlits: 0,
            bytesPerFlit: BYTE_32
    }});
endfunction

function CheriMemResponse readResp(CheriMasterID masterID, Bit#(256) data);
    return (MemoryResponse {
        masterID: 0,
        transactionID: 0,
        error: NoError,
        operation: tagged Read {
            data: Data { data: data },
            last: True
        }
    });
endfunction

module mkTestLowPriorityMaster(Test);
    Reg#(Bool) correct <- mkRegU;

    CheriForward master0    <- mkForward();
    CheriForward master1    <- mkForward();
    CheriForward slave      <- mkForward();

    Vector#(2, CheriMaster) masters = vector(master0.master, master1.master);
    Vector#(1, CheriSlave)  slaves  = vector(slave.slave);

    function routeReq(req) = tagged Valid 0;

    mkOrderedBus(masters, slaves, routeReq, 1);

    method String testName = "Test that a low priority master can send.";
    // One failure case is that the presence of a high priority master with
    // nothing to send stops the low priority master from sending.

    method Stmt runTest = seq
        master1.slave.request.put(readReq(0, 1));
        action
            let gotReq <- slave.master.request.get();
            correct <= (pack(gotReq) == pack(readReq(0, 1)));
        endaction
        testAssert(correct);
        slave.master.response.put(readResp(1, 1234));
        action
            let gotResp <- master1.slave.response.get();
            correct <= (pack(gotResp) == pack(readResp(1, 1234)));
        endaction
        testAssert(correct);

        action
            master0.slave.request.put(readReq('h100, 0));
            master1.slave.request.put(readReq('h200, 1));
        endaction
        action
            let gotReq <- slave.master.request.get();
            correct <= (pack(gotReq) == pack(readReq('h100, 0)));
        endaction
        testAssert(correct);

        slave.master.response.put(readResp(0, 4321));
        action
            let gotResp <- master0.slave.response.get();
            correct <= (pack(gotResp) == pack(readResp(0, 4321)));
        endaction
        testAssert(correct);

        action
            let gotReq <- slave.master.request.get();
            correct <= (pack(gotReq) == pack(readReq('h200, 1)));
        endaction
        testAssert(correct);

        slave.master.response.put(readResp(1, 'habcd));
        action
            let gotResp <- master1.slave.response.get();
            correct <= (pack(gotResp) == pack(readResp(0, 'habcd)));
        endaction
        testAssert(correct);

    endseq;

endmodule

module mkNeverReadySlave(CheriSlave);
    interface CheckedPut request;
        method canPut = False;
        method Action put(CheriMemRequest req) if (False);
        endmethod
    endinterface

    interface CheckedGet response;
        method canGet = False;
        method peek() if (False) = ?;
        method get() if (False);
            return ?;
        endmethod
    endinterface
endmodule

module mkTestUnreadySlaveDoesntLockBus(Test);
    Reg#(Bool)   correct    <- mkRegU;

    CheriForward master0    <- mkForward();
    CheriForward master1    <- mkForward();
    CheriSlave   slave0     <- mkNeverReadySlave();
    CheriForward slave1     <- mkForward();
    Vector#(2, CheriMaster) masters = vector(master0.master, master1.master);
    Vector#(2, CheriSlave)  slaves  = vector(slave0, slave1.slave);

    function routeReq(req) =
        tagged Valid unpack(zeroExtend(pack(req.addr)[0]));

    mkOrderedBus(masters, slaves, routeReq, 4);

    method String testName = "Test that an unready slave doesn't block others.";

    method Stmt runTest = seq
        action
            // To unready slave at high priority
            master0.slave.request.put(readReq(0, 0));
            // To ready slave at low priority
            master1.slave.request.put(readReq(1, 1));
        endaction
        action
            let gotReq <- slave1.master.request.get();
            correct <= (pack(gotReq) == pack(readReq(1, 1)));
        endaction
        testAssert(correct);

        slave1.master.response.put(readResp(1, 'hDEAD_DEAD_BEEF_4321));
        action
            let gotResp <- master1.slave.response.get();
            correct <= (pack(gotResp) ==
                pack(readResp(1, 'hDEAD_DEAD_BEEF_4321)));
        endaction
        testAssert(correct);
    endseq;
endmodule


module mkTestOrderedBus(Empty);
    let testSimple          <- mkTestSimple();
    let testLowPriority     <- mkTestLowPriorityMaster();
    let testUnreadySlave    <- mkTestUnreadySlaveDoesntLockBus();

    runTests(list(
        testSimple,
        testLowPriority,
        testUnreadySlave
    ));
endmodule
