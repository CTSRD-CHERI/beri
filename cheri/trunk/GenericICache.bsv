/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2013 Alex Horsman
 * Copyright (c) 2013, 2014 Alexandre Joannou
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

import Debug :: *;
import MasterSlave :: *;
import GetPut :: *;
import ConfigReg ::*;
import FIFO :: *;
import FIFOF :: *;
import SpecialFIFOs :: *;
import Vector :: *;
import MEM :: *;
import AsymmetricBRAM :: *;
import MemTypes :: *;
import DefaultValue :: *;
import Assert :: *;
import MIPS :: *;

typedef struct {
    Bit#(tag_size) tag;
    Bit#(index_size) index;
    Bit#(offset_size) offset;
} PAddrT#(  numeric type tag_size,
            numeric type index_size,
            numeric type offset_size) deriving (Bits, Eq);

typedef struct {
    Bit#(tag_width) tag;
    Bool            valid;
} TagT#(numeric type tag_width) deriving (Bits, Eq);

typedef enum {Init, Serving, MissRead} CacheState deriving (Bits, Eq);

module mkGenericICache#(Bit#(16) coreId) (CacheInstIfc#(nb_ways, sets_per_way, bytes_per_line))
        provisos(
            Bits#(PhyAddress, paddr_size),
            Log#(nb_ways, nb_ways_size),
            Log#(bytes_per_line, offset_size),
            Log#(sets_per_way, index_size),
            Add#(TAdd#(tag_size, index_size), offset_size, paddr_size),
            Mul#(bytes_per_line, 8, line_size),
            Add#(inst_size, 0, 32),
            Add#(line_size, 0, 256),
            Div#(line_size, inst_size, ratio),
            Log#(ratio, ratio_size),
            Div#(TMul#(sets_per_way, bytes_per_line), 4, data_bram_size),
            Log#(data_bram_size, data_index_size),
            Add#(index_size, offset_size, page_offset_size),
            Add#(tag_size, page_offset_size, paddr_size),
            Add#(index_size, ratio_size, data_index_size)
        );

//////////////////////////////////////////////////////////////
//
//               tag_width       index_size    offset_size
//            <--------------> <-------------> <----------->
//  paddr :  |      tag       |     index     |    offset   |
//            <-------------------------------------------->
//
//////////////////////////////////////////////////////////////

`define TagMEM MEM#(Bit#(index_size),TagT#(tag_size))
`define DataBRAM AsymmetricBRAM#(Bit#(data_index_size),Bit#(inst_size),Bit#(index_size),Bit#(line_size))

    // requests fifo
    FIFO#(CacheRequestInstT)                    req_fifo        <-  mkLFIFO;
    // responses fifo
    FIFO#(CacheResponseInstT)                   rsp_fifo        <-  mkBypassFIFO;
    // ivalidate requests fifo
    FIFOF#(PAddrT#(tag_size, index_size, offset_size))
                                                inval_fifo      <-  mkSizedFIFOF(20);
    // memory interface request fifo
    FIFOF#(CheriMemRequest)                     mem_req_fifo    <-  mkFIFOF1;
    // memory interface response fifo
    FIFOF#(CheriMemResponse)                    mem_rsp_fifo    <-  mkFIFOF;
    // selected victim way to write the new data in
    Reg#(UInt#(nb_ways_size))                   victimWay       <-  mkReg(0);
    // cached/uncached request sent
    Reg#(Bool)                                  cachedMiss      <-  mkRegU;
    // counter used to initialize the icache
    Reg#(Bit#(index_size))                      initCount       <-  mkReg(0);
    // icache state register
    Reg#(CacheState)                            cacheState      <-  mkConfigReg(Init);

    // MEMs
    // Tag MEMs
    Vector#(nb_ways, `TagMEM) tags <- replicateM(mkMEM);
    Vector#(nb_ways, Vector#(sets_per_way, Reg#(TagT#(tag_size))))
    tagsDebug <- replicateM(replicateM(mkReg(TagT{valid:False, tag: ?})));
    // Data BRAMs
    Vector#(nb_ways, `DataBRAM) data <- replicateM(mkAsymmetricBRAM(False,False));

    // invalid tag
    TagT#(tag_size) tagInvalid = TagT {
        tag:   ?,
        valid: False
    };

    ///////////////////////////////////////////////////
    // utils function to easily access the tag BRAMs //
    ///////////////////////////////////////////////////
    // sends a write request to the tag BRAM for a single way
    function Action writeTag (  Bit#(index_size) windex,
                                TagT#(tag_size) wdata,
                                `TagMEM wayTagMEM);
        action
            wayTagMEM.write(windex, wdata);
        endaction
    endfunction
    // writes to the tag debug vector for a single way
    // /!\ this is instantaneous whereas the actual write of
    // the MEM takes one cycle
    function Action writeDebugTag (
        Bit#(index_size) windex,
        TagT#(tag_size) wdata,
        Vector#(sets_per_way, Reg#(TagT#(tag_size))) wayTagDebug)
        = action wayTagDebug[windex] <= wdata; endaction;
    // sends a read request to the tag MEM for a single way
    function Action readTag (Bit#(index_size) rindex,`TagMEM wayTagMEM)
        = wayTagMEM.read.put(rindex);
    // gets the read response of the tag MEM for a single way
    function ActionValue#(TagT#(tag_size)) getReadTag (`TagMEM wayTagMEM)
        = wayTagMEM.read.get();
    // tag invalidate wrapper functions
    // TODO, use the tag information to select one single way
    function Action invalTag (Bit#(index_size) inval_index,`TagMEM wayTagMEM)
        = writeTag(inval_index, TagT{valid: False, tag: ?}, wayTagMEM);
    function Action invalDebugTag (
        Bit#(index_size) inval_index,
        Vector#(sets_per_way, Reg#(TagT#(tag_size))) wayTagDebug)
        = writeDebugTag(inval_index, TagT{valid: False, tag: ?}, wayTagDebug);

    ////////////////////////////////////////////////////
    // utils function to easily access the data BRAMs //
    ////////////////////////////////////////////////////
    // sends a write request to the data BRAM for a single way
    function Action writeData ( Bit#(index_size) windex,
                                Bit#(line_size) wdata,
                                `DataBRAM wayDataBRAM);
        action
            wayDataBRAM.write(windex, wdata);
        endaction
    endfunction
    // sends a read request to the data BRAM for a single way
    function Action readData (  Bit#(data_index_size) rindex,
                                `DataBRAM wayDataBRAM);
        action
            wayDataBRAM.read(rindex);
        endaction
    endfunction
    // gets the read response of the data BRAM for a single way
    function ActionValue#(Bit#(32)) getReadData (`DataBRAM wayDataBRAM);
        actionvalue
            Bit#(32) ret_data <- wayDataBRAM.getRead();
            return ret_data;
        endactionvalue
    endfunction

    /////////////////////
    // Utils functions //
    /////////////////////
    // get the tag from a physical address
    function Bit#(tag_size) getTag(PhyAddress paddr);
        return paddr[valueOf(paddr_size)-1:valueOf(page_offset_size)];
    endfunction

    // get the index from a physical address
    function Bit#(index_size) getIndex(PhyAddress addr);
        return addr[valueOf(TAdd#(offset_size,index_size))-1:valueOf(offset_size)];
    endfunction

    // get the offset from a physical address
    /*
    function Bit#(offset_size) getOffset(PhyAddress addr);
        return addr[valueOf(offset_size)-1:0];
    endfunction
    */

    /////////////////////
    // Eviction policy //
    /////////////////////

    // TODO implement better replacement policy
    // select a victim way by returning a way number
    Reg#(UInt#(nb_ways_size)) nextVictimWay <- mkReg(0);
    function ActionValue#(UInt#(nb_ways_size)) selectVictimWay
    (Vector#(nb_ways, TagT#(tag_size)) tags_vector);
        function Bool tagInvalid(TagT#(tag_size) tag) = !tag.valid;
        return actionvalue
            case (findIndex(tagInvalid, tags_vector)) matches
                tagged Valid .x: begin
                    return x;
                end
                tagged Invalid: begin
                    nextVictimWay <= nextVictimWay + 1;
                    return nextVictimWay;
                end
            endcase
        endactionvalue;
    endfunction

    ////////////////////
    // internal rules //
    ////////////////////

    // Sets every valid bit to False in the tags MEM
    rule initialize(cacheState == Init);

        function Action initTag(`TagMEM wayTagMEM) =
        writeTag(pack(initCount), TagT{valid:False, tag: ?}, wayTagMEM);

        debug2("icache", $display("<time %0t, core %0d, ICache> Initializing set#%0d (each way)", $time, coreId, initCount));
        mapM_(initTag, tags);
        initCount <= initCount + 1;
        if (initCount == fromInteger(valueOf(TSub#(sets_per_way,1))))
            cacheState <= Serving;
    endrule

    (* descending_urgency = "doRead, doCacheInstructions, doInvalidate" *)
    rule doInvalidate(cacheState == Serving && inval_fifo.notEmpty);
        // Invalidate the indexed set in all the ways
        // dequeues the inval_fifo
        // TODO - check in what field of the received address the index is
        PAddrT#(tag_size, index_size, offset_size) addr = inval_fifo.first;
        mapM_(writeTag(addr.index, tagInvalid), tags);
        mapM_(writeDebugTag(addr.index, tagInvalid), tagsDebug);
        inval_fifo.deq();
        debug2("icache", $display("<time %0t, core %0d, ICache> Invalidate set#%0d (each way)", $time, coreId, addr.index));
    endrule

    rule doCacheInstructions(cacheState == Serving && req_fifo.first.cop.inst != Read && !inval_fifo.notEmpty);
        // get the index from the virtual address
        Bit#(index_size) index = getIndex(req_fifo.first.tr.addr);
        case (req_fifo.first.cop.inst)
            CacheInvalidate, CacheInvalidateWriteback: begin
                // Invalidate the indexed set in all the ways
                mapM_(invalTag(index), tags);
                mapM_(invalDebugTag(index), tagsDebug);
                debug2("icache", $display("<time %0t, core %0d, ICache> Invalidate set#%0d (each way)", $time, coreId, index));
            end
        endcase
        // consume the request
        req_fifo.deq;
    endrule

    rule doRead(cacheState == Serving && req_fifo.first.cop.inst == Read && !inval_fifo.notEmpty);

        function Bool hitOn(Bit#(tag_size) value, TagT#(tag_size) tag_entry);
            return (( value == tag_entry.tag) && tag_entry.valid);
        endfunction

        // initialize variables
        CacheRequestInstT                   req         =   req_fifo.first;
        PhyAddress                          addr        =   req.tr.addr;
        Vector#(nb_ways, TagT#(tag_size))   tagRead     <-  mapM(getReadTag, tags);
        Vector#(nb_ways, Bit#(32))          dataRead    <-  mapM(getReadData, data);
        Vector#(nb_ways, Bool)              wayHit      =   map(hitOn(getTag(addr)), tagRead);
        Bool                                hit         =   \or (wayHit);
        CacheResponseInstT                  resp        =   CacheResponseInstT{inst: ?, exception: None};
 
        debug2("icache", $display("<time %0t, core %0d, ICache> Serving ", $time, coreId, fshow(req)));
        if (req.tr.exception != None) begin // In case of TLB miss, return the exception
            debug2("icache", $display("<time %0t, core %0d, ICache> TLB Miss, returning exception", $time, coreId));
            resp.exception = req.tr.exception;
            resp.inst = classifyMIPSInstruction(32'b0);
            rsp_fifo.enq(resp);
            req_fifo.deq;
        end
        else begin // There is no exception in the incomming request
            cycReport($display("[$IL1%s]", (hit)?"H":"M"));
            if (hit && req.tr.cached) begin // In case of hit on a cached read
                // return data from the appropriate way and consume the request
                
                //TODO check that there is only a single 1 in hit vector ?
                //dynamicAssert(Bool b, String s);
                Vector#(4,Bit#(8)) hitData = unpack(dataRead[fromMaybe(0,findElem(True,wayHit))]);
                resp.inst = classifyMIPSInstruction(pack(Vector::reverse(hitData)));
                rsp_fifo.enq(resp);
                req_fifo.deq;
            end
            else if (!hit && req.tr.cached) begin // In case of miss on a cached read
                // send a cache line request to main memory
                CheriMemRequest mem_req = defaultValue;
                mem_req.addr = unpack(pack(addr));
                mem_req.masterID = unpack(truncate({coreId,1'b0}));
                mem_req.operation = tagged Read {
                                      uncached: False,
                                      linked: False,
                                      noOfFlits: 0,
                                      bytesPerFlit: BYTE_32
                                    };
                mem_req_fifo.enq(mem_req);
                debug2("icache", $display("<time %0t, core %0d, ICache> Sending ", $time, coreId, fshow(mem_req)));
                // select a way to write the memory response
                UInt#(nb_ways_size) selectedWay <- selectVictimWay(tagRead);
                // invalidate the victim
                invalTag(getIndex(req_fifo.first.tr.addr), tags[selectedWay]);
                invalDebugTag(getIndex(req_fifo.first.tr.addr), tagsDebug[selectedWay]);
                // go to MissRead state
                victimWay   <= selectedWay;
                cachedMiss  <= True;
                cacheState  <= MissRead;
            end
            else if (!req.tr.cached) begin // In case of uncached read
                // send a word request
                CheriMemRequest mem_req = defaultValue;
                mem_req.addr = unpack(pack(addr));
                mem_req.masterID = unpack(truncate({coreId,1'b0}));
                mem_req.operation = tagged Read {
                                      uncached: True,
                                      linked: False,
                                      noOfFlits: 0,
                                      bytesPerFlit: BYTE_4
                                    };
                mem_req_fifo.enq(mem_req);
                debug2("icache", $display("<time %0t, core %0d, ICache> Sending ", $time, coreId, fshow(mem_req)));
                // go to MissRead state
                cachedMiss  <= False;
                cacheState  <= MissRead;
            end
        end
    endrule

    rule getMemoryResponse (cacheState == MissRead);
        let addr = req_fifo.first.tr.addr;
        // prepare the response, and get the memory response
        CacheResponseInstT resp = CacheResponseInstT{inst: ?, exception: None};
        CheriMemResponse bigResponse = mem_rsp_fifo.first;
        mem_rsp_fifo.deq;
        case (bigResponse.operation) matches
            tagged Read .r : begin
                // fill the response with the instruction and enqueues it
                Vector#(8, Bit#(32)) line = unpack(pack(r.data.data));
                Vector#(4, Bit#(8)) instruction_bits = unpack(pack(line[addr[4:2]]));
                resp.inst = classifyMIPSInstruction(pack(Vector::reverse(instruction_bits)));
                rsp_fifo.enq(resp);
                // consume the request
                req_fifo.deq;
                // in case of a cached miss, need to write the data to the cache
                if (cachedMiss) begin
                    Bit#(index_size) write_addr = getIndex(addr);
                    writeTag(write_addr, TagT{valid: True, tag: getTag(addr)}, tags[victimWay]);
                    writeDebugTag(write_addr, TagT{valid: True, tag: getTag(addr)}, tagsDebug[victimWay]);
                    writeData(write_addr, r.data.data, data[victimWay]);
                    debug2("icache", $display("<time %0t, core %0d, ICache> Writing @0x%0x=0x%0x", $time, coreId, write_addr, r.data.data));
                end
                // jump back to serving state
                cacheState <= Serving;
            end
            default : dynamicAssert(False, "Only a read response is expected in ICache MissRead State");
        endcase
    endrule

    ///////////////////////
    // Interface methods //
    ///////////////////////

    method Action put(reqIn) if (cacheState == Serving);
        Bit#(data_index_size) data_index = pack(reqIn.tr.addr)[valueOf(TAdd#(index_size,offset_size))-1:2];
        case (reqIn.cop.inst)
            Read, Write: begin
                // start the lookup in every ways
                mapM_(readTag(truncateLSB(data_index)), tags);
                mapM_(readData(data_index), data);
                // enqueue the request
                req_fifo.enq(reqIn);
            end
            CacheInvalidate, CacheInvalidateWriteback: begin
                // enqueue the request (no lookup)
                req_fifo.enq(reqIn);
            end
        endcase
    endmethod

    method ActionValue#(CacheResponseInstT) getRead();
        debug2("icache", $display("<time %0t, core %0d, ICache> Returning response ", $time, coreId, fshow(rsp_fifo.first)));
        // dequeue the response fifo
        rsp_fifo.deq;
        return rsp_fifo.first;
    endmethod

    method Action invalidate(PhyAddress addr);
        inval_fifo.enq(unpack(pack(addr)));
    endmethod

    method L1ChCfg getConfig();
        return L1ChCfg{ a: fromInteger(valueOf(nb_ways)-1),
                        l: fromInteger(valueOf(TLog#(bytes_per_line))-1),
                        s: (valueOf(sets_per_way)==32) ?
                            7 :
                            fromInteger(valueOf(TLog#(sets_per_way))-6)};
    endmethod

    method Action debugDump();
        for (Integer i=0; i<valueOf(sets_per_way); i=i+1) begin
            for (Integer j=0; j<valueOf(nb_ways); j=j+1) begin
                debugInst($display("DEBUG ICACHE TAG set#%3d way#%2d Valid=%x Tag=%x", i, j, tagsDebug[j][i].valid, tagsDebug[j][i].tag));
            end
        end
    endmethod

    interface Master memory;
        interface request   = toCheckedGet (mem_req_fifo);
        interface response  = toCheckedPut (mem_rsp_fifo);
    endinterface

`undef TagMEM
`undef DataBRAM

endmodule
