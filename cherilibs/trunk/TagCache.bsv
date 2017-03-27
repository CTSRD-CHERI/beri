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
import FIFOF::*;
import FF::*;
import GetPut::*;
import MasterSlave::*;
import Vector::*;
import Debug::*;
import Library::*;
import MemTypes::*;
import DefaultValue::*;
import Assert::*;
import CacheCore::*;
`ifdef STATCOUNTERS
import StatCounters::*;
`endif

`ifdef CAP
  `define USECAP 1
  typedef 256 CapWidth;
`elsif CAP128
  `define USECAP 1
  typedef 128 CapWidth;
`elsif CAP64
  `define USECAP 1
  typedef 64 CapWidth;
`endif

/******************************************************************************
 * mkTagCache
 *
 * This module provides a proxy for memory accesses which adds support for
 * tagged memory. It connects to memory on one side and the processor/L2 cache
 * on the other. Tag values are stored in memory (currently at the top of DRAM
 * and there is a cache of 32ki tags (representing 1MB memory) stored in BRAM. 
 * Read responses are amended with the correct tag value and write requests update
 * the value in the tag cache (which is later written back to memory).
 *
 *****************************************************************************/

typedef enum {TagCache, Processor} MemReqSource deriving (Bits, Eq);

typedef struct {
    CheriPhyBitOffset    offset;
    Bool             outOfRange;
    CapTags              capTag;
} TagReq deriving (Bits, Eq, Bounded, FShow);

interface TagCacheIfc;
  interface Slave#(CheriMemRequest, CheriMemResponse) cache;
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef STATCOUNTERS
  interface Get#(ModuleEvents) cacheEvents;
  `endif
endinterface

typedef Vector#(4,Bit#(CapsPerFlit)) CapLineVec;
typedef TMul#(CapsPerFlit,4) CapsPerLine;

(*synthesize*)
module mkTagCache(TagCacheIfc);
  FF#(CapLineVec,4)                 tagsOut <- mkUGFFBypass();
  FF#(TagReq,4)                     tagReqs <- mkUGFF();
  FF#(CheriMemRequest, 5)           tabReqs <- mkUGFF();
  FF#(CheriMemResponse, 2)          tabRsps <- mkUGFF();
  FF#(CheriMemRequest, 1)           memReqs <- mkLFF1();
  FF#(CheriMemResponse, 32)         memRsps <- mkUGFF();
  Reg#(Bit#(2))                       frame <- mkReg(0);
  Reg#(CheriTransactionID)         transNum <- mkReg(0);
  CacheCore#(4, TSub#(Indices, 1), 1)           core <- mkCacheCore(12, WriteAllocate, OnlyReadResponses, InOrder, TCache, 
                                           zeroExtend(tabReqs.remaining()),
                                           ff2fifof(tabReqs), ff2fifof(tabRsps));
                                           
`ifndef NOTAG
  // Simply stuff "True" into commits because we never cancel transactions here.
  rule stuffCommits;
    core.nextWillCommit(True);
  endrule
  
  rule getTableRead(core.response.canGet && tagsOut.notFull);
    CheriMemResponse memResp <- core.response.get();
    TagReq tagReq = tagReqs.first;
    tagReqs.deq;
    debug2("tagcache", $display("<time %0t TagCache> servicing tag request ", $time, fshow(tagReq)));
    debug2("tagcache", $display("<time %0t TagCache> got valid cache response ", $time, fshow(memResp)));
    Data#(CheriDataWidth) readData = memResp.data;
    if (!tagReq.outOfRange) begin
      // Cast to a vector of tag chunks.  The chunks are the set of tags for one line.
      Vector#(TDiv#(CheriDataWidth,CapsPerLine), Bit#(CapsPerLine)) sets = unpack(readData.data);
      // Pick out the index 
      CheriPhyBitOffset index = (tagReq.offset >> valueOf(TLog#(CapsPerLine)));
      // Shift by the bottom two bits so that non-burst requests will have
      // the tag bit in the bottom.
      Bit#(TLog#(CapsPerLine)) shift = truncate(tagReq.offset);
      CapLineVec thisSet = unpack(sets[index] >> shift);
      tagsOut.enq(thisSet);
    end else tagsOut.enq(replicate(0));
  endrule
  
  rule forwardTableReqs(tabReqs.notEmpty);
    debug2("tagcache", $display("Injecting request from TagCache core: time %d :", $time, fshow(tabReqs.first)));
    memReqs.enq(tabReqs.first);
    tabReqs.deq;
  endrule
`endif
  Bool responseCanGet = memRsps.notEmpty();
`ifndef NOTAG
  // If the tag is not ready for a read response, we can't get.
  if (memRsps.first.operation matches tagged Read .rop &&& !tagsOut.notEmpty)
    responseCanGet = False;
`endif
  function CheriMemResponse memResponsePeek();
    CheriMemResponse resp = memRsps.first;
    CheriMemResponse newResp = resp;
    if (resp.operation matches tagged Read .rop) begin
      Vector#(TDiv#(CheriDataWidth,CapWidth),Bool) tags = replicate(True);
      `ifndef NOTAG
        tags  = unpack(tagsOut.first[frame]);
      `endif
      newResp.data.cap = tags;
    end
    return newResp;
  endfunction
  
  interface Slave cache;
    interface CheckedPut request;
      method Bool canPut();
        return True;
      endmethod
      method Action put(CheriMemRequest reqIn);
        debug2("tagcache", $display("TagCache request: time %d :", $time, fshow(reqIn)));
        memReqs.enq(reqIn);
        CheriCapAddress capAddr = unpack(pack(reqIn.addr));
        `ifndef NOTAG
          Bool startLookup = True;
          TagReq tagReq = unpack(0);
          tagReq.offset = truncate(capAddr.capNumber);
          CheriPhyAddr tabBase = unpack(40'h3F000000); // 32MB table to tags covering 4GB of physical address space.
          CheriPhyAddr tblAddr = tabBase;
          // The byte address in the table is the line number >> 3 (the byte we seek) added to the table base.
          if (pack(reqIn.addr) < 40'h80000000) begin // Only caclulate the table address for the bottom 2 Gigs.
            tblAddr = unpack(zeroExtend(capAddr.capNumber>>3) + pack(tabBase));
            //tblAddr.byteOffset = 0;
            if (pack(tblAddr) >= 40'h40000000) $display("Panic! tblAddr %x is beyond DRAM!");
            tagReq.outOfRange = False;
          end else tagReq.outOfRange = True;
          
          CheriMemRequest tabReq = defaultValue;
          tabReq.addr = tblAddr;
          tabReq.masterID = 12;
          tabReq.transactionID = transNum;
          case (reqIn.operation) matches
            tagged Read .rop: begin
              tabReq.operation = tagged Read {
                                      uncached: tagReq.outOfRange,
                                      linked: False,
                                      noOfFlits: 0,
                                      bytesPerFlit: cheriBusBytes
                                  };
              tagReqs.enq(tagReq);
              debug2("tagcache", $display("<time %0t TagCache> Putting tag request %x ", $time, pack(tabReq.addr), fshow(tagReq)));
            end
            tagged Write .wop &&& (!tagReq.outOfRange): begin
              tagReq.capTag = wop.data.cap;
              Vector#(TDiv#(CheriDataWidth,8), Bool) byteEnable = replicate(False);
              //Bit#(TLog#(TDiv#(CheriDataWidth,8))) byteSelect = truncate(capAddr.capNumber>>3);
              // Select the table byte to write...
              byteEnable[tblAddr.byteOffset] = True;
              // Select the table bits to write
              Bit#(3) bitOffset = capAddr.capNumber[2:0];
              Bit#(8) bitEnable = 0;
              Bit#(8) tw = 0;
              Integer i = 0;
              for (i=0; i<valueOf(CapsPerFlit); i=i+1) begin
                bitEnable[bitOffset+fromInteger(i)] = 1;
                tw[bitOffset+fromInteger(i)] = pack(tagReq.capTag[i]);
              end
              // Just replicate the byte and let the byte and bit select choose the bits to write.
              CheriData tagsToWrite = Data{
                cap: ?,
                data: truncate({tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw,tw})
              };
              tabReq.operation = tagged Write {
                                    uncached: False,
                                    conditional: False,
                                    byteEnable: byteEnable,
                                    bitEnable: bitEnable,
                                    data: tagsToWrite,
                                    last: True
                                  };
            end
            default: startLookup = False;
          endcase
          if (startLookup) begin
            debug2("tagcache", $display("<time %0t TagCache> Request to cache core ", $time, fshow(tabReq)));
            core.put(tabReq);
            transNum <= transNum + 1;
          end
        `endif
      endmethod
    endinterface
    interface CheckedGet response;
      method Bool canGet();
        return responseCanGet;
      endmethod
      method CheriMemResponse peek();
        return memResponsePeek();
      endmethod
      method ActionValue#(CheriMemResponse) get() if (responseCanGet);
        CheriMemResponse resp = memResponsePeek();
        memRsps.deq;
        `ifndef NOTAG
          if (resp.operation matches tagged Read .rop) begin
            if (rop.last) begin
              tagsOut.deq;
              frame <= 0;
            end else frame <= frame + 1;
          end
        `endif
        debug2("tagcache", $display("<time %0t TagCache> Returning response: ", $time, fshow(resp)));
        return resp;
      endmethod
    endinterface
  endinterface

  interface Master memory;
    interface request  = toCheckedGet(ff2fifof(memReqs));
    interface CheckedPut response;
      method Bool canPut();
        return (memRsps.notFull() && tabRsps.notFull());
      endmethod
      method Action put(CheriMemResponse r) if (memRsps.notFull() && tabRsps.notFull());
        `ifdef NOTAG
          memRsps.enq(r);
        `else
          MemReqSource reqSource = (r.masterID==12)?TagCache:Processor;
          debug2("tagcache", $display("<time %0t TagCache> response from memory: source=%x ", $time, reqSource, fshow(r)));
          if (reqSource == TagCache) begin
            if (r.operation matches tagged Read.rop) tabRsps.enq(r);
            debug2("tagcache", $display("<time %0t TagCache> tag response", $time));
          end else begin
            memRsps.enq(r);
            debug2("tagcache", $display("<time %0t TagCache> memory response", $time));
          end
        `endif
      endmethod
    endinterface
  endinterface
  `ifdef STATCOUNTERS
  interface Get cacheEvents;
    method ActionValue#(ModuleEvents) get () = core.cacheEvents.get();
  endinterface
  `endif

endmodule
