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
import ConfigReg::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Library::*;

interface Fifo#(type dataT);
  method Action enq(dataT d);
  method dataT first;
  method Action deq;
  method dataT search;
  method Action upd(dataT d);
endinterface

//XXX ndave: If we can clean this up a bit, we could use it for verification

module mkBypassFifo(Fifo#(dataT))
  provisos(Bits#(dataT, dataSz));

  Reg#(dataT)            data <- mkRegU;
  Reg#(Bool)            valid <- mkReg(False);
  Wire#(Maybe#(dataT)) enqing <- mkDWire(Invalid);
  Wire#(Bool)          deqing <- mkDWire(False);
  Wire#(Maybe#(dataT)) upding <- mkDWire(Invalid);

  rule doValid;
    valid <= isValid(enqing) && !deqing ? True : deqing ? False : valid;
  endrule

  rule doData;
    data <= isValid(enqing) && !deqing ? validValue(enqing) :
            isValid(upding) ? validValue(upding) : data;
  endrule

  method Action enq(dataT d) if(!valid);
    enqing <= Valid(d);
  endmethod

  method dataT first if(valid || isValid(enqing));
    return valid ? data : validValue(enqing);
  endmethod

  method Action deq if(valid || isValid(enqing));
    deqing <= True;
  endmethod

  method dataT search if(valid);
    return data;
  endmethod

  method Action upd(dataT d) if(valid && !deqing);
    upding <= Valid(d);
  endmethod
endmodule

interface Bram#(type indexT, type dataT);
  method Action readReq(indexT index);
  method ActionValue#(dataT) readResp();
  method Action write(indexT index, dataT data);

  method Action readReqD(indexT index);
  method ActionValue#(dataT) readRespD();
  method Action writeD(indexT index, dataT data);
endinterface

interface InitialisedBram#(type indexT, type dataT);
  interface Bram#(indexT, dataT) bram;
  method Bool isInitialised;
endinterface

`ifndef VERIFY2

module mkUnguardedBram(Bram#(indexT, dataT))
  provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT));

  RegFile#(indexT, dataT) mem <- mkRegFileWCF(minBound, maxBound);
  Reg#(dataT)         dataReg <- mkRegU;

  method Action readReq(indexT index);
    dataReg <= mem.sub(index);
  endmethod

  method ActionValue#(dataT) readResp;
    return dataReg;
  endmethod
  
  method Action write(indexT index, dataT data);
    mem.upd(index, data);
  endmethod
  
  method Action readReqD(index) if (False) = noAction;
  method readRespD if (False);
    return (?);
	endmethod
  method Action writeD(index, data) if (False) = noAction;
endmodule

// Bram with implicit conditions on reads but absolutely no write
// forwarding i.e. reads during writes will see stale value.
module mkBramNoWriteForward(Bram#(indexT, dataT))
  provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT));

  Bram#(indexT, dataT)  bram <- mkUnguardedBram;
  FIFOF#(void)         tokenQ <- mkLFIFOF; // this ensures at most one outstanding read.

  method Action readReq(indexT index);
    bram.readReq(index);
    tokenQ.enq(?);
  endmethod

  method ActionValue#(dataT) readResp;
    let bramData <- bram.readResp();
    tokenQ.deq();
    return bramData;
  endmethod
  
  method Action write(indexT index, dataT data);
    bram.write(index, data);
  endmethod
  
  method Action readReqD(index) if (False) = noAction;
  method readRespD if (False) = ?;
  method Action writeD(index, data) if (False) = noAction;
endmodule

module mkBram(Bram#(indexT, dataT))
  provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT));

  Bram#(indexT, dataT)              bram <- mkUnguardedBram;
  FIFO#(indexT)                readIndex <- mkLFIFO;
  FIFO#(Maybe#(dataT))       forwardData <- mkLFIFO;
  Fifo#(Tuple2#(indexT, dataT)) readData <- mkBypassFifo;
  Reg#(indexT)                writeIndex <- mkConfigReg(minBound);
  Reg#(dataT)                  writeData <- mkConfigRegU;
  RWire#(indexT)          writeIndexWire <- mkRWire();
  RWire#(dataT)            writeDataWire <- mkRWire();

  rule fill;
    let forwarded <- popFIFO(forwardData);
    let index     <- popFIFO(readIndex);
    let bramData  <- bram.readResp();
    let data      =  isValid(forwarded) ? validValue(forwarded) : bramData;
    readData.enq(tuple2(index, data));
  endrule

  rule update;
    match {.i, .d} = readData.search;
    readData.upd(tuple2(i, (Valid(i) == writeIndexWire.wget()) ? validValue(writeDataWire.wget) : (i==writeIndex) ? writeData : d));
  endrule

  method Action readReq(indexT index);
    forwardData.enq((Valid(index) == writeIndexWire.wget()) ? writeDataWire.wget() : Invalid);
    bram.readReq(index);
    readIndex.enq(index);
  endmethod

  method ActionValue#(dataT) readResp();
    readData.deq;
    match {.i, .d} = readData.first;
    return (Valid(i)==writeIndexWire.wget()) ? validValue(writeDataWire.wget()) : (i==writeIndex) ? writeData : d;
  endmethod
  
  method Action write(indexT index, dataT data);
    bram.write(index, data);
    writeIndex <= index;
    writeData <= data;
    writeIndexWire.wset(index);
    writeDataWire.wset(data);
  endmethod

  method Action readReqD(indexT index);
    forwardData.enq(Invalid);
    bram.readReq(index);
    readIndex.enq(index);
  endmethod

  method ActionValue#(dataT) readRespD();
    match {.i, .d} = readData.first;
    readData.deq;
    return (d);
  endmethod

  method Action writeD(indexT index, dataT data);
    bram.write(index, data);
  endmethod
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

  method Action readReqD(indexT index);
		addr  <= index;
		value <= rf.sub(index);
		valid <= True;
  endmethod

  method ActionValue#(dataT) readRespD();
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
  Reg#(Bool)        initialised <- mkConfigReg(False);
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
                            provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT), Arith#(indexT));
  Bram#(indexT, dataT) the_bram <- mkBram;
  InitialisedBram#(indexT, dataT) wrapped_bram <- mkInitialisedBramWrapper(the_bram, getInitialValue);
  return wrapped_bram;
endmodule

module mkInitialisedBramNoWriteForward#(function dataT getInitialValue(indexT idx))(InitialisedBram#(indexT, dataT))
                            provisos(Bits#(dataT, dataSz), Bits#(indexT, indexSz), Bounded#(indexT), Eq#(indexT), Arith#(indexT));
  Bram#(indexT, dataT) the_bram <- mkBramNoWriteForward;
  InitialisedBram#(indexT, dataT) wrapped_bram <- mkInitialisedBramWrapper(the_bram, getInitialValue);
  return wrapped_bram;
endmodule
