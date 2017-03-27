/*-
 * Copyright (c) 2015, 2016 Alexandre Joannou
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

import DefaultValue::*;
import GetPut::*;
import MemTypes::*;
import MEM::*;
import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import Vector::*;
import Debug::*;

`ifdef CAP
  `define USECAP 1
`elsif CAP128
  `define USECAP 1
`elsif CAP64
  `define USECAP 1
`endif

// Events structures to be filled by the modules reporting stats
///////////////////////////////////////////////////////////////////////////////
// Cache Core events
///////////////////////////////////////////////////////////////////////////////
typedef struct { 
    Bit#(16)    id;
    WhichCache  whichCache;
    Bool        incHitWrite;
    Bool        incMissWrite;
    Bool        incHitRead;
    Bool        incMissRead;
    Bool        incHitPftch;
    Bool        incMissPftch;
    Bool        incEvict;
    Bool        incPftchEvict;
    `ifdef USECAP
    Bool        incSetTagWrite;
    Bool        incSetTagRead;
    `endif
} CacheCoreEvents deriving (Bits, Eq, FShow);

instance DefaultValue#(CacheCoreEvents);
    function defaultValue = unpack(0);
endinstance

function Get#(ModuleEvents) dfltCacheCoreEventGet;
    return (interface Get;
                method ActionValue#(ModuleEvents) get;
                    return tagged CacheCore_E defaultValue;
                endmethod
            endinterface);
endfunction

// MIPS memory events
///////////////////////////////////////////////////////////////////////////////
typedef struct { 
    Bit#(16)    id;
    Bool        incByteRead;
    Bool        incByteWrite;
    Bool        incHWordRead;
    Bool        incHWordWrite;
    Bool        incWordRead;
    Bool        incWordWrite;
    Bool        incDwordRead;
    Bool        incDwordWrite;
    `ifdef USECAP
    Bool        incCapRead;
    Bool        incCapWrite;
    `endif
} MIPSMemEvents deriving (Bits, Eq, FShow);

instance DefaultValue#(MIPSMemEvents);
    function defaultValue = unpack(0);
endinstance

function Get#(ModuleEvents) dfltMIPSMemEventGet;
    return (interface Get;
                method ActionValue#(ModuleEvents) get;
                    return tagged MIPSMem_E defaultValue;
                endmethod
            endinterface);
endfunction

// Master events
///////////////////////////////////////////////////////////////////////////////
typedef struct {
    Bit#(16)    id;
    Bool        incReadReq;
    Bool        incWriteReq;
    Bool        incWriteReqFlit;
    Bool        incReadRsp;
    Bool        incReadRspFlit;
    Bool        incWriteRsp;
} MasterEvents deriving (Bits, Eq, FShow);

instance DefaultValue#(MasterEvents);
    function defaultValue = unpack(0);
endinstance

function Get#(ModuleEvents) dfltMasterEventGet;
    return (interface Get;
                method ActionValue#(ModuleEvents) get;
                    return tagged Master_E defaultValue;
                endmethod
            endinterface);
endfunction

`ifdef USECAP
typedef 10 CountersPerModules; // max counters associated with a reporting module
`else
typedef 10 CountersPerModules; // should be 8, but getting worst case to make software easier for now
`endif

// union of all possible module reports
typedef union tagged {
    CacheCoreEvents CacheCore_E;
    MIPSMemEvents   MIPSMem_E;
    MasterEvents    Master_E;
} ModuleEvents deriving (Bits, Eq, FShow);

///////////////////////////////////////////////////////////////////////////////

// Interface to the stat counter module
///////////////////////////////////////////////////////////////////////////////
typedef 5 SelectorWidth;

typedef struct {
    Bit#(SelectorWidth) moduleSelector;
    Bit#(SelectorWidth) counterSelector;
} Selectors deriving (Bits, Eq, FShow, Bounded);

typedef union tagged {
    Selectors Read;
    void ResetAll;
    void Nop;
} StatCountersReq deriving (Bits, Eq, FShow);

instance DefaultValue#(StatCountersReq);
    function defaultValue = tagged Nop;
endinstance

interface StatCounters;
    interface Put#(StatCountersReq) request;
    interface Get#(Maybe#(Bit#(64))) response;
    method Action commitReset(Bool c);
endinterface

typedef enum {Init, Ready} StatCountersState deriving (Bits, Eq, Bounded);

///////////////////////////////////////////////////////////////////////////////

// Implementing the StatCounter module
///////////////////////////////////////////////////////////////////////////////

module mkStatCounters#(Integer rsp_fifo_depth, Vector#(no_of_modules, Get#(ModuleEvents)) moduleEvents) (StatCounters)
provisos(
    Mul#(no_of_modules, CountersPerModules, no_of_counters),
    Log#(no_of_counters, cnt_idx_w),
    Add#(_, 5, cnt_idx_w) // 5 < cnt_idx_w
);

    Vector#(no_of_modules, Vector#(CountersPerModules, Array#(Reg#(UInt#(8)))))
        counters <- replicateM(replicateM(mkCReg(2,0)));
    MEM#(UInt#(cnt_idx_w), UInt#(64))
        mem <- mkMEM();
    FIFOF#(Maybe#(Bit#(64))) rsp <- mkSizedBypassFIFOF(rsp_fifo_depth);
    FIFO#(Tuple3#(UInt#(cnt_idx_w),Bool,Bool)) memAccessFifo <- mkLFIFO();
    FIFO#(Bool) resetFIFO <- mkSizedFIFO(rsp_fifo_depth);
    
    Reg#(StatCountersState) state <- mkReg(Init);
    Reg#(UInt#(cnt_idx_w)) initCount    <- mkReg(0);
    Reg#(UInt#(cnt_idx_w)) refreshCount <- mkReg(0);

    RWire#(StatCountersReq) req_wire <- mkRWire();

    // general helper functions
    ////////////////////////////////////////////////////////////////////////////

    function Reg#(UInt#(8)) getCounter (UInt#(cnt_idx_w) idx);
        return concat(counters)[idx][0];
    endfunction

    function UInt#(cnt_idx_w) getCounterIdx (Selectors ss);
        UInt#(cnt_idx_w) stride = fromInteger(valueOf(CountersPerModules));
        UInt#(cnt_idx_w) row_offset = zeroExtend(unpack(ss.moduleSelector)) * stride;
        return zeroExtend(unpack(ss.counterSelector)) + row_offset;
    endfunction

    // Events gathering helper functions
    ////////////////////////////////////////////////////////////////////////////

    //CacheCore counters handling
    function Action gatherCacheEvents(CacheCoreEvents e, Vector#(CountersPerModules, Array#(Reg#(UInt#(8)))) cnt) = action
        if (e.incHitWrite   ) cnt[0][1] <= cnt[0][1] + 1;
        if (e.incMissWrite  ) cnt[1][1] <= cnt[1][1] + 1;
        if (e.incHitRead    ) cnt[2][1] <= cnt[2][1] + 1;
        if (e.incMissRead   ) cnt[3][1] <= cnt[3][1] + 1;
        if (e.incHitPftch   ) cnt[4][1] <= cnt[4][1] + 1;
        if (e.incMissPftch  ) cnt[5][1] <= cnt[5][1] + 1;
        if (e.incEvict      ) cnt[6][1] <= cnt[6][1] + 1;
        if (e.incPftchEvict ) cnt[7][1] <= cnt[7][1] + 1;
        `ifdef USECAP
        if (e.incSetTagWrite) cnt[8][1] <= cnt[8][1] + 1;
        if (e.incSetTagRead ) cnt[9][1] <= cnt[9][1] + 1;
        `endif
        debug2("StatCounters", $display("<time %0t, StatCounters> gatherCacheEvents function, ", $time, fshow(e)));
    endaction;

    // MIPS counters handling
    function Action gatherMIPSEvents(MIPSMemEvents e, Vector#(CountersPerModules, Array#(Reg#(UInt#(8)))) cnt) = action
        if (e.incByteRead   ) cnt[0][1] <= cnt[0][1] + 1;
        if (e.incByteWrite  ) cnt[1][1] <= cnt[1][1] + 1;
        if (e.incHWordRead  ) cnt[2][1] <= cnt[2][1] + 1;
        if (e.incHWordWrite ) cnt[3][1] <= cnt[3][1] + 1;
        if (e.incWordRead   ) cnt[4][1] <= cnt[4][1] + 1;
        if (e.incWordWrite  ) cnt[5][1] <= cnt[5][1] + 1;
        if (e.incDwordRead  ) cnt[6][1] <= cnt[6][1] + 1;
        if (e.incDwordWrite ) cnt[7][1] <= cnt[7][1] + 1;
        `ifdef USECAP
        if (e.incCapRead    ) cnt[8][1] <= cnt[8][1] + 1;
        if (e.incCapWrite   ) cnt[9][1] <= cnt[9][1] + 1;
        `endif
        debug2("StatCounters", $display("<time %0t, StatCounters> gatherMIPSEvents function, ", $time, fshow(e)));
    endaction;

    // Master counters handling
    function Action gatherMasterEvents(MasterEvents e, Vector#(CountersPerModules, Array#(Reg#(UInt#(8)))) cnt) = action
        if (e.incReadReq      ) cnt[0][1] <= cnt[0][1] + 1;
        if (e.incWriteReq     ) cnt[1][1] <= cnt[1][1] + 1;
        if (e.incWriteReqFlit ) cnt[2][1] <= cnt[2][1] + 1;
        if (e.incReadRsp      ) cnt[3][1] <= cnt[3][1] + 1;
        if (e.incReadRspFlit  ) cnt[4][1] <= cnt[4][1] + 1;
        if (e.incWriteRsp     ) cnt[5][1] <= cnt[5][1] + 1;
        debug2("StatCounters", $display("<time %0t, StatCounters> gatherMasterEvents function, ", $time, fshow(e)));
    endaction;

    // demux function, based on module type
    function Action gatherModuleEvents(Get#(ModuleEvents) moduleEvents, Vector#(CountersPerModules, Array#(Reg#(UInt#(8)))) moduleCounter) = action
        ModuleEvents e <- moduleEvents.get;
        case (e) matches
            tagged CacheCore_E .cce : begin
                gatherCacheEvents(cce, moduleCounter);
            end
            tagged MIPSMem_E .mme : begin
                gatherMIPSEvents(mme, moduleCounter);
            end
            tagged Master_E .me : begin
                gatherMasterEvents(me, moduleCounter);
            end
        endcase
    endaction;

    // module rules
    ////////////////////////////////////////////////////////////////////////////

    rule initialize(state == Init);
        debug2("StatCounters", $display("<time %0t, StatCounters> fire initialize rule (initCount = %0d)", $time, initCount));
        mem.write(unpack(pack(initCount)), 0);
        getCounter(unpack(pack(initCount))) <= 0;
        initCount <= initCount + 1;
        if (initCount == fromInteger(valueof(TSub#(TMul#(no_of_modules,CountersPerModules),1)))) begin
            debug2("StatCounters", $display("<time %0t, StatCounters> initialize rule, stat <= Ready", $time));
            state <= Ready;
        end
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule gatherEvents (state == Ready);
        debug2("StatCounters", $display("<time %0t, StatCounters> fire gatherEvents rule", $time));
        zipWithM_ ( gatherModuleEvents, moduleEvents, counters );
    endrule

    (* fire_when_enabled *)
    rule accessMemory_stage_2 (state == Ready);
        let data <- mem.read.get();
        match {.idx, .send_rsp, .send_valid_rsp} <- toGet(memAccessFifo).get();
        let cnt = getCounter(idx);
        let new_data = data + zeroExtend(cnt);
        debug2("StatCounters", $display("<time %0t, StatCounters> stage2 rule - update BRAM counter %0d <= %0d", $time, idx, new_data));
        // update stat counter internal state internal ...
        mem.write(idx, new_data); // ... by updating the block ram
        cnt <= 0; // ... and reseting the register
        if (send_rsp)begin
            // handle response FIFO
            let the_rsp = tagged Invalid;
            if (send_valid_rsp) begin
                the_rsp = tagged Valid pack(new_data);
            end
            debug2("StatCounters", $display("<time %0t, StatCounters> stage2 - send response ", $time, fshow(the_rsp)));
            rsp.enq(the_rsp);
        end
    endrule

    (* fire_when_enabled *)
    rule accessMemory_stage_1 (state == Ready);
        debug2("StatCounters", $display("<time %0t, StatCounters> stage1 rule", $time));
        UInt#(cnt_idx_w) idx = refreshCount;
        Bool send_valid_rsp = False;
        Bool resetReq = False;
        Maybe#(StatCountersReq) mop = req_wire.wget();
        StatCountersReq op = fromMaybe(tagged Nop, mop);
        case (op) matches
            tagged Nop : begin
                debug2("StatCounters", $display("<time %0t, StatCounters> stage1 - nop, refreshCount %0d", $time, refreshCount));
                if (refreshCount == fromInteger(valueof(TSub#(TMul#(no_of_modules,CountersPerModules),1)))) begin
                    refreshCount <= 0;
                end
                else refreshCount <= refreshCount + 1;
            end
            tagged ResetAll: begin
                resetReq = True;
                debug2("StatCounters", $display("<time %0t, StatCounters> stage1 - reset", $time));
            end
            tagged Read .ss: begin
                send_valid_rsp = True;
                idx = getCounterIdx(ss);
                debug2("StatCounters", $display("<time %0t, StatCounters> stage1 - read, selecting module %0d, counter %0d (cnt_idz %0d)", $time, ss.moduleSelector, ss.counterSelector, idx));
            end
        endcase
        if (isValid(mop)) resetFIFO.enq(resetReq);
        mem.read.put(idx);
        memAccessFifo.enq(tuple3(idx, isValid(mop), send_valid_rsp));
        debug2("StatCounters", $display("<time %0t, StatCounters> stage1 - memAccess idx:%0d, send_rsp:%0d, send_valid_rsp:%0d", $time, idx, isValid(mop), send_valid_rsp));
    endrule

    interface Put request;
        method Action put (StatCountersReq req) if (state == Ready) = action
            debug2("StatCounters", $display("<time %0t, StatCounters> put request ", $time, fshow(req)));
            req_wire.wset(req);
        endaction;
    endinterface

    interface response = toGet (rsp);

    method Action commitReset(Bool c) = action
        debug2("StatCounters", $display("<time %0t, StatCounters> commitReset called with ", $time,fshow(c)));
        // handle reset FIFO
        Bool r <- toGet(resetFIFO).get();
        if (r == True && c == True) begin
            debug2("StatCounters", $display("<time %0t, StatCounters> ===> performing reset <===", $time));
            initCount <= 0;
            state <= Init;
        end
    endaction;

endmodule
