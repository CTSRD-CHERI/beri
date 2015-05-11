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
 
 This library provides Bluespec wrappers for Altera's Avalon Streaming
 interface.

 * Names - SOPC Builder expects the following names to be used for streaming
   interfaces (i.e. these are the names you should use in the top-level
   interface):
    * aso - Avalon-ST source
    * asi - Avalon-ST sink

 * Original version, May 2010
 * Update in September 2011 - added non-blocking streams
 * Update in October 2011 - added version with startofpacket and endofpacket
  
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
interface AvalonStreamSourcePhysicalIfc#(numeric type dataT_width);
   method Bit#(dataT_width) stream_out_data;
   method Bool stream_out_valid;
   method Action stream_out(Bool ready);
endinterface

interface AvalonStreamSourceVerboseIfc#(type dataT, numeric type dataT_width);
   interface Put#(dataT) tx;
   interface AvalonStreamSourcePhysicalIfc#(dataT_width) physical;
endinterface

typedef AvalonStreamSourceVerboseIfc#(dataT,SizeOf#(dataT)) AvalonStreamSourceIfc#(type dataT);

module mkPut2AvalonStreamSource(AvalonStreamSourceVerboseIfc#(dataT,dataT_width))
   provisos(Bits#(dataT,dataT_width));
   
   Wire#(Maybe#(Bit#(dataT_width))) data_dw <- mkDWire(tagged Invalid);
   Wire#(Bool) ready_w <- mkBypassWire;
   
   interface Put tx;
      method Action put(dataT d) if(ready_w);
				data_dw <= tagged Valid pack(d);
      endmethod
   endinterface

   interface AvalonStreamSourcePhysicalIfc physical;
      method Bit#(dataT_width) stream_out_data;
				return fromMaybe(0,data_dw);
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
 Source Stream NB (Non-blocking)
 i.e. with no ready signal, so no flow-control, but with a valid signal
 *****************************************************************************/

// Avalon-ST source physical interface.  Note that names of modules
// match SOPC's expectations.
(* always_ready, always_enabled *)
interface AvalonStreamSourceNBPhysicalIfc#(numeric type dataT_width);
   method Bit#(dataT_width) stream_out_data;
   method Bool stream_out_valid;
endinterface

interface AvalonStreamSourceNBVerboseIfc#(type dataT, numeric type dataT_width);
   interface Put#(dataT) tx;
   interface AvalonStreamSourceNBPhysicalIfc#(dataT_width) physical;
endinterface

typedef AvalonStreamSourceNBVerboseIfc#(dataT,SizeOf#(dataT)) AvalonStreamSourceNBIfc#(type dataT);

module mkPut2AvalonStreamSourceNB(AvalonStreamSourceNBVerboseIfc#(dataT,dataT_width))
   provisos(Bits#(dataT,dataT_width));
   
   Wire#(Maybe#(Bit#(dataT_width))) data_dw <- mkDWire(tagged Invalid);
   
   interface Put tx;
      method Action put(dataT d);
	 data_dw <= tagged Valid pack(d);
      endmethod
   endinterface

   interface AvalonStreamSourceNBPhysicalIfc physical;
      method Bit#(dataT_width) stream_out_data;
	 return fromMaybe(0,data_dw);
      endmethod
      method Bool stream_out_valid;
	 return isValid(data_dw);
      endmethod
   endinterface
endmodule


/*****************************************************************************
 Source Stream NBNV (Non-blocking, no-valid)
 i.e. with no ready signal and no valid signal so data received every
 clock cycle and there is no flow-control
 *****************************************************************************/

// Avalon-ST source physical interface.  Note that names of modules
// match SOPC's expectations.
(* always_ready, always_enabled *)
interface AvalonStreamSourceNBNVPhysicalIfc#(numeric type dataT_width);
   method Bit#(dataT_width) stream_out_data;
endinterface

interface AvalonStreamSourceNBNVVerboseIfc#(type dataT, numeric type dataT_width);
   interface Put#(dataT) tx;
   interface AvalonStreamSourceNBNVPhysicalIfc#(dataT_width) physical;
endinterface

typedef AvalonStreamSourceNBNVVerboseIfc#(dataT,SizeOf#(dataT)) AvalonStreamSourceNBNVIfc#(type dataT);

module mkPut2AvalonStreamSourceNBNV(AvalonStreamSourceNBNVVerboseIfc#(dataT,dataT_width))
   provisos(Bits#(dataT,dataT_width));
   
   Wire#(Maybe#(Bit#(dataT_width))) data_dw <- mkDWire(tagged Invalid);
   
   interface Put tx;
      method Action put(dataT d);
	 data_dw <= tagged Valid pack(d);
      endmethod
   endinterface

   interface AvalonStreamSourceNBNVPhysicalIfc physical;
      method Bit#(dataT_width) stream_out_data;
	 return fromMaybe(0,data_dw);
      endmethod
   endinterface
endmodule


/*****************************************************************************
 Sink Stream
 - a sink stream with ready and valid signals, so full flow-control
 *****************************************************************************/

// Avalon-ST sink physical interface.  Note that names of modules
// match SOPC's expectations.

(* always_ready, always_enabled *)
interface AvalonStreamSinkPhysicalIfc#(type dataT_width);
   method Action stream_in(Bit#(dataT_width) data, Bool valid);
   method Bool stream_in_ready;
endinterface

interface AvalonStreamSinkVerboseIfc#(type dataT, numeric type dataT_width);
   interface Get#(dataT) rx;
   interface AvalonStreamSinkPhysicalIfc#(dataT_width) physical;
endinterface

typedef AvalonStreamSinkVerboseIfc#(dataT,SizeOf#(dataT)) AvalonStreamSinkIfc#(type dataT);


module mkAvalonStreamSink2Get(AvalonStreamSinkVerboseIfc#(dataT,dataT_width))
   provisos(Bits#(dataT,dataT_width));
   
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
      method Action stream_in(Bit#(dataT_width) data, Bool valid);
	 if(valid)
	    d_dw <= tagged Valid unpack(data);
      endmethod
      method Bool stream_in_ready;
	 return f.notFull;
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
 Sink Stream Non-Blocking, No-Valid
 i.e. which is always ready (no flow-control) and sends valid data every cycle
 *****************************************************************************/

// Avalon-ST sink physical interface.  Note that names of modules
// match SOPC's expectations.

(* always_ready, always_enabled *)
interface AvalonStreamSinkNBNVPhysicalIfc#(type dataT_width);
   method Action stream_in(Bit#(dataT_width) data);
endinterface

interface AvalonStreamSinkNBNVVerboseIfc#(type dataT, numeric type dataT_width);
   interface Get#(dataT) rx;
   interface AvalonStreamSinkNBNVPhysicalIfc#(dataT_width) physical;
endinterface

typedef AvalonStreamSinkNBNVVerboseIfc#(dataT,SizeOf#(dataT)) AvalonStreamSinkNBNVIfc#(type dataT);


module mkAvalonStreamSinkNBNV2Get(AvalonStreamSinkNBNVVerboseIfc#(dataT,dataT_width))
   provisos(Bits#(dataT,dataT_width));
   
   FIFOF#(dataT) f <- mkLFIFOF;
   Wire#(Maybe#(dataT)) d_dw <- mkDWire(tagged Invalid);
   
   rule push_data_into_fifo (isValid(d_dw));
      f.enq(fromMaybe(?,d_dw));
   endrule
   
   interface Get rx = toGet(f);

   interface AvalonStreamSinkNBNVPhysicalIfc physical;
      // method to receive data.  Note that the data should be held
      // until stream_in_ready is True, i.e. there is room in the internal
      // FIFO - f - so we should never loose data from our d_dw DWire
      method Action stream_in(Bit#(dataT_width) data);
	    d_dw <= tagged Valid unpack(data);
      endmethod
   endinterface
endmodule


/*****************************************************************************
 Sink Stream Non-blocking
 i.e. which is always ready but contains a valid signal so data does
 not need to be sent every cycle
 *****************************************************************************/

// Avalon-ST sink physical interface.  Note that names of modules
// match SOPC's expectations.

(* always_ready, always_enabled *)
interface AvalonStreamSinkNBPhysicalIfc#(type dataT_width);
   method Action stream_in(Bit#(dataT_width) data, Bool valid);
endinterface

interface AvalonStreamSinkNBVerboseIfc#(type dataT, numeric type dataT_width);
   interface Get#(dataT) rx;
   interface AvalonStreamSinkNBPhysicalIfc#(dataT_width) physical;
endinterface

typedef AvalonStreamSinkNBVerboseIfc#(dataT,SizeOf#(dataT)) AvalonStreamSinkNBIfc#(type dataT);


module mkAvalonStreamSinkNB2Get(AvalonStreamSinkNBVerboseIfc#(dataT,dataT_width))
   provisos(Bits#(dataT,dataT_width));
   
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
      method Action stream_in(Bit#(dataT_width) data, Bool valid);
	 if(valid)
	    d_dw <= tagged Valid unpack(data);
      endmethod
   endinterface
endmodule


endpackage
