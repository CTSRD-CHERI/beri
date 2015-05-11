/*-
 * Copyright (c) 2011 Simon W. Moore
 * Copyright (c) 2011 Jonathan Woodruff
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

 DMAVideoSource
 ==============
 
 Peripheral to provide a capability aware frame buffer.  Streams pixel data
 over an Avalon memory-mapped master interface to an Avalon stream.  This
 Avalon stream is formatted to work with TPadLCDdriver.bsv
 
 Currently the resolution is assumed to be 800x600 for the tPad colour LCD,
 but this should be parameterised, e.g if we wanted to hook it to a VGA
 output.
  
 *****************************************************************************/

package DMAVideoSource;

import FIFO::*;
import FIFOF::*;
import FIFOLevel::*;
import GetPut::*;
import ClientServer::*;
import AvalonStreaming::*;
import Avalon2ClientServer64be::*;
import BRAM::*;

Bool sim = False;

typedef struct {
		UInt#(5) r;   // red
		UInt#(6) g;   // green
		UInt#(5) b;   // blue
	} RGBT deriving (Bits,Eq);

typedef struct {
		RGBT pix0;
		RGBT pix1;
		RGBT pix2;
		RGBT pix3;
	} PixelPackT deriving (Bits,Eq);
	
typedef struct {
		Bool startOfFrame;
		Bool endOfFrame;
	} PixelTypeT deriving (Bits,Eq);
	 
typedef struct {
  Bool      unsealed;  // The Capability register to use
  Perms     perms;    // The offset into the capability register
  Bit#(48)  reserved;
  Bit#(64)  oType_eaddr;
  Bit#(64)  base;
  UInt#(64) length;
} Capability deriving(Bits, Eq);

typedef struct {
  Bool      permit_execute;
  Bool      permit_store_cap;
  Bool      permit_load_cap;
  Bool      permit_store;
  Bool      permit_load;
  Bool      permit_store_ephemeral_cap;
  Bool      permit_seal;
  Bool      reserved_1;
  Bool      reserved_2;
  Bool      reserved_3;
  Bool      access_CR28;
  Bool      access_CR29;
  Bool      access_CR30;
  Bool      access_CR31;
  Bool      non_ephemeral;
} Perms deriving(Bits, Eq); // 15 bits

Capability defaultCap = Capability{
    unsealed: True,
    perms: unpack(15'h7FFF),
    reserved: 48'b0,
    oType_eaddr: 64'b0,
    base: 		64'h04000000,
    length: 	64'h000EA600
  };
	
function BRAMRequest#(Bit#(18), Bit#(64)) makeRequest(Bool write, Bit#(18) addr, Bit#(64) data);
	return BRAMRequest{
		write: write,
		responseOnWrite:False,
		address: addr,
		datain: data
	};
endfunction

BRAM_Configure	defaultValue = BRAM_Configure {
	memorySize : 0,
	latency : 1, // No output reg
	outFIFODepth : 3,
	loadFormat : None,
	allowWriteResponseBypass : False};

interface DMAVideoSourceIfc;
   interface AvalonPacketStreamSourcePhysicalIfc#(SizeOf#(RGBT)) aso;
	 interface AvalonPipelinedMasterIfc#(29) avm;
endinterface


(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkDMAVideoSource(DMAVideoSourceIfc);
   
	AvalonPacketStreamSourceIfc#(RGBT) stream_out <- mkPut2AvalonPacketStreamSource;
	Server2AvalonPipelinedMasterIfc#(29) avalon <- mkServer2AvalonPipelinedMaster();
   
	UInt#(32) top = (800*600)*2;  // total memory read size.

	Reg#(UInt#(32)) 	count 				<- mkReg(0);
	Reg#(UInt#(2))		pixSwitch 		<- mkReg(0);
   
	Reg#(Capability) 		frameBuf 		<- mkReg(defaultCap);
	//FIFOLevelIfc#(PixelPackT,256) 	pixelBuf 	<- mkGFIFOLevel(True,False,True);
	FIFOF#(PixelPackT) 	pixelBuf 		<- mkSizedFIFOF(256);
  // the following two fifos must be shorter than pixelBuf to ensure that data from the memory pipe will not be dropped
  FIFOF#(PixelTypeT)	pixTypBuf		<- mkSizedFIFOF(250);
	 
	rule fetchPixels;	
		avalon.server.request.put(
			MemAccessPacketT{
				rw: MemRead,
				addr: frameBuf.base[31:3] + pack(count)[31:3],
				data: 64'b0,
				byteenable: 8'hFF,
				cached: False
			}
		);

		pixTypBuf.enq(PixelTypeT{
			startOfFrame: (count == 0), 
			endOfFrame: (count == top)
		});

		if (count < top) count <= count + 8;
		else count <= 0;
	endrule
	
	rule bufferPixels;
		Bit#(64) bits = extend(pack(count));//64'b0;

		ReturnedDataT ret <- avalon.server.response.get();
		bits = fromMaybe(64'b0, ret);
		
		PixelPackT pp = PixelPackT{
			pix0: unpack(bits[15:0]),
			pix1: unpack(bits[31:16]),
			pix2: unpack(bits[47:32]),
			pix3: unpack(bits[63:48])
		};
		pixelBuf.enq(pp);
	endrule
	
	rule scan;
		RGBT p = unpack(0);

		$display("In display");
		
		Bool sof = False;
		Bool eof = False;
		
		case (pixSwitch) // Select the pixel from the four in a packet.
			0: begin
				p = pixelBuf.first().pix0;
				sof = pixTypBuf.first.startOfFrame;
			end
			1: p = pixelBuf.first().pix1;
			2: p = pixelBuf.first().pix2;
			3: begin
				p = pixelBuf.first().pix3;
				eof = pixTypBuf.first.endOfFrame;
				pixelBuf.deq;
				pixTypBuf.deq;
				$display("dequeing pixel packet");
			end
		endcase
		pixSwitch <= pixSwitch + 1;
		$display("putting pixel");
		
		
    stream_out.tx.put(PacketDataT{d:p, sop:sof, eop:eof});
  endrule
   
  interface aso = stream_out.physical;
  interface avm = avalon.avm;
	
endmodule


endpackage
