/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Robert N. M. Watson
 * Copyright (c) 2015 Colin Rothwell
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

`ifndef CHERIOS

import MIPS::*;
import Debug::*;
import Library::*;

import List  :: *;
import FIFO  :: *;
import FIFOF :: *;
import FF    :: *;
import SpecialFIFOs::*;
import ConfigReg::*;

import GetPut::*;
import ClientServer::*;
import Vector::*;
import Debug::*;

import MEM :: *;
import Clocks   :: *;

import BeriUGBypassFIFOF :: *;

`ifdef CAP
  `define USECAP 1
`elsif CAP128
  `define USECAP 1
`elsif CAP64
  `define USECAP 1
`endif

/* =================================================================
mkTLB
 =================================================================*/
 
typedef enum {Init, Serving, Read, DoRead, DoWrite, WriteVictim, FinishRead} TLBState deriving (Bits, Eq);
typedef Bit#(3) InterfaceNum;
typedef struct {
  Bool        valid;
  Bit#(5)     whichLoBit; // Bit to check for which EntryLo to use, the MSB of the page mask.
  Bit#(1)     oddPage;    // Which page is cached.
  Bool        global;
  Bit#(12)    pageMask;
  TlbEntryHi  entryHi;
  TlbEntryLo  entryLo;
} CachedTLBEntry deriving (Bits, Eq);

typedef struct {
    Bool                     found;
    Bit#(LogTLBSizePlusOne)  index;
    TlbRequest               request;
    InterfaceNum             requestInterface;
  } TlbReadToken deriving(Bits, Eq);
  
typedef struct {
    Bool        valid;
    Bit#(8)     asid;
    Address     badvaddr;
    Exception   exp;
  } TlbMiss deriving(Bits, Eq);

typedef enum { Smt, Rsp } TlbResponseSource deriving (Bits, Eq);
 
interface TLBIfc;
  interface Server#(TLBEntryT, TLBEntryT) readWrite;
  interface Vector#(NumTLBLookups, TranslationIfc) lookup;
  method Action debugDump;
  method Action putConfig(Bit#(LogAssosTLBSize) tlbRandom, Bool largeTlb, Bit#(8) entryHiAsid);
endinterface

`ifdef NOT_FLAT
  (*synthesize*)
`endif

module mkTLB#(Bit#(16) coreId)(TLBIfc ifc);
  FIFOF#(TLBEntryT)                      readWrite_fifo <- mkUGFIFOF1;
  FIFOF#(Bit#(LogTLBSizePlusOne))        readOut_fifo   <- mkFIFOF1;

  // These are not protected, but must never fill up or we will drop stuff.  Both req and rsp.
  // This works here because there only one outstanding TLB lookup is supported per cache.
  Vector#(NumTLBLookups,  FIFOF#(TlbRequest)) req_fifos   <- replicateM(mkUGFIFOF1);
  Vector#(NumTLBLookups, FIFOF#(TlbResponse)) rsp_fifos   <- replicateM(mkUGFIFOF1);
  Vector#(NumTLBLookups, Reg#(InstId))           instId   <- replicateM(mkConfigReg(7));

  CachedTLBEntry defaultCachedTLBEntry = ?;
  defaultCachedTLBEntry.valid = False;
  Vector#(NumTLBLookups, Vector#(AssosTLBSize, Reg#(CachedTLBEntry))) last_hit <- replicateM(replicateM(mkReg(defaultCachedTLBEntry)));
  
  FIFOF#(TlbReadToken) read_fifo <- mkLFIFOF;
  TlbAssosEntry invalidEntry = ?;
  invalidEntry.valid = False;
  Vector#(AssosTLBSize, Reg#(TlbAssosEntry))  entrySrch     <- replicateM(mkReg(invalidEntry));
  MEM#(Bit#(LogTLBSize), TlbAssosEntry)       entryHiHash   <- mkMEMNoFlow();
  MEM#(Bit#(LogTLBSizePlusOne), TlbEntryLo)   entryLo0      <- mkMEMNoFlow();
  MEM#(Bit#(LogTLBSizePlusOne), TlbEntryLo)   entryLo1      <- mkMEMNoFlow();

  Reg#(TLBState)               tlbState      <- mkReg(Init);
  Reg#(Bit#(LogTLBSize))       count         <- mkReg(0);
  Reg#(Bit#(8))                asid          <- mkConfigReg(0);
  Reg#(Bit#(LogAssosTLBSize))  randomIndex   <- mkConfigReg(fromInteger(assosTLBSize-1)); 
  Reg#(Bool)                   assosTlb      <- mkConfigRegU;

  Bit#(LogTLBSize) assosTLBSizeBits = fromInteger(assosTLBSize); 

  `ifdef MULTI
    Bit#(16)                   coreid        =  coreId;
  `endif

  rule initialize(tlbState == Init);
    entryHiHash.write(count, invalidEntry);
    Integer top = tlbSize-1;
    if (count == fromInteger(top)) tlbState <= Serving;
    count <= count + 1;
  endrule
  
  rule doRead(tlbState == DoRead);
    TLBEntryT reqIn = readWrite_fifo.first;
    Bit#(LogTLBSizePlusOne) tlbAddr = reqIn.tlbAddr;
    Bit#(LogTLBSize) hashKey = tlbAddr[logTLBSize-1:0] - assosTLBSizeBits;
    if (reqIn.write) hashKey = reqIn.assosEntry.entryHi.vpn2[logTLBSize-1:0] - assosTLBSizeBits;
    entryHiHash.read.put(hashKey);
    if (reqIn.tlbAddr < zeroExtend(assosTLBSizeBits)) begin
      entryLo0.read.put(zeroExtend(reqIn.tlbAddr));
      entryLo1.read.put(zeroExtend(reqIn.tlbAddr));
    end else begin
      entryLo0.read.put(zeroExtend(hashKey)+zeroExtend(assosTLBSizeBits));
      entryLo1.read.put(zeroExtend(hashKey)+zeroExtend(assosTLBSizeBits));
      tlbAddr = zeroExtend(hashKey)+zeroExtend(assosTLBSizeBits);
    end
    if (!reqIn.write) begin
      readWrite_fifo.deq();
      readOut_fifo.enq(tlbAddr);
      tlbState <= FinishRead;
    end else tlbState <= DoWrite;
    debug2("tlb", $display("TLB Read"));
  endrule
  
  rule doWrite(tlbState == DoWrite);
    TLBEntryT reqIn = readWrite_fifo.first;
    readWrite_fifo.deq();
    Bit#(LogTLBSizePlusOne) tlbAddr = reqIn.tlbAddr;
    Bit#(LogTLBSize) hashKey = reqIn.assosEntry.entryHi.vpn2[logTLBSize-1:0] - assosTLBSizeBits;
    Bool writeVictim = False;
    // Read the entry being replaced, if it is valid, place it in the 
    // associative victim cache.
    TLBEntryT oldEnt = ?;
    oldEnt.entryLo0 <- entryLo0.read.get();
    oldEnt.entryLo1 <- entryLo1.read.get();
    oldEnt.assosEntry <- entryHiHash.read.get();
    if (reqIn.tlbAddr < zeroExtend(assosTLBSizeBits)) begin
      entrySrch[reqIn.tlbAddr] <= reqIn.assosEntry;
      entryLo0.write(zeroExtend(reqIn.tlbAddr),reqIn.entryLo0);
      entryLo1.write(zeroExtend(reqIn.tlbAddr),reqIn.entryLo1);
    end else begin
      // If we are replacing a valid entry and this is a random write, save the victim.
      if (oldEnt.assosEntry.valid && reqIn.random) begin
        readWrite_fifo.enq(oldEnt);
        writeVictim = True;
      end
      entryHiHash.write(hashKey, reqIn.assosEntry);
      entryLo0.write(zeroExtend(hashKey)+zeroExtend(assosTLBSizeBits),reqIn.entryLo0);
      entryLo1.write(zeroExtend(hashKey)+zeroExtend(assosTLBSizeBits),reqIn.entryLo1);
    end
    // Clear the page caches for each interface.
    for(Integer i = 0; i < valueOf(NumTLBLookups); i=i+1) begin
      for (Integer j = 0; j < valueOf(AssosTLBSize); j=j+1)
        last_hit[i][j].valid <= False;
    end
    
    if (writeVictim)
      tlbState <= WriteVictim;
    else
      tlbState <= Serving;
    debug2("tlb", $display("TLB Write Done"));
  endrule
  
  rule writeVictimOut(tlbState == WriteVictim);
    TLBEntryT oldEnt = readWrite_fifo.first;
    readWrite_fifo.deq();
    entrySrch[randomIndex] <= oldEnt.assosEntry;
    entryLo0.write(zeroExtend(randomIndex),oldEnt.entryLo0);
    entryLo1.write(zeroExtend(randomIndex),oldEnt.entryLo1);
    tlbState <= Serving;
  endrule
  
  function Bool fifofNotEmpty(FIFOF#(a) f) = f.notEmpty();
  Bool aRequestIsIn = Vector::any(fifofNotEmpty, req_fifos);

  function getSourceString (sourceNum) = (case (sourceNum)
    0: return "Probe";
    1: return "Instruction";
    2: return "Data";
    /*3: return "Capability";*/
    3: return "DMA Instruction";
    4: return "DMA Data";
    default: return "Coprocessor";
  endcase);

  rule startTLB(tlbState == Serving);
    if (aRequestIsIn) begin
      Integer i;
      Bit#(LogAssosTLBSize) key = ?;
      Bool found = False;              
      InterfaceNum requestSource = ?;
      Address request = ?;
      
      Bool foundReq = False;
      for (i=0; i<=valueOf(NumTLBLookups)-1; i=i+1) begin
        if (req_fifos[i].notEmpty && !foundReq) begin
          request = req_fifos[i].first.addr;
          requestSource = fromInteger(i);
          foundReq = True;
        end
      end
      String sourceString = getSourceString(requestSource);

      `ifndef MULTI
        tlbtrace($display("%s TLB Search: Incoming VPN=%x ASID=%x", sourceString, request[63:13], asid));
      `else
        tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: %s TLB Search: Incoming VPN=%x ASID=%x", $time, coreid, sourceString, request[63:13], asid));
      `endif
			// This for-loop implelements the associative tlb search
      for (i=0; i<assosTLBSize; i=i+1) begin
        if (entrySrch[i].valid && // If the entry in the tlb is valid
            entrySrch[i].entryHi.r==request[63:62] &&  // If the top bits (the address space) of the request matches.
            // If the virtual page number matches, takeing into account the page size as defined by the page mask.
            ((entrySrch[i].entryHi.vpn2 ^ request[39:13]) & (~zeroExtend(entrySrch[i].pageMask))) == 0 && 
            // If the address space matches or this is a global entry.
            (entrySrch[i].entryHi.asid==asid || entrySrch[i].g)) begin
          if (found) $display("Two matching TLB indices! %d and %d.", key, fromInteger(i));
          key = fromInteger(i);
          found = True;
        end
        if (entrySrch[i].valid)
          debug2("tlb", $display("               Found=%x Table index=%2.0x VPN=%x ASID=%x",
                     found, i, {entrySrch[i].entryHi.r,entrySrch[i].entryHi.vpn2},
                     entrySrch[i].entryHi.asid));
      end

      Bit#(LogTLBSize) hashKey = request[logTLBSize+12:13] - zeroExtend(assosTLBSizeBits);
      entryHiHash.read.put(hashKey); // Submit the address to the entryHi table in any case.
      if (found) begin
        entryLo1.read.put(zeroExtend(key));
        entryLo0.read.put(zeroExtend(key));
      end else begin
        entryLo1.read.put(zeroExtend(hashKey) + zeroExtend(assosTLBSizeBits));
        entryLo0.read.put(zeroExtend(hashKey) + zeroExtend(assosTLBSizeBits));
      end
      
      //tlbState <= Read;
      read_fifo.enq(TlbReadToken{
              found: found,
              index: zeroExtend(key),
              request: req_fifos[requestSource].first,
              requestInterface: requestSource
            });
      req_fifos[requestSource].deq();
    end else if (readWrite_fifo.notEmpty)
      tlbState <= DoRead;
  endrule
  
  rule readTLB(tlbState == Serving);
    PhyAddress response = 0;
    Bool cached = ?;
    
    TlbReadToken read = read_fifo.first;
    Address request = read.request.addr;
    Bool write = read.request.write;
    Bool ll = read.request.ll;
    Bool fromDebug = read.request.fromDebug;
    Bit#(LogTLBSizePlusOne) foundIndex = read.index;
    Bool found = read.found;
    InterfaceNum requestSource = read.requestInterface;
    String sourceString = getSourceString(requestSource);
    TlbAssosEntry hashEntry <- entryHiHash.read.get();
    TlbEntryLo lo0 <- entryLo0.read.get();
    TlbEntryLo lo1 <- entryLo1.read.get();
    TlbAssosEntry matchedEntryHi = entrySrch[foundIndex];
    Bit#(5) whichLoBit = (found) ? matchedEntryHi.whichLoBit:0;
    TlbEntryLo matchedEntry = (request[12+whichLoBit] == 1'b1) ? lo1:lo0;
    Bit#(12) pageMask = (found) ? entrySrch[foundIndex].pageMask:0;
    response = {matchedEntry.pfn[27:12],
                matchedEntry.pfn[11:0]&~pageMask | request[23:12]&pageMask, 
                request[11:0]};
    debug2("tlb", $display("response: %x, matchedPFN: %x, pageMask: %x, request: %x, whichLoBit: %d, lo0/1: %x", 
              response, matchedEntry.pfn, pageMask, request, whichLoBit, (request[12+whichLoBit] == 1'b1)));
    cached = (matchedEntry.c != Uncached);
    
    if (!found && assosTlb) begin
      Bit#(LogTLBSize) hashKey = request[logTLBSize+12:13] - zeroExtend(assosTLBSizeBits);
    	if (hashEntry.valid && hashEntry.entryHi.r==request[63:62] 
    	    && hashEntry.entryHi.vpn2==request[39:13]
          && (hashEntry.entryHi.asid==asid || hashEntry.g)) begin
        foundIndex = zeroExtend(hashKey) + zeroExtend(assosTLBSizeBits);
        found = True;
        matchedEntryHi = hashEntry;
      end
      if (hashEntry.valid)
        debug2("tlb", $display("               Found=%x Mapped index=%2.0x VPN=%x ASID=%x",
                   found, hashKey, {hashEntry.entryHi.r,hashEntry.entryHi.vpn2},
                   hashEntry.entryHi.asid));
      else
        debug2("tlb", $display("               Mapped index %2.0x is invalid", hashKey));
    end
    
    // If no entry is matched, TLB miss; XTLB vector should be used.
    Exception exception = read_fifo.first.request.exception;
    if (!found && exception == None) begin
      if (requestSource == 1) // Instruction miss
        exception = ITLB;
      else
        if (write) exception = DTLBS;
        else exception = DTLBL;
    end
    
    // If the request is from the probe interface, replace the response with the index.
    if (requestSource == 0) response = zeroExtend(foundIndex);

    // If an entry is matched but is invalid, also a TLB miss; common vector
    // should be used.
    Bool valid = matchedEntry.v;
    if (exception == None && !valid) begin
      if (requestSource == 1) // Instruction miss
        exception = ITLBI;
      else
        if (write) exception = DTLBSI;
        else exception = DTLBLI;
    end

    // If an entry is valid and not writable, and this is a store operation,
    // this is a TLB modification exception.
    Bool writeAllowed = matchedEntry.d;
    if (exception == None && write && !writeAllowed) exception = Mod;

    //if (found)
      //debug2("tlb", $display("%s TLB Lookup Delivered: Found=%x index=%2.0x, pfn:%x cache:%d dirty:%d valid:%d global:%d", 
      //  sourceString, found, foundIndex, matchedEntry.pfn, matchedEntry.c, matchedEntry.d, matchedEntry.v, matchedEntry.g));
    //else
      //debug2("tlb", $display("%s TLB Lookup Missed", sourceString));
    
    Privilege priv = User;
    if (request[63:60] >= 4'h4) priv = Supervisor;
    if (request[63:60] >= 4'h8) priv = Kernel;
    
    //if (exception!=None) response = 36'b0;
    TlbResponse returnVal = TlbResponse{
            valid: True,
            addr: response, 
            exception: exception, 
            write: write, 
            ll:ll, 
            cached:cached, 
            fromDebug:fromDebug,
            priv:priv, 
            instId: read_fifo.first.request.instId
            `ifdef USECAP
              , noCapLoad: matchedEntry.noCapLoad,
              noCapStore: matchedEntry.noCapStore
            `endif
          };

    //tlbState <= Serving;
    read_fifo.deq;

    // Only use response for probe interface.
    rsp_fifos[requestSource].enq(returnVal);
    debug2("tlb", $display("%t: TLB put response into rsp_fifos", $time, fshow(returnVal), " to ", sourceString));
    if (exception==None) begin
      Bit#(LogAssosTLBSize) ti = truncate(request[20:12]); // TLB cache index.
      last_hit[requestSource][ti] <= CachedTLBEntry{
              valid: True,
              whichLoBit: whichLoBit,
              oddPage: request[12+whichLoBit],
              pageMask: matchedEntryHi.pageMask,
              global: matchedEntryHi.g,
              entryHi: matchedEntryHi.entryHi,
              entryLo: matchedEntry
            };
      `ifndef MULTI
        tlbtrace($display("(lookup %s %x->%x)", sourceString, request, response));
      `else
        tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: (lookup %s %x->%x)", $time, coreid, sourceString, request, response));
      `endif
    end else begin
      // Remember if we had a miss so we can fail quickly next time.
      debug2("tlb", $display("TLB %d Missed TLB.", requestSource));
      `ifndef MULTI
        tlbtrace($display("(lookup %s on %x was a miss, ExpCode:%d)", sourceString, request, exception));
      `else
        tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: (lookup %s on %x was a miss, ExpCode:%d)", $time, coreid, sourceString, request, exception));
      `endif
    end
  endrule 
  
  Vector#(NumTLBLookups, TranslationIfc) lookups;
  lookups [0] = interface TranslationIfc; // This is the TLB probe interface
    method ActionValue#(TlbResponse) request(TlbRequest reqIn) if (tlbState == Serving && !req_fifos[0].notEmpty);
      req_fifos[0].enq(reqIn);
      TlbResponse resp = ?;
      resp.valid = False;
      debug2("tlb", $display("TLB %d Put in search. Physical Page Base = %x, time: %t", 0, reqIn.addr, $time));
      return resp;
    endmethod
    method ActionValue#(TlbResponse) response if (rsp_fifos[0].notEmpty);
      TlbResponse returnVal = rsp_fifos[0].first;
      rsp_fifos[0].deq();
      debug2("tlb", $display("TLB %d Lookup Gotten from lookup. Physical Page Base = %x, time: %t", 0, returnVal.addr, $time));
      return returnVal;
    endmethod
  endinterface;
  for (Integer i=1; i<valueOf(NumTLBLookups); i=i+1) begin
    lookups [i] = interface TranslationIfc;

      let canPut = (req_fifos[i].notFull);

      method ActionValue#(TlbResponse) request(TlbRequest reqIn) if (canPut);
        Bit#(LogAssosTLBSize) ti = truncate(reqIn.addr[20:12]); // TLB cache index.
        // micro TLB hit address. Select it as default for speed.
        PhyAddress addr = {last_hit[i][ti].entryLo.pfn[27:12],
                                last_hit[i][ti].entryLo.pfn[11:0]&~last_hit[i][ti].pageMask 
                                | reqIn.addr[23:12]&last_hit[i][ti].pageMask,
                                reqIn.addr[11:0]};
        TlbResponse returnVal = TlbResponse{ valid: False,
                                              addr: addr, 
                                              exception: reqIn.exception, 
                                              write:reqIn.write, 
                                              ll:reqIn.ll, 
                                              cached:True, 
                                              fromDebug:reqIn.fromDebug, 
                                              priv:Kernel,
                                              `ifdef USECAP
                                                noCapLoad: False,
                                                noCapStore: False,
                                              `endif
                                              instId:reqIn.instId
                                  };
        debug2("tlb", $display("Attempted TLB %d lookup: reqId:%d, lastId:%x", i, reqIn.instId, instId[i]));
        if (reqIn.addr[63:56] == 8'h90 || (reqIn.addr[63:32] == 32'hFFFFFFFF && reqIn.addr[31:29] == 3'b101)) returnVal.cached = False;
        if (case(reqIn.addr[63:56])
              8'h98: return True;
              8'h90: return True;
              8'hA0: return True;
              8'hA8: return True;
              8'hB0: return True;
              default: return False;
            endcase || reqIn.exception!=None) begin // Simple translation for the xkphys regions which map into physical memory.
          returnVal.addr = reqIn.addr[39:0];
          returnVal.valid = True;
        end else if (reqIn.addr[63:32] == 32'hFFFFFFFF && (reqIn.addr[31:29] == 3'b100 || reqIn.addr[31:29] == 3'b101)) begin // Simple translation for the kseg1 & kseg0 regions which map into 512MB of physical memory.
          returnVal.addr = zeroExtend(reqIn.addr[28:0]);
          returnVal.addr[39:29] = 11'b0;
          returnVal.valid = True;
        end else if (last_hit[i][ti].valid 
                      && last_hit[i][ti].entryHi.r==reqIn.addr[63:62] 
                      // If the virtual page number matches, takeing into account the page size as defined by the page mask.
                      && ((last_hit[i][ti].entryHi.vpn2 ^ reqIn.addr[39:13]) & (~zeroExtend(last_hit[i][ti].pageMask))) == 0
                      && last_hit[i][ti].oddPage==reqIn.addr[23:12][last_hit[i][ti].whichLoBit] 
                      && (last_hit[i][ti].entryHi.asid==asid || last_hit[i][ti].global)) begin
          Privilege priv = User;
          if (reqIn.addr[63:60] >= 4'h4) priv = Supervisor;
          if (reqIn.addr[63:60] >= 4'h8) priv = Kernel;
          // If an entry is matched but is invalid, also a TLB miss; common vector
          // should be used.
          Exception exception = reqIn.exception;
          if (exception == None && !last_hit[i][ti].entryLo.v) begin
            if (i == 1) // Instruction miss
              exception = ITLBI;
            else        // Data miss
              if (reqIn.write) exception = DTLBSI;
              else exception = DTLBLI;
          end
          // If an entry is valid and not writable, and this is a store operation,
          // this is a TLB modification exception.
          Bool writeAllowed = last_hit[i][ti].entryLo.d;
          if (exception == None && reqIn.write && !writeAllowed) exception = Mod;
          returnVal.valid = True;
          returnVal.exception = exception;
          returnVal.cached = (last_hit[i][ti].entryLo.c != Uncached);
          returnVal.priv = priv;
          `ifdef USECAP
            returnVal.noCapLoad = last_hit[i][ti].entryLo.noCapLoad;
            returnVal.noCapStore = last_hit[i][ti].entryLo.noCapStore;
          `endif
          String sourceString = getSourceString(i);
          `ifndef MULTI
            tlbtrace($display("(lookup %s %x->%x)", sourceString, reqIn.addr, addr));
          `else
            tlbtrace($display("Time:%0d, Core:%0d, Thread:0 :: (lookup %s %x->%x)", $time, coreid, sourceString, reqIn.addr, addr));
          `endif
        // Only enq a new attempt if there is not one outstanding.
        end else begin
          req_fifos[i].enq(reqIn);
          debug2("tlb", $display("TLB %d Put in search. Virtual address = %x, instid: %x, time: %t", i, reqIn.addr, reqIn.instId, $time));
        end
        
        if (returnVal.valid) debug2("tlb", $display("TLB %d valid response", i, fshow(returnVal)));
        instId[i] <= reqIn.instId;
        return returnVal;
      endmethod
      method ActionValue#(TlbResponse) response() if (rsp_fifos[i].notEmpty);
        TlbResponse returnVal = rsp_fifos[i].first;
        debug2("tlb", $display("TLB %d took response from FIFO", i, fshow(rsp_fifos[i].first)));
        rsp_fifos[i].deq;
        return returnVal;
      endmethod
    endinterface;
  end

  interface Server readWrite;
    interface Put request;
      method Action put(reqIn) if (tlbState == Serving && !readWrite_fifo.notEmpty);
        readWrite_fifo.enq(reqIn);
        debug2("tlb", $display("Initiating TLB Read or Write: Write=%x Addr=%x EntHi=%x EntLo0=%x EntLo1=%x", reqIn.write, reqIn.tlbAddr, reqIn.assosEntry.entryHi, reqIn.entryLo0, reqIn.entryLo1));
      endmethod
    endinterface
    interface Get response;
      method get() if (tlbState == FinishRead && !readWrite_fifo.notEmpty);
        actionvalue
          TLBEntryT reqOut = ?;
          reqOut.tlbAddr = readOut_fifo.first;
          readOut_fifo.deq;
          reqOut.assosEntry <- entryHiHash.read.get();
          if (reqOut.tlbAddr < zeroExtend(assosTLBSizeBits))
            reqOut.assosEntry = entrySrch[readOut_fifo.first];
          reqOut.entryLo0 <- entryLo0.read.get();
          reqOut.entryLo1 <- entryLo1.read.get();
          debug2("tlb", $display("Delivering TLB Read: Addr=%x EntHi=%x EntLo0=%x EntLo1=%x", 
            reqOut.tlbAddr, reqOut.assosEntry.entryHi, reqOut.entryLo0, reqOut.entryLo1));
          tlbState <= Serving;
          return reqOut;
        endactionvalue
      endmethod
    endinterface
  endinterface
  
  interface lookup = lookups;
  
  method Action debugDump();
    for (Integer i=0; i<assosTLBSize; i=i+1) begin
      debugInst($display("DEBUG TLB ENTRY %2d Valid=%x Table VPN=%x ASID=%x", i, entrySrch[i].valid, {entrySrch[i].entryHi.r,entrySrch[i].entryHi.vpn2}, entrySrch[i].entryHi.asid));
    end
  endmethod
  
  method Action putConfig(Bit#(LogAssosTLBSize) tlbRandom, Bool largeTlb, Bit#(8) entryHiAsid);
     randomIndex <= tlbRandom;
     assosTlb <= largeTlb;
     asid <= entryHiAsid;
  endmethod
endmodule
`endif // CHERIOS
