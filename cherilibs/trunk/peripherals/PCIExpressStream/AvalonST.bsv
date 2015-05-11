/*-
 * Copyright (c) 2013 Alex Horsman
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

package AvalonST;

import GetPut::*;
import FIFOF::*;


(* always_ready, always_enabled *)
interface AvalonSourceExt#(type dataT);
  method Action aso(Bool ready);
  method dataT aso_data;
  method Bool aso_valid;
endinterface

interface AvalonSource#(type dataT);
  interface AvalonSourceExt#(dataT) aso;
  interface Put#(dataT) send;
endinterface


module mkAvalonSource(AvalonSource#(dataT))
provisos(Bits#(dataT,dataWidth));

  Wire#(Maybe#(dataT)) data <- mkDWire(Invalid);
  PulseWire isReady <- mkPulseWire;

  interface AvalonSourceExt aso;
    method Action aso(ready);
      if (ready) begin
        isReady.send();
      end
    endmethod
    method aso_data = fromMaybe(?,data);
    method aso_valid = isValid(data);
  endinterface

  interface Put send;
    method Action put(x) if (isReady);
      data <= Valid(x);
    endmethod
  endinterface

endmodule


(* always_ready, always_enabled *)
interface AvalonSinkExt#(type dataT);
  method Action asi(dataT data, Bool valid);
  method Bool asi_ready;
endinterface

interface AvalonSink#(type dataT);
  interface AvalonSinkExt#(dataT) asi;
  interface Get#(dataT) receive;
endinterface


module mkAvalonSink(AvalonSink#(dataT))
provisos(Bits#(dataT,dataWidth));

  FIFOF#(dataT) queue <- mkGLFIFOF(True,False);

  interface AvalonSinkExt asi;
    method Action asi(data,valid);
      if (valid && queue.notFull) begin
        queue.enq(data);
      end
    endmethod
    method asi_ready = queue.notFull;
  endinterface

  interface receive = toGet(queue);

endmodule


endpackage
