/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2013 Alex Horsman
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

import MIPS::*;
import MemTypes::*;
import DefaultValue::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import MEM::*;
import ConfigReg::*;
import Assert::*;
import Debug::*;
import MasterSlave::*;
import GetPut::*;

typedef struct {
    Bit#(tag_size) tag;
    Bit#(index_size) index;
    Bit#(offset_size) offset;
} PAddrT#(  numeric type tag_size,
            numeric type index_size,
            numeric type offset_size) deriving (Bits, Eq);

typedef struct {
    Bit#(tag_size) tag;
    `ifdef CAP
    Bool capability;
    `endif
    Bool valid;
} TagT#(numeric type tag_size) deriving (Bits, Eq);

typedef union tagged {
    UInt#(nb_ways_size) CachedMiss;
    void UncachedMiss;
} MissReqT#(numeric type nb_ways_size) deriving (Bits);

typedef enum {Init, Serving, Miss
    `ifdef MULTI
    , StoreConditional
    `endif
} CacheState deriving (Bits, Eq);

module mkGenericDCache#(Bit#(16) coreId) (CacheDataIfc#(nb_ways, sets_per_way, bytes_per_line))
    provisos (
            Bits#(PhyAddress, paddr_size),
            Log#(nb_ways, nb_ways_size),
            Log#(bytes_per_line, offset_size),
            Log#(sets_per_way, index_size),
            Add#(TAdd#(tag_size, index_size), offset_size, paddr_size),
            Mul#(bytes_per_line, 8, line_size),
            Add#(line_size, 0, 256)
        );

`define TagMEM MEM#(Bit#(index_size),TagT#(tag_size))
`define DataMEM MEM#(Bit#(index_size), Bit#(line_size))

    // requests fifo
    FIFO#(CacheRequestDataT)                    req_fifo        <-  mkLFIFO;
    // response fifo
    FIFO#(CacheResponseDataT)                   rsp_fifo        <-  mkBypassFIFO;
    // commit fifo
    FIFOF#(Bool)                                commit_fifo     <-  mkSizedBypassFIFOF(4);
    // miss fifo
    FIFO#(MissReqT#(nb_ways_size))              miss_req_fifo   <-  mkFIFO;
    // invalidate requests fifo
    FIFOF#(PAddrT#(tag_size, index_size, offset_size))
                                                inval_fifo      <-  mkSizedFIFOF(20);
    // memory interface request fifo
    FIFOF#(CheriMemRequest)                     mem_req_fifo    <-  mkFIFOF;
    // memory interface response fifo
    FIFOF#(CheriMemResponse)                    mem_rsp_fifo    <-  mkFIFOF;
    // counter used to initialize the icache
    Reg#(Bit#(index_size))                      initCount       <-  mkReg(0);
    // icache state register
    Reg#(CacheState)                            cacheState      <-  mkConfigReg(Init);

    // MEMs
    // Tag MEMs
    Vector#(nb_ways, `TagMEM)
    tags <- replicateM(mkMEM);
    Vector#(nb_ways, Vector#(sets_per_way, Reg#(TagT#(tag_size))))
    tagsDebug <- replicateM(replicateM(mkReg(TagT{
                                                valid : False,
                                                `ifdef CAP
                                                capability: ?,
                                                `endif
                                                tag : ?
                                            })));
    // Data MEMs
    Vector#(nb_ways, `DataMEM)
    data <- replicateM(mkMEM);

    // invalid tag
    TagT#(tag_size) tagInvalid = TagT {
        `ifdef CAP
        capability: ?,
        `endif
        tag:   ?,
        valid: False
    };

    //////////////////////////////////////////////
    // utils function to easily access the MEMs //
    //////////////////////////////////////////////
    // sends a write request to the tag MEM for a single way
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
    function Action writeDebugTag ( Bit#(index_size) windex,
                                    TagT#(tag_size) wdata,
                                    Vector#(sets_per_way, Reg#(TagT#(tag_size))) wayTagDebug);
        action
            wayTagDebug[windex] <= wdata;
        endaction
    endfunction
    // sends a read request to the tag MEM for a single way
    function Action lookupTag ( Bit#(index_size) rindex,
                                `TagMEM wayTagMEM);
        action
            wayTagMEM.read.put(rindex);
        endaction
    endfunction
    // sends a read request to the data MEM for a single way
    function Action lookupData ( Bit#(index_size) rindex,
                                `DataMEM wayDataMEM);
        action
            wayDataMEM.read.put(rindex);
        endaction
    endfunction

    /////////////////////
    // Eviction policy //
    /////////////////////

    // TODO implement better replacement policy
    // select a victim way by returning a way number
    Reg#(UInt#(nb_ways_size)) nextVictimWay <- mkReg(0);
    function ActionValue#(UInt#(nb_ways_size)) selectVictimWay
    (Vector#(nb_ways, TagT#(tag_size)) tags_vector);
        function Bool isTagInvalid(TagT#(tag_size) tag) = !tag.valid;
        return actionvalue
            case (findIndex(isTagInvalid, tags_vector)) matches
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

    // Sets every valid bit to False in the tags MEM
    rule do_initialize (cacheState == Init);
        mapM_(writeTag(pack(initCount), tagInvalid), tags);
        mapM_(writeDebugTag(pack(initCount), tagInvalid), tagsDebug);
        initCount <= initCount + 1;
        debug2("dcache", $display("<time %0t, core %0d, DCache> Initializing set#%0d (each way)", $time, coreId, initCount));
        if (initCount == fromInteger(valueOf(TSub#(sets_per_way,1))))
            cacheState <= Serving;
    endrule

    // fire in Serving state with priority over getResponse method so that an
    // invalidate request matching a miss request will effectively invalidate
    // the miss response before it can be fed back to the main pipeline
    `ifdef MULTI
    rule do_inval ((cacheState == Serving || cacheState == StoreConditional) && inval_fifo.notEmpty);
    `else
    rule do_inval (cacheState == Serving && inval_fifo.notEmpty);
    `endif
        // Invalidate the indexed set in all the ways
        // dequeues the inval_fifo
        PAddrT#(tag_size, index_size, offset_size) addr = inval_fifo.first;
        mapM_(writeTag(addr.index, tagInvalid), tags);
        mapM_(writeDebugTag(addr.index, tagInvalid), tagsDebug);
        inval_fifo.deq();
        debug2("dcache", $display("<time %0t, core %0d, DCache> Invalidate set#%0d (each way)", $time, coreId, addr.index));
    endrule

    rule do_req (cacheState == Serving && !inval_fifo.notEmpty);

        // function to deal with MEM outputs (used to be mapped over vector of ways)
        function ActionValue#(TagT#(tag_size)) readTag(`TagMEM  wayTagMEM)
            = wayTagMEM.read.get;
        function ActionValue#(Bit#(line_size)) readData(`DataMEM wayDataMEM)
            = wayDataMEM.read.get;
        function Bool   hitOn(Bit#(tag_size) value, TagT#(tag_size) tag_entry)
            = (( value == tag_entry.tag) && tag_entry.valid);

        // initialize some variables
        CacheRequestDataT                   req         = req_fifo.first;
        PAddrT#(tag_size, index_size, offset_size) addr = unpack(pack(req.tr.addr));
        Vector#(nb_ways, TagT#(tag_size))   tagRead     <- mapM(readTag, tags);
        Vector#(nb_ways, Bit#(line_size))   dataRead    <- mapM(readData, data);
        Vector#(nb_ways, Bool)              hitVect     = map(hitOn(addr.tag), tagRead);
        Bool                                hit         = \or (hitVect);
        Maybe#(UInt#(nb_ways_size))         wayHit      = findElem(True, hitVect);
        Bool                                cached      = req.tr.cached;

        debug2("dcache", $display("<time %0t, core %0d, DCache> Serving ", $time, coreId, fshow(req)));
        dynamicAssert(countElem(True, hitVect) <= 1, "There shouldn't be more than one tag match");

        // get the data and prepare the response
        TagT#(tag_size) hitTag  = tagRead[fromMaybe(0,findElem(True,hitVect))];
        Bit#(line_size) hitData = dataRead[fromMaybe(0,findElem(True,hitVect))];
        Bool exception = !commit_fifo.first;
        if (!exception) exception = (req.tr.exception != None); // If we didn't have an exception already, we may have one from the TLB.
        commit_fifo.deq; // dequeues the commit fifo
        CacheResponseDataT resp = CacheResponseDataT {
                                    data: ?,
                                    `ifdef CAP
                                    capability: False,
                                    `endif
                                    exception: req.tr.exception
        };

        `ifdef MULTI
        // A load linked causes the cache to miss so that the shared L2Cache is accessed
        if (req.tr.ll) begin
            cached = False;
        end
        `endif

        // check the request type
        case (req.cop.inst)
            // in case of a read command
            Read : begin
                cycReport($display("[$DL1R%s]", (hit)?"H":"M"));
                // In case of exception (from TLB or WriteBack stage)
                if (exception) begin
                    debug2("dcache", $display("<time %0t, core %0d, DCache> TLB / WriteBack stage exception", $time, coreId));
                    // consume the request by dequeing the request fifo
                    req_fifo.deq;
                    // set the response data to 0, exception field is already set
                    resp.data = tagged Line 0;
                    // enqueue the response
                    rsp_fifo.enq(resp);
                end
                // In case of cached read hit
                else if (cached && hit) begin
                    `ifdef CAP
                    // set the response capability field
                    resp.capability = hitTag.capability;
                    if (resp.capability && req.tr.noCapLoad && resp.exception == None) begin
                        resp.exception = CTLBL;
                        exception = True; // make sure exception is True (might not be used)
                    end
                    `endif
                    // set the response data to the hit data
                    resp.data = tagged Line hitData;
                    // consume the request by dequeing the request fifo
                    req_fifo.deq;
                    // enqueue the response
                    rsp_fifo.enq(resp);
                end
                // Other case : miss or uncached read
                else begin
                    MissReqT#(nb_ways_size) miss_req;
                    if (cached) begin
                        // prepare a Cached miss request and elect the victim way
                        UInt#(nb_ways_size) selectedWay <- selectVictimWay(tagRead);
                        miss_req = tagged CachedMiss selectedWay;
                    end else begin
                        // prepare an Uncached miss request
                        miss_req = tagged UncachedMiss;
                    end
                    // enqueue the miss request and go to Miss state
                    miss_req_fifo.enq(miss_req);
                    cacheState <= Miss;
                    // initialize byte enable for the memory request
                    Bit#(32) byteEnable = (cached) ? 32'hFFFFFFFF : req.byteEnable;
                    `ifdef MULTI
                    // reset the cached variable to True for the actual memory request
                    if (req.tr.ll) begin
                        cached = True;
                    end
                    `endif
                    // send the memory request
                    function BytesPerFlit memSizeTobpf(MemSize m);
                        return case (m) matches
                            Byte : BYTE_1;
                            HalfWord: BYTE_2;
                            Word: BYTE_4;
                            DoubleWord: BYTE_8;
                            //: BYTE_16;
                            Line: BYTE_32;
                        endcase;
                    endfunction
                    CheriMemRequest mem_req = defaultValue;
                    mem_req.addr = unpack(req.tr.addr);
                    mem_req.masterID = unpack(truncate({coreId,1'b1}));
                    mem_req.operation = tagged Read {
                                          uncached: ! cached,
                                          linked: req.tr.ll,
                                          noOfFlits: 0,
                                          bytesPerFlit: (cached) ? BYTE_32 : memSizeTobpf(req.memSize)
                                        };
                    mem_req_fifo.enq(mem_req);
                    debug2("dcache", $display("<time %0t, core %0d, DCache> Sending ", $time, coreId, fshow(mem_req)));
                end
            end
            // in case of a write command
            Write : begin
                cycReport($display("[$DL1W%s]", (hit)?"H":"M"));
                // prepare updateData
                Vector#(bytes_per_line, Bit#(8)) reqData = unpack(pack(req.data));
                Vector#(bytes_per_line, Bit#(8)) updateData = unpack(pack(dataRead[fromMaybe(0, wayHit)]));
                Vector#(bytes_per_line, Bool) beVect = unpack(pack(req.byteEnable));
                for (Integer i = 0; i < valueOf(bytes_per_line); i=i+1) begin
                    if (beVect[i]) begin
                        updateData[i] = reqData[i];
                    end
                end
                `ifdef CAP
                if (req.capability && req.tr.noCapStore && resp.exception == None) begin
                    resp.exception = CTLBS;
                    exception = True;
                end
                `endif
                // prepare updateTag
                TagT#(tag_size) updateTag = tagRead[fromMaybe(0, wayHit)];
                // if there is no exception
                if (!exception) begin
                    // in case of cached write hit
                    if (cached && hit) begin
                        // update the local copy
                        data[fromMaybe(0, wayHit)].write(addr.index, pack(updateData));
                        `ifdef CAP
                        updateTag.capability = req.capability;
                        `endif
                        writeTag(addr.index, updateTag, tags[fromMaybe(0, wayHit)]);
                        writeDebugTag(addr.index, updateTag, tagsDebug[fromMaybe(0, wayHit)]);
                        debug2("dcache", $display("<time %0t, core %0d, DCache> Writing @0x%0x=0x%0x", $time, coreId, addr, updateData));
                    end
                    // in case of uncached write
                    else if (!cached) begin
                        // If it was a hit, but this is an uncached access, invalidate the line.
                        if (hit) begin
                            writeTag(addr.index, tagInvalid, tags[fromMaybe(0, wayHit)]);
                            writeDebugTag(addr.index, tagInvalid, tagsDebug[fromMaybe(0, wayHit)]);
                            debug2("dcache", $display("<time %0t, core %0d, DCache> Write hit, Invalidating set#%0d, way#%0d", $time, coreId, addr.index, fromMaybe(0, wayHit)));
                        end
                    end
                    // send the memory write request
                    CheriMemRequest mem_req = defaultValue;
                    mem_req.addr = unpack(pack(addr));
                    mem_req.masterID = unpack(truncate({coreId,1'b1}));
                    mem_req.operation = tagged Write {
                                          uncached: ! cached,
                                          conditional: False,
                                          byteEnable: unpack(req.byteEnable),
                                          data: Data{
                                            `ifdef CAP
                                            cap: unpack(pack(req.capability)),
                                            `endif
                                            data: req.data
                                          },
                                          last: True
                                        };
                    mem_req_fifo.enq(mem_req);
                    debug2("dcache", $display("<time %0t, core %0d, DCache> Sending ", $time, coreId, fshow(mem_req)));
                end
                // consume the request by dequeing the request fifo
                req_fifo.deq;
                // enqueue the response
                rsp_fifo.enq(resp);
            end
            `ifdef MULTI
            // in case of a store conditional command
            StoreConditional : begin
                cycReport($display("[$DL1SC%s]", (hit)?"H":"M"));
                `ifdef CAP
                if (req.capability && req.tr.noCapStore && resp.exception == None) begin
                    resp.exception = CTLBS;
                    exception = True;
                end
                `endif
                // If there hasn't been an exception, do the SC
                if (!exception) begin 
                    // send the memory conditional write request
                    CheriMemRequest mem_req = defaultValue;
                    mem_req.addr = unpack(pack(addr));
                    mem_req.masterID = unpack(truncate({coreId,1'b1}));
                    mem_req.operation = tagged Write {
                                          uncached: ! cached,
                                          conditional: True,
                                          byteEnable: unpack(req.byteEnable),
                                          data: Data{
                                            `ifdef CAP
                                            cap: unpack(pack(req.capability)),
                                            `endif
                                            data: req.data
                                          },
                                          last: True
                                        };
                    mem_req_fifo.enq(mem_req);
                    debug2("dcache", $display("<time %0t, core %0d, DCache> Sending ", $time, coreId, fshow(mem_req)));
                    // invalidate the line in case of hit TODO make this
                    // smarter (store the pending data to write on the sc
                    // response)
                    if (hit) begin
                        writeTag(addr.index, tagInvalid, tags[fromMaybe(0, wayHit)]);
                        writeDebugTag(addr.index, tagInvalid, tagsDebug[fromMaybe(0, wayHit)]);
                    end
                    // go to StoreConditional state
                    cacheState <= StoreConditional; 
                end  
                else begin 
                    // Store Conditional Fail   
                    // consume the request by dequeing the request fifo
                    req_fifo.deq;
                    // enqueue the response
                    resp.data = tagged Line 256'b0;  
                    rsp_fifo.enq(resp);
                end   
            end  
            `endif
            // in case of an other type of commad
            default : begin
                // check the targeted cache
                case (req.cop.cache)
                    // a data cache command
                    DCache : begin
                        // check the cache request type
                        case (req.cop.inst)
                            CacheInvalidate, CacheInvalidateWriteback: begin
                                // invalidate the tag for all the ways
                                mapM_(writeTag(addr.index, tagInvalid), tags);
                                mapM_(writeDebugTag(addr.index, tagInvalid), tagsDebug);
                            end
                            CacheNop: begin
                                // no memory operation
                            end
                            default :
                                dynamicAssert(False , "Unknown Data cache command");
                        endcase
                    end
                    // an L2 cache command
                    L2 : begin
                        // simply forward the request
                        CheriMemRequest mem_req = defaultValue;
                        mem_req.addr = unpack(pack(addr));
                        mem_req.masterID = unpack(truncate({coreId,1'b1}));
                        mem_req.operation = tagged CacheOp req.cop;
                        mem_req_fifo.enq(mem_req);
                        debug2("dcache", $display("<time %0t, core %0d, DCache> Sending ", $time, coreId, fshow(mem_req)));
                    end
                    // unknown cache targeted
                    default :
                        dynamicAssert(False , "Unknown cache targeted for a Cache operation");
                endcase
                // Cache instructions don't throw TLB exceptions.
                resp.exception = None;
                // consume the request by dequeing the request fifo
                req_fifo.deq;
                // enqueue the response
                rsp_fifo.enq(resp);
            end
        endcase
    endrule

    // get the memory response for misses or uncached read and go back to
    // Serving state.
    // This rule can only fire when in Miss state, and with both a miss
    // request and a memory response available, as well as with a non full
    // miss response fifo.
    // N.B. : the pipeline request is still in the request fifo, and the
    // miss response fifo has necessarily been emptied
    rule do_miss (cacheState == Miss);
        // init the addr variable
        PAddrT#(tag_size, index_size, offset_size) addr = unpack(req_fifo.first.tr.addr);
        // get the memory response
        CheriMemResponse bigResponse <- toGet(mem_rsp_fifo).get;
        debug2("dcache", $display("<time %0t, core %0d, DCache> Memory response ", $time, coreId, fshow(bigResponse)));
        case (bigResponse.operation) matches
            tagged Read .r : begin
                // prepare the miss response
                CacheResponseDataT miss_rsp = CacheResponseDataT {
                    `ifdef CAP
                    capability: unpack(pack(r.data.cap)),
                    `endif
                    data: tagged Line r.data.data,
                    exception: None
                };
                `ifdef CAP
                if (unpack(pack(r.data.cap)) && req_fifo.first.tr.noCapLoad) begin
                    miss_rsp.exception = CTLBL;
                end
                `endif
                // consume the request by dequeing the request fifo
                req_fifo.deq;
                // enqueue the response
                rsp_fifo.enq(miss_rsp);

                // get the miss request
                MissReqT#(nb_ways_size) miss_req <- toGet(miss_req_fifo).get;
                // check the miss request type
                case (miss_req) matches
                    // in case of cached miss response
                    tagged CachedMiss .victimWay : begin
                        debug2("dcache", $display("<time %0t, core %0d, DCache> Writing @0x%0x=0x%0x", $time, coreId, addr, r.data.data));
                        // do the cache update
                        data[victimWay].write(addr.index, unpack(r.data.data));
                        TagT#(tag_size) newTag = TagT {
                            `ifdef CAP
                            capability: unpack(pack(r.data.cap)),
                            `endif
                            tag: addr.tag,
                            valid: True
                        };
                        writeTag(addr.index, newTag, tags[victimWay]);
                        writeDebugTag(addr.index, newTag, tagsDebug[victimWay]);
                    end
                    default :
                        dynamicAssert(False , "Unknown miss request type");
                endcase
                // go back to Serving state
                cacheState <= Serving;
            end
            default : dynamicAssert(False, "Only read a read response is expected in DCache Miss state");
        endcase
    endrule

    `ifdef MULTI
    // Store conditional check write. It is the first of the two writes from MemAccess
    rule do_sc_response(cacheState == StoreConditional);
        // get the memory response
        CheriMemResponse bigResponse <- toGet(mem_rsp_fifo).get;
        case (bigResponse.operation) matches
            tagged SC .scop : begin
                debug2("dcache", $display("<time %0t, core %0d, DCache> Memory response ", $time, coreId, fshow(bigResponse)));
                // prepare the sc response
                CacheResponseDataT sc_rsp = CacheResponseDataT {
                    `ifdef CAP
                    capability: ?,
                    `endif
                    data: scop ? tagged Line 256'h1 : tagged Line 256'h0,
                    exception: None
                };
                // consume the request by dequeing the request fifo
                req_fifo.deq;
                // enqueue the response
                rsp_fifo.enq(sc_rsp); 
                // go back to Serving state
                cacheState <= Serving;
            end
            default : dynamicAssert(False, "Only read a read response is expected in DCache Miss state");
        endcase
    endrule
    `endif

    method Action put(CacheRequestDataT reqIn);
        PAddrT#(tag_size, index_size, offset_size) addr = unpack(pack(reqIn.tr.addr));
        // enqueue the request in the request fifo
        req_fifo.enq(reqIn);
        // submit lookup to MEMs
        mapM_(lookupTag(addr.index), tags);
        mapM_(lookupData(addr.index), data);
    endmethod

    method Action nextWillCommit(Bool nextCommitting);
        commit_fifo.enq(nextCommitting);
    endmethod


    method ActionValue#(CacheResponseDataT) getResponse();
        actionvalue
            CacheResponseDataT resp = rsp_fifo.first;
            rsp_fifo.deq;
            return resp;
        endactionvalue
    endmethod


    method Action invalidate(PhyAddress addr);
        // simply enqueue the inval request
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
                debugInst($display("DEBUG DCACHE TAG set#%3d way#%2d Valid=%x Tag=%x", i, j, tagsDebug[j][i].valid, tagsDebug[j][i].tag));
            end
        end
    endmethod

    interface Master memory;
        interface request   = toCheckedGet (mem_req_fifo);
        interface response  = toCheckedPut (mem_rsp_fifo);
    endinterface

`undef TagMEM
`undef DataMEM

endmodule
