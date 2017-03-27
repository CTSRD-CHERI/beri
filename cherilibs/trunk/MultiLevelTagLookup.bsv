/*-
 * Copyright (c) 2016-2017 Alexandre Joannou
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
import ConfigReg::*;
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
} CheriTagResponse deriving (Bits,FShow);

interface TagLookupIfc;
  interface Slave#(CheriMemRequest, CheriTagResponse) cache;
  interface Master#(CheriMemRequest, CheriMemResponse) memory;
  `ifdef STATCOUNTERS
  interface Get#(ModuleEvents) cacheEvents;
  `endif
endinterface

// internal types
///////////////////////////////////////////////////////////////////////////////

typedef enum {Init, Idle, ReadTag, SetTag, ClearTag, FoldZeroes} State deriving (Bits, Eq, FShow);
typedef TMul#(CapsPerFlit,4) CapsPerLine;

typedef union tagged {
  Bool Node;
  LineTags Leaf;
} TableEntry deriving (Bits);

typedef struct {
  CheriPhyAddr startAddr;
  Integer size;
  Integer shiftAmnt;
  Integer groupFactor;
  Integer groupFactorLog;
} TableLvl deriving (FShow);

instance FShow#(Integer);
  function Fmt fshow (Integer i) = $format("%d",i);
endinstance

// XXX (maximum table depth of 8)
typedef UInt#(3) TDepth;

// mkTagLookup module definition
///////////////////////////////////////////////////////////////////////////////

/*
  descending_urgency = "initialise,drainMemRsp,readTagState,setTagState"
*/
//XXX(* synthesize *) can't synthesize with polymorphic interface (=> parameter keyword useless...)
module mkMultiLevelTagLookup #(
  // master ID to be used for memory requests
  parameter CheriMasterID mID,
  // ending address of the tags table
  parameter CheriPhyAddr tagTabEndAddr,
  // from leaf 0 ---> root n. telem = Integer
  parameter Vector#(tdepth, Integer) tableStructure,
  // Size of the memory covered
  parameter Integer memCoveredSize
) (TagLookupIfc);

  // static parameters
  /////////////////////////////////////////////////////////////////////////////

  // covered region include DRAM and BROM
  // starting address of the covered region
  CheriPhyAddr coveredStrtAddr = unpack(40'h00000000);
  // ending address of the covered region
  CheriPhyAddr coveredEndAddr  = unpack(40'h40010000);
  // tagd table is at top of DRAM
  // starting address of the tags table
  CheriPhyAddr tagTabStrtAddr  = unpack(40'h3F000000);

  // root lvl
  TDepth rootLvl = fromInteger(valueof(tdepth)-1);
  TDepth leafLvl = 0;

  // table descriptor
  function TableLvl lvlDesc (Integer d);
    Integer sz;
    if (d < 0) let _ = error("MultiLevelTagLookup: negative table level " + integerToString(d));
    // leaf lvl
    sz = div(memCoveredSize,8*valueof(CapBytes));
    TableLvl tlvl = TableLvl {
          startAddr: unpack(pack(tagTabEndAddr)-fromInteger(sz)),
          size: sz,
          shiftAmnt: 0,
          groupFactor: 0,
          groupFactorLog: 0
      };
    // intermediate node lvl
    if (d != 0) begin
      TableLvl t = lvlDesc(d-1);
      if (tableStructure[d] > valueof(CheriDataWidth) || tableStructure[d] < 2)
        let _ = error("grouping factor " + integerToString(tableStructure[d]) +
          " must be between 2 and "+ integerToString(valueof(CheriDataWidth)) +
          " (for clearing tags algorithm)");
      if (mod(t.size,tableStructure[d]) != 0)
        let _ = error("table level " + integerToString(d) +
          ", invalid grouping factor " + integerToString(tableStructure[d]) +
          " ("+integerToString(t.size) +
          "not divisible by "+integerToString(tableStructure[d])+")");
      sz = div(t.size, tableStructure[d]);
      tlvl = TableLvl {
          startAddr: unpack(pack(t.startAddr)-fromInteger(sz)),
          size: sz,
          shiftAmnt: t.shiftAmnt + log2(tableStructure[d]),
          groupFactor: tableStructure[d],
          groupFactorLog: log2(tableStructure[d])
      };
    end
    // force the table start address to be "flit" alligned
    // XXX necessary for the tag clear algorithm to work
    // XXX (it relies on all tags of a node being returned in a single mem rsp)
    tlvl.startAddr.byteOffset = 0;
    return tlvl;
  endfunction
  //endfunction
  // table descriptor has leaf lvl 0 ---> root lvl n
  Vector#(tdepth,TableLvl) tableDesc = genWith (lvlDesc);

  // components instanciations
  /////////////////////////////////////////////////////////////////////////////

  // state register
  Reg#(State) state <- mkConfigReg(Init);
  // address to zero when in Init state
  Reg#(CheriPhyAddr) zeroAddr <- mkReg(tagTabStrtAddr);
  // transaction number for memory requests
  Reg#(CheriTransactionID) transNum <- mkReg(0);
  // pending read requests fifo covered or not
  FF#(Bool,1) readReqs <- mkLFF1();
  // lookup response fifo
  FF#(LineTags,1) lookupRsp      <- mkUGFFDebug("TagLookup_lookupRsp");
  // memory requests fifo
  FF#(CheriMemRequest, 8)  mReqs <-  mkUGFFDebug("TagLookup_mReqs");
  // memory response fifo
  FF#(CheriMemResponse, 2) mRsps <- mkUGFFDebug("TagLookup_mRsps");
  // Ensure only one outstanding request at a time.
  // As we enq and deq in the same rule, more than one would wedge the state machine.
  //FF#(CheriMemResponse, 2) tagCacheRsps <- mkUGFF();
  FF#(Bool, 4)             useNextRsp <- mkUGFFDebug("TagLookup_useNextRsp");
  FF#(CheriMemRequest, 1) tagCacheReq <- mkFF();
  PulseWire                    getReq <- mkPulseWire();
  // tag cache CacheCore module
  CacheCore#(4, TSub#(Indices, 1), 1)  tagCache <- mkCacheCore(
    12, WriteAllocate, RespondAll, InOrder, TCache,
    zeroExtend(mReqs.remaining()), ff2fifof(mReqs), ff2fifof(mRsps));

  // current lookup's depth
  Reg#(TDepth)    currentDepth     <- mkRegU();
  Reg#(CapNumber) pendingCapNumber <- mkRegU();
  Reg#(Vector#(CapsPerFlit,Bool)) pendingTags <- mkRegU();
  Reg#(Vector#(CapsPerFlit,Bool)) pendingCapEnable <- mkRegU();
  Vector#(tdepth,Reg#(Bit#(CheriDataWidth))) oldTags <- replicateM(mkRegU());

  // module helper functions
  /////////////////////////////////////////////////////////////////////////////

  function Bool isCovered (CheriPhyAddr addr);
    Bool r = True;
    if (addr < coveredStrtAddr || addr >= coveredEndAddr) r = False;
    if (addr >= tagTabStrtAddr && addr < tagTabEndAddr) r = False;
    return r;
  endfunction

  function CheriPhyBitAddr getTableAddr(TDepth cd, CapNumber cn);
    TableLvl t = tableDesc[cd];
    CheriPhyBitAddr bitAddr = unpack(zeroExtend(cn >> t.shiftAmnt));
    bitAddr.byteAddr = unpack(pack(bitAddr.byteAddr) + pack(t.startAddr));
    return bitAddr;
  endfunction

  function TableEntry getTableEntry(TDepth cd, CapNumber cn, Bit#(CheriDataWidth) tags);
    CheriPhyBitAddr a = getTableAddr(cd,cn);
    CheriPhyBitOffset bitOffset = truncate(pack(a));
    if (cd == leafLvl) begin
      // if leaf lvl, return a LineTags
      Vector#(TDiv#(CheriDataWidth,SizeOf#(LineTags)),LineTags) lines = unpack(tags);
      CheriPhyBitOffset idx = bitOffset >> valueof(TLog#(SizeOf#(LineTags)));
      // XXX here we rely on unaligned accesses to be single flit,
      // as we may create non existing tags by shifting right by alignShift
      // TODO add an assertion at the entrance in the module
      Bit#(TLog#(SizeOf#(LineTags))) alignShift = truncate(bitOffset);
      return tagged Leaf unpack(pack(lines[idx])>>alignShift);
    end else begin
      // if node lvl, return a single tag
      return tagged Node unpack(tags[bitOffset]);
    end
  endfunction

  function Bit#(CheriDataWidth) getOldTagsEntry (
    TDepth cd,
    CapNumber cn,
    Bit#(CheriDataWidth) tags);
    TableLvl t = tableDesc[cd+1]; // XXX TODO add dynamic assertion on level XXX
    CheriPhyBitAddr a = getTableAddr(cd,cn);
    CheriPhyBitOffset shft = truncate(pack(a));
    CheriPhyBitOffset shftMask = ~0<<t.groupFactorLog;
    Bit#(CheriDataWidth) tagsMask = ~(~0<<t.groupFactor);
    return ((tags>>(shft&shftMask))&tagsMask);
  endfunction

  function Bit#(CheriDataWidth) getNewTagsEntry (
    TDepth cd,
    CapNumber cn,
    Vector#(howmanybits,Bool) ts,
    Vector#(howmanybits,Bool) ce,
    Bit#(CheriDataWidth) old);
    TableLvl t = tableDesc[cd+1]; // XXX TODO add dynamic assertion on level XXX
    CheriPhyBitAddr a = getTableAddr(cd,cn);
    CheriPhyBitOffset shft = truncate(pack(a));
    CheriPhyBitOffset shftMask = ~(~0<<t.groupFactorLog);
    CheriPhyBitOffset bitOffset = shft&shftMask;
    Bit#(CheriDataWidth) newTags = old;
    Integer i = 0;
    for (i = 0; i < valueOf(howmanybits); i = i + 1) begin
      if (ce[i]) newTags[bitOffset+fromInteger(i)] = pack(ts[i]);
    end
    return newTags;
  endfunction

  function CheriMemRequest craftTagReadReq (TDepth d, CapNumber cn);
    CheriPhyAddr a = getTableAddr(d,cn).byteAddr;
    CheriMemRequest mReq = defaultValue;
    mReq.addr            = a;
    mReq.masterID        = mID;
    mReq.transactionID   = transNum;
    mReq.operation       = tagged Read {
                              uncached: False,
                              linked: False,
                              noOfFlits: 0,
                              bytesPerFlit: cheriBusBytes
                            };
    return mReq;
  endfunction

  function CheriMemRequest craftTagWriteReq (
    TDepth d, // depth in the table
    CapNumber cn, // capability number targetted
    Vector#(howmanybits,Bool) ts, // tags
    Vector#(howmanybits,Bool) ce, // "cap enable"
    Maybe#(TableLvl) nz); // need zeroing
    // prepare address
    CheriPhyBitAddr a = getTableAddr(d,cn);
    CheriPhyByteOffset byteOffset = a.byteAddr.byteOffset;
    Bit#(3) bitOffset = a.bitOffset;

    Bool z = False; // no zeroing detected yet...

    // prepare byte enable
    Vector#(CheriBusBytes, Bool) wbyteE = replicate(False);
    if (nz matches tagged Valid .t) begin
      z = True; // we need zeroing
      Integer i = 0;
      CheriPhyByteOffset nodeOffset = byteOffset&(~0 << (t.groupFactorLog - 3));
      for (i = 0; i < (div(t.groupFactor,8)); i = i + 1) begin
        wbyteE[nodeOffset+fromInteger(i)] = True;
      end
    end
    wbyteE[byteOffset] = True;
    // prepare bit enable and new data
    Bit#(8) wbitE   = z ? ~0 : 0;
    Bit#(8) newData = 0;
    function fand(x,y) = x && y;
    Vector#(howmanybits,Bool) leafData = zipWith(fand,ts,ce);
    if (d == leafLvl) begin
      Integer i = 0;
      for (i = 0; i < valueOf(howmanybits); i = i + 1) begin
        wbitE[bitOffset+fromInteger(i)] = z ? 1 : pack(ce[i]);
        newData[bitOffset+fromInteger(i)] = pack(leafData[i]);
      end
    end else begin
      wbitE[bitOffset] = 1;
      newData[bitOffset] = pack(any(id,leafData));
    end

    CheriMemRequest mReq = defaultValue;
    mReq.addr            = a.byteAddr;
    mReq.masterID        = mID;
    mReq.transactionID   = transNum;
    CheriData wdata = Data {
                cap: ?,
                data: zeroExtend(newData) << {byteOffset,3'b0}
              };
    mReq.operation = tagged Write {
                          uncached: False,
                          conditional: False,
                          byteEnable: wbyteE,
                          bitEnable: wbitE,
                          data: wdata,
                          last: True
                        };
    return mReq;
  endfunction

  function Action doTransition (
    Maybe#(CheriMemRequest) mmr,
    TDepth newDepth,
    State newState,
    Bool useRsp
    ) = action
    debug2("taglookup",
      $display("<time %0t TagLookup> table structure -", $time, fshow(tableDesc)
    ));
    case (mmr) matches
      tagged Valid .mr: begin
        // send the tag cache request and increment the transaction number
        debug2("taglookup",
          $display("<time %0t TagLookup> sending lookup: ",
          $time, fshow(mr)
        ));
        tagCacheReq.enq(mr);
        useNextRsp.enq(useRsp);
        transNum <= transNum + 1;
      end
    endcase
    // update lookup depth
    currentDepth <= newDepth;
    // do state transistion
    state <= newState;
    debug2("taglookup",
      $display("<time %0t TagLookup> pendingCapNumber %x, currentDepth %d -> %d, state ",
      $time, pendingCapNumber, currentDepth, newDepth, fshow(state), " -> ", fshow(newState)
    ));
  endaction;
  
  rule feedTagCache;
    tagCache.put(tagCacheReq.first());
    tagCacheReq.deq();
  endrule

  // module rules
  /////////////////////////////////////////////////////////////////////////////

  // initialisation rule
  /////////////////////////////////////////////////////////////////////////////
  rule initialise (state == Init);
    `ifndef BLUESIM
      TableLvl t = tableDesc[rootLvl];
      // zero toplevel of tag table in memory
      if (zeroAddr < unpack(pack(t.startAddr) + fromInteger(t.size))) begin
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
        tagCacheReq.enq(mReq);
        useNextRsp.enq(False);
        debug2("taglookup",
          $display(
          "<time %0t TagLookup> zeroing tag table toplevel: ",
          $time, fshow(mReq)
        ));
        // increment transaction number and address
        transNum <= transNum + 1;
        zeroAddr.lineNumber <= zeroAddr.lineNumber + 1;
      end else 
    `endif
    // when table zeroed, go to Serving state
    state <= Idle;
  endrule

  // Simply stuff "True" into commits because we never cancel transactions here
  /////////////////////////////////////////////////////////////////////////////
  rule stuffCommits;
    tagCache.nextWillCommit(True);
  endrule

  // drain unused memory response when in Idle state (useful for unused write responses)
  rule drainMemRsp (tagCache.response.canGet() && (getReq || !useNextRsp.first()));
    let _ <- tagCache.response.get();
    useNextRsp.deq();
    debug2("taglookup",
      $display(
      "<time %0t TagLookup> Dequed memory request, getReq: %x, useNextRsp: %x, state: ",
      $time, getReq, useNextRsp.first(), fshow(state)
    ));
  endrule
  
  // Main lookup rule
  /////////////////////////////////////////////////////////////////////////////
  rule doLookup (state != Idle && state != Init && useNextRsp.notFull);
    // Common signals
    ///////////////////////////////////////////////////////////////////////////
    // current memory response
    //CheriMemResponse memRsp = tagCacheRsps.first();
    Bool memRspReady = False;
    if (tagCache.response.canGet())
      memRspReady = useNextRsp.first;
    CheriMemResponse memRsp = tagCache.response.peek();
    //CheriMemResponse memRsp <- tagCache.response.get();
    debug2("taglookup",
      $display(
      "<time %0t TagLookup> memRsp valid: %x, current memRsp ",
      $time, tagCache.response.canGet(), fshow(memRsp)
    ));
    // current tag table entry
    Bit#(CheriDataWidth) rspData = memRsp.data.data;
    TableEntry tagTableEntry = getTableEntry(currentDepth, pendingCapNumber, rspData);
    // state transition signals (with default values)
    Maybe#(CheriMemRequest) newCacheReq = tagged Invalid;
    TDepth newDepth                     = currentDepth - 1;
    State newState                      = state;
    Bool  useRsp                        = False;
    Bool  doATransition                 = False;
    // define a zingle zero or a single one
    Vector#(1,Bool) zero = replicate (False);
    Vector#(1,Bool) one  = replicate (True);

    case (state) matches
      // ReadTag state
      /////////////////////////////////////////////////////////////////////////
      ReadTag &&& (memRspReady && lookupRsp.notFull()): begin
        // check transition behaviour
        case (tagTableEntry) matches
          tagged Node .t: begin
            if (!t) begin
              // early 0
              debug2("taglookup",
                $display(
                "<time %0t TagLookup> ReadTag 0 early response (currentDepth %d)",
                $time, currentDepth
              ));
              // enqueue a 0 response
              lookupRsp.enq(unpack(0));
              // prepare jump back to Idle state
              newState = Idle;
            end else begin
              // tag 1, need new lookup ("recursive state")
              debug2("taglookup",
                $display(
                "<time %0t TagLookup> ReadTag 1 (currentDepth %d)",
                $time, currentDepth
              ));
              // request next table entry
              newCacheReq = tagged Valid craftTagReadReq(newDepth,pendingCapNumber);
              useRsp = True;
            end
          end
          tagged Leaf .ts: begin
            // Reached a Leaf of the table, return lookup
            debug2("taglookup",
              $display(
              "<time %0t TagLookup> ReadTag leaf node reached (currentDepth %d) : %b",
              $time, currentDepth, ts
            ));
            // enqueue the lookup response
            lookupRsp.enq(ts);
            // prepare jump back to Idle state
            newState = Idle;
          end
        endcase
        getReq.send();
        doATransition = True;
      end
      // SetTag state
      /////////////////////////////////////////////////////////////////////////
      SetTag &&& memRspReady: begin
        // detect 0 -> 1 transition
        CheriPhyBitAddr a = getTableAddr(currentDepth,pendingCapNumber);
        Maybe#(TableLvl) needZeros = (!unpack(rspData[{a.byteAddr.byteOffset,a.bitOffset}])) ?
            tagged Valid tableDesc[currentDepth] : tagged Invalid;
        if (needZeros matches tagged Valid .t) debug2("taglookup",
          $display(
          "<time %0t TagLookup> SetTag 0 -> 1 transition detected at depth %d",
          $time, currentDepth
        ));
        // transition behaviour
        case (tagTableEntry) matches
          tagged Node .t: begin
            if (currentDepth == leafLvl+1) begin
              newCacheReq = tagged Valid craftTagWriteReq(leafLvl,pendingCapNumber,pendingTags,pendingCapEnable,needZeros);
              newState = Idle;
            end else begin
              newCacheReq = tagged Valid craftTagWriteReq(newDepth,pendingCapNumber,one,one,needZeros);
              useRsp = True;
            end
          end
          tagged Leaf .ts: begin
            newState = Idle;
          end
        endcase
        getReq.send();
        doATransition = True;
      end

      // ClearTag state
      /////////////////////////////////////////////////////////////////////////////
      ClearTag &&& memRspReady: begin
        // get all the tags for the current entry
        Bit#(CheriDataWidth) currentTags =
          getOldTagsEntry(currentDepth,pendingCapNumber,rspData);
        // transition behaviour
        case (tagTableEntry) matches
          // On a non leaf node with a zero, finish early
          tagged Node .t &&& (t == False): begin
            debug2("taglookup",
              $display(
                "<time %0t TagLookup> early 0 clearing tag",
                $time
            ));
            newState = Idle;
          end
          // On a non leaf node with a one, recurse further
          tagged Node .t &&& (t == True): begin
            debug2("taglookup",
              $display(
                "<time %0t TagLookup> found 1 when clearing tag, keep going down...",
                $time
            ));
            // update the already looked up tags
            oldTags[currentDepth] <= currentTags;
            // send next lookup
            newCacheReq = tagged Valid craftTagReadReq(newDepth,pendingCapNumber);
            useRsp = True;
          end
          // On a leaf node...
          tagged Leaf .ts: begin
            // unconditionally write a zero at the current level
            newCacheReq = tagged Valid craftTagWriteReq(leafLvl,pendingCapNumber,pendingTags,pendingCapEnable,tagged Invalid);
            // if we were not already at the root level...
            if (leafLvl < rootLvl) begin
              // ...get the new state of tags for the current level
              Bit#(CheriDataWidth) nt =
                getNewTagsEntry(leafLvl,pendingCapNumber,pendingTags,pendingCapEnable,currentTags);
              // ...check on previous level
              if (nt == 0) begin
                newDepth = leafLvl + 1;
                newState = FoldZeroes;
              end else newState = Idle;
            end
            // otherwise jump back to Idle State
            else newState = Idle;
          end
        endcase
        getReq.send();
        doATransition = True;
      end
      // FoldZeroes state
      /////////////////////////////////////////////////////////////////////////////
      FoldZeroes: begin
        // unconditionally fold a zero at the current level
        newCacheReq = tagged Valid craftTagWriteReq(currentDepth,pendingCapNumber,zero,one,tagged Invalid);
        // get the new state of tags for the current level
        Bit#(CheriDataWidth) nt =
          getNewTagsEntry(currentDepth,pendingCapNumber,zero,one,oldTags[currentDepth]);
        // check on previous level (if we were not already at the root level)
        if (nt == 0 && currentDepth < rootLvl) begin
          newDepth = currentDepth + 1;
          newState = FoldZeroes;
        end
        // otherwise jump back to Idle State
        else newState = Idle;
        doATransition = True;
      end
      default: begin
        // Handle the case where there is a pending response that the state machine doesn't want.
        if (tagCache.response.canGet() && !useNextRsp.first()) getReq.send();
      end
    endcase
    // do the transition
    if (doATransition) doTransition(newCacheReq, newDepth, newState, useRsp);
  endrule

  // module Slave interface
  /////////////////////////////////////////////////////////////////////////////

  interface Slave cache;

    // lookup Slave request interface
    //////////////////////////////////////////////////////
    interface CheckedPut request;
      method Bool canPut() = (state == Idle);
      // tag request
      //////////////////////////////
      method Action put(CheriMemRequest req) if (state == Idle);
        debug2("taglookup",
          $display(
            "<time %0t TagLookup> received request ",
            $time, fshow(req)
        ));
        // next state to go to
        State nextState  = Idle;
        // check whether we are in the covered region
        Bool doTagLookup = isCovered(req.addr);
        // initialise future pending tags
        Vector#(CapsPerFlit,Bool) newPendingTags = unpack(0);
        Vector#(CapsPerFlit,Bool) newPendingCapEnable = unpack(0);
        // initialise a toplevel table lookup
        CheriCapAddress capAddr = unpack(pack(req.addr));
        CheriMemRequest mReq = craftTagReadReq (rootLvl,capAddr.capNumber);
        case (req.operation) matches
          // when it's a read
          //////////////////////////////
          tagged Read .rop: begin
            readReqs.enq(doTagLookup);
            nextState = ReadTag;
          end
          // when it's a write
          //////////////////////////////
          tagged Write .wop: begin
            // what to write ?
            // derive "cap enable"
            Vector#(CapsPerFlit,Bool) capEnable;
            Integer i = 0;
            Integer bot = 0;
            for (i = 0; i < valueOf(CapsPerFlit); i = i + 1) begin
              Bit#(CapBytes) capBEs = pack(wop.byteEnable)[bot+valueOf(CapBytes)-1:bot];
              capEnable[i] = (capBEs == 0) ? False:True;
              bot = bot + valueOf(CapBytes);
            end
            // get cap tags
            Vector#(CapsPerFlit,Bool) capTags = wop.data.cap;
            // and cap tags with cap enable
            function Bool andBool (Bool x, Bool y) = (x == True && y == True ) ? True : False;
            Vector#(CapsPerFlit,Bool) andTags = zipWith(andBool,capTags,capEnable);
            // update new pending tags
            newPendingTags = capTags;
            newPendingCapEnable = capEnable;
            //check wether to write anything or not
            function Bool isTrue  (Bool x) = x == True;
            function Bool isFalse (Bool x) = x == False;
            if (all(isFalse,capEnable)) begin
              nextState = Idle;
              doTagLookup = False;
            end else if (all(isFalse,andTags)) begin
              // when all tags to write are 0
              nextState = ClearTag;
            end else begin
              // when writing at least a 1
              mReq = craftTagWriteReq(rootLvl,capAddr.capNumber,capTags,capEnable,tagged Invalid);
              nextState = SetTag;
            end
          end
          // ignore other types of requests
          default: begin
            doTagLookup = False;
            nextState = Idle;
          end
        endcase
        // when a lookup is required
        if (doTagLookup) begin
          pendingCapNumber <= capAddr.capNumber;
          pendingTags      <= newPendingTags;
          pendingCapEnable <= newPendingCapEnable;
          debug2("taglookup",
            $display(
              "<time %0t TagLookup> Starting lookup with capNum = ",
              $time, fshow(capAddr.capNumber),
              " ( pending tags = ", fshow(newPendingTags),
              ", pending cap enable = ",fshow(newPendingCapEnable)," )"
          ));
          doTransition(tagged Valid mReq,rootLvl,nextState,True);
        end else debug2("taglookup",
          $display(
            "<time %0t TagLookup> memory not covered",
            $time
        ));
      endmethod
    endinterface

    // lookup Slave response interface
    //////////////////////////////////////////////////////
    interface CheckedGet response;
      method Bool canGet() = !readReqs.first() || lookupRsp.notEmpty();
      method CheriTagResponse peek() = (readReqs.first()) ?
          tagged Covered lookupRsp.first():
          tagged Uncovered;
      method ActionValue#(CheriTagResponse) get() if (!readReqs.first() || lookupRsp.notEmpty());
        // put response together
        CheriTagResponse tr = tagged Uncovered;
        // in case of covered request, dequeue the lookup response
        if (readReqs.first()) begin
          tr = tagged Covered lookupRsp.first();
          lookupRsp.deq();
        end
        // dequeue the pending request
        readReqs.deq();
        // debug msg and return response
        debug2("taglookup",
          $display(
            "<time %0t TagLookup> got valid lookup response ",
            $time, fshow(tr)
        ));
        return tr;
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
