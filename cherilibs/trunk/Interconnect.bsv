/*-
 * Copyright (c) 2014 Alexandre Joannou
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

package Interconnect;

import Debug::*;
import FIFO::*;
import MasterSlave::*;
import NumberTypes :: *;
import Vector :: *;
import Assert :: *;

//////////////////////////////
// helper functions & types //
//////////////////////////////

typeclass Routable#(type a, numeric type width)
    dependencies(a determines width);
    function UInt#(width) getRoutingField   (a val);
    function Bool         getLastField      (a val);
endtypeclass

typedef struct {
    UInt#(width) base;
    UInt#(width) span;
} Range#(numeric type width) deriving (FShow);

typedef Vector#(n, Range#(width)) MappingTable#(numeric type n, numeric type width);

// helper function to tell whether a routable packet hits in a range or not
function Bool hitInRange(packet_t p, Range#(width) r)
    provisos (Routable#(packet_t, width))
    = ((getRoutingField(p) >= r.base) && getRoutingField(p) < (r.base + r.span));

// helper function to route a packet to the right output from a MappingTable
function Maybe#(BuffIndex#(TLog#(n_out), n_out)) routeFromMap (MappingTable#(n_out, width) mt, packet_t p)
    provisos (Routable#(packet_t, width));
    Maybe#(UInt#(TLog#(n_out))) tmp = findIndex(hitInRange(p), mt);
    if (isValid(tmp)) return tagged Valid BuffIndex{ bix: fromMaybe(0, tmp)};
    else return tagged Invalid;
endfunction

// helper function to route a packet to the right output from the routing field in the packet
function Maybe#(BuffIndex#(TLog#(n_out), n_out)) routeFromField (packet_t p)
    provisos (Routable#(packet_t, TLog#(n_out)));
    return tagged Valid BuffIndex{ bix: getRoutingField(p)};
endfunction

///////////////////////////////////////
// internal helper functions & types //
///////////////////////////////////////

typedef struct {
    Bool valid;
    packet_t packet;
    BuffIndex#(TLog#(n_out), n_out) dest;
} ToArbiterT#(type packet_t, numeric type n_out) deriving (Bits);

typedef enum {FIRST_FLIT, NEXT_FLIT} InputStateT deriving (Bits, Eq, FShow);

// helper function to turn a PulseWire into a Bool
function Bool toBool (PulseWire p) = p;

// helper function to return the valid field of a Wire#(ToArbiterT)
function Bool isToArbiterValid (Wire#(ToArbiterT#(packet_t, n_out)) t) = t.valid;

// helper function to return the associated bool with a canGet method  of a CheckedGet
function Bool canGet (CheckedGet#(packet_t) cg) = cg.canGet;

// helper function to return the desired sub-interface within Master/Slave
function CheckedGet#(req_t) getMasterReqIfc (Master#(req_t, rsp_t) m) = m.request;
function CheckedPut#(rsp_t) getMasterRspIfc (Master#(req_t, rsp_t) m) = m.response;
function CheckedPut#(req_t) getSlaveReqIfc  (Slave#(req_t, rsp_t) s)  = s.request;
function CheckedGet#(rsp_t) getSlaveRspIfc  (Slave#(req_t, rsp_t) s)  = s.response;

/////////////
// Modules //
/////////////
// XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
// The following modules assume that :
//  - a burst has a Routable first flit returning a valid value for its routing field
//    (the following flits routing field is not used)
//  - the last flit of a burst has a True "last flit" field
//  - When using the routing function routeFromMap, ranges in the MappingTable do not overlap
//
//  NB: the canGet and canPut method for the CheckedGet and CheckedPut interfaces
//      can be plugged into the standard FIFOF provided by bluespec since the
//      reference guide states that the notFull and notEmpty methods expose the
//      implicit condition for the enq and deq methods.
// XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX

/////////////////
// Generic Bus //
/////////////////

module mkOneWayBus
        #(
        Vector#(n_in, CheckedGet#(packet_t)) inputs,
        Vector#(n_out, CheckedPut#(packet_t)) outputs,
        function Maybe#(BuffIndex#(TLog#(n_out), n_out)) route (packet_t p))
        (Empty)
        provisos(
            Bits#(packet_t, packet_size),
            Routable#(packet_t, width),
            FShow#(packet_t));

    // wire to input
    Vector#(n_in, PulseWire) w_get <- replicateM(mkPulseWire);

    // wires to arbiter
    Vector#(n_in, Wire#(ToArbiterT#(packet_t, n_out)))
        w_to_arbiter <- replicateM(mkDWire(ToArbiterT{valid: False, packet: ?, dest: ?}));

    // state
    Reg#(Bool)                              is_allocated <- mkReg(False);
    Reg#(BuffIndex#(TLog#(n_in), n_in))     last_source  <- mkRegU;
    Reg#(BuffIndex#(TLog#(n_out), n_out))   last_dest    <- mkRegU;
    Reg#(InputStateT)                       state        <- mkReg(FIRST_FLIT);

    // rule generator function for the input fsm / deq the input fifo
    function Rules gen_input_rules (Integer i) = rules

        // do the get
        rule get_input (w_get[i]);
            // get the input
            let _ <- inputs[i].get;
        endrule

        // in case of first flit in a burst
        rule route_first_flit (inputs[i].canGet && state == FIRST_FLIT);
            Maybe#(BuffIndex#(TLog#(n_out), n_out)) sel_out = route(inputs[i].peek);
                case (sel_out) matches
                    tagged Valid .s_out: begin
                        last_dest <= s_out;
                        ToArbiterT#(packet_t, n_out) to_arbiter = ToArbiterT {
                                                                    valid: True,
                                                                    packet: inputs[i].peek,
                                                                    dest: s_out};

                        w_to_arbiter[i] <= to_arbiter;
                    end
                    default: begin
                        $display("%t: INVALID PACKET ", $time, fshow(inputs[i].peek));
                        dynamicAssert(False, "Every packet should have a destination address mapped to an output");
                    end
                endcase
        endrule

        // in case of new flit in a burst
        rule handle_next_flit (inputs[i].canGet && state == NEXT_FLIT);
            ToArbiterT#(packet_t, n_out) to_arbiter = ToArbiterT {
                                                        valid: True,
                                                        packet: inputs[i].peek,
                                                        dest: last_dest};

            w_to_arbiter[i] <= to_arbiter;
        endrule
    endrules;

    // arbiter for the output fifos
    rule arbiter;
        // If the bus is already allocated
        if (state == NEXT_FLIT) begin
            // If the corresponding input has a packet ready
            if (w_to_arbiter[last_source].valid && outputs[w_to_arbiter[last_source].dest].canPut) begin
                // update the bus state and put the packet in the output
                state <= (getLastField(w_to_arbiter[last_source].packet)) ? FIRST_FLIT : NEXT_FLIT;
                outputs[w_to_arbiter[last_source].dest].put(w_to_arbiter[last_source].packet);
                // send a dequeue signal to the selected input
                w_get[last_source].send;
            end
        end
        // If the bus is not already allocated
        else begin
            // compute the rotation amount for the fair priority algorithm
            UInt#(TLog#(n_in)) rot = fromInteger(valueOf(n_in) - 1) - unwrapBI(last_source);

            // rotate vector of wires to parse in a fair order
            Vector#(n_in, Bool) rotated = rotateBy(map(isToArbiterValid, w_to_arbiter), rot);

            // elect the new input
            Maybe#(UInt#(TLog#(n_in))) new_idx = findElem(True, rotated);
            case (new_idx) matches
                // in case of hit
                tagged Valid .n_idx: begin
                    // get the index rotated back to the original vector
                    BuffIndex#(TLog#(n_in), n_in) idx = sbtrctBIUInt(BuffIndex{ bix: n_idx }, rot);
                    if (outputs[w_to_arbiter[idx].dest].canPut) begin
                        // update the bus state and put the packet in the output
                        last_source <= idx;
                        state <= (getLastField(w_to_arbiter[idx].packet)) ? FIRST_FLIT : NEXT_FLIT;
                        outputs[w_to_arbiter[idx].dest].put(w_to_arbiter[idx].packet);
                        // send a dequeue signal to the selected input
                        w_get[idx].send;
                    end
                end
                // do nothing if there was no hit
                default : begin
                end
            endcase
        end
    endrule

    // instanciate the rules

    Vector#(n_in, Rules)    all_input_rules     = genWith(gen_input_rules);

    mapM(addRules, all_input_rules);

endmodule

module mkBus
        #(
        Vector#(n_in, Master#(req_t,rsp_t)) masters,
        function Maybe#(BuffIndex#(TLog#(n_out), n_out)) routeReq (req_t req),
        Vector#(n_out, Slave#(req_t,rsp_t)) slaves,
        function Maybe#(BuffIndex#(TLog#(n_in), n_in)) routeRsp (rsp_t rsp))
        (Empty)
        provisos(
            FShow#(req_t), FShow#(rsp_t),
            Routable#(req_t, m2s_width),
            Bits#(req_t, req_size),
            Routable#(rsp_t, s2m_width),
            Bits#(rsp_t, rsp_size));

    // requests bus
    mkOneWayBus(    map(getMasterReqIfc, masters),
                    map(getSlaveReqIfc, slaves),
                    routeReq);
    // responses bus
    mkOneWayBus(    map(getSlaveRspIfc, slaves),
                    map(getMasterRspIfc, masters),
                    routeRsp);

endmodule

//////////////////////
// Generic CrossBar //
//////////////////////

module mkOneWayCrossBar
        #(
        Vector#(n_in, CheckedGet#(packet_t)) inputs,
        Vector#(n_out, CheckedPut#(packet_t)) outputs,
        function Maybe#(BuffIndex#(TLog#(n_out), n_out)) route (packet_t p))
        (Empty)
        provisos(
            Bits#(packet_t, packet_size),
            Routable#(packet_t, width));

    // wires to inputs
    // XXX w_get is a pulseWireOR so that there is no conflict between the
    // rules trying to dequeue an input. This iscorrect as long as there are
    // no overlapping ranges in the mapping table
    Vector#(n_in, PulseWire)            w_get   <- replicateM(mkPulseWireOR);
    Vector#(n_in, Wire#(InputStateT))   w_state <- replicateM(mkDWire(FIRST_FLIT));

    // wires to arbiters
    Vector#(n_in, Wire#(ToArbiterT#(packet_t, n_out)))
        w_to_arbiter    <-  replicateM(mkDWire(ToArbiterT{valid: False, packet: ?, dest: ?}));

    //Input state
    Vector#(n_in, Reg#(InputStateT))
        input_state     <- replicateM(mkReg(FIRST_FLIT));
    Vector#(n_in, Reg#(BuffIndex#(TLog#(n_out), n_out)))
        input_out_idx   <- replicateM(mkRegU);

    // outputs state
    Vector#(n_out, Reg#(Bool))
        output_is_allocated <- replicateM(mkReg(False));
    Vector#(n_out, Reg#(BuffIndex#(TLog#(n_in), n_in)))
        output_from_source  <- replicateM(mkRegU);

    ///////////
    // rules //
    ///////////

    // rule generator function for the input fsm / deq the input fifo
    function Rules gen_input_rules (Integer i) = rules

        // do the get and update the input state
        rule get_input (w_get[i]);
            // get the input
            let _ <- inputs[i].get;
            // effectively update the state of the input fsm
            input_state[i] <= w_state[i];
        endrule

        // in case of first flit in a burst
        rule do_first_flit (input_state[i] == FIRST_FLIT);

            InputStateT next_state = FIRST_FLIT;

            if (inputs[i].canGet) begin
                Maybe#(BuffIndex#(TLog#(n_out), n_out)) sel_out = route(inputs[i].peek);
                case (sel_out) matches
                    tagged Valid .s_out: begin
                        input_out_idx[i] <= s_out;

                        ToArbiterT#(packet_t, n_out) to_arbiter = ToArbiterT {
                                                                    valid: True,
                                                                    packet: inputs[i].peek,
                                                                    dest: s_out};

                        w_to_arbiter[i] <= to_arbiter;

                        if (!getLastField(inputs[i].peek)) begin
                            next_state = NEXT_FLIT;
                        end
                    end
                    default: begin
                        dynamicAssert(False, "Every packet should have a destination address mapped to an output");
                    end
                endcase
            end
            w_state[i] <= next_state;

        endrule

        // in case of new flit in a burst
        rule do_next_flit (input_state[i] == NEXT_FLIT);

            InputStateT next_state = NEXT_FLIT;

            if (inputs[i].canGet) begin

                ToArbiterT#(packet_t, n_out) to_arbiter = ToArbiterT {
                                                            valid: True,
                                                            packet: inputs[i].peek,
                                                            dest: input_out_idx[i]};

                w_to_arbiter[i] <= to_arbiter;

                if (getLastField(inputs[i].peek)) begin
                    next_state = FIRST_FLIT;
                end
            end
            w_state[i] <= next_state;

        endrule
    endrules;

    // helper function to tell whether an input request hits in an output
    function Bool hitInOutput(BuffIndex#(TLog#(n_out), n_out) i, Wire#(ToArbiterT#(packet_t, n_out)) t) =
        (t.valid && i == t.dest);

    // rule generator function for updating outputs based on the wires coming
    // out of the input rules
    function Rules gen_output_rules (Integer i) = rules

        // arbiter for the output fifo
        rule arbiter (outputs[i].canPut);
            // If the output is already allocated
            if (output_is_allocated[i]) begin
                // If the corresponding input has a packet ready
                if (w_to_arbiter[output_from_source[i]].valid) begin
                    // update the output state and enqueue the output fifo
                    output_is_allocated[i] <= !getLastField(w_to_arbiter[output_from_source[i]].packet);
                    outputs[i].put(w_to_arbiter[output_from_source[i]].packet);
                    // send a dequeue signal to the selected input
                    w_get[output_from_source[i]].send;
                end
            end
            // If the output is not already allocated
            else begin

                // compute the rotation amount for the fair priority algorithm
                UInt#(TLog#(n_in)) rot = fromInteger(valueOf(n_in) - 1) - unwrapBI(output_from_source[i]);

                // rotate vector of wires to parse in a fair order
                Vector#(n_in, Wire#(ToArbiterT#(packet_t, n_out))) rotated = rotateBy(w_to_arbiter, rot);

                // check what input hit for this output (enq && dest)
                Maybe#(UInt#(TLog#(n_in))) new_idx = findIndex(hitInOutput(fromInteger(i)), rotated);
                case (new_idx) matches
                    // in case of hit
                    tagged Valid .n_idx: begin
                        // get the index rotated back to the original vector
                        BuffIndex#(TLog#(n_in), n_in) idx = sbtrctBIUInt(BuffIndex{ bix: n_idx }, rot);
                        // update the output state and enqueue the output fifo
                        output_from_source[i]  <= idx;
                        output_is_allocated[i] <= !getLastField(w_to_arbiter[idx].packet);
                        outputs[i].put(w_to_arbiter[idx].packet);
                        // send a dequeue signal to the selected input
                        w_get[idx].send;
                    end
                    // do nothing if there was no hit
                    default : begin
                    end
                endcase
            end
        endrule

    endrules;

    // instanciate the rules

    Vector#(n_in, Rules)    all_input_rules     = genWith(gen_input_rules);
    Vector#(n_out, Rules)   all_output_rules    = genWith(gen_output_rules);

    mapM(addRules, all_input_rules);
    mapM(addRules, all_output_rules);

endmodule

module mkCrossBar
        #(
        Vector#(n_in, Master#(req_t,rsp_t)) masters,
        function Maybe#(BuffIndex#(TLog#(n_out), n_out)) routeReq (req_t req),
        Vector#(n_out, Slave#(req_t,rsp_t)) slaves,
        function Maybe#(BuffIndex#(TLog#(n_in), n_in)) routeRsp (rsp_t rsp))
        (Empty)
        provisos(
            Routable#(req_t, m2s_width),
            Bits#(req_t, req_size),
            Routable#(rsp_t, s2m_width),
            Bits#(rsp_t, rsp_size));

    // requests crossbar
    mkOneWayCrossBar(   map(getMasterReqIfc, masters),
                        map(getSlaveReqIfc, slaves),
                        routeReq);
    // responses crossbar
    mkOneWayCrossBar(   map(getSlaveRspIfc, slaves),
                        map(getMasterRspIfc, masters),
                        routeRsp);

endmodule

/////////////////////////////
// SingleMasterOrderedBus  //
/////////////////////////////

import FIFO :: *;

module mkSingleMasterOrderedBus
        #(
        Master#(req_t,rsp_t) master,
        Vector#(n_out, Slave#(req_t,rsp_t)) slaves,
        function Maybe#(BuffIndex#(TLog#(n_out), n_out)) routeReq (req_t req),
        Integer in_flight_transactions)
        (Empty)
        provisos(
            Routable#(req_t, m2s_width),
            Routable#(rsp_t, s2m_width),
            Bits#(req_t, req_size),
            Bits#(rsp_t, rsp_size),
            FShow#(req_t), FShow#(rsp_t));

    staticAssert(in_flight_transactions > 0, "Can't authorize less than maximum 1 in flight transaction in the bus");

    FIFO#(BuffIndex#(TLog#(n_out), n_out )) pendingSlave <- mkSizedFIFO(in_flight_transactions);
    Reg#(InputStateT)                       req_state    <- mkReg(FIRST_FLIT);
    Vector#(n_out, Wire#(Maybe#(req_t)))    w_put_req    <- replicateM(mkDWire(tagged Invalid));
    Vector#(n_out, Wire#(Bool))             w_canPut_req <- replicateM(mkDWire(False));
    Vector#(n_out, Wire#(Bool))             w_canGet_rsp <- replicateM(mkDWire(False));
    Vector#(n_out, Wire#(rsp_t))            w_peek_rsp   <- replicateM(mkDWire(?));
    Vector#(n_out, Wire#(Bool))             w_get_rsp    <- replicateM(mkDWire(False));

    rule req_send_first_flit (req_state == FIRST_FLIT);
        Maybe#(BuffIndex#(TLog#(n_out), n_out)) slv_idx = routeReq(master.request.peek);
        case (slv_idx) matches
            tagged Valid .s_idx: begin
                if (w_canPut_req[s_idx]) begin
                    w_put_req[s_idx] <= tagged Valid master.request.peek;
                    let rtodebug <- master.request.get;
                    pendingSlave.enq(s_idx);
                    req_state <= (getLastField(master.request.peek)) ? FIRST_FLIT : NEXT_FLIT;
                end
            end
            default: begin
                dynamicAssert(False, "Every packet should have a destination address mapped to an output");
            end
        endcase
    endrule

    rule req_send_next_flit (req_state == NEXT_FLIT && w_canPut_req[pendingSlave.first]);
        w_put_req[pendingSlave.first] <= tagged Valid master.request.peek;
        let _ <- master.request.get;
        req_state <= (getLastField(master.request.peek)) ? FIRST_FLIT : NEXT_FLIT;
    endrule

    rule rsp_receive (w_canGet_rsp[pendingSlave.first]);
        /*$display("%t: SingleMasterOrdered bus response Slave %d ",*/
            /*$time, pendingSlave.first,*/
            /*fshow(w_peek_rsp[pendingSlave.first]));*/
        master.response.put(w_peek_rsp[pendingSlave.first]);
        w_get_rsp[pendingSlave.first] <= True;
        if (getLastField(w_peek_rsp[pendingSlave.first])) pendingSlave.deq;
    endrule

    function Rules gen_output_rules (Integer i) = rules
        rule update_req_wires;
            w_canPut_req[i] <= slaves[i].request.canPut;
        endrule
        rule update_rsp_wires;
            w_peek_rsp[i] <= slaves[i].response.peek;
            w_canGet_rsp[i] <= slaves[i].response.canGet;
        endrule
        rule do_get (w_get_rsp[i]);
            let _ <- slaves[i].response.get;
        endrule
        rule do_put (w_put_req[i] matches tagged Valid .req);
            slaves[i].request.put(req);
        endrule
    endrules;
    Vector#(n_out, Rules) all_output_rules = genWith(gen_output_rules);
    mapM(addRules, all_output_rules);

endmodule

// Ordered Bus
// Supports multiple masters. Doesn't have a reverse routing to masters
// function, because it keeps track of master IDs using the response source
// buffer. This bus implements static priority: masters with lower ids are
// serviced ahead of masters with larger ids.

// Guarentee: responses are returned in the order their requests traversed the
// bus.

typedef BuffIndex#(TLog#(count), count) MinimalBuffIndex#(numeric type count);

module mkOrderedBus
        #(Vector#(masterCount, Master#(reqType, respType)) masters,
          Vector#(slaveCount, Slave#(reqType, respType)) slaves,
          function Maybe#(BuffIndex#(TLog#(slaveCount), slaveCount)) routeReq
              (reqType req),
          Integer inflightTransactions)
        (Empty)
        provisos (
            FShow#(reqType), FShow#(respType),
            Bits#(reqType, a__), Bits#(respType, b__),
            Routable#(respType, c__)
        );

    staticAssert(inflightTransactions > 0, "It doesn't make sense to have a" +
        "bus that supports no transactions...");

    FIFO#(
        Tuple2#(MinimalBuffIndex#(slaveCount), MinimalBuffIndex#(masterCount))
    ) nextResponse <- mkSizedFIFO(inflightTransactions);
    let nextResponseSlave = tpl_1(nextResponse.first());
    let nextResponseMaster = tpl_2(nextResponse.first());

    Vector#(masterCount, RWire#(MinimalBuffIndex#(slaveCount))) reqTargets <-
        replicateM(mkRWire);
    Vector#(slaveCount, PulseWire) respTakenFromSlave <- replicateM(mkPulseWire);

    // Conceptually, these wires actually form "the bus".
    Wire#(reqType)     reqWire     <- mkWire;
    Wire#(respType)    respWire    <- mkWire;

    // I need this function because it's the only way to get correct results
    // when using a BuffIndex type with count 1, which translates as a UInt#(0)
    function Bool equalityCircuit(someType left, someType right)
            provisos(Bits#(someType, size));
        let pairXor = pack(left) ^ pack(right);
        let notEq = reduceOr(pairXor);
        return !unpack(notEq);
    endfunction

    function Bool reqHasReadySlave(
            RWire#(MinimalBuffIndex#(slaveCount)) slaveIndexWire);
        case (slaveIndexWire.wget())
            matches tagged Valid .slaveIndex:
                return slaves[slaveIndex].request.canPut();
            default:
                return False;
        endcase
    endfunction

    function Bool thisMasterSends(indexToCheck);
        let maybeCorrectIndex = findIndex(reqHasReadySlave, reqTargets);
        case (maybeCorrectIndex) matches
            tagged Valid .correctIndex:
                return indexToCheck == correctIndex;
            tagged Invalid:
                return False;
        endcase
    endfunction

    function Rules perMasterRules(Integer masterIndex) = rules
        let master = masters[masterIndex];
        let buffIndexMaster = fromInteger(masterIndex);

        rule forwardReqTarget (master.request.canGet());
            case (routeReq(master.request.peek())) matches
                tagged Valid .slaveIndex: begin
                    debug2("orderedBus", $display("%t: Master %d has request "
                        + "for Slave %d", $time, masterIndex, slaveIndex));
                    reqTargets[masterIndex].wset(slaveIndex);
                end
                tagged Invalid: begin
                    $display(fshow(master.request.peek()));
                    dynamicAssert(False, "Request for invalid slave!");
                end
            endcase
        endrule

        rule forwardRequestFromMaster (thisMasterSends(buffIndexMaster));
            let req <- master.request.get();
            reqWire <= req;
            case (reqTargets[masterIndex].wget())
                matches tagged Valid .slaveIndex: begin
                    debug2("orderedBus", $display("%t: Master %d sending to "
                        + "Slave %d ", $time, masterIndex, slaveIndex,
                            fshow(req)));
                    nextResponse.enq(tuple2(slaveIndex, buffIndexMaster));
                end
                default:
                    dynamicAssert(False, "Should have had valid slave index!");
            endcase
        endrule

        rule forwardResponseToMaster
                (equalityCircuit(nextResponseMaster, buffIndexMaster));
            debug2("orderedBus", $display("%t: Response placed from wire to "
                + "Master %d", $time, buffIndexMaster));
            master.response.put(respWire);
            if (getLastField(respWire)) nextResponse.deq();
            respTakenFromSlave[nextResponseSlave].send();
        endrule

    endrules;

    function Bool thisSlaveReceives(indexToCheck);
        case (routeReq(reqWire)) matches
            tagged Valid .reqSlaveId:
                return (reqSlaveId == indexToCheck);
            default:
                return False;
        endcase
    endfunction

    function Rules perSlaveRules(Integer slaveIndex) = rules
        let slave = slaves[slaveIndex];
        MinimalBuffIndex#(slaveCount) buffIndexSlave = fromInteger(slaveIndex);

        rule forwardRequestToSlave (thisSlaveReceives(buffIndexSlave));
            slave.request.put(reqWire);
        endrule

        rule forwardResponseFromSlave
                (equalityCircuit(nextResponseSlave, buffIndexSlave));

            debug2("orderedBus", $display("%t: Response from Slave %d put on "
                + "wire. ", $time, buffIndexSlave));
            respWire <= slave.response.peek();
        endrule

        // Take Alexandre's suggestion to only dequeue if it's the result has
        // been taken by the master
        rule deqFromSlave(respTakenFromSlave[slaveIndex]);
            debug2("orderedBus", $display("%t: Dequeuing slave %d ", $time,
                slaveIndex, fshow(respWire)));
            let _ <- slave.response.get();
        endrule

    endrules;
    Vector#(masterCount, Rules) masterRules = genWith(perMasterRules);
    Vector#(slaveCount, Rules)  slaveRules  = genWith(perSlaveRules);
    mapM(addRules, masterRules);
    mapM(addRules, slaveRules);

endmodule

endpackage
