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
 
 AvalonStreaming
 ===============
 Simon Moore, May 2010
 
 This library provides Bluespec wrappers for Altera's Avalon Streaming
 interface.

 * Names - SOPC Builder expects the following names to be used for streaming
   interfaces (i.e. these are the names you should use in the top-level
   interface):
    * aso - Avalon-ST source
    * asi - Avalon-ST sink
 
 * Update in April 2011 - added Sink which is always ready
 * Update in June 2011  - added mkConnectionStreamPhysical
 * Update in Jan 2012   - added source and sink with channels
                          and simplified interfaces 

 *****************************************************************************/

package AvalonStreaming;

import GetPut::*;
import FIFOF::*;

/*****************************************************************************
 Source Stream
 *****************************************************************************/

// Avalon-ST source physical interface.  Note that names of modules
// match SOPC's expectations.
(* always_ready, always_enabled *)
interface AvalonStreamSourcePhysicalIfc#(type dataT);
  method dataT stream_out_data;
  method Bool stream_out_valid;
  method Action stream_out(Bool ready);
endinterface

interface AvalonStreamSourceIfc#(type dataT);
  interface Put#(dataT) tx;
  interface AvalonStreamSourcePhysicalIfc#(dataT) physical;
endinterface


module mkPut2AvalonStreamSource(AvalonStreamSourceIfc#(dataT))
  provisos(Bits#(dataT,dataT_width), Max#(dataT_width, 4096, 4096));
   
  Wire#(Maybe#(dataT)) data_dw <- mkDWire(tagged Invalid);
  Wire#(Bool) ready_w <- mkBypassWire;
   
  interface Put tx;
    method Action put(dataT d) if(ready_w);
      data_dw <= tagged Valid d;
    endmethod
  endinterface
  
  interface AvalonStreamSourcePhysicalIfc physical;
    method dataT stream_out_data;
      return fromMaybe(?,data_dw);
    endmethod
    method Bool stream_out_valid;
      return isValid(data_dw);
    endmethod
    method Action stream_out(Bool ready);
      ready_w <= ready;
    endmethod
  endinterface
endmodule


/*****************************************************************************
 Source Stream with Channel Numbers
 *****************************************************************************/

// Avalon-ST source physical interface.  Note that names of modules
// match SOPC's expectations.
(* always_ready, always_enabled *)
interface AvalonStreamSourceChanPhysicalIfc#(type chanT, type dataT);
   method chanT stream_out_chan;
   method dataT stream_out_data;
   method Bool stream_out_valid;
   method Action stream_out(Bool ready);
endinterface

interface AvalonStreamSourceChanIfc#(type chanT, type dataT);
   interface Put#(Tuple2#(chanT,dataT)) tx;
   interface AvalonStreamSourceChanPhysicalIfc#(chanT,dataT) physical;
endinterface


module mkPut2AvalonStreamSourceChan(AvalonStreamSourceChanIfc#(chanT,dataT))
//  provisos(Bits#(chanT,chanT_width), Bits#(dataT,dataT_width));
  provisos(Bits#(chanT,chanT_width), Max#(chanT_width,128,128),
	   Bits#(dataT,dataT_width), Max#(dataT_width,4096,4096));
   
  Wire#(chanT) chan_dw <- mkDWire(unpack(0));
  Wire#(Maybe#(dataT)) data_dw <- mkDWire(tagged Invalid);
  Wire#(Bool) ready_w <- mkBypassWire;
   
  interface Put tx;
    method Action put(Tuple2#(chanT,dataT) d) if(ready_w);
      chan_dw <= tpl_1(d);
      data_dw <= tagged Valid tpl_2(d);
    endmethod
  endinterface

  interface AvalonStreamSourceChanPhysicalIfc physical;
    method chanT stream_out_chan;
      return chan_dw;
    endmethod
    method dataT stream_out_data;
      return fromMaybe(?,data_dw);
    endmethod
    method Bool stream_out_valid;
      return isValid(data_dw);
    endmethod
    method Action stream_out(Bool ready);
      ready_w <= ready;
    endmethod
  endinterface
endmodule


/*****************************************************************************
 Source Stream NB (Non-blocking), i.e. with no ready signal
 *****************************************************************************/

// Avalon-ST source physical interface.  Note that names of modules
// match SOPC's expectations.
(* always_ready, always_enabled *)
interface AvalonStreamSourceNBPhysicalIfc#(type dataT);
  method dataT stream_out_data;
endinterface

interface AvalonStreamSourceNBIfc#(type dataT);
   interface Put#(dataT) tx;
   interface AvalonStreamSourceNBPhysicalIfc#(dataT) physical;
endinterface


module mkPut2AvalonStreamSourceNB(AvalonStreamSourceNBIfc#(dataT))
  provisos(Bits#(dataT,dataT_width), Max#(dataT_width,4096,4096));
   
  Wire#(Maybe#(dataT)) data_dw <- mkDWire(tagged Invalid);
   
  interface Put tx;
    method Action put(dataT d);
      data_dw <= tagged Valid d;
    endmethod
  endinterface

  interface AvalonStreamSourceNBPhysicalIfc physical;
    method dataT stream_out_data;
      return fromMaybe(?,data_dw);
    endmethod
  endinterface
endmodule


/*****************************************************************************
 Sink Stream
 *****************************************************************************/

// Avalon-ST sink physical interface.  Note that names of modules
// match SOPC's expectations.

(* always_ready, always_enabled *)
interface AvalonStreamSinkPhysicalIfc#(type dataT);
  method Action stream_in(dataT data, Bool valid);
  method Bool stream_in_ready;
endinterface

interface AvalonStreamSinkIfc#(type dataT);
  interface Get#(dataT) rx;
  interface AvalonStreamSinkPhysicalIfc#(dataT) physical;
endinterface


module mkAvalonStreamSink2Get(AvalonStreamSinkIfc#(dataT))
  provisos(Bits#(dataT,dataT_width), Max#(dataT_width,4096,4096));
   
  FIFOF#(dataT) f <- mkLFIFOF;
  Wire#(Maybe#(dataT)) d_dw <- mkDWire(tagged Invalid);
   
  rule push_data_into_fifo (isValid(d_dw));
    f.enq(fromMaybe(?,d_dw));
  endrule
   
  interface Get rx = toGet(f);
  
  interface AvalonStreamSinkPhysicalIfc physical;
    // method to receive data.  Note that the data should be held
    // until stream_in_ready is True, i.e. there is room in the internal
    // FIFO - f - so we should never loose data from our d_dw DWire
    method Action stream_in(dataT data, Bool valid);
      if(valid)
	d_dw <= tagged Valid data;
    endmethod
    method Bool stream_in_ready;
      return f.notFull;
    endmethod
  endinterface
endmodule


/*****************************************************************************
 Sink Stream with Channel
 *****************************************************************************/

// Avalon-ST sink physical interface.  Note that names of modules
// match SOPC's expectations.

(* always_ready, always_enabled *)
interface AvalonStreamSinkChanPhysicalIfc#(type chanT, type dataT);
  method Action stream_in(chanT chan, dataT data, Bool valid);
  method Bool stream_in_ready;
endinterface

interface AvalonStreamSinkChanIfc#(type chanT, type dataT);
  interface Get#(Tuple2#(chanT,dataT)) rx;
  interface AvalonStreamSinkChanPhysicalIfc#(chanT,dataT) physical;
endinterface


module mkAvalonStreamSinkChan2Get(AvalonStreamSinkChanIfc#(chanT, dataT))
  provisos(Bits#(chanT,chanT_width), Max#(chanT_width,128,128),
	   Bits#(dataT,dataT_width), Max#(dataT_width,4096,4096));
   
  FIFOF#(Tuple2#(chanT,dataT)) f <- mkLFIFOF;
  Wire#(Maybe#(Tuple2#(chanT,dataT))) cd_dw <- mkDWire(tagged Invalid);
   
  rule push_data_into_fifo (isValid(cd_dw));
    f.enq(fromMaybe(?,cd_dw));
  endrule
   
  interface Get rx = toGet(f);
  
  interface AvalonStreamSinkChanPhysicalIfc physical;
    // method to receive data.  Note that the data should be held
    // until stream_in_ready is True, i.e. there is room in the internal
    // FIFO - f - so we should never loose data from our d_dw DWire
    method Action stream_in(chanT chan, dataT data, Bool valid);
      if(valid)
	cd_dw <= tagged Valid tuple2(chan,data);
    endmethod
    method Bool stream_in_ready;
      return f.notFull;
    endmethod
  endinterface
endmodule


/*****************************************************************************
 Sink Stream Non-blocking (i.e. which is always ready)
 *****************************************************************************/

// Avalon-ST sink physical interface.  Note that names of modules
// match SOPC's expectations.

(* always_ready, always_enabled *)
interface AvalonStreamSinkNBPhysicalIfc#(type dataT);
  method Action stream_in(dataT data);
endinterface

interface AvalonStreamSinkNBIfc#(type dataT);
  interface Get#(dataT) rx;
  interface AvalonStreamSinkNBPhysicalIfc#(dataT) physical;
endinterface


module mkAvalonStreamSinkNB2Get(AvalonStreamSinkNBIfc#(dataT))
  provisos(Bits#(dataT,dataT_width), Max#(dataT_width,4096,4096));
   
  FIFOF#(dataT) f <- mkLFIFOF;
  Wire#(Maybe#(dataT)) d_dw <- mkDWire(tagged Invalid);
   
  rule push_data_into_fifo (isValid(d_dw));
    f.enq(fromMaybe(?,d_dw));
  endrule
   
  interface Get rx = toGet(f);
  
  interface AvalonStreamSinkNBPhysicalIfc physical;
    // method to receive data.  Note that the data should be held
    // until stream_in_ready is True, i.e. there is room in the internal
    // FIFO - f - so we should never loose data from our d_dw DWire
    method Action stream_in(dataT data);
      d_dw <= tagged Valid data;
    endmethod
  endinterface
endmodule

/*****************************************************************************
 Source Packet Stream (supports startofpacket and endofpacket signals)
 *****************************************************************************/

// Avalon-ST source physical interface.  Note that names of modules
// match SOPC's expectations.
(* always_ready, always_enabled *)
interface AvalonPacketStreamSourcePhysicalIfc#(numeric type dataT_width);
   method Bit#(dataT_width) stream_out_data;
   method Bool stream_out_valid;
   method Action stream_out(Bool ready);
   method Bool stream_out_startofpacket;
   method Bool stream_out_endofpacket;
endinterface

typedef struct {
   dataT d;  // data (generic)
   Bool sop; // start-of-packet marker
   Bool eop; // end-of-packet marker
   } PacketDataT#(type dataT) deriving (Bits,Eq);

interface AvalonPacketStreamSourceVerboseIfc#(type dataT, numeric type dataT_width);
   interface Put#(PacketDataT#(dataT)) tx;
   interface AvalonPacketStreamSourcePhysicalIfc#(dataT_width) physical;
endinterface

typedef AvalonPacketStreamSourceVerboseIfc#(dataT,SizeOf#(dataT)) AvalonPacketStreamSourceIfc#(type dataT);

module mkPut2AvalonPacketStreamSource(AvalonPacketStreamSourceVerboseIfc#(dataT,dataT_width))
   provisos(Bits#(dataT,dataT_width));
   
   Wire#(Maybe#(Bit#(dataT_width))) data_dw <- mkDWire(tagged Invalid);
   Wire#(Bool) ready_w <- mkBypassWire;
   Wire#(Bool) sop_dw <- mkDWire(False);
   Wire#(Bool) eop_dw <- mkDWire(False);
   
   interface Put tx;
      method Action put(PacketDataT#(dataT) d) if(ready_w);
   data_dw <= tagged Valid pack(d.d);
   sop_dw <= d.sop;
   eop_dw <= d.eop;
      endmethod
   endinterface

   interface AvalonPacketStreamSourcePhysicalIfc physical;
      method Bit#(dataT_width) stream_out_data;
   return fromMaybe(0,data_dw);
      endmethod
      method Bool stream_out_valid;
   return isValid(data_dw);
      endmethod
      method Action stream_out(Bool ready);
   ready_w <= ready;
      endmethod
      method Bool stream_out_startofpacket;
   return sop_dw;
      endmethod
      method Bool stream_out_endofpacket;
   return eop_dw;
      endmethod
   endinterface
endmodule

/*****************************************************************************
 Sink Packet Stream
 - a sink stream with ready and valid signals, so full flow-control
 - receives startofpacket and endofpacket signals
 *****************************************************************************/

// Avalon-ST sink physical interface.  Note that names of modules
// match SOPC's expectations.

(* always_ready, always_enabled *)
interface AvalonPacketStreamSinkPhysicalIfc#(type dataT_width);
   method Action stream_in(Bit#(dataT_width) data, Bool valid,
         Bool startofpacket, Bool endofpacket);
   method Bool stream_in_ready;
endinterface

interface AvalonPacketStreamSinkVerboseIfc#(type dataT, numeric type dataT_width);
   interface Get#(PacketDataT#(dataT)) rx;
   interface AvalonPacketStreamSinkPhysicalIfc#(dataT_width) physical;
endinterface

typedef AvalonPacketStreamSinkVerboseIfc#(dataT,SizeOf#(dataT)) AvalonPacketStreamSinkIfc#(type dataT);


module mkAvalonPacketStreamSink2Get(AvalonPacketStreamSinkVerboseIfc#(dataT,dataT_width))
   provisos(Bits#(dataT,dataT_width));
   
   FIFOF#(PacketDataT#(dataT)) f <- mkLFIFOF;
   Wire#(Maybe#(PacketDataT#(dataT))) d_dw <- mkDWire(tagged Invalid);

   rule push_data_into_fifo (isValid(d_dw));
      f.enq(fromMaybe(?,d_dw));
   endrule
   
   interface Get rx = toGet(f);

   interface AvalonPacketStreamSinkPhysicalIfc physical;
      // method to receive data.  Note that the data should be held
      // until stream_in_ready is True, i.e. there is room in the internal
      // FIFO - f - so we should never loose data from our d_dw DWire
      method Action stream_in(Bit#(dataT_width) data, Bool valid, Bool startofpacket, Bool endofpacket);
   if(valid)
      d_dw <= tagged Valid PacketDataT{d:unpack(data), sop:startofpacket, eop:endofpacket};
      endmethod
      method Bool stream_in_ready;
   return f.notFull;
      endmethod
   endinterface
endmodule


/*****************************************************************************
 Connect avalon streams
 *****************************************************************************/

module mkConnectionStreamPhysical(
   AvalonStreamSourcePhysicalIfc#(dataT) aso,
   AvalonStreamSinkPhysicalIfc#(dataT) asi,
   Empty default_ifc);
   
  rule connect_data_and_valid;
    let d = aso.stream_out_data();
    let v = aso.stream_out_valid();
    asi.stream_in(d, v);
  endrule
   
  rule connect_ready;
    let r = asi.stream_in_ready;
    aso.stream_out(r);
  endrule
endmodule


module mkConnectionStreamPhysicalChan(
   AvalonStreamSourceChanPhysicalIfc#(chanT,dataT) aso,
   AvalonStreamSinkChanPhysicalIfc#(chanT,dataT) asi,
   Empty default_ifc);
   
  rule connect_data_and_valid;
    let c = aso.stream_out_chan();
    let d = aso.stream_out_data();
    let v = aso.stream_out_valid();
    asi.stream_in(c, d, v);
  endrule
   
  rule connect_ready;
    let r = asi.stream_in_ready;
    aso.stream_out(r);
  endrule
endmodule


endpackage
