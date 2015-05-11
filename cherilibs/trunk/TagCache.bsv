/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Philip Withnall
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2014 Alexandre Joannou
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
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

import List::*;
import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import GetPut::*;
import MasterSlave::*;
import Vector::*;
import Debug::*;
import Library::*;
import ConfigReg::*;
import MEM :: * ;
import MemTypes::*;
import DefaultValue::*;
import Assert::*;

/******************************************************************************
 * mkTagCache
 *
 * This module provides a proxy for memory accesses which adds support for
 * tagged memory. It connects to memory on one side and the processor/L2 cache
 * on the other. Tag values are stored in memory (currently at the top of DRAM
 * and there is a cache of 16ki tags (512kB memory) stored in BRAM. Read
 * responses are amended with the correct tag value and write requests update
 * the value in the tag cache (which is later written back to memory).
 *
 * To explain the numbers used as indicies into the address it helps to think
 * of the original 40-bit address divided up like so:
 *
 * 39     32 31         19 18    11 10   5 4    0
 * +---------------------------------------------+
 * |  oob   |    tag      | index  | word | byte |
 * +---------------------------------------------+
 *
 * oob:    8 bits for addresses outside 4GB range where tags are supported
 * tag:   13 bit cache tag stored in the tag BRAM
 * index:  8 bit index into cache
 * word:   6 bit index into 64-bit line giving tag for 256-bit word
 * byte:   5 bit byte index into a 256-bit word
 *****************************************************************************/

typedef enum {Init, Serving, MissStart, MissRead, MissData} CacheState deriving (Bits, Eq);
typedef enum {TagCache, Processor} MemReqSource deriving (Bits, Eq);

typedef struct {
    Bit#(8)  oob;
    Bit#(13) tag;
    Bit#(8)  index;
    Bit#(6)  word;
    Bit#(5)  byteOffset;
} TagCacheAddr deriving (Bits, Eq, Bounded, FShow);

typedef struct {
  Bit#(13)  tag;
  Bool    valid;
  Bool    dirty;
} TagT deriving (Bits, Eq, Bounded, FShow);

typedef struct {
  TagT          tag;
  TagCacheAddr  addr;
  Bit#(64)      data;
} EvictionT deriving (Bits, Eq, Bounded, FShow);

interface TagCacheIfc;
  interface Slave#(CheriMemRequest, CheriMemResponse) cache;
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
endinterface

(*synthesize*)
module mkTagCache(TagCacheIfc);
  // FIFO containing the current in progress request
  FIFOF#(CheriMemRequest)            preReq_fifo     <- mkBypassFIFOF;
  FIFO#(CheriMemRequest)             req_fifo        <- mkLFIFO;

  // BRAMs containing cache tags and data (i.e. cached tags!)
  MEM#(Bit#(8), TagT)             tags            <- mkMEM;
  MEM#(Bit#(8), Bit#(64))         data            <- mkMEM;

  FIFO#(Bool)                     tag_out_fifo    <- mkSizedFIFO(8);
  FIFOF#(CheriMemResponse)           sendResp_fifo   <- mkBypassFIFOF;
  FIFOF#(CheriMemResponse)            mem_out_fifo   <- mkFIFOF;

  TagT invalidTag = TagT{valid: False, tag: 0, dirty: False};
  EvictionT invalidEviction = EvictionT{tag: invalidTag, addr: ?, data: ?};
  Reg#(EvictionT)                 eviction        <- mkReg(invalidEviction);

  // FIFO of requests going to the memory interface
  FIFOF#(CheriMemRequest)            memReq_fifo     <- mkFIFOF;
  // FIFO recording whether the last memory request was for the data or the tag cache
  FIFO#(MemReqSource)             nextMemSource   <- mkSizedFIFO(8);
  // FIFO for memory responses containing tags
  FIFOF#(CheriMemResponse)           preRespQ_fifo   <- mkBypassFIFOF;
  FIFOF#(CheriMemResponse)           cache_respQ     <- mkBypassFIFOF;

  Reg#(CacheState)                cacheState      <- mkConfigReg(Init);
  Reg#(Bit#(8))                   count           <- mkConfigReg(0);

`ifndef NOTAG
  rule initialize(cacheState == Init);
    tags.write(pack(count), invalidTag);
    if (count == 255) begin
      cacheState <= Serving;
      count <= 0;
    end else count <= count + 1;
  endrule

  // Only start the lookup when there aren't any more active requests, ie, let a burst go through in sequence.
  (* descending_urgency = "writeBackEviction, getCheriMemResponse, sendMissDataRequest" *)
  rule getCheriMemResponse(cacheState == Serving);
    let req = req_fifo.first;
    TagCacheAddr addr = unpack(pack(req.addr));
    let tagRead  <- tags.read.get();
    let dataRead <- data.read.get();

    // Only track tags for the bottom 4GB for now.  Return 0 otherwise.
    // Currently the cache system will allow tags to be valid for higher addresses until
    // they are evicted, but we will drop them here since we don't have storage for them.
    Bool outOfBound = addr.oob != 0;
    Bool hit = addr.tag == tagRead.tag && tagRead.valid;
    // Check the old victim value to see if it's a hit before going to memory.
    Bool hitVictim = addr.index == eviction.addr.index && addr.tag == eviction.tag.tag && eviction.tag.valid;

    if (!hit && !outOfBound && tagRead.valid)
      begin
        let evicted = EvictionT{
                tag: tagRead,
                data: dataRead,
                addr: unpack({8'h0,tagRead.tag,addr.index,11'h0})
            };
        debug2("tcache", $display("TagCache: addr %x miss, victim buf <= ", addr, fshow(evicted)));
        eviction <= evicted;
      end
    if (hitVictim && !hit && !outOfBound)
      begin
        // Swap the victim buffer with the current read since it will be overwritten.
        debug2("tcache", $display("TagCache: addr %x hit in victim buf", addr, fshow(eviction)));
        // Old values of the victim!
        dataRead = eviction.data;
        tagRead = eviction.tag;
        hit = True;
      end

    cycReport($display("[$T%s%s]", req.operation matches tagged Read .* ?"R":"W",(hit)?"H":"M"));

    if (hit || outOfBound)
      begin // If it's a hit...
        req_fifo.deq;
        // send the data request to dram
        memReq_fifo.enq(req);
        debug2("tagcache", $display("<time %0t, TagCache> forward req:", $time, fshow(req)));
        case (req.operation) matches
          tagged Read .rop :
          begin
            nextMemSource.enq(Processor); // signal that the next response from memory is data, not tags
            Bool response = outOfBound ? False : dataRead[addr.word]==1'b1;
            tag_out_fifo.enq(response);
            debug2("tcache", $display("TagCache Read Hit! %x=%x response=%b", addr, dataRead, response));
          end
          tagged Write .wop &&& (!outOfBound) :
          begin // Else, do the the write.
            nextMemSource.enq(Processor); // signal that the next response from memory is data, not tags
            if (dataRead[addr.word] != pack(wop.data.cap))
              begin
                dataRead[addr.word] = pack(wop.data.cap);
                tagRead.dirty = True;
                debug2("tcache", $display("TagCache Write Hit! %x=%x (%d:=%b)", addr, dataRead, addr.word, wop.data.cap));
              end
          end
        endcase
        debug2("tcache", $display("TagCache: write back hit line %x <= %x", addr.index, dataRead, fshow(tagRead)));
        // Always write the new tags and data in case the victim was hit
        // and should replace the current entry.
        tags.write(addr.index  , tagRead);
        data.write(addr.index  , dataRead);
      end
    else
      begin // If it is a miss
        let tagAddr =  {16'h3F, pack(addr)[31:13], 5'h0};
        CheriMemRequest mem_req = defaultValue;
        mem_req.addr = unpack(tagAddr);
        mem_req.masterID = ?;
        mem_req.transactionID = ?;
        mem_req.operation = tagged Read {
                              uncached: False,
                              linked: False,
                              noOfFlits: 0,
                              bytesPerFlit: BYTE_32
                            };
        memReq_fifo.enq(mem_req);
        nextMemSource.enq(TagCache);
        cacheState <= MissRead;
        debug2("tcache", $display("TagCache request tag data at %x", $time, fshow(mem_req)));
      end
  endrule

  rule getDRAMResponse(cacheState == MissRead);
    let req = req_fifo.first;
    TagCacheAddr addr = unpack(pack(req.addr));
    CheriMemResponse resp <- toGet(cache_respQ).get;
    Vector#(4, Bit#(64)) words = ?;
    case (resp.operation) matches
        tagged Read .rop: words = unpack(rop.data.data);
        default: dynamicAssert(False, "only read responses are handled");
    endcase
    let word = words[pack(addr)[12:11]];

    debug2("tcache", $display("TagCache fill %x = %x ", addr, word, fshow(words), fshow(resp)));
    Bool response = word[addr.word] == 1'b1;
    Bool isDirty = False;
    case (req.operation) matches
        tagged Read .rop : begin
        tag_out_fifo.enq(response);
      end
      tagged Write .wop: begin // Else, do the the write.
        word[addr.word] = pack(wop.data.cap);
        isDirty = True;
      end
    endcase

    data.write(addr.index, word);
    TagT newTag = TagT{tag: addr.tag, valid: True, dirty: isDirty};
    tags.write(addr.index, newTag);
    debug2("tcache", $display("TagCache: write back filled line %x <= %x ", addr.index, word, fshow(newTag)));
    
    cacheState <= MissData;
  endrule

  rule sendMissDataRequest(cacheState == MissData);
    let req <- popFIFO(req_fifo);
    // send the data request to dram
    debug2("tagcache", $display("<time %0t, TagCache> forward req after miss: ", $time, fshow(req)));
    memReq_fifo.enq(req);
    nextMemSource.enq(Processor); // signal that the next response from memory is data, not tags
    cacheState <= Serving;
  endrule

  rule writeBackEviction(eviction.tag.valid && eviction.tag.dirty);
    EvictionT ev = eviction;
    TagCacheAddr addr = ev.addr;
    let wbAddr = {16'h3f, pack(addr)[31:13],5'h0};
    CheriMemRequest mem_req = defaultValue;
    mem_req.addr = unpack(wbAddr);
    mem_req.masterID = ?;
    mem_req.transactionID = ?;
    mem_req.operation = tagged Write {
                          uncached: False,
                          conditional: False,
                          byteEnable: unpack(32'hFF <<{pack(addr)[12:11],3'b0}),
                          data: Data{
                            `ifdef CAP
                            cap: ?,
                            `endif
                            data: zeroExtend(ev.data) << {pack(addr)[12:11], 6'b0}
                          },
                          last: True
                        };
    nextMemSource.enq(TagCache);
    debug2("tcache", $display("TagCache Eviction Writeback write tag data time %d", $time, fshow(mem_req)));
    memReq_fifo.enq(mem_req);
    ev.tag.dirty = False;
    debug2("tcache", $display("TagCache Eviction Writeback victim buffer <= ", fshow(ev)));
    eviction <= ev;
  endrule
`endif

  rule handleRequest(cacheState == Serving);
    CheriMemRequest reqIn = preReq_fifo.first;
    preReq_fifo.deq;
    TagCacheAddr addr = unpack(pack(reqIn.addr));
    debug2("tcache", $display("TagCache request: addr=%x at time %d", addr, $time));
    `ifdef NOTAG
      memReq_fifo.enq(reqIn);
      nextMemSource.enq(Processor);
    `else
      Bool cancel = False;
      case (reqIn.operation) matches tagged Write .* &&& (pack(addr)[39:24] == 16'h003f):
        cancel = True;
      endcase
      // Potentially cancel a write if it is to the tagCache region.
      // This is likely to create strange behaviour in the region, as stores
      // may be seen by the caches but not seen after eviction, but it will
      // not allow writes to affect security.
      if (!cancel)
        begin
          // Each 64-bit line in the tag cache represents 64*32 bytes of memory (2kiB).
          // The cache has 256 lines which is tags for 512k of memory.
          tags.read.put(addr.index);
          data.read.put(addr.index);
          req_fifo.enq(reqIn);    // enq in the current request
        end
    `endif
  endrule
  
  Bool isReadResponse = False;
  if (mem_out_fifo.first.operation matches tagged Read .unused) isReadResponse = True;
  rule sendReadResponse(isReadResponse);
    CheriMemResponse resp <- toGet(mem_out_fifo).get;
    CheriMemResponse newResp = resp;
    Bool tag = True;
    `ifndef NOTAG
      debug2("tcache", $display("TagCache response: %x at time %d", tag_out_fifo.first, $time));
      tag  <- popFIFO(tag_out_fifo);
    `endif
    if (mem_out_fifo.first.operation matches tagged Read .rop)
      newResp.operation = tagged Read {
                            data: Data {
                              cap: unpack(pack(tag)),
                              data: rop.data.data
                            },
                            last: rop.last
                          };
    debug2("tagcache", $display("<time %0t, TagCache> return response:", $time, fshow(newResp)));
    sendResp_fifo.enq(newResp);
  endrule
  rule sendWriteResponse(!isReadResponse);
    CheriMemResponse resp <- toGet(mem_out_fifo).get;
    sendResp_fifo.enq(resp);
  endrule

  interface Slave cache;
    interface request  = toCheckedPut(preReq_fifo);
    interface response = toCheckedGet(sendResp_fifo);
  endinterface

  interface Master memory;
    interface request  = toCheckedGet(memReq_fifo);
    interface CheckedPut response;
      method Bool canPut();
        return mem_out_fifo.notFull() && cache_respQ.notFull();
      endmethod
      method Action put(CheriMemResponse r);
        `ifdef NOTAG
          mem_out_fifo.enq(r);
        `else
          let reqSource <- popFIFO(nextMemSource);
          if (reqSource == TagCache) begin
            if (r.operation matches tagged Read .unused)
              cache_respQ.enq(r);
          end else begin
            mem_out_fifo.enq(r);
          end
        `endif
      endmethod
    endinterface
  endinterface

endmodule
