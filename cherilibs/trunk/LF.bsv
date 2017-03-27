/*-
 * Copyright (c) 2015 Jonathan Woodruff
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

 LF LIFO (Stack) library
 ===========
 
 This is a library of pure Bluespec LIFO components
 
 *****************************************************************************/

import ConfigReg::*;
import FIFO::*;
import FIFOF::*;
import RegFile::*;
import Vector::*;
import DReg    :: *;
import SpecialFIFOs :: *;

interface LF#(type data, numeric type depth);
  method Action push(data x);
  method ActionValue#(data) pop();
  method data peek();
  method Bool notFull();
  method Bool notEmpty();
  method Bit#(TLog#(depth)) remaining();
endinterface

// Equal to Bluespec equivelant
module mkUGLF(LF#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
	RegFile#(Bit#(logDepth),data)    rf <- mkRegFileWCF(minBound, maxBound); // BRAM
  Reg#(Bit#(logDepth))         top[2] <- mkCReg(2,0);
  
  Bit#(logDepth) thisTop = top[0];
  Bit#(logDepth) nextTop = top[1] + 1;
  Bool empty = (top[0]==0);
  Bool full  = (top[1] == -1);
  
  method Action push(data in);
    rf.upd(nextTop,in);
    top[1] <= nextTop;
  endmethod
  method ActionValue#(data) pop();
    top[0] <= thisTop - 1;
    return rf.sub(thisTop);
  endmethod
  method data peek() = rf.sub(thisTop);
  method Bool notFull() = !full;
  method Bool notEmpty() = !empty;
  method Bit#(TLog#(depth)) remaining() = -1 - thisTop;
endmodule

module mkLF(LF#(data, depth))
provisos(Log#(depth,logDepth),Bits#(data, data_width));
  LF#(data, depth) lf <- mkUGLF();
  return guardLF(lf);
endmodule

function LF#(data, depth) guardLF (LF#(data, depth) lf) =
  interface LF#(data, depth);
    method Action push(data in) if (lf.notFull);
      lf.push(in);
    endmethod
    method ActionValue#(data) pop() if (lf.notEmpty) = lf.pop();
    method data peek() if (lf.notEmpty) = lf.peek;
    method Bool notFull() = lf.notFull;
    method Bool notEmpty() = lf.notEmpty;
    method Bit#(TLog#(depth)) remaining() = lf.remaining();
  endinterface;
