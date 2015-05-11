/*-
 * Copyright (c) 2013 Simon W. Moore
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

 HDMIVideoTestSource
 ===================
 
 This peripheral produces an AvalonStream of pixel values with a test
 pattern to test HDMI_Driver
 
 The video resolution is provided via a conduit interface which can be directly
 connected to the hdmi_resolution conduit on HDMI_Driver.  I.e. the HDMI_Driver
 tells this module what resolution to produce and then this module sends back
 a stream of pixels with a test pattern.
  
 *****************************************************************************/

package HDMIVideoTestSource;

import FIFO::*;
import GetPut::*;
import AvalonStreaming::*;

typedef struct {
   UInt#(8) r;   // red
   UInt#(8) g;   // green
   UInt#(8) b;   // blue
   } RGBT deriving (Bits,Eq);

interface HDMIVideoTestSourceIfc;
  interface AvalonPacketStreamSourcePhysicalIfc#(SizeOf#(RGBT)) aso;
  (* always_ready, always_enabled *) method Action coe_resolution(UInt#(12) xres, UInt#(12) yres);
endinterface


(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkHDMIVideoTestSource(HDMIVideoTestSourceIfc);
   
  AvalonPacketStreamSourceIfc#(RGBT) stream_out <- mkPut2AvalonPacketStreamSource;
  
  Reg#(Bit#(12)) xwidth <- mkReg(640);  // X resolution
  Reg#(Bit#(12)) ywidth <- mkReg(480);  // X resolution
  
  Reg#(Bit#(12)) x <- mkReg(0);
  Reg#(Bit#(12)) y <- mkReg(0);
  
  rule test_pattern;
    RGBT p = unpack(0);
    let sof = (x==0) && (y==0);
    let eof = (x==(xwidth-1)) && (y==(ywidth-1));
    if(x[5] == y[5]) begin
      p.r = (x[6]==1) || (x[7]==1) ? 8'hff : 0;
      p.g = (x[6]==0) || (x[7]==1) ? 8'hff : 0;
      p.b = y[5]==1 ? 8'hff : 0;
    end
    stream_out.tx.put(PacketDataT{d:p, sop:sof, eop:eof});

    if(x<(xwidth-1))
      x <= x+1;
    else
      begin
        x <= 0;
        y <= y<(ywidth-1) ? y+1 : 0;
      end
  endrule
  
  interface aso = stream_out.physical;
  method Action coe_resolution(UInt#(12) xres, UInt#(12) yres);
    xwidth <= pack(xres);
    ywidth <= pack(yres);
  endmethod
endmodule


endpackage
