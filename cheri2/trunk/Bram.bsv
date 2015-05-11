/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2012-2013 Robert M. Norton
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
 *
 ******************************************************************************
 *
 * Author: Asif Khan <asif.khan@sri.com>
 *         Nirav Dave <ndave@csl.sri.com>
 *         Robert M. Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Unguarded and guarded implementations of Block RAM
 *
 ******************************************************************************/

import RegFile::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Library::*;
import EHR::*;
import BRAM::*;
import DefaultValue::*;
import MEM::*;

interface Fifo#(type dataT);
  method Action enq(dataT d);
  method dataT first;
  method Action deq;
  method dataT search;
  method Action upd(dataT d);
endinterface

module mkBypassFifo(Fifo#(dataT))
   provisos(Bits#(dataT, dataSz));

   EHR#(3, Maybe#(dataT))  mvalue <- mkEHR(Invalid);
   function full(n) = isValid(mvalue[n]);

   // -----

   method Action enq(x) if (!full(0));
      mvalue[0] <= tagged Valid x;
   endmethod

   // -----

   method dataT search if (mvalue[1] matches tagged Valid .x);
      return x;
   endmethod

   method Action upd(dataT d) if (full(1));
      mvalue[1] <= tagged Valid d;
   endmethod

   // -----

   method dataT first() if (mvalue[2] matches tagged Valid .x);
      return x;
   endmethod

   method Action deq() if (full(2));
      mvalue[2] <= Invalid;
   endmethod
endmodule

interface Bram#(type indexT, type dataT);
  method Action readReq(indexT index);
  method ActionValue#(dataT) readResp();
  method Action write(indexT index, dataT data);

  method Action readReqD(indexT index); // for debug unit
  method ActionValue#(dataT) readRespD();
  method Action writeD(indexT index, dataT data);
endinterface

interface InitialisedBram#(type indexT, type dataT);
  interface Bram#(indexT, dataT) bram;
  method Bool isInitialised;
endinterface

`ifndef VERIFY

module mkBram(Bram#(indexT, dataT))
  provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz),
	   Bounded#(indexT), Eq#(indexT));

  MEM#(indexT, dataT)               bram <- mkMEM;
  FIFO#(indexT)                readIndex <- mkPipelineFIFO;
  FIFO#(Maybe#(dataT))       forwardData <- mkPipelineFIFO;
  Fifo#(Tuple2#(indexT, dataT)) readData <- mkBypassFifo;
  EHR#(2, indexT)             writeIndex <- mkEHR(minBound);
  EHR#(2, dataT)               writeData <- mkEHRU;

  rule fill;
    let forwarded <- popFIFO(forwardData);
    let index     <- popFIFO(readIndex);
    let bramData  <- bram.read.get();
    let data      =  (forwarded matches tagged Valid .x ? x : bramData);
    readData.enq(tuple2(index, data));
  endrule

  rule update;
    match {.i, .d} = readData.search;
    readData.upd(tuple2(i, (i == writeIndex[1] ? writeData[1] : d)));
  endrule

  method Action readReq(indexT index);
    forwardData.enq(index == writeIndex[1] ? tagged Valid writeData[1] : Invalid);
    bram.read.put(index);
    readIndex.enq(index);
  endmethod

  method ActionValue#(dataT) readResp;
    match {.i, .d} = readData.first;
    readData.deq;
     return d;
     //(i==writeIndex[1] ? writeData[1] : d);
  endmethod

  method Action write(indexT index, dataT data);
    bram.write(index, data);
    writeIndex[0] <= index;
    writeData[0] <= data;
  endmethod

   // =======

  method Action readReqD(indexT index);
    forwardData.enq(Invalid);
    bram.read.put(index);
    readIndex.enq(index);
  endmethod

  method ActionValue#(dataT) readRespD;
    match {.i, .d} = readData.first;
    readData.deq;
    return (d);
  endmethod

  method Action writeD(indexT index, dataT data);
    bram.write(index, data);
  endmethod
endmodule

module mkBramNoWriteForward(Bram#(indexT, dataT))
                            provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT));
   MEM#(indexT, dataT) mem <- mkMEM;
   Bram#(indexT, dataT) the_bram = (
      interface Bram;
	 method readReq  = mem.read.put;
	 method readResp = mem.read.get;
	 method write    = mem.write;

	 method readReqD  = mem.read.put;
	 method readRespD = mem.read.get;
	 method writeD    = mem.write;
      endinterface );

   return the_bram;
endmodule

`else // VERIFY

module mkBram(Bram#(indexT, dataT))
  provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT));

  RegFile#(indexT, dataT)             rf <- mkRegFileFull();
  Reg#(Bool)                       valid <- mkReg(False);
  Reg#(indexT)                     addr  <- mkRegU;
  Reg#(dataT)                      value <- mkRegU;

  method Action readReq(indexT index) if (!valid);
    addr  <= index;
    value <= rf.sub(index);
    valid <= True;
  endmethod

  method ActionValue#(dataT) readResp if (valid);
    valid <= False;
	return value;
  endmethod

  method Action write(indexT index, dataT data);
    rf.upd(index,data);
    if (valid && (addr == index))
	  value <= data;
  endmethod

// =======

  method Action readReqD(indexT index) if (!valid);
    addr  <= index;
    value <= rf.sub(index);
    valid <= True;
  endmethod

  method ActionValue#(dataT) readRespD if (valid);
    valid <= False;
	return value;
  endmethod

  method Action writeD(indexT index, dataT data);
    rf.upd(index,data);
    if (valid && (addr == index))
	  value <= data;
  endmethod

endmodule

module mkBramNoWriteForward(Bram#(indexT, dataT))
    provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT));
  let m <- mkBram;
  return m;
endmodule

`endif

module mkInitialisedBramWrapper#(Bram#(indexT, dataT) the_bram, function dataT getInitialValue(indexT idx))(InitialisedBram#(indexT, dataT))
                            provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT), Arith#(indexT));
  Reg#(Bool)        initialised <- mkReg(False);
  Reg#(indexT)        initIndex <- mkReg(minBound);

  rule initialiseBram if (!initialised);
    the_bram.write(initIndex, getInitialValue(initIndex));
    initIndex <= initIndex + 1;
    if (initIndex == maxBound)
      initialised <= True;
  endrule

  method Bool isInitialised;
    return initialised;
  endmethod

  interface Bram bram;
    method Action readReq(indexT index) if (initialised);
      the_bram.readReq(index);
    endmethod

    method ActionValue#(dataT) readResp if (initialised);
      let r <- the_bram.readResp();
      return r;
    endmethod

    method Action write(indexT idx, dataT data) if (initialised);
      the_bram.write(idx, data);
    endmethod

    method Action readReqD(indexT index) if (initialised);
      the_bram.readReqD(index);
    endmethod

    method ActionValue#(dataT) readRespD if (initialised);
      let r <- the_bram.readRespD();
      return r;
    endmethod

    method Action writeD(indexT idx, dataT data) if (initialised);
      the_bram.writeD(idx, data);
    endmethod
  endinterface
endmodule

module mkInitialisedBram#(function dataT getInitialValue(indexT idx))(InitialisedBram#(indexT, dataT))
                            provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz),
				     Bounded#(indexT), Eq#(indexT), Arith#(indexT));
  Bram#(indexT, dataT) the_bram <- mkBram;
  InitialisedBram#(indexT, dataT) wrapped_bram <- mkInitialisedBramWrapper(the_bram, getInitialValue);
  return wrapped_bram;
endmodule

module mkInitialisedBramNoWriteForward#(function dataT getInitialValue(indexT idx))(InitialisedBram#(indexT, dataT))
                            provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT), Arith#(indexT));
   MEM#(indexT, dataT) mem <- mkMEM;
   Bram#(indexT, dataT) the_bram = (
      interface Bram;
	 method readReq  = mem.read.put;
	 method readResp = mem.read.get;
	 method write    = mem.write;

	 method readReqD  = ?;
	 method readRespD = ?;
	 method writeD    = ?;
      endinterface
				    );
   InitialisedBram#(indexT, dataT) wrapped_bram <- mkInitialisedBramWrapper(the_bram, getInitialValue);
   return wrapped_bram;
endmodule
