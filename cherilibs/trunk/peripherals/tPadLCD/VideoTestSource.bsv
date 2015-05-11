/*-
 * Copyright (c) 2011 Simon W. Moore
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

 VideoTestSource
 ===============
 
 This peripheral produces an AvalonStream of pixel values with a test
 pattern to test TPadLCDdriver.
 
 Currently the resolution is assumed to be 800x600 but this should probably
 be parameterised.
  
 *****************************************************************************/

package VideoTestSource;

import FIFO::*;
import GetPut::*;
import AvalonStreaming::*;

typedef struct {
   UInt#(5) r;   // red
   UInt#(6) g;   // green
   UInt#(5) b;   // blue
   } RGBT deriving (Bits,Eq);

interface VideoTestSourceIfc;
   interface AvalonPacketStreamSourcePhysicalIfc#(SizeOf#(RGBT)) aso;
endinterface


(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkVideoTestSource(VideoTestSourceIfc);
   
   AvalonPacketStreamSourceIfc#(RGBT) stream_out <- mkPut2AvalonPacketStreamSource;
   
   let xres = 800;  // X resolution
   let yres = 600;  // Y resolution
   
   Reg#(Bit#(12)) x <- mkReg(0);
   Reg#(Bit#(12)) y <- mkReg(0);
   
   rule scan;
      RGBT p = unpack(0);
      let sof = (x==0) && (y==0);
      let eof = (x==(xres-1)) && (y==(yres-1));
      if(x[5] == y[5]) begin
					p.r = (x[6]==1) || (x[7]==1) ? 5'b11111 : 0;
					p.g = (x[6]==0) || (x[7]==1) ? 6'b111111 : 0;
					p.b = y[5]==1 ? 5'b11111 : 0;
			 end
//      p.r = unpack(truncate(pack(x)));
//      p.g = unpack(truncate(pack(y)));
//      p.b = unpack(truncate(pack(y)>>5));
      stream_out.tx.put(PacketDataT{d:p, sop:sof, eop:eof});

      if(x<(xres-1)) x <= x+1;
      else begin
				x <= 0;
				y <= y<(yres-1) ? y+1 : 0;
			end
   endrule
   
   interface aso = stream_out.physical;
      
endmodule


endpackage
