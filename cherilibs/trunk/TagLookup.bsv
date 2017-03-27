/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Philip Withnall
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2014-2016 Alexandre Joannou
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

import Vector::*;
import MemTypes::*;
import MasterSlave::*;
import GetPut::*;
import FF::*;
import CacheCore::*;
import DefaultValue::*;
`ifdef STATCOUNTERS
import StatCounters::*;
`endif
import Debug::*;

// interface types
///////////////////////////////////////////////////////////////////////////////

typedef Vector#(4,Bit#(CapsPerFlit)) LineTags;
typedef union tagged {
  void Uncovered;
  LineTags Covered;
} CheriTagResponse deriving (Bits);

interface TagLookupIfc;
  interface Slave#(CheriMemRequest, CheriTagResponse) cache;
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef STATCOUNTERS
  interface Get#(ModuleEvents) cacheEvents;
  `endif
endinterface

// internal types
///////////////////////////////////////////////////////////////////////////////

typedef enum {Init, Serving} State deriving (Bits, Eq);
typedef TMul#(CapsPerFlit,4) CapsPerLine;

// mkTagLookup module definition
///////////////////////////////////////////////////////////////////////////////

(*synthesize*)
module mkTagLookup #(CheriMasterID mID) (TagLookupIfc);

  // constant parameters
  /////////////////////////////////////////////////////////////////////////////

  // covered region include DRAM and BROM
  // starting address of the covered region
  CheriPhyAddr coveredStrtAddr = unpack(40'h00000000);
  // ending address of the covered region
  CheriPhyAddr coveredEndAddr  = unpack(40'h40010000);
  // tagd table is at top of DRAM
  // starting address of the tags table
  CheriPhyAddr tagTabStrtAddr  = unpack(40'h3F000000);
  // ending address of the tags table
  CheriPhyAddr tagTabEndAddr   = unpack(40'h40000000);

  // components instanciations
  /////////////////////////////////////////////////////////////////////////////

  // state register
  Reg#(State) state <- mkReg(Init);
  // address to zero when in Init state
  Reg#(CheriPhyAddr) zeroAddr <- mkReg(tagTabStrtAddr);
  // transaction number for memory requests
  Reg#(CheriTransactionID) transNum <- mkReg(0);
  // pending read requests fifo
  FF#(Tuple2#(Bool,CheriPhyBitOffset),4) readReqs <- mkFF();
  // memory requests fifo
  FF#(CheriMemRequest, 5)  mReqs <- mkUGFFDebug("TagLookup_mReqs");
  // memory response fifo
  FF#(CheriMemResponse, 2) mRsps <- mkUGFFDebug("TagLookup_mRsps");
  // tag cache CacheCore module
  CacheCore#(4, TSub#(Indices, 1), 1)  tagCache <- mkCacheCore(
    12, WriteAllocate, OnlyReadResponses, InOrder, TCache,
    zeroExtend(mReqs.remaining()), ff2fifof(mReqs), ff2fifof(mRsps));

  // module rules
  /////////////////////////////////////////////////////////////////////////////

  // initialisation rule
  rule initialise (state == Init);
    `ifndef BLUESIM
      // zero all the tags table in memory
      if (zeroAddr < tagTabEndAddr) begin
        // prepare memory request
        CheriMemRequest mReq = defaultValue;
        mReq.addr            = zeroAddr;
        mReq.masterID        = mID;
        mReq.transactionID   = transNum;
        mReq.operation       = tagged Write {
                                        uncached: False,
                                        conditional: False,
                                        byteEnable: unpack(-1),
                                        bitEnable: -1,
                                        data: unpack(0),
                                        last: True
                                      };
        // send memory request
        tagCache.put(mReq);
        $display(
          "<time %0t TagLookup> zeroing tag table: ",
          $time, fshow(mReq)
        );
        // increment transaction number and address
        transNum <= transNum + 1;
        zeroAddr.lineNumber <= zeroAddr.lineNumber + 1;
      end else 
    `endif
    // when table zeroed, go to Serving state
    state <= Serving;
  endrule

  // Simply stuff "True" into commits because we never cancel transactions here
  rule stuffCommits;
    tagCache.nextWillCommit(True);
  endrule

  // module helper functions
  /////////////////////////////////////////////////////////////////////////////

  function Bool isCovered (CheriPhyAddr addr);
    Bool r = True;
    if (addr < coveredStrtAddr && addr >= coveredEndAddr) r = False;
    if (addr >= tagTabStrtAddr && addr < tagTabEndAddr) r = False;
    return r;
  endfunction

  function CheriTagResponse tagsFromCacheRsp (CheriMemResponse mr);
    CheriTagResponse r;
    Data#(CheriDataWidth) rData = mr.data;
    match {.covered,.offset} = readReqs.first();
    // Cast to a vector of tag chunks. The chunks are the set of tags for one line.
    Vector#(TDiv#(CheriDataWidth,CapsPerLine), Bit#(CapsPerLine)) sets = unpack(rData.data);
    // Pick out the index 
    CheriPhyBitOffset index = (offset >> valueOf(TLog#(CapsPerLine)));
    // Shift by the bottom two bits so that non-burst requests will have
    // the tag bit in the bottom.
    Bit#(TLog#(CapsPerLine)) shift = truncate(offset);
    LineTags thisSet = unpack(sets[index] >> shift);
    if (!covered) r = tagged Uncovered;
    else r = tagged Covered thisSet;
    return r;
  endfunction

  // module Slave interface
  /////////////////////////////////////////////////////////////////////////////

  interface Slave cache;

    // lookup Slave request interface
    //////////////////////////////////////////////////////
    interface CheckedPut request;
      method Bool canPut() = state == Serving;
      // incoming lookup request
      method Action put(CheriMemRequest req) if (state == Serving);
        // check whether we are in the covered region
        Bool doTagLookup = isCovered(req.addr);
        // various addresses variables
        CheriCapAddress capAddr = unpack(pack(req.addr));
        CheriPhyAddr tblAddr    = tagTabStrtAddr;
        // The byte address in the table is the line number >> 3 (the byte we seek) added to the table base.
        // Only caclulate the table address for lower general-purpose memory.
        tblAddr = unpack(zeroExtend(capAddr.capNumber>>3) + pack(tagTabStrtAddr));
        // build the request to the tag cache
        // common part of the request
        CheriMemRequest mReq = defaultValue;
        mReq.addr            = tblAddr;
        mReq.masterID        = mID;
        mReq.transactionID   = transNum;
        case (req.operation) matches
          // when it's a read
          //////////////////////////////
          tagged Read .rop: begin
            mReq.operation = tagged Read {
                                    uncached: False,
                                    linked: False,
                                    noOfFlits: 0,
                                    bytesPerFlit: cheriBusBytes
                                };
            readReqs.enq(tuple2(doTagLookup,truncate(capAddr.capNumber)));
          end
          // when it's a write
          //////////////////////////////
          tagged Write .wop: begin
            Vector#(CapBytes, Bool) byteEnable = replicate(False);
            // select the table byte to write
            byteEnable[tblAddr.byteOffset] = True;
            // select the table bits to write
            Bit#(3) bitOffset = capAddr.capNumber[2:0];
            Bit#(8) bitEnable = 0;
            Bit#(8) tw = 0;
            Integer i = 0;
            for (i = 0; i < valueOf(CapsPerFlit); i = i + 1) begin
              bitEnable[bitOffset+fromInteger(i)] = 1;
              tw[bitOffset+fromInteger(i)] = pack(wop.data.cap[i]);
            end
            // Just replicate the byte and let the byte and bit select choose the bits to write.
            CheriData tagsToWrite = Data{
              cap: ?,
              data: pack(replicate(tw))
            };
            mReq.operation = tagged Write {
                                  uncached: False,
                                  conditional: False,
                                  byteEnable: byteEnable,
                                  bitEnable: bitEnable,
                                  data: tagsToWrite,
                                  last: True
                                };
          end
          // ignore other types of requests
          default: doTagLookup = False;
        endcase
        // when a lookup is required
        if (doTagLookup) begin
          debug2("taglookup",
            $display("<time %0t TagLookup> Request to cache core ",
            $time, fshow(mReq)
          ));
          // send the tag cache request
          tagCache.put(mReq);
          // increment the transaction number
          transNum <= transNum + 1;
        end
      endmethod
    endinterface

    // lookup Slave response interface
    //////////////////////////////////////////////////////
    interface CheckedGet response;
      method Bool canGet() = tagCache.response.canGet();
      method CheriTagResponse peek();
        CheriMemResponse mRsp = tagCache.response.peek();
        return tagsFromCacheRsp(mRsp);
      endmethod
      method ActionValue#(CheriTagResponse) get() if (tagCache.response.canGet());
        // get response from the tag cache and read fifo
        CheriMemResponse mRsp <- tagCache.response.get();
        readReqs.deq();
        // debug
        debug2("taglookup",
          $display(
            "<time %0t TagLookup> got valid cache response ",
            $time, fshow(mRsp)
        ));
        return tagsFromCacheRsp(mRsp);
      endmethod
    endinterface
  endinterface

  // module Master interface
  /////////////////////////////////////////////////////////////////////////////

  interface Master memory;
    interface request  = toCheckedGet(ff2fifof(mReqs));
    interface response = toCheckedPut(ff2fifof(mRsps));
  endinterface

  // module cacheEvents interface
  /////////////////////////////////////////////////////////////////////////////

  `ifdef STATCOUNTERS
  interface Get cacheEvents;
    method ActionValue#(ModuleEvents) get () = tagCache.cacheEvents.get();
  endinterface
  `endif

endmodule
