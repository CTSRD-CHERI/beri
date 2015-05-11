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

 HDMI Timing Driver
 ==================
 
 This Qsys peripheral takes an AvalonStream of pixel values and maps them
 to the Terasic HDMI Transmitter daughter card (HDMI_TX_HSMC).  It needs
 to be clocked at the video pixel clock frequency which may be variable
 so an Avalon clock crossing bridge is needed to interface to the AvalonMM
 slave interface which allows the following parameters to be set from
 software.
 
 Address map (32-bit word offset, little endian 12-bit values in 32-bit word)
 ===========
 
  0  x-resolutions          (in pixels)
  1  horizontal pulse width (in pixel clock ticks)
  2  horizontal back porch  (in pixel clock ticks)
  3  horizontal front porch (in pixel clock ticks)
  4  y-resolution           (in pixels/lines)
  5  vertical pulse width   (in lines)
  6  vertical back porch    (in lines)
  7  vertical front porch   (in lines)

 *****************************************************************************/


package HDMI_Driver;


import FIFO::*;
import FIFOF::*;
import Vector::*;
import GetPut::*;
import ClientServer::*;
import AvalonStreaming::*;
import Avalon2ClientServer::*;

// 8-bit colour channel type (3 of these for 24-bit input colour)
typedef UInt#(8) ColourChanT;
// 12-bit HDMI channel colour
typedef UInt#(12) HDMIColourChanT;

// AvalonStream type for 24-bit pixels with start-of-frame marked
typedef struct {
   ColourChanT r;    // red
   ColourChanT g;    // green
   ColourChanT b;    // blue
   Bool        sof;  // start of frame
   } Pixel24bT deriving (Bits,Eq);

// 24-bit pixel type
typedef struct {
   ColourChanT r;    // red
   ColourChanT g;    // green
   ColourChanT b;    // blue
   } RGBT deriving (Bits,Eq);



(* always_ready, always_enabled *)
interface HDMIphysical;
  // LCD physical interface
  method HDMIColourChanT hdmi_r; // red
  method HDMIColourChanT hdmi_g; // green
  method HDMIColourChanT hdmi_b; // blue
  method Bool hdmi_hsd;          // hsync
  method Bool hdmi_vsd;          // vsync
  method Bool hdmi_de;           // data enable
endinterface


interface HDMI_Timing36bitIfc;
  interface Put#(Pixel24bT) pixel_stream;
  interface HDMIphysical phy;
endinterface
      

// convert 8-bit channel colour into 12-bit HDMI colour
function HDMIColourChanT hdmiCol(ColourChanT col8);
  HDMIColourChanT c12 = extend(col8);
  return c12<<4;  // correct if 24-bit colour mode selected on HDMI chip
endfunction


interface HDMI_Timing36bit_Reconfig_Ifc;
  interface Put#(Pixel24bT) pixel_stream;
  interface HDMIphysical phy;
  (* always_ready, always_enabled *)
  method Action videoparams(
     Int#(12) p_xres,
     Int#(12) p_hsync_pulse_width,
     Int#(12) p_hsync_back_porch,
     Int#(12) p_hsync_front_porch,
     Int#(12) p_yres,
     Int#(12) p_vsync_pulse_width,
     Int#(12) p_vsync_back_porch,
     Int#(12) p_vsync_front_porch);
endinterface
      


module mkHDMI_Timing36bitReconfigurable(HDMI_Timing36bit_Reconfig_Ifc);
   
  Wire#(Int#(12)) xres               <- mkBypassWire;
  Wire#(Int#(12)) hsync_pulse_width  <- mkBypassWire;
  Wire#(Int#(12)) hsync_back_porch   <- mkBypassWire;
  Wire#(Int#(12)) hsync_front_porch  <- mkBypassWire;
  Wire#(Int#(12)) yres               <- mkBypassWire;
  Wire#(Int#(12)) vsync_pulse_width  <- mkBypassWire;
  Wire#(Int#(12)) vsync_back_porch   <- mkBypassWire;
  Wire#(Int#(12)) vsync_front_porch  <- mkBypassWire;

  let        hsync_time = hsync_pulse_width + hsync_back_porch;
  let        vsync_time = vsync_pulse_width + vsync_back_porch;
  let          no_pixel = Pixel24bT{r:0,g:0,b:0,sof:False};
  let         red_pixel = Pixel24bT{r:~0,g:0,b:0,sof:True};
  
  FIFOF#(Pixel24bT) pixel_buf <- mkGFIFOF(False,True); // ungarded deq
  Reg#(Pixel24bT)   pixel_out <- mkRegU;
  Reg#(Bool)              vsd <- mkRegU;
  Reg#(Bool)              hsd <- mkRegU;
  Reg#(Bool)               de <- mkRegU;               // data enable for HDMI
  Reg#(Int#(12))            x <- mkReg(0);
  Reg#(Int#(12))            y <- mkReg(0);
  
  (* no_implicit_conditions, fire_when_enabled *)
  rule every_clock_cycle (pixel_buf.notEmpty);
    // Note the above explicit condition that we have pixels to render
    if(x < (xres+hsync_front_porch-1))
      x <= x+1;
    else
      begin
        x <= -hsync_time;
        y <= y < (yres+vsync_front_porch-1) ? y+1 : -vsync_time;
      end
    
    let hsync_pulse = (x < (-hsync_back_porch));
    let vsync_pulse = (y < (-vsync_back_porch));
    hsd <= !hsync_pulse;
    vsd <= !vsync_pulse;
    
    // determine drawing region
    let drawing = (y>=0) && (y<yres) && (x>=0) && (x<xres);
    de <= drawing;
    
    // determine pixel colour
    let pixel_col = no_pixel;
    if(drawing)
      begin // in drawing region
	// check that the pixel stream is synchronised with the LCD timing,
	// otherwise output red
        if(pixel_buf.notEmpty && (pixel_buf.first.sof == ((x==0) && (y==0))))
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
    interface HDMIphysical phy;
      method HDMIColourChanT hdmi_r;  return hdmiCol(pixel_out.r);  endmethod
      method HDMIColourChanT hdmi_g;  return hdmiCol(pixel_out.g);  endmethod
      method HDMIColourChanT hdmi_b;  return hdmiCol(pixel_out.b);  endmethod
      method Bool hdmi_hsd;           return hsd;                   endmethod
      method Bool hdmi_vsd;           return vsd;                   endmethod
      method Bool hdmi_de;            return de;                    endmethod
  endinterface   

  method Action videoparams(
     p_xres,
     p_hsync_pulse_width,
     p_hsync_back_porch,
     p_hsync_front_porch,
     p_yres,
     p_vsync_pulse_width,
     p_vsync_back_porch,
     p_vsync_front_porch);

    xres              <= p_xres;
    hsync_pulse_width <= p_hsync_pulse_width;
    hsync_back_porch  <= p_hsync_back_porch;
    hsync_front_porch <= p_hsync_front_porch;
    yres              <= p_yres;
    vsync_pulse_width <= p_vsync_pulse_width;
    vsync_back_porch  <= p_vsync_back_porch;
    vsync_front_porch <= p_vsync_front_porch;
  endmethod
endmodule


// AvalonStream wrapper around the above
(* always_ready, always_enabled *)
interface AvalonStream2HDMI36bitIfc;
  interface AvalonPacketStreamSinkPhysicalIfc#(SizeOf#(RGBT)) asi;
  interface HDMIphysical coe;
endinterface


// AvalonStream wrapper around the above with parameters
(* always_ready, always_enabled *)
interface HDMI_Driver_Ifc;
  // AvalonST pixel stream
  interface AvalonPacketStreamSinkPhysicalIfc#(SizeOf#(RGBT)) asi;
  // Avalon memory mapped interface for parameters
  interface AvalonSlaveIfc#(3) avs;
  // Conduit for HDMI output
  interface HDMIphysical coe;
  // Conduits for X and Y resolution currently set
  // (e.g. for test pattern generator)
  method ActionValue#(Int#(12)) coe_resolution_xres;
  method ActionValue#(Int#(12)) coe_resolution_yres;
endinterface


(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkHDMI_Driver(HDMI_Driver_Ifc);
   
  HDMI_Timing36bit_Reconfig_Ifc   hdmitiming <- mkHDMI_Timing36bitReconfigurable;
  AvalonPacketStreamSinkIfc#(RGBT)  streamIn <- mkAvalonPacketStreamSink2Get;
  AvalonSlave2ClientIfc#(3)           avalon <- mkAvalonSlave2Client;
  
  Vector#(8,Reg#(Int#(12))) p; // parameters
  p[0] <- mkReg(720); // xres
  p[1] <- mkReg(62);  // hsync_pulse_width
  p[2] <- mkReg(60);  // hsync_back_porch
  p[3] <- mkReg(16);  // hsync_front_porch
  p[4] <- mkReg(480); // yres
  p[5] <- mkReg(6);   // vsync_pulse_width
  p[6] <- mkReg(30);  // vsync_back_porch
  p[7] <- mkReg(9);   // vsync_front_porch
  
  rule send_parameters;
    hdmitiming.videoparams(
     p[0],   // p_xres
     p[1],   // p_hsync_pulse_width
     p[2],   // p_hsync_back_porch
     p[3],   // p_hsync_front_porch
     p[4],   // p_yres
     p[5],   // p_vsync_pulse_width
     p[6],   // p_vsync_back_porch
     p[7]);  // p_vsync_front_porch
  endrule
  
  rule connect_stream_to_lcd_interface;
    let s <- streamIn.rx.get;
    hdmitiming.pixel_stream.put(Pixel24bT{
       r: s.d.r,
       g: s.d.g,
       b: s.d.b,
       sof: s.sop
       });
    // N.B. eop (end-of-packet) currently ignored
  endrule
  
  rule handle_avalon_accesses;
    let req <- avalon.client.request.get();
    ReturnedDataT rtn = tagged Invalid;
    if(req.rw == MemWrite)
      p[req.addr] <= truncate(unpack(pack(req.data)));
    else
      begin
        AvalonWordT d = unpack(pack(extend(p[req.addr])));
        rtn = tagged Valid d;
      end
    avalon.client.response.put(rtn);
  endrule
   
  interface coe = hdmitiming.phy;
  interface asi = streamIn.physical;
  interface avs = avalon.avs;
  method ActionValue#(Int#(12)) coe_resolution_xres;  return p[0];  endmethod
  method ActionValue#(Int#(12)) coe_resolution_yres;  return p[4];  endmethod
endmodule

                 

endpackage
