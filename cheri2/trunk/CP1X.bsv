/*-
 * Copyright (c) 2012-2013 SRI International
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
 * Authors:
 *   Asif Khan  <asif.khan@sri.com>
 *   Nirav Dave <ndave@csl.sri.com>
 *
 ******************************************************************************
 *
 * Description: CP1X Coprocessor
 *
 ******************************************************************************/



import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;

import MFIFO::*;
import Library::*;

import MIPS::*;
import CHERITypes::*;


interface CP1X;
  method Action req(CP1XOperation op);
  method ActionValue#(Maybe#(Value)) rsp(Bool commit, Value v);

  method Action dIn(Value v);
  method ActionValue#(Value) dOut;
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkCP1X(CP1X);
  FIFO#(CP1XOperation) opQ <- mkPipeFIFO;

  FIFOF#(Value) dOutQ <- mkFIFOF();
  MFIFO#(Value)  dInQ <- mkMFIFO();

  method Action req(CP1XOperation op) = opQ.enq(op);

  method ActionValue#(Maybe#(Value)) rsp(Bool commit, Value v);
    let op <- popFIFO(opQ);

    if(commit && op.cp1X_dest)
      dOutQ.enq(v);

    let nv <- (commit && op.cp1X_hasResult) ? dInQ.mdeq() : toAV(Invalid);

    return nv;
  endmethod

  method Action dIn(Value v) = dInQ.enq(v);
  method ActionValue#(Value) dOut = popFIFOF(dOutQ);

endmodule
