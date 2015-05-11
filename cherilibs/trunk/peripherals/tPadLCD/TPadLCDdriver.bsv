/*-
 * Copyright (c) 2011 Simon W. Moore
 * Copyright (c) 2013 Jonathan Woodruff
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

 TPadLCDdriver
 =============
 
 This peripheral takes an AvalonStream of pixel values and maps them to
 the tPad colour screen which has an 800x600 resolution.
 
 Pixels are 16-bits, 5-bit red, 6-bit green, 5-bit blue.
 
 Extended to mirror the display via the VGA port on the tPad DE2-115
 as SVGA resolution (800 x 600) with 40MHz pixel clock giving 60Hz refresh
  
 *****************************************************************************/

package TPadLCDdriver;

import FIFO::*;
import FIFOF::*;
import GetPut::*;
import AvalonStreaming::*;

typedef UInt#(6) ColourChannelT;
typedef UInt#(8) VGAColourChannelT;

(* always_ready, always_enabled *)
interface TPadLCDphysical;
   // LCD physical interface
   method ColourChannelT hc_r; // red
   method ColourChannelT hc_g; // green
   method ColourChannelT hc_b; // blue
   method Bool hc_den;         // data-enable
   // VGA physical interface (mirrors LCD)
   method VGAColourChannelT vga_r; // red
   method VGAColourChannelT vga_g; // green
   method VGAColourChannelT vga_b; // blue
   method Bool vga_hs;             // hsync to VGA
   method Bool vga_vs;             // vsync to VGA
   method Bool vga_sync_n;         // not-sync to DAC
   method Bool vga_blank_n;        // not-blank to DAC
   // N.B. VGA_CLK and HC_NCLK also need to be driven from the
   // same 40MHz pixel clock supplied to this module
endinterface

(* always_ready, always_enabled *)
interface TPadLCDphysicalNested;
   interface TPadLCDphysical phy;
endinterface
   

typedef struct {
   UInt#(5) r;   // red
   UInt#(6) g;   // green
   UInt#(5) b;   // blue
   Bool sof;     // start of frame
   } Pixel16bitT deriving (Bits,Eq);

typedef struct {
   UInt#(5) r;   // red
   UInt#(6) g;   // green
   UInt#(5) b;   // blue
   } RGBT deriving (Bits,Eq);

interface TPadTiming16bitIfc;
   interface Put#(Pixel16bitT) pixel_stream;
   interface TPadLCDphysical phy;
endinterface
      

module mkTPadTiming16bit(TPadTiming16bitIfc);
   
   let xres = 800;  // X resolution
   let yres = 600;  // Y resolution
   let hsync = 256; // period for HC_DEN to be low at the end of each line
   let vsync = 28;  // number of blank lines at start of frame

/*
SVGA Signal 800 x 600 @ 60 Hz timing

Screen refresh rate	60 Hz
Vertical refresh	37.878787878788 kHz
Pixel freq.		40.0 MHz

Horizontal timing (line)

Polarity of horizontal sync pulse is positive.

Scanline part	Pixels	Time [µs]
Visible area	800	20
Front porch	40	1
Sync pulse	128	3.2
Back porch	88	2.2
Whole line	1056	26.4

Vertical timing (frame)

Polarity of vertical sync pulse is positive.

Frame part	Lines	Time [ms]
Visible area	600	15.84
Front porch	1	0.0264
Sync pulse	4	0.1056
Back porch	23	0.6072
Whole frame	628	16.5792
*/

   let vga_hsync_time = 128;
   let vga_hsync_back_porch = 88;
	 let vga_hsync_front_porch = 40;
   let vga_vsync_time = 4;
   let vga_vsync_back_porch = 23;
	 let vga_vsync_front_porch = 1;
   let no_pixel = Pixel16bitT{r:0,g:0,b:0,sof:False};
   let red_pixel = Pixel16bitT{r:5'b11111,g:0,b:0,sof:True};

   FIFOF#(Pixel16bitT) pixel_buf <- mkGFIFOF(False,True); // ungarded deq
   Reg#(Pixel16bitT) pixel_out <- mkRegU;
   Reg#(Bool) vga_hsync <- mkRegU;
   Reg#(Bool) vga_vsync <- mkRegU;
   Reg#(Bool) vga_sync_dac <- mkRegU;
   Reg#(Int#(12)) x <- mkReg(0); 
   Reg#(Int#(12)) y <- mkReg(-vsync); 

   (* no_implicit_conditions *)
   rule every_clock_cycle (True);
      if(((y>0) || ((y==0) && (x>0)))
				 && pixel_buf.notEmpty && pixel_buf.first.sof)
				 begin // resynchronise
						x <= -hsync;
						y <= -vsync;
				 end
      else if(x < (xres-1))
				 x <= x+1;
      else
				 begin
						x <= -hsync;
						y <= y<(yres-1) ? y+1 : -vsync;
				 end
				 
      // VGA synchronisation
      let vga_hs = (y>=0)
			          && ( x<(-hsync+vga_hsync_front_porch)
			          || x>-vga_hsync_back_porch);
      let vga_vs = (y >= -vga_vsync_back_porch) || (y < (-vsync + 1));
      vga_hsync <= !vga_hs;
      vga_vsync <= !vga_vs;
      vga_sync_dac <= !(vga_hs || vga_vs);
     
      // determine pixel colour
      let pixel_col = no_pixel;
      if((y>=0) && (x>=0))
				 begin // in drawing region
						if(pixel_buf.notEmpty)
							 begin
									pixel_col = pixel_buf.first;
									pixel_col.sof = True;    // use SOF for DEN on output
									pixel_buf.deq;
							 end
						else // data missing so draw red
							 pixel_col = red_pixel;
				 end
      pixel_out <= pixel_col;
   endrule      

   interface pixel_stream = toPut(pixel_buf);
	 interface TPadLCDphysical phy;
			method ColourChannelT hc_r;     return extend(pixel_out.r)<<1; endmethod
			method ColourChannelT hc_g;     return pixel_out.g;            endmethod
			method ColourChannelT hc_b;     return extend(pixel_out.b)<<1; endmethod
			method Bool hc_den;             return pixel_out.sof;          endmethod
			method VGAColourChannelT vga_r; return extend(pixel_out.r)<<3; endmethod
			method VGAColourChannelT vga_g; return extend(pixel_out.g)<<2; endmethod
			method VGAColourChannelT vga_b; return extend(pixel_out.b)<<3; endmethod
			method Bool vga_sync_n;         return vga_sync_dac;           endmethod
			method Bool vga_blank_n;        return pixel_out.sof;          endmethod
//      method Bool vga_sync_n;         return True;                   endmethod
//      method Bool vga_blank_n;        return True;                   endmethod
      method Bool vga_hs;             return vga_hsync;              endmethod
      method Bool vga_vs;             return vga_vsync;              endmethod
   endinterface   
endmodule


(* always_ready, always_enabled *)
interface AvalonStream2TPadLCD16bitIfc;
   interface AvalonPacketStreamSinkPhysicalIfc#(SizeOf#(RGBT)) asi;
   interface TPadLCDphysical coe_tpadlcd;
endinterface

(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkAvalonStream2TPadLCD16bit(AvalonStream2TPadLCD16bitIfc);
   
   TPadTiming16bitIfc lcdtiming <- mkTPadTiming16bit;
   AvalonPacketStreamSinkIfc#(RGBT) streamIn <- mkAvalonPacketStreamSink2Get;
   
   rule connect_stream_to_lcd_interface;
      let s <- streamIn.rx.get;
      lcdtiming.pixel_stream.put(Pixel16bitT{
				 r: s.d.r,
				 g: s.d.g,
				 b: s.d.b,
				 sof: s.sop
				 });
      // N.B. eop (end-of-packet) currently ignored
   endrule
   
   interface coe_tpadlcd = lcdtiming.phy;
	 interface asi = streamIn.physical;
			
endmodule


endpackage
