/*-
 * Copyright (c) 2014 Jonathan Woodruff
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
 *****************************************************************************

 Philips USB interface logic
 ===========
 
 This module should run at 100MHz and translates an Avalon memory mapped interface
 to the asynchronous interface of the Philips ISP1761 chip on the Terasic DE4.
 
 *****************************************************************************/

import ConfigReg::*;
import FIFO::*;
import FIFOF::*;
import RegFile::*;
import Vector::*;
import DReg    :: *;
import SpecialFIFOs :: *;

interface FF#(type data, numeric type depth);
  method Action enq(data x);
  method Action deq();
  method data first();
  method Bool notFull();
  method Bool notEmpty();
  method Bit#(TAdd#(TLog#(depth), 1)) remaining();
endinterface

interface FFNext#(type data, numeric type depth);
  method Action enq(data x);
  method Action deq();
  method data first();
  method data next();
  method Bool notFull();
  method Bool notEmpty();
  method Bool nextNotEmpty();
  method Bit#(TAdd#(TLog#(depth), 1)) remaining();
endinterface

// Equal to Bluespec equivelant
module mkUGFF(FF#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
	RegFile#(Bit#(logDepth),data)    rf <- mkRegFileWCF(minBound, maxBound); // BRAM
  Reg#(Bit#(TAdd#(logDepth,1))) lhead <- mkConfigRegA(0);
  Reg#(Bit#(TAdd#(logDepth,1))) ltail <- mkConfigRegA(0);
  
  Bit#(TAdd#(logDepth,1)) level = lhead - ltail;
  Bool empty = (level==0);
  Bool full  = (level==fromInteger(valueOf(depth)));
  Bit#(logDepth) head = truncate(lhead);
  Bit#(logDepth) tail = truncate(ltail);
  
  method Action enq(data in);
    rf.upd(head,in);
    lhead <= lhead + 1;
  endmethod
  method Action deq();
    ltail <= ltail+1;
  endmethod
  method data first() = rf.sub(tail);
  method Bool notFull() = !full;
  method Bool notEmpty() = !empty;
  method Bit#(TAdd#(TLog#(depth), 1)) remaining() = fromInteger(valueOf(depth)) - level;
endmodule

module mkFF(FF#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
  FF#(data, depth) ff <- mkUGFF();
  return guardFF(ff);
endmodule

// FIFO with an interface for telling you the next first value
// by forwarding the deq.
module mkFFNext(FFNext#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
	RegFile#(Bit#(logDepth),data)       rf <- mkRegFileWCF(minBound, maxBound); // BRAM
  Reg#(Bit#(TAdd#(logDepth,1)))    lhead <- mkConfigRegA(0);
  Reg#(Bit#(TAdd#(logDepth,1))) ltail[2] <- mkCReg(2,0);
  
  Bit#(TAdd#(logDepth,1)) level = lhead - ltail[0];
  Bool empty = (level==0);
  Bool full  = (level==fromInteger(valueOf(depth)));
  Bit#(logDepth) head = truncate(lhead);
  Bit#(logDepth) tail = truncate(ltail[0]);
  
  // Look at new tail versus old head.
  // We don't want to look at forwarded head since data
  // data is not forwarded.
  Bit#(TAdd#(logDepth,1)) nlevel = lhead - ltail[1];
  Bool nempty = (nlevel==0);
  Bool nfull  = (nlevel==fromInteger(valueOf(depth)));
  Bit#(logDepth) ntail = truncate(ltail[1]);
  
  method Action enq(data in) if (!full);
    rf.upd(head,in);
    lhead <= lhead + 1;
  endmethod
  method Action deq() if (!empty);
    ltail[0] <= ltail[0]+1;
  endmethod
  method data first() if (!empty) = rf.sub(tail);
  method data next() if (!nempty) = rf.sub(ntail);
  method Bool notFull() = !full;
  method Bool notEmpty() = !empty;
  method Bool nextNotEmpty() = !nempty;
  method Bit#(TAdd#(TLog#(depth), 1)) remaining() = fromInteger(valueOf(depth)) - level;
endmodule

// FIFO with an interface for telling you the next first value
// by forwarding the deq.
module mkUGFFNext(FFNext#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
	RegFile#(Bit#(logDepth),data)       rf <- mkRegFileWCF(minBound, maxBound); // BRAM
  Reg#(Bit#(TAdd#(logDepth,1)))    lhead <- mkConfigRegA(0);
  Reg#(Bit#(TAdd#(logDepth,1))) ltail[2] <- mkCReg(2,0);
  
  Bit#(TAdd#(logDepth,1)) level = lhead - ltail[0];
  Bool empty = (level==0);
  Bool full  = (level==fromInteger(valueOf(depth)));
  Bit#(logDepth) head = truncate(lhead);
  Bit#(logDepth) tail = truncate(ltail[0]);
  
  // Look at new tail versus old head.
  // We don't want to look at forwarded head since data
  // data is not forwarded.
  Bit#(TAdd#(logDepth,1)) nlevel = lhead - ltail[1];
  Bool nempty = (nlevel==0);
  Bit#(logDepth) ntail = truncate(ltail[1]);
  
  method Action enq(data in);
    //if (full) $display("Panic!  Enquing to full FF!");
    rf.upd(head,in);
    lhead <= lhead + 1;
  endmethod
  method Action deq();
    //if (empty) $display("Panic!  Deqing from empty FF!");
    ltail[0] <= ltail[0]+1;
  endmethod
  method data first() = rf.sub(tail);
  method data next()  = rf.sub(ntail);
  method Bool notFull() = !full;
  method Bool notEmpty() = !empty;
  method Bool nextNotEmpty() = !nempty;
  method Bit#(TAdd#(TLog#(depth), 1)) remaining() = fromInteger(valueOf(depth)) - level;
endmodule

/* Like FFNext without the forwarding paths. */
module mkUGFFNextSlow(FFNext#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
	FF#(data, depth) ff <- mkUGFF();
  
  method enq = ff.enq;
  method deq = ff.deq;
  method first() = ff.first();
  method next()  = ff.first();
  method notFull() = ff.notFull();
  method notEmpty() = ff.notEmpty();
  method nextNotEmpty() = ff.notEmpty();
  method Bit#(TAdd#(TLog#(depth), 1)) remaining() = ff.remaining();
endmodule

// Avoids bypass logic at the cost of latency when reading
// a location that was enqued immediatly previously.
module mkFFsmall(FF#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
	RegFile#(Bit#(logDepth),data)       rf <- mkRegFileWCF(minBound, maxBound); // BRAM
  Reg#(Bit#(TAdd#(logDepth,1)))    lhead <- mkConfigRegA(0);
  Reg#(Bit#(TAdd#(logDepth,1))) ltail[2] <- mkCReg(2,0);
  Reg#(data)                         top <- mkRegU;
  Reg#(Maybe#(Bit#(logDepth))) lastWrite <- mkDReg(tagged Invalid);
  
  Bit#(TAdd#(logDepth,1)) level = lhead - ltail[0];
  Bool empty = (level==0);
  Bool full  = (level==fromInteger(valueOf(depth)));
  Bit#(logDepth) head = truncate(lhead);
  Bit#(logDepth) tail = truncate(ltail[0]);
  Bool readReady = !isValid(lastWrite) || (tail != fromMaybe(0,lastWrite));
  
  rule updateTop;
    top <= rf.sub(truncate(ltail[1]));
  endrule
  
  method Action enq(data in) if (!full);
    rf.upd(head,in);
    lhead <= lhead + 1;
    lastWrite <= tagged Valid head;
  endmethod
  method Action deq() if (!empty && readReady);
    ltail[0] <= ltail[0] + 1;
  endmethod
  method data first() if (!empty && readReady) = top;
  method Bool notFull() = !full;
  method Bool notEmpty() = !empty;
  method Bit#(TAdd#(TLog#(depth), 1)) remaining() = fromInteger(valueOf(depth)) - level;
endmodule

// Works ok, but a bit bigger than Bluespec in the single element case
(* always_ready = "enq, deq, first, notFull, notEmpty" *)
module mkUGFFBypass(FF#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
  Reg#(Bit#(TAdd#(logDepth,1))) lhead[2] <- mkCReg(2,0);
  Reg#(Bit#(TAdd#(logDepth,1)))    ltail <- mkConfigReg(0);
  Reg#(Vector#(depth, data))       rf[2] <- mkCReg(2,?);
  
  Bit#(TAdd#(logDepth,1)) level = lhead[1] - ltail;
  Bool full  = (level==fromInteger(valueOf(depth)));
  Bool empty = (level==0);
  
  // This is the level that the Deq and First methods see,
  // taking into account an Enq earlier in the cycle.
  Bit#(TAdd#(logDepth,1)) levelDeq = lhead[1] - ltail;
  Bool emptyDeq = (levelDeq==0);
  
  Bit#(logDepth) head = truncate(lhead[0]);
  Bit#(logDepth) tail = truncate(ltail);
  
  method Action enq(data in);
    rf[0][head] <= in;
    lhead[0] <= lhead[0] + 1;
  endmethod
  method Action deq();
    ltail <= ltail+1;
  endmethod
  method data first() = rf[1][tail];
  method Bool notFull() = !full;
  method Bool notEmpty() = !empty;
  method Bit#(TAdd#(TLog#(depth), 1)) remaining() = fromInteger(valueOf(depth)) - level;
endmodule

module mkFFBypass(FF#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
  FF#(data, depth) ff <- mkUGFFBypass();
  return guardFF(ff);
endmodule

// Equal to Bluespec equivelant
module mkUGFFBypass1(FF#(data, 1))
provisos(Bits#(data, data_width));
  Reg#(Bool)          full[2] <- mkCReg(2,False);
  Reg#(data)          dataReg <- mkConfigRegU;
  Wire#(Maybe#(data)) dataNow <- mkDWire(tagged Invalid);
  
  method Action enq(data in);
    dataReg <= in;
    dataNow <= tagged Valid in;
    full[0] <= True;
  endmethod
  method Action deq();
    full[1] <= False;
  endmethod
  method data first();
    data ret = dataReg;
    if (dataNow matches tagged Valid .dn) ret = dn;
    return ret;
  endmethod
  method Bool notFull() = !full[0];
  method Bool notEmpty() = full[1];
  method Bit#(1) remaining() = (full[1]) ? 1:0;
endmodule

module mkFFBypass1(FF#(data, 1))
provisos(Bits#(data, data_width));
  FF#(data, 1) ff <- mkUGFFBypass1();
  return guardFF(ff);
endmodule

function FIFOF#(data_t) ff2fifof (FF#(data_t, depth) ff) =
  interface FIFOF#(data_t);
    method      enq = ff.enq;
    method      deq = ff.deq;
    method    first = ff.first;
    method  notFull = ff.notFull;
    method notEmpty = ff.notEmpty;
  endinterface;
  
function FF#(data, depth) guardFF (FF#(data, depth) ff) =
  interface FF#(data, depth);
    method Action enq(data in) if (ff.notFull);
      ff.enq(in);
    endmethod
    method Action deq() if (ff.notEmpty);
      ff.deq();
    endmethod
    method data first() if (ff.notEmpty) = ff.first;
    method Bool notFull() = ff.notFull;
    method Bool notEmpty() = ff.notEmpty;
    method Bit#(TAdd#(TLog#(depth), 1)) remaining() = ff.remaining();
  endinterface;
