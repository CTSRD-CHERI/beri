/*-
 * Copyright (c) 2014, 2015 Alexandre Joannou
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
 */

package MasterSlave;

import FIFOF :: *;
import SpecialFIFOs :: *;
import GetPut :: *;
import ClientServer :: *;
import Connectable :: *;

//////////////////////////
// CheckedPut interface //
//////////////////////////

interface CheckedPut#(type t);
   (* always_ready *)
   method Bool canPut();
   method Action put(t val);
endinterface

typeclass ToCheckedPut#(type a, type b)
    dependencies(a determines b);
    function CheckedPut#(b) toCheckedPut (a val);
endtypeclass

instance ToCheckedPut#(CheckedPut#(data_t), data_t);
    function CheckedPut#(data_t) toCheckedPut (CheckedPut#(data_t) cp) = cp;
endinstance

instance ToCheckedPut#(FIFOF#(data_t), data_t);
    function CheckedPut#(data_t) toCheckedPut (FIFOF#(data_t) f) =
        interface CheckedPut#(data_t);
            method canPut = f.notFull;
            method Action put(data_t d) if (f.notFull);
              f.enq(d);
            endmethod
        endinterface;
endinstance

instance ToPut#(CheckedPut#(data_t), data_t);
    function Put#(data_t) toPut (CheckedPut#(data_t) cp) =
        interface Put#(data_t);
            method put = cp.put;
        endinterface;
endinstance

instance Connectable#(CheckedPut#(data_t), CheckedGet#(data_t));
    module mkConnection#(CheckedPut#(data_t) cp, CheckedGet#(data_t) cg)(Empty);
        mkConnection(toGet(cg), toPut(cp));
    endmodule
endinstance
instance Connectable#(CheckedPut#(data_t), Get#(data_t));
    module mkConnection#(CheckedPut#(data_t) cp, Get#(data_t) g)(Empty);
        mkConnection(toPut(cp), g);
    endmodule
endinstance
instance Connectable#(Get#(data_t), CheckedPut#(data_t));
    module mkConnection#(Get#(data_t) g, CheckedPut#(data_t) cp)(Empty);
        mkConnection(toPut(cp), g);
    endmodule
endinstance

module mkPutToCheckedPut#(Put#(d) put)(CheckedPut#(d)) provisos (Bits#(d, _));

    FIFOF#(d) holdingFIFOF <- mkBypassFIFOF();

    mkConnection(toGet(holdingFIFOF), put);

    method canPut = holdingFIFOF.notFull;
    method put    = holdingFIFOF.enq;
endmodule

//////////////////////////
// CheckedGet interface //
//////////////////////////

interface CheckedGet#(type t);
   (* always_ready *)
   method Bool canGet();
   method t peek();
   method ActionValue#(t) get();
endinterface

typeclass ToCheckedGet#(type a, type b)
    dependencies(a determines b);
    function CheckedGet#(b) toCheckedGet (a val);
endtypeclass

instance ToCheckedGet#(CheckedGet#(data_t), data_t);
    function CheckedGet#(data_t) toCheckedGet (CheckedGet#(data_t) cg) = cg;
endinstance

instance ToCheckedGet#(FIFOF#(data_t), data_t);
    function CheckedGet#(data_t) toCheckedGet (FIFOF#(data_t) f) =
        interface CheckedGet#(data_t);
            method canGet = f.notEmpty;
            method data_t peek if (f.notEmpty);
              return f.first;
            endmethod
            method ActionValue#(data_t) get if (f.notEmpty);
              f.deq; 
              return f.first;
            endmethod
        endinterface;
endinstance

instance ToGet#(CheckedGet#(data_t), data_t);
    function Get#(data_t) toGet (CheckedGet#(data_t) cg) =
        interface Get#(data_t);
            method get = cg.get;
        endinterface;
endinstance

instance Connectable#(CheckedGet#(data_t), CheckedPut#(data_t));
    module mkConnection#(CheckedGet#(data_t) cg, CheckedPut#(data_t) cp)(Empty);
        mkConnection(toGet(cg), toPut(cp));
    endmodule
endinstance
instance Connectable#(CheckedGet#(data_t), Put#(data_t));
    module mkConnection#(CheckedGet#(data_t) cg, Put#(data_t) p)(Empty);
        mkConnection(toGet(cg), p);
    endmodule
endinstance
instance Connectable#(Put#(data_t), CheckedGet#(data_t));
    module mkConnection#(Put#(data_t) p, CheckedGet#(data_t) cg)(Empty);
        mkConnection(toGet(cg), p);
    endmodule
endinstance

module mkGetToCheckedGet#(Get#(d) get)(CheckedGet#(d)) provisos (Bits#(d, _));

    FIFOF#(d) holdingFIFOF <- mkBypassFIFOF();

    mkConnection(get, toPut(holdingFIFOF));

    method canGet = holdingFIFOF.notEmpty;
    method peek   = holdingFIFOF.first;
    method get    = actionvalue holdingFIFOF.deq; return holdingFIFOF.first; endactionvalue;
endmodule

//////////////////////
// Master interface //
//////////////////////

interface Master#(type req_t, type rsp_t);
    interface CheckedGet#(req_t) request;
    interface CheckedPut#(rsp_t) response;
endinterface

function Master#(req_t, rsp_t) mkMaster(req_src_t req, rsp_src_t rsp)
        provisos (
            ToCheckedGet#(req_src_t, req_t),
            ToCheckedPut#(rsp_src_t, rsp_t)
        ) =
    interface Master#(req_t, rsp_t);
        interface request = toCheckedGet(req);
        interface response = toCheckedPut(rsp);
    endinterface;

function Client#(req_t,rsp_t) masterToClient (Master#(req_t, rsp_t) m) =
    interface Client#(req_t, rsp_t);
        interface request  = toGet(m.request);
        interface response = toPut(m.response);
    endinterface;

instance Connectable#(Master#(req_t, rsp_t), Slave#(req_t, rsp_t));
    module mkConnection#(Master#(req_t, rsp_t) m, Slave#(req_t, rsp_t) s)(Empty);
        mkConnection(masterToClient(m), slaveToServer(s));
    endmodule
endinstance
instance Connectable#(Master#(req_t, rsp_t), Server#(req_t, rsp_t));
    module mkConnection#(Master#(req_t, rsp_t) m, Server#(req_t, rsp_t) s)(Empty);
        mkConnection(masterToClient(m), s);
    endmodule
endinstance
instance Connectable#(Server#(req_t, rsp_t), Master#(req_t, rsp_t));
    module mkConnection#(Server#(req_t, rsp_t) s, Master#(req_t, rsp_t) m)(Empty);
        mkConnection(masterToClient(m), s);
    endmodule
endinstance

/////////////////////
// Slave interface //
/////////////////////

interface Slave#(type req_t, type rsp_t);
    interface CheckedPut#(req_t) request;
    interface CheckedGet#(rsp_t) response;
endinterface

function Slave#(req_t, rsp_t) mkSlave(CheckedPut#(req_t) req, CheckedGet#(rsp_t) rsp) =
    interface Slave#(req_t, rsp_t);
        interface request = req;
        interface response = rsp;
    endinterface;

function Server#(req_t,rsp_t) slaveToServer (Slave#(req_t, rsp_t) s) =
    interface Server#(req_t, rsp_t);
        interface request  = toPut(s.request);
        interface response = toGet(s.response);
    endinterface;

instance Connectable#(Slave#(req_t, rsp_t), Master#(req_t, rsp_t));
    module mkConnection#(Slave#(req_t, rsp_t) s, Master#(req_t, rsp_t) m)(Empty);
        mkConnection(masterToClient(m), slaveToServer(s));
    endmodule
endinstance
instance Connectable#(Slave#(req_t, rsp_t), Client#(req_t, rsp_t));
    module mkConnection#(Slave#(req_t, rsp_t) s, Client#(req_t, rsp_t) c)(Empty);
        mkConnection(slaveToServer(s), c);
    endmodule
endinstance
instance Connectable#(Client#(req_t, rsp_t), Slave#(req_t, rsp_t));
    module mkConnection#(Client#(req_t, rsp_t) c, Slave#(req_t, rsp_t) s)(Empty);
        mkConnection(slaveToServer(s), c);
    endmodule
endinstance

///////////////////////
// Forward interface //
///////////////////////

interface ForwardPutGet#(type a);
    interface CheckedPut#(a) cput;
    interface CheckedGet#(a) cget;
endinterface

module mkForwardPutGet (ForwardPutGet#(a))
    provisos(Bits#(a, a_width));
    FIFOF#(a) fifo <- mkSizedBypassFIFOF(1);
    interface CheckedPut cput = toCheckedPut(fifo);
    interface CheckedGet cget = toCheckedGet(fifo);
endmodule

interface Forward#(type req_t, type rsp_t);
    interface Slave#(req_t, rsp_t) slave;
    interface Master#(req_t, rsp_t) master;
endinterface

module mkForward (Forward#(req_t, rsp_t))
    provisos(
        Bits#(req_t, req_t_width),
        Bits#(rsp_t, rsp_t_width)
    );

    ForwardPutGet#(req_t) req <- mkForwardPutGet;
    ForwardPutGet#(rsp_t) rsp <- mkForwardPutGet;

    interface Slave slave;
        interface CheckedPut request  = req.cput;
        interface CheckedGet response = rsp.cget;
    endinterface
    interface Master master;
        interface CheckedGet request  = req.cget;
        interface CheckedPut response = rsp.cput;
    endinterface
endmodule

endpackage
