/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Alex Horsman
 * Copyright (c) 2013 Alan A. Mujumdar
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

import FIFO::*;
import SpecialFIFOs::*;
import FIFOF::*;
import GetPut::*;
import ClientServer::*;
import MasterSlave::*;
import Vector::*;
import ConfigReg::*;
import MEM::*;
import MemTypes::*;
import Assert::*;
import DefaultValue::*;
import Debug::*;


typedef Bit#(8) Byte;

typedef Bit#(24) Tag;
typedef Bit#(11) Key;
typedef Bit#(5)  Offset;
typedef Vector#(32,Byte) CacheLine;
typedef Vector#(32,Bool) ByteMask;

typedef struct {
  Tag tag;
  Key key;
  Offset offset;
} CacheAddress deriving (Bits, Eq, Bounded);

typedef struct {
  `ifdef CAP
    Bool capability;
  `endif
  Tag  tag;
  Bool valid;
  Bool dirty;
  `ifdef MULTI
    Vector#(CORE_COUNT, Bool) linked;
    Vector#(TMul#(CORE_COUNT, 2), Bool) sharers;
  `endif
} TagLine deriving (Bits, Eq, Bounded);

typedef struct {
  `ifdef CAP
    Bool capability;
  `endif
  CacheAddress addr;
  CacheLine    entry;
  `ifdef MULTI
    Vector#(TMul#(CORE_COUNT, 2), Bool) sharers;
  `endif
} CacheEviction deriving (Bits, Eq, Bounded);

typedef 4 PrefetchSize;

/* =================================================================
mkL2Cache
 =================================================================*/

`ifndef MULTI
  typedef enum {Init, Serving, MemRead} CacheState deriving (Bits, Eq);
`else
  // store conditional in multicore CHERI requires 2 memory accesses. to avoid
  // updating the cache before a confirmation from the Writeback stage, a separate
  // rule is used to service the SC. The rule simply checks if the SC is a success
  // or a fail and does not update the cache.
  typedef enum {Init, Serving, MemRead, StoreConditional} CacheState deriving (Bits, Eq);
`endif

interface L2CacheIfc;
  interface Slave#(CheriMemRequest, CheriMemResponse) cache;
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef MULTI
    interface Client#(InvalidateCache, InvalidateCache) invalidate;
  `endif
endinterface: L2CacheIfc

(*synthesize*)
module mkL2Cache(L2CacheIfc ifc);
  FIFOF#(CheriMemRequest)              preReq_fifo <- mkBypassFIFOF;
  FIFO#(CheriMemRequest)                  req_fifo <- mkPipelineFIFO;
  FIFOF#(CheriMemResponse)               resp_fifo <- mkBypassFIFOF;

  FIFO#(CacheEviction)                  evict_fifo <- mkSizedFIFO(5);

  MEM#(Key, TagLine)                          tags <- mkMEM();
  MEM#(Key, CacheLine)                        data <- mkMEM();
  // Total size is 512x256 bits = 64 kbytes.

  FIFOF#(CheriMemRequest)              memReq_fifo <- mkSizedFIFOF(8);
  FIFOF#(CheriMemResponse)            memResp_fifo <- mkBypassFIFOF;

  Reg#(CacheState)                      cacheState <- mkConfigReg(Init);
  
  OrderingLimiterIfc                       orderer <- mkOrderingLimiter;
  `ifdef MULTI
    FIFOF#(InvalidateCache)         invalidateFifo <- mkBypassFIFOF;
    // If there is a miss on load linked, the tags still need to be updated with the
    // LL flag. The register below is access by the DRAM rule when the line is fetched
    Reg#(Vector#(CORE_COUNT, Bool)) missLoadLinked <- mkReg(replicate(False));
    Vector#(CORE_COUNT, Reg#(Maybe#(Tag))) loadLinkedTag <- replicateM(mkReg(tagged Invalid));
    Reg#(UInt#(TLog#(TMul#(2,CORE_COUNT))))
        missMasterID   <- mkReg(unpack('1));
  `endif

  Reg#(UInt#(11))  count <- mkReg(0);
  Reg#(Bit#(4)) reqCount <- mkReg(0);
  Reg#(Bit#(4)) reqTotal <- mkReg(0);
  Reg#(Bit#(4)) rspCount <- mkReg(0);
  Reg#(Bit#(4)) rspTotal <- mkReg(0);
  FIFO#(Key)    fill_fifo <- mkSizedFIFO(4);

  rule initialize(cacheState == Init);
    debug2("l2", $display("<time %0t, L2> Initializing tag %0d", $time, count));
    `ifndef MULTI
      tags.write(pack(count), TagLine{
        `ifdef CAP
        capability: ?,
        `endif
        valid: False, dirty: ?, tag: ?});
    `else
      tags.write(pack(count), TagLine{
        `ifdef CAP
        capability: ?,
        `endif
        valid: False, linked: unpack(0), sharers: unpack(0)});
    `endif
    count <= count + 1;
    if (count == 2047) cacheState <= Serving;
  endrule

  rule putRequest(cacheState == Serving);
    CheriMemRequest reqIn = preReq_fifo.first();
    preReq_fifo.deq();
    CacheAddress reqAddr = unpack(pack(reqIn.addr));
    tags.read.put(reqAddr.key);
    data.read.put(reqAddr.key);
    req_fifo.enq(reqIn);
    debug($display("L2Cache - putRequest ", fshow(reqIn)));
  endrule

  `ifdef MULTI
  Bit#(TLog#(TMul#(CORE_COUNT, 2))) currentMasterID  = truncate(pack(req_fifo.first.masterID));
  Bit#(TLog#(CORE_COUNT)) currentCoreID  = truncateLSB(pack(currentMasterID));
  `endif

  CheriMemRequest req   = req_fifo.first;
  CacheAddress    addr  = unpack(pack(req.addr));

  rule getCheriMemResponse(cacheState == Serving);
    TagLine tagsRead = tags.read.peek();
    CacheLine dataRead = data.read.peek();
    Bool miss = !(addr.tag == tagsRead.tag && tagsRead.valid);
    CacheState newCacheState = Serving;
    `ifdef MULTI
      Bool validReq = True;

      // Simplest possible cache coherence mechanism is currently used in the default
      // L2Cache. It simply invalidates the L1's on every write into the L2. It is
      // highly inefficient but it maintains L1 cache coherency
      Vector#(CORE_COUNT, Bool) loadLinked = tagsRead.linked;
      Vector#(TMul#(CORE_COUNT, 2), Bool) sharersList = tagsRead.sharers;
      Vector#(TMul#(CORE_COUNT, 2), Bool) otherSharersList = sharersList;
      otherSharersList[currentMasterID] = False;
      Bool sharedBlock = any(id, otherSharersList);
      if (req.operation matches tagged Read .unused)
        sharersList[currentMasterID] = True;

      debug($display("L2Cache sharersList %b", sharersList));

      if (req.operation matches tagged Write .wop &&& sharedBlock) begin
        InvalidateCache inv = InvalidateCache{sharers     : otherSharersList,
                                              addr        : req.addr};
        invalidateFifo.enq(inv);
        debug($display("L2Cache Invalidate %x", req.addr));
      end

      if (req.operation matches tagged Read .rop &&& rop.linked) begin
        debug($display("L2Cache Load Linked %x", addr));
        loadLinked[currentCoreID] = True;
        // XXX Part of the new LL/SC mechanism
        loadLinkedTag[currentCoreID] <= tagged Valid addr.tag;
      end

      Bool scResult = False;
      // XXX Part of the new LL/SC mechanism
      if (req.operation matches tagged Write .wop) begin
        for (Integer i=0; i<valueof(CORE_COUNT); i=i+1) begin
          if (isValid(loadLinkedTag[i])) begin
            if (fromMaybe(?, loadLinkedTag[i]) == addr.tag) begin
              if (currentCoreID == fromInteger(i) && wop.conditional && !wop.uncached) begin
                scResult = True;
              end
              loadLinkedTag[i] <= tagged Invalid;
            end
          end         
        end
      end

      missLoadLinked <= loadLinked;
      missMasterID   <= req.masterID;

      if (req.operation matches tagged Write .wop &&& wop.conditional) begin
        // XXX Old LL/SC mechanism. Legacy code is still present in the L2 such as the
        // linked filed in tags and the missLoadLinked register. These will be removed
        // once the new mechanism is approved.
        /*
        if ((!miss || scResult) && !wop.uncached && tagsRead.linked[currentCoreID]) begin
          scResult = True;
        end
        */
        debug($display("L2Cache Store Conditional(%b) %x,%x,%b addr: %x", scResult, !miss, !wop.uncached, tagsRead.linked, req_fifo.first.addr));
        CheriMemResponse memResp = defaultValue;
        memResp.masterID = req.masterID;
        memResp.transactionID = req.transactionID;
        memResp.error = NoError;
        memResp.operation = tagged SC scResult;
        resp_fifo.enq(memResp);
        if (!scResult) begin
          validReq = False;
        end
      end
    `endif

    cycReport($display("[$L2%s%s]", req.operation matches tagged Read .* ?"R":"W",(miss)?"M":"H"));

    `ifdef MULTI
      if (validReq) begin
    `endif
      case (req.operation) matches
      tagged CacheOp .cop &&& (cop.cache == L2): begin
        function Action invalidate() = action
          debug2("l2", $display("<time %0t, L2> Invalidating key=0x%0x", $time, addr.key));
          tags.write(addr.key, TagLine{
            `ifdef CAP
            capability: ?,
            `endif
            valid: False, dirty: ?, tag: ?});
          `ifdef MULTI
            // If a line is invalidated then the L1's sharing the block should be too.
            InvalidateCache inv = InvalidateCache{sharers      : sharersList,
                                                  addr         : req.addr};
            invalidateFifo.enq(inv);
          `endif
        endaction;
        function Action writeback() = action
          if (tagsRead.valid && tagsRead.dirty) begin
            debug2("l2", $display("<time %0t, L2> Writeback @0x%0x=0x%0x", $time, addr, dataRead));
            CheriMemRequest memReq = defaultValue;
            memReq.addr = unpack({tagsRead.tag,addr.key,addr.offset});
            memReq.operation = tagged Write {
                                    uncached: True,
                                    conditional: False,
                                    byteEnable: unpack(32'hFFFFFFFF),
                                    data : Data {
                                        `ifdef CAP
                                        cap: unpack(pack(tagsRead.capability)),
                                        `endif
                                        data: pack(dataRead)
                                    },
                                    last: True
                                };
            memReq_fifo.enq(memReq);
            debug2("l2", $display("<time %0t, L2> Sending ", $time, fshow(memReq)));
          end
        endaction;
        case (cop.inst) matches
          CacheInvalidate &&& (!miss): begin
            invalidate();
          end
          CacheInvalidateWriteback &&& (!miss): begin
            invalidate();
            writeback();
          end
          CacheWriteback &&& (!miss): begin
            writeback();
          end
        endcase
      end
      tagged Read .rop &&& (!miss && ! rop.uncached): begin
        //Return cached data.
        CheriMemResponse memResp = defaultValue;
        memResp.masterID = req.masterID;
        memResp.transactionID = req.transactionID;
        memResp.error = NoError;
        memResp.operation = tagged Read {
            data: Data {
                `ifdef CAP
                cap: unpack(pack(tagsRead.capability)),
                `endif
                data: pack(dataRead)
            },
            last: True
        };
        resp_fifo.enq(memResp);
        debug2("l2", $display(fshow(memResp)));
        `ifdef MULTI
          // While using the directory coherence scheme we always write the tags
          tags.write(addr.key, TagLine{
            `ifdef CAP
              capability  : tagsRead.capability,
            `endif
            tag           : tagsRead.tag,
            dirty         : tagsRead.dirty,
            valid         : tagsRead.valid,
            linked        : loadLinked,
            sharers       : sharersList
          });
          debug($display("Read Hit! %x=%x", addr, pack(dataRead)));
        `endif
      end
      tagged Write .wop &&& (!miss && ! wop.uncached): begin
        //Construct new line.
        CacheLine maskedWrite = dataRead;
        CacheLine writeData = unpack(wop.data.data);
        for (Integer i = 0; i < 32; i=i+1) begin
          if (wop.byteEnable[i]) begin
              maskedWrite[i] = writeData[i];
          end
        end
        debug2("l2", $display("<time %0t, L2> Writing @0x%0x=0x%0x", $time, addr, maskedWrite));
        //Write updated line to cache.
        data.write(addr.key, maskedWrite);
        tags.write(addr.key, TagLine{
          `ifdef CAP
            capability    : unpack(pack(wop.data.cap)),
          `endif
          `ifdef MULTI
            linked        : replicate(False),
            sharers       : sharersList,
          `endif
          tag             : tagsRead.tag,
          dirty           : True,
          valid           : tagsRead.valid
          });
      end
      tagged Write .wop &&& (wop.uncached): begin
        //Write directly to memory.
        memReq_fifo.enq(req);
        debug2("l2", $display("<time %0t, L2> Uncached Write - Invalidating key=0x%0x", $time, addr.key));
        debug2("l2", $display("<time %0t, L2> Sending ", $time, fshow(req)));
        if (!miss) begin
          //Invalidate existing cache line.
          `ifndef MULTI
            tags.write(addr.key, TagLine{
                `ifdef CAP
                capability: ?,
                `endif
                valid: False, dirty: ?, tag: ?});
          `else
            tags.write(addr.key, TagLine{
                `ifdef CAP
                capability: ?,
                `endif
                valid: False, dirty: ?, tag: ?, linked: replicate(False), sharers: replicate(False)});
          `endif
        end
      end
      default: begin
        if (req.operation matches tagged Read .rop &&& (!rop.uncached && addr.key < (0 - 5))) begin
          reqTotal <= fromInteger(valueof(PrefetchSize));
        end
        else begin
            reqTotal <= 1;
        end
        reqCount <= 0;
        rspCount <= 0;
        rspTotal <= 0;
        newCacheState = MemRead;
      end
    endcase
    if (newCacheState == Serving) begin
      req_fifo.deq();
      let unusedA <- tags.read.get();
      let unusedB <- data.read.get();
    end
    cacheState <= newCacheState;

    `ifdef MULTI
      end
      else begin
        // If the Store Conditional failed then no changes should be made in the L2
       let unusedA <- tags.read.get();
       let unusedB <- data.read.get();
       req_fifo.deq();
      end
    `endif
  endrule

  rule putDRAMRequest(cacheState == MemRead && reqCount != reqTotal);
    Bool cached = (case (req.operation) matches
                    tagged Read .r: return ! r.uncached;
                    tagged Write .w: return ! w.uncached;
                  endcase);
    TagLine tagsRead <- tags.read.get();
    CacheLine dataRead <- data.read.get();
    if (!tagsRead.valid || tagsRead.tag != addr.tag || !cached) begin
      //Request required cache line from memory.
      CheriMemRequest memReq = defaultValue;
      memReq.addr = unpack({pack({addr.tag,addr.key}) + zeroExtend(reqCount), addr.offset});
      // In case of fetch on write miss or cached miss, force line aligned read address
      if (cached || (req.operation matches tagged Write .w ? True : False)) begin
        debug2("l2", $display("L2 - Fetch on write Miss / cached Miss"));
        memReq.addr = unpack({pack(memReq.addr)[39:5],5'h0});
      end
      memReq.operation = tagged Read {
                              uncached: !cached,
                              linked: False,
                              noOfFlits: 0,
                              bytesPerFlit: (cached) ? BYTE_32 : (case (req.operation) matches
                                tagged Read .rop : return rop.bytesPerFlit;
                                endcase)
                          };
      memReq_fifo.enq(memReq);
      debug2("l2", $display("<time %0t, L2> Sending ", $time, fshow(memReq)));

      rspTotal <= rspTotal + 1;
      if (tagsRead.valid && tagsRead.dirty && cached) begin
        debug2("l2", $display("<time %0t, L2> Evicting @0x%0x", $time, {tagsRead.tag,addr.key}));
        //Store existing line for eviction.
        evict_fifo.enq(CacheEviction{
          `ifdef CAP
            capability: tagsRead.capability,
          `endif
          `ifdef MULTI
            sharers: tagsRead.sharers,
          `endif
          addr  : CacheAddress{tag: tagsRead.tag, key: addr.key + zeroExtend(reqCount), offset: 5'h0},
          entry : dataRead
        });
      end
      `ifdef MULTI
        // If a line is evicted then we must invalidate the L1's as we will lose the list
        // of sharers from the tags after this operation. 
        if ((valueof(CORE_COUNT) > 1) && tagsRead.valid && cached) begin
          let address = pack(CacheAddress{tag: tagsRead.tag, key: addr.key + zeroExtend(reqCount), offset: 5'h0});
          InvalidateCache inv = InvalidateCache{sharers      : tagsRead.sharers,
                                                addr         : unpack(address)};
          invalidateFifo.enq(inv);
          debug($display("%0t, L2Cache Invalidate L1 on Evict, Sharers:%b, Addr:%x", $time(), inv.sharers, inv.addr));
        end
      `endif
      fill_fifo.enq(addr.key + zeroExtend(reqCount));
    end
    if (reqCount + 1 != reqTotal) begin
      tags.read.put(addr.key+zeroExtend(reqCount)+1);
      data.read.put(addr.key+zeroExtend(reqCount)+1);
    end
    reqCount <= reqCount + 1;
  endrule

  rule getDRAMResponse(cacheState == MemRead && reqCount == reqTotal);
    CheriMemResponse resp <- toGet(memResp_fifo).get;
    debug2("l2", $display("<time %0t, L2> Miss @0x%0x - ", $time, addr.key, fshow(resp)));
    resp.masterID = req.masterID;
    resp.transactionID = req.transactionID;
    case (resp.operation) matches 
      tagged Read .resp_op: begin
 
        `ifdef MULTI
          Bit#(CORE_COUNT) sharedMapping = 0;
          sharedMapping[missMasterID] = 1;
          Vector#(TMul#(CORE_COUNT,2), Bool) sharersList = replicate(False);
          sharersList[missMasterID] = True;
        `endif
  
        case (req.operation) matches
          tagged Read .rop: begin
            //Return data from memory.
            if (rspCount == 0) begin
              resp_fifo.enq(resp);
            end
            if (!rop.uncached) begin
              //Store data in cache.
              data.write(fill_fifo.first, unpack(resp_op.data.data));
  
              tags.write(fill_fifo.first, TagLine{
                `ifdef CAP
                  capability: unpack(pack(resp_op.data.cap)),
                `endif
                `ifdef MULTI
                  linked        : missLoadLinked,
                  sharers       : sharersList,
                `endif
                tag   : addr.tag,
                valid : True,
                dirty : False
              });
              `ifdef MULTI
                for (Integer i=0; i<valueOf(CORE_COUNT); i=i+1) begin
                  if (missLoadLinked[i]) begin
                    debug($display("L2Cache Miss Load Linked"));
                  end
                end
              `endif
            end
          end
          tagged Write .wop: begin
            CacheLine maskedWrite = unpack(resp_op.data.data);
            CacheLine writeData = unpack(wop.data.data);
            for (Integer i = 0; i < 32; i=i+1) begin
              if (wop.byteEnable[i]) begin
                maskedWrite[i] = writeData[i];
              end
            end
            debug2("l2", $display("<time %0t, L2> Writing @0x%0x=0x%0x", $time, addr.key, maskedWrite));
            data.write(fill_fifo.first, maskedWrite);
  
            tags.write(fill_fifo.first, TagLine{
              `ifdef CAP
                capability: unpack(pack(wop.data.cap)),
              `endif
              `ifdef MULTI
                linked        : replicate(False),
                sharers       : replicate(False),
              `endif
              tag   : addr.tag,
              valid : True,
              dirty : True
            });
          end
        endcase
        rspCount <= rspCount + 1;
        fill_fifo.deq();
        if (rspCount + 1 == rspTotal) begin
          req_fifo.deq();
          cacheState <= Serving;
        end
      end
      default: dynamicAssert(False, "only read responses are handled");
    endcase
  endrule

  rule writeDirtyLine(cacheState == MemRead && reqCount == reqTotal);
    CacheEviction evict = evict_fifo.first;
    CheriMemRequest memReq = defaultValue;
    memReq.addr = unpack(pack(evict.addr));
    memReq.operation = tagged Write {
                uncached: True,
                conditional: False,
                byteEnable: unpack(32'hFFFFFFFF),
                data: Data {
                    `ifdef CAP
                    cap: unpack(pack(evict.capability)),
                    `endif
                    data: pack(evict.entry)
                },
                last: True
            };
    memReq_fifo.enq(memReq);
    debug2("l2", $display("<time %0t, L2> Eviction Writeback @0x%0x=0x%0x ", $time, evict.addr, evict.entry));
    debug2("l2", $display("<time %0t, L2> Sending ", $time, fshow(memReq)));
    evict_fifo.deq();
  endrule

  interface Slave cache;
    interface request  = toCheckedPut(preReq_fifo);
    interface response = toCheckedGet(resp_fifo);
  endinterface

  interface Master memory;
    interface CheckedGet request;
      method Bool canGet();
        return memReq_fifo.notEmpty();//orderer.allowRequest(memReq_fifo.first());
      endmethod
      method CheriMemRequest peek() if (orderer.allowRequest(memReq_fifo.first()));
        return memReq_fifo.first();
      endmethod
      method ActionValue#(CheriMemRequest) get() if (orderer.allowRequest(memReq_fifo.first()));
        orderer.putRequest(memReq_fifo.first());
        memReq_fifo.deq();
        return memReq_fifo.first();
      endmethod
    endinterface
    interface CheckedPut response;
      method Bool canPut();
        return memResp_fifo.notFull();
      endmethod
      method Action put(CheriMemResponse resp);
        orderer.putResponse(resp);
        if (resp.operation matches tagged Read .unused) begin
          memResp_fifo.enq(resp);
        end
      endmethod
    endinterface
  endinterface

  `ifdef MULTI
    interface Client invalidate;
      interface Get request;
        method ActionValue#(InvalidateCache) get() if(invalidateFifo.notEmpty);
          InvalidateCache inv = invalidateFifo.first;
          invalidateFifo.deq();
          return inv;
        endmethod
      endinterface
    endinterface
  `endif
endmodule

// mkOrderingLimiter
// This module ensures that reads to the same line as an outstanding write
// are blocked until the write response is recieved.

interface OrderingLimiterIfc;
  method Bool allowRequest(CheriMemRequest req);
  method Action putRequest(CheriMemRequest req);
  method Action putResponse(CheriMemResponse resp);
endinterface: OrderingLimiterIfc

(*synthesize*)
module mkOrderingLimiter(OrderingLimiterIfc);
  FIFOF#(Bit#(2))       writeTableLocation <- mkUGSizedFIFOF(8);
  Vector#(4, FIFOF#(Bit#(8)))   writeTable <- replicateM(mkUGSizedFIFOF(1));
  /*
  rule debugdisplay;
    trace($display("writeTableLocation.notFull=%d", 
      writeTableLocation.notFull));
    for (Integer i=0; i<4; i=i+1) begin
      case (writeTable[i].notEmpty)
        True:  trace($display("    %d - %x", i, writeTable[i].first()));
        False: trace($display("    %d - Empty", i));
      endcase
    end
  endrule
  */
  method Bool allowRequest(CheriMemRequest req);
    // Make a hash that takes into account both upper bits and lower bits to prevent
    // blocking of reads to large, aligned offsets due to eviction and replacement.
    Bit#(8) addressHash = req.addr.lineNumber[7:0]^
                          req.addr.lineNumber[18:11];
    Bit#(2) key = addressHash[1:0];
    Bool blockNextRequest = (case (req.operation) matches
        tagged Read .rop:  return (writeTable[key].notEmpty) ? writeTable[key].first == addressHash : False;
        tagged Write .wop: return writeTable[key].notEmpty;
        default: return False;
      endcase);
          
    return !blockNextRequest;
  endmethod
  
  method Action putRequest(CheriMemRequest req);
    // Make a hash that takes into account both upper bits and lower bits to prevent
    // blocking of reads to large, aligned offsets due to eviction and replacement.
    Bit#(8) addressHash = req.addr.lineNumber[7:0]^
                          req.addr.lineNumber[18:11];
    Bit#(2) key = addressHash[1:0];
    if (req.operation matches tagged Write .unused) begin
      writeTable[key].enq(addressHash);
      writeTableLocation.enq(key);
    end
  endmethod
  
  method Action putResponse(CheriMemResponse resp);
    if (resp.operation matches tagged Write .wresp) begin
      writeTable[writeTableLocation.first()].deq();
      writeTableLocation.deq();
    end
  endmethod
endmodule
