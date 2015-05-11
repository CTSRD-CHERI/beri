/*-
 * Copyright (c) 2013 Simon W. Moore
 * All rights reserved.
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

package TestStreams;

import GetPut::*;
import Connectable::*;
import ClientServer::*;
import AvalonStreaming::*;

typedef UInt#(8) StreamT;

interface TestStreamSource;
  interface AvalonStreamSourcePhysicalIfc#(StreamT) aso; // Avalon stream out
endinterface


(* synthesize,
 reset_prefix = "csi_clockreset_reset_n",
 clock_prefix = "csi_clockreset_clk" *)
module mkTestStreamSource(TestStreamSource);
  AvalonStreamSourceIfc#(StreamT) aso_adapter <- mkPut2AvalonStreamSource;
  
  Reg#(UInt#(32)) tst <- mkReg(0);
  
  rule push_test_data(msb(tst)==0);
    aso_adapter.tx.put(truncate(tst));
    tst <= tst+1;
  endrule
  
  interface aso = aso_adapter.physical;
  
endmodule



(* always_ready, always_enabled *)
interface TestStreamSink;
  interface AvalonStreamSinkPhysicalIfc#(StreamT) asi; // Avalon stream in
  method ActionValue#(StreamT) coe_sum();
  method ActionValue#(Bool) coe_err();
endinterface


(* synthesize,
 reset_prefix = "csi_clockreset_reset_n",
 clock_prefix = "csi_clockreset_clk" *)
module mkTestStreamSink(TestStreamSink);
  AvalonStreamSinkIfc#(StreamT)   asi_adapter <- mkAvalonStreamSink2Get;
  
  Reg#(UInt#(32)) sum <- mkReg(0);
  Reg#(UInt#(8)) expected <- mkReg(0);
  Reg#(Bool) err <- mkReg(False);
  
  rule push_test_data;
    let d <- asi_adapter.rx.get();
    err <= err || (d!=expected);
    sum <= sum + extend(d);
    expected <= expected+1;
  endrule

  method ActionValue#(StreamT) coe_sum();
    return truncate(sum);
  endmethod
  
  method ActionValue#(Bool) coe_err();
    return err;
  endmethod
  
  interface asi = asi_adapter.physical;
  
endmodule


endpackage

