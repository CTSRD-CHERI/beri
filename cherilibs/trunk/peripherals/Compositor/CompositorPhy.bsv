/*-
 * Copyright (c) 2013 Philip Withnall
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

package CompositorPhy;

import Avalon2ClientServer::*;
import AvalonBurstMaster::*;
import AvalonStreaming::*;
import ClientServer::*;
import Compositor::*;
import CompositorUtils::*;
import Connectable::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Peripheral::*;
import SpecialFIFOs::*;

`include "compositor-parameters.bsv"

/**
 * Interface for the compositor as a whole which uses generic types. This wraps
 * the CompositorIfc, adding control registers (regs and getIrqs()), while still
 * maintaining generic types on all its interfaces. It's intended that this is
 * then wrapped in a further interface which makes these types more specific
 * (e.g. to the Avalon bus).
 *
 * regs is a control register slave connection to the peripheral bus, on which
 * the compositor's registers are mapped in memory. All control requests and
 * responses go over this interface. The register layout in memory is defined by
 * the specific bus used for the control interface, and is documented in the
 * specialisation wrappers of this interface (such as CompositorPhyIfc).
 *
 * extMemory is a bus master connection to DRAM (either to main memory, or to a
 * private graphics DRAM, as decided by the SOC designer).
 *
 * pixelsOut is a stream interface providing output packets, each containing a
 * single output pixel and some frame metadata. Pixels are outputted in a raster
 * scan pattern (left to right, top to bottom).
 *
 * getIrqs() returns the compositor's IRQ line, which is 1 when an interrupt is
 * asserted, and is only reset after an explicit acknowledgement (via the
 * control registers) by the processor, as is standard on MIPS.
 */
interface CompositorPhyInnerIfc;
	interface Server#(PerifReq, PerifResp) regs;
	interface Client#(CompositorMemoryRequest, RgbaSlice) extMemory;
	(* always_ready *)
	interface Get#(CompositorOutputPacket) pixelsOut;
	(* always_ready, always_enabled *)
	method Bit#(1) getIrqs ();
endinterface: CompositorPhyInnerIfc

/**
 * Interface for the compositor as a whole which uses Avalon and Bluebus types;
 * a specialisation of the CompositorPhyInnerIfc.
 *
 * regs, extMemory and pixelsOut are as documented in CompositorPhyInnerIfc.
 *
 * The control register layout exposed on Bluebus is in terms of aligned
 * double-words, as offsets from the bottom of the control register mapping in
 * memory:
 *   0: Command header. Write-only. When written to, this enqueues the given
 *      command to be run with the current contents of the command payload
 *      register as its payload (so the payload register must be written before
 *      the header register).
 *   1: Command payload. Read-write. This gives the payload to be used with the
 *      next command to be enqueued.
 *   2: Response header. Read-write. Reading this gives the header of the next
 *      response from the compositor in FIFO order. The response will remain
 *      unchanged in the header and payload registers until a write to this
 *      register (of any value) is made; that will dequeue the current response
 *      and the next response will appear in the registers.
 *   3: Response payload. Read-only. This gives the payload associated with the
 *      response currently in the response header register.
 *
 * The behaviour of other registers is undefined.
 *
 * For the semantics of the command and response headers and payloads, see the
 * documentation for CompositorCommand and CompositorResponse.
 */
interface CompositorPhyIfc;
	interface Peripheral#(1) regs;
	interface Client#(AvalonBurstMaster::MemAccessPacketT#(27), AvalonBurstMaster::AvalonBurstWordT) extMemory;
	(* always_ready *)
	interface Get#(PacketDataT#(RgbPixel)) pixelsOut;
endinterface: CompositorPhyIfc

/**
 * Sequence number to associate a CompositorResponse with the CompositorCommand
 * which caused it.
 *
 * The bit width of this type is part of the compositor's ABI, so any changes
 * need to be reflected in the kernel driver.
 */
typedef UInt#(4) CompositorCommandSequenceNumber;

/**
 * Page selector to choose which set of parameters to return from a
 * GetParameters command. Splitting the output into pages is necessary due to
 * the limited width of the response bus.
 *
 * MONITOR: Parameters related to the primary monitor currently connected to the
 * compositor.
 * COMPOSITOR: Parameters related to the compositor hardware itself.
 * MANUFACTURER: Parameters related to the compositor's manufacturer.
 */
typedef enum {
	MONITOR,
	COMPOSITOR,
	MANUFACTURER
} CompositorParametersPage deriving (Eq);

/* Conversion of CompositorParametersPages to/from bit vectors. Use a 3-bit
 * encoding to allow of bit of breathing room for future expansion.
 * Note that this is part of the compositor ABI, so should not be changed in
 * backwards-incompatible ways. */
instance Bits#(CompositorParametersPage, 3);
	function Bit#(3) pack (CompositorParametersPage p);
		case (p) matches
			MONITOR: return 3'h0;
			COMPOSITOR: return 3'h1;
			MANUFACTURER: return 3'h2;
		endcase
	endfunction: pack

	function CompositorParametersPage unpack (Bit#(3) i);
		case (i)
			3'h0: return MONITOR;
			3'h1: return COMPOSITOR;
			3'h2: return MANUFACTURER;
			default: begin
				Action y = $error ("Illegal parameters page: %x", i);
				return MONITOR;
			end
		endcase
	endfunction: unpack
endinstance: Bits

/**
 * Monitor subpixel types supported by a given monitor. If non-UNKNOWN and
 * non-NONE, this indicates that the monitor supports sub-pixel rendering of,
 * for example, fonts to improve anti-aliasing.
 *
 * UNKNOWN: Subpixel status is unknown.
 * NONE: Subpixels are not supported.
 * HORIZONTAL_RGB: Horizontal subpixels are supported in RGB order.
 * HORIZONTAL_BGR: Horizontal subpixels are supported in BGR order.
 * VERTICAL_RGB: Vertical subpixels are supported in RGB order.
 * VERTICAL_BGR: Vertical subpixels are supported in BGR order.
 */
typedef enum {
	UNKNOWN,
	NONE,
	HORIZONTAL_RGB,
	HORIZONTAL_BGR,
	VERTICAL_RGB,
	VERTICAL_BGR
} CompositorMonitorSubpixel deriving (Eq);

/* Conversion of CompositorMonitorSubpixels to/from bit vectors. Use a 3-bit
 * encoding to allow of bit of breathing room for future expansion.
 * Note that this is part of the compositor ABI, so should not be changed in
 * backwards-incompatible ways. */
instance Bits#(CompositorMonitorSubpixel, 3);
	function Bit#(3) pack (CompositorMonitorSubpixel s);
		case (s) matches
			UNKNOWN: return 3'h0;
			NONE: return 3'h1;
			HORIZONTAL_RGB: return 3'h2;
			HORIZONTAL_BGR: return 3'h3;
			VERTICAL_RGB: return 3'h4;
			VERTICAL_BGR: return 3'h5;
		endcase
	endfunction: pack

	function CompositorMonitorSubpixel unpack (Bit#(3) i);
		case (i)
			3'h0: return UNKNOWN;
			3'h1: return NONE;
			3'h2: return HORIZONTAL_RGB;
			3'h3: return HORIZONTAL_BGR;
			3'h4: return VERTICAL_RGB;
			3'h5: return VERTICAL_BGR;
			default: begin
				Action y = $error ("Illegal subpixel type: %x", i);
				return UNKNOWN;
			end
		endcase
	endfunction: unpack
endinstance: Bits

/**
 * Pixel formats supported by the compositor. These specify how the compositor
 * can interpret pixel data in memory, mapping byte positions and values to
 * colours.
 *
 * B8G8R8A8: 32-bit BGRA colour with 8 bits per component.
 */
typedef enum {
	B8G8R8A8
} CompositorPixelFormat deriving (Eq);

/* Conversion of CompositorPixelFormats to/from bit vectors. Use a 3-bit
 * encoding to allow of bit of breathing room for future expansion.
 * Note that this is part of the compositor ABI, so should not be changed in
 * backwards-incompatible ways.
 *
 * Note also: this should be encoded one-hot, so that supported formats can be
 * returned as a set. */
instance Bits#(CompositorPixelFormat, 8);
	function Bit#(8) pack (CompositorPixelFormat p);
		case (p) matches
			B8G8R8A8: return 8'h00;
		endcase
	endfunction: pack

	function CompositorPixelFormat unpack (Bit#(8) i);
		case (i)
			8'h00: return B8G8R8A8;
			default: begin
				Action y = $error ("Illegal pixel format: %x", i);
				return B8G8R8A8;
			end
		endcase
	endfunction: unpack
endinstance: Bits

/**
 * Page selector to choose which set of statistics to return from a
 * GetStatistics command. Splitting the output into pages is necessary due to
 * the limited width of the response bus.
 *
 * PIPELINE1: Statistics related to the pipeline and flow control.
 * PIPELINE2: Statistics related to the pipeline and flow control.
 * PIPELINE3: Statistics related to the pipeline and flow control.
 * MEMORIES: Statistics related to the compositor's memory interfaces.
 * FRAME_RATE: Statistics related to frame output and clock cycle counting.
 */
typedef enum {
	PIPELINE1,
	PIPELINE2,
	PIPELINE3,
	MEMORIES,
	FRAME_RATE
} CompositorStatisticsPage deriving (Eq);

/* Conversion of CompositorStatisticsPages to/from bit vectors. Use a 3-bit
 * encoding to allow of bit of breathing room for future expansion.
 * Note that this is part of the compositor ABI, so should not be changed in
 * backwards-incompatible ways. */
instance Bits#(CompositorStatisticsPage, 3);
	function Bit#(3) pack (CompositorStatisticsPage p);
		case (p) matches
			PIPELINE1: return 3'h0;
			PIPELINE2: return 3'h1;
			PIPELINE3: return 3'h2;
			MEMORIES: return 3'h3;
			FRAME_RATE: return 3'h4;
		endcase
	endfunction: pack

	function CompositorStatisticsPage unpack (Bit#(3) i);
		case (i)
			3'h0: return PIPELINE1;
			3'h1: return PIPELINE2;
			3'h2: return PIPELINE3;
			3'h3: return MEMORIES;
			3'h4: return FRAME_RATE;
			default: begin
				Action y = $error ("Illegal statistics page: %x", i);
				return FRAME_RATE;
			end
		endcase
	endfunction: unpack
endinstance: Bits

/**
 * Control command structure, as written to the command header and payload
 * registers to enqueue a command to the compositor. See the Bits instance for
 * CompositorCommand for information on the bit layout.
 *
 * The header is formed by:
 *   seqNum: A driver-chosen sequence number for the command, which will be
 *           returned in the associated response to allow responses to different
 *           commands to be differentiated.
 *   fence: Whether an interrupt should be raised when the response to this
 *          command is enqueued. (Note: This is when the response is enqueued,
 *          not when it's dequeued. This allows for a fence to be at the end of
 *          a long sequence of instructions, causing an interrupt to be emitted
 *          as the last instruction is processed, and allowing the CPU to wake
 *          up and dequeue all the responses in one go.) This also causes
 *          execution of the command to block on all previous commands (in
 *          program order) completing (TODO: not implemented yet).
 *
 * The payload union gives a different payload layout for each command opcode.
 * They are documented inline below.
 *
 * The bit layout of this struct is part of the compositor's ABI, so any changes
 * need to be reflected in the kernel driver.
 */
typedef struct {
	CompositorCommandSequenceNumber seqNum;
	Bool fence;

	union tagged {
		void Noop;
		struct {
			UInt#(TLog#(MaxTiles)) allocatedTilesBase; /* address of the first tile of the CFB in memory, in tiles */
			UInt#(TLog#(MaxXTiles)) width; /* in tiles */
			UInt#(TLog#(MaxYTiles)) height; /* in tiles */
		} AllocateCfb;
		struct {
			ClientFrameBufferId cfbId;
		} FreeCfb;
		struct {
			ClientFrameBufferId cfbId;
			UInt#(TLog#(MaxXResolution)) xPosition; /* in pixels */
			UInt#(TLog#(MaxYResolution)) yPosition; /* in pixels */
			UInt#(TLog#(MaxVisibleTiles)) zPosition; /* higher numbers correspond to layers nearer the top */
			Bool updateInProgress;
		} UpdateCfb;
		struct {
			ClientFrameBufferId cfbToUpdate;
			ClientFrameBufferId cfbUpdated;
		} SwapCfbs;
		void GetConfiguration;
		struct {
			CompositorConfiguration configuration;
		} SetConfiguration;
		/* TODO: This instruction will be removed once the relevant functionality is implemented in hardware. */
		struct {
			UInt#(TLog#(MaxLayers)) layer;
			TileCacheEntryAddress address;
			TileCacheEntry entry;
		} UpdateTileCacheEntry;
		struct {
			CompositorParametersPage page;
		} GetParameters;
		struct {
			CompositorStatisticsPage page;
		} GetStatistics;
		struct {
			Bool reset;
			Bool isPaused;
		} ControlStatistics;
	} payload;
} CompositorCommand;

/* Conversion of CompositorCommands to/from bit vectors. */
instance Bits#(CompositorCommand, 96);
	function Bit#(96) pack (CompositorCommand c);
		/* This is needed by FIFOs which handle CompositorCommands. */
		Bit#(32) commandHeader = 0;
		Bit#(64) commandPayload = 0;
		UInt#(4) opcode;

		case (c.payload) matches
			tagged Noop: opcode = 0;
			tagged AllocateCfb .p: begin
				opcode = 1;
				commandPayload[6:0] = pack (p.width);
				commandPayload[13:8] = pack (p.height);
				commandPayload[31:16] = pack (p.allocatedTilesBase);
			end
			tagged FreeCfb .p: begin
				opcode = 2;
				commandPayload[15:0] = p.cfbId;
			end
			tagged UpdateCfb .p: begin
				opcode = 3;
				commandPayload[11:0] = pack (p.xPosition);
				commandPayload[26:16] = pack (p.yPosition);
				commandPayload[46:32] = pack (p.zPosition);
				commandPayload[47:47] = pack (p.updateInProgress);
				commandPayload[63:48] = p.cfbId;
			end
			tagged SwapCfbs .p: begin
				opcode = 4;
				commandPayload[15:0] = p.cfbToUpdate;
				commandPayload[31:16] = p.cfbUpdated;
			end
			tagged GetConfiguration: opcode = 5;
			tagged SetConfiguration .p: begin
				opcode = 6;
				commandPayload[11:0] = pack (p.configuration.xResolution);
				commandPayload[26:16] = pack (p.configuration.yResolution);
			end
			tagged UpdateTileCacheEntry .p: begin
				opcode = 9;
				commandPayload[60:58] = pack (p.layer);
				commandPayload[57:46] = p.address;
				commandPayload[45:0] = (pack (p.entry))[51:6] /* TODO: HACK! Drop the height and isOpaque */;
			end
			tagged GetParameters .p: begin
				opcode = 10;
				commandPayload[2:0] = pack (p.page);
			end
			tagged GetStatistics .p: begin
				opcode = 11;
				commandPayload[2:0] = pack (p.page);
			end
			tagged ControlStatistics .p: begin
				opcode = 12;
				commandPayload[1] = pack (p.reset);
				commandPayload[0] = pack (p.isPaused);
			end
			default: begin
				Action y = $error ("Illegal command with sequence number: %x", c.seqNum);
				opcode = 0;
			end
		endcase

		commandHeader = { 8'h00 /* padding */, 7'h00 /* padding */, pack (c.fence), 4'h0 /* padding */, pack (c.seqNum), 4'h0 /* padding */, pack (opcode) };

		return { commandHeader, commandPayload };
	endfunction: pack

	function CompositorCommand unpack (Bit#(96) i);
		CompositorCommand retval;

		let opcode = i[67:64];
		let seqNum = i[75:72];
		let fence = i[80];

		retval.seqNum = unpack (seqNum);
		retval.fence = unpack (fence);

		case (opcode)
			4'h0: retval.payload = tagged Noop;
			4'h1: retval.payload = tagged AllocateCfb { width: unpack (i[6:0]), height: unpack (i[13:8]), allocatedTilesBase: unpack (i[31:16]) };
			4'h2: retval.payload = tagged FreeCfb { cfbId: unpack (i[15:0]) };
			4'h3: retval.payload = tagged UpdateCfb { xPosition: unpack (i[11:0]), yPosition: unpack (i[26:16]),
			                                          zPosition: unpack (i[46:32]), updateInProgress: unpack (i[47:47]),
			                                          cfbId: i[63:48] };
			4'h4: retval.payload = tagged SwapCfbs { cfbToUpdate: unpack (i[15:0]), cfbUpdated: unpack (i[31:16]) };
			4'h5: retval.payload = tagged GetConfiguration;
			4'h6: retval.payload = tagged SetConfiguration { configuration: CompositorConfiguration {
				xResolution: unpack (i[11:0]),
				yResolution: unpack (i[26:16])
			} };
			4'h9: retval.payload = tagged UpdateTileCacheEntry { layer: unpack (i[60:58]), address: i[57:46], entry: unpack ({ 1'b0, i[45:0], 6'd15 }) } /* TODO: Hack! Make up the height and isOpaque */;
			4'hA: retval.payload = tagged GetParameters { page: unpack (i[2:0]) };
			4'hB: retval.payload = tagged GetStatistics { page: unpack (i[2:0]) };
			4'hC: retval.payload = tagged ControlStatistics { reset: unpack (i[1]), isPaused: unpack (i[0]) };
			default: begin
				Action y = $error ("Illegal command: %x", i);
				retval.payload = tagged Noop;
			end
		endcase

		return retval;
	endfunction: unpack
endinstance: Bits

/* Allow CompositorCommands to be formatted for debug output (only). */
instance FShow#(CompositorCommand);
	function Fmt fshow (CompositorCommand cmd);
		String opcode;
		Fmt operands;

		case (cmd.payload) matches
			tagged Noop: begin
				opcode = "Noop";
				operands = $format ("");
			end
			tagged AllocateCfb .p: begin
				opcode = "AllocateCfb";
				operands = $format ("width: %0d, height: %0d, allocatedTilesBase: %0d", p.width, p.height, p.allocatedTilesBase);
			end
			tagged FreeCfb .p: begin
				opcode = "FreeCfb";
				operands = $format ("cfbId: %0d", p.cfbId);
			end
			tagged UpdateCfb .p: begin
				opcode = "UpdateCfb";
				operands = $format ("cfbId: %0d, xPosition: %0d, yPosition: %0d, zPosition: %0d, updateInProgress: %b",
				                    p.cfbId, p.xPosition, p.yPosition, p.zPosition, p.updateInProgress);
			end
			tagged SwapCfbs .p: begin
				opcode = "SwapCfbs";
				operands = $format ("cfbToUpdate: %0d, cfbUpdated: %0d", p.cfbToUpdate, p.cfbUpdated);
			end
			tagged GetConfiguration .p: begin
				opcode = "GetConfiguration";
				operands = $format ("");
			end
			tagged SetConfiguration .p: begin
				opcode = "SetConfiguration";
				operands = $format ("configuration: ", fshow (p.configuration));
			end
			tagged UpdateTileCacheEntry .p: begin
				opcode = "UpdateTileCacheEntry";
				operands = $format ("layer: %0d, address: %0d, entry: ", p.layer, p.address, fshow (p.entry));
			end
			tagged GetParameters .p: begin
				opcode = "GetParameters";
				operands = $format ("page: %0d", p.page);
			end
			tagged GetStatistics .p: begin
				opcode = "GetStatistics";
				operands = $format ("page: %0d", p.page);
			end
			tagged ControlStatistics .p: begin
				opcode = "ControlStatistics";
				operands = $format ("reset: %b, isPaused: %b", p.reset, p.isPaused);
			end
			default: begin
				Action y = $error ("Unknown payload type in command: %x", cmd);
				opcode = "Unknown";
				operands = $format ("");
			end
		endcase

		return $format ("%s (%sseqNum: %0d) { ", opcode, cmd.fence ? "FENCE, " : "", cmd.seqNum, operands, " }");
	endfunction: fshow
endinstance: FShow

/**
 * Response status to a compositor command. Every command passed to the
 * compositor will result in a response status.
 *
 * The bit values of this type is part of the compositor's ABI, so any changes
 * need to be reflected in the kernel driver.
 */
typedef enum {
	FAILURE,
	SUCCESS
} CompositorResponseStatus deriving (Eq);

/* Conversion of CompositorResponseStatuses to/from bit vectors. Use a 4-bit encoding to allow of bit of breathing room for future expansion. */
instance Bits#(CompositorResponseStatus, 4);
	function Bit#(4) pack (CompositorResponseStatus s);
		return { 3'h0, (s == SUCCESS) ? 1'b1 : 1'b0 };
	endfunction: pack

	function CompositorResponseStatus unpack (Bit#(4) i);
		if (i[3:1] != 0)
			Action y = $error ("Illegal compositor response: %x", i);

		return (i[0] == 1'b1) ? SUCCESS : FAILURE;
	endfunction: unpack
endinstance: Bits

/**
 * Control response structure, as read from the response header and payload
 * registers to dequeue a response from the compositor. See the Bits instance
 * for CompositorResponse for information on the bit layout.
 *
 * The header is formed by:
 *   seqNum: A driver-chosen sequence number for the command, which will be
 *           returned in the associated response to allow responses to different
 *           commands to be differentiated.
 *   fence: Whether an interrupt should be raised when the response to this
 *          command is enqueued. (Note: This is when the response is enqueued,
 *          not when it's dequeued. This allows for a fence to be at the end of
 *          a long sequence of instructions, causing an interrupt to be emitted
 *          as the last instruction is processed, and allowing the CPU to wake
 *          up and dequeue all the responses in one go.) This also causes
 *          execution of the command to block on all previous commands (in
 *          program order) completing (TODO: not implemented yet).
 *
 * The payload union gives a different payload layout for each command opcode.
 * They are documented inline below.
 *
 * The bit layout of this struct is part of the compositor's ABI, so any changes
 * need to be reflected in the kernel driver.
 */
typedef struct {
	CompositorCommandSequenceNumber seqNum;
	CompositorResponseStatus status;

	union tagged {
		void Noop;
		void AllocateCfb;
		void FreeCfb;
		void UpdateCfb;
		void SwapCfbs;
		struct {
			CompositorConfiguration configuration;
		} GetConfiguration;
		void SetConfiguration;
		void UpdateTileCacheEntry;
		struct {
			CompositorParametersPage page;
			union tagged {
				struct {
					UInt#(12) xResolutionNative; /* pixels */
					UInt#(11) yResolutionNative; /* pixels */
					UInt#(7) refreshRate; /* Hertz */
					UInt#(10) ppi; /* pixels per inch */
					CompositorMonitorSubpixel subpixel;
				} Monitor;
				struct {
					UInt#(12) xResolutionMax; /* pixels */
					UInt#(11) yResolutionMax; /* pixels */
					UInt#(12) zResolutionMax; /* TODO */
					UInt#(TLog#(5)) tileSize; /* log_2(pixels) */
					CompositorPixelFormat pixelFormats;
				} Compositor;
				struct {
					UInt#(8) revisionId;
					UInt#(16) vendorId;
					UInt#(16) deviceId;
				} Manufacturer;
			} parameters;
		} GetParameters;
		struct {
			CompositorStatisticsPage page;
			union tagged {
				struct {
					UInt#(29) headToTceqCycles;
					UInt#(29) tceqToTcerCycles;
				} Pipeline1;
				struct {
					UInt#(29) tcerToMemqCycles;
					UInt#(29) memqToMemrCycles;
				} Pipeline2;
				struct {
					UInt#(29) memrToCuCycles;
					UInt#(29) cuToOutCycles;
				} Pipeline3;
				struct {
					UInt#(29) numTceRequests;
					UInt#(29) numMemoryRequests;
				} Memories;
				struct {
					UInt#(29) numCycles;
					UInt#(29) numFrames;
				} FrameRate;
			} statistics;
		} GetStatistics;
		void ControlStatistics;
	} payload;
} CompositorResponse;

/* Conversion of CompositorResponses to/from bit vectors. */
instance Bits#(CompositorResponse, 96);
	function Bit#(96) pack (CompositorResponse r);
		Bit#(32) responseHeader = 0;
		Bit#(64) responsePayload = 0;
		UInt#(4) opcode;

		/* The response header is returned in doubleword 2. */
		responseHeader = { 16'h0 /* padding */, 4'h0 /* padding */, pack (r.seqNum), 4'h0 /* opcode, set below */, pack (r.status) };

		/* The response payload is returned in doubleword 3. */
		case (r.payload) matches
			tagged Noop: begin
				opcode = 0;
				responsePayload = unpack (0);
			end
			tagged AllocateCfb .p: begin
				opcode = 1;
				responsePayload = unpack (0);
			end
			tagged FreeCfb: begin
				opcode = 2;
				responsePayload = unpack (0);
			end
			tagged UpdateCfb: begin
				opcode = 3;
				responsePayload = unpack (0);
			end
			tagged SwapCfbs: begin
				opcode = 4;
				responsePayload = unpack (0);
			end
			tagged GetConfiguration .p: begin
				opcode = 5;
				responsePayload = { 32'h0 /* padding */, 4'h0 /* padding */, pack (p.configuration.xResolution),
			                            5'h0 /* padding */, pack (p.configuration.yResolution) };
			end
			tagged SetConfiguration: begin
				opcode = 6;
				responsePayload = unpack (0);
			end
			tagged UpdateTileCacheEntry: begin
				opcode = 9;
				responsePayload = unpack (0);
			end
			tagged GetParameters .p: begin
				opcode = 10;
				case (p.parameters) matches
					tagged Monitor .m: begin
						responsePayload = {
							3'h0 /* page */,
							1'h0 /* padding */,
							pack (m.xResolutionNative),
							5'h0 /* padding */,
							pack (m.yResolutionNative),
							1'h0 /* padding */,
							pack (m.refreshRate),
							6'h0 /* padding */,
							pack (m.ppi),
							5'h0 /* padding */,
							pack (m.subpixel)
						};
					end
					tagged Compositor .c: begin
						responsePayload = {
							3'h1 /* page */,
							1'h0 /* padding */,
							pack (c.xResolutionMax),
							5'h0 /* padding */,
							pack (c.yResolutionMax),
							4'h0 /* padding */,
							pack (c.zResolutionMax),
							5'h0 /* padding */,
							pack (c.tileSize),
							pack (c.pixelFormats)
						};
					end
					tagged Manufacturer .v: begin
						responsePayload = {
							3'h2 /* page */,
							21'h0 /* padding */,
							pack (v.revisionId),
							pack (v.vendorId),
							pack (v.deviceId)
						};
					end
				endcase
			end
			tagged GetStatistics .p: begin
				opcode = 11;
				case (p.statistics) matches
					tagged Pipeline1 .o: begin
						responsePayload = {
							3'h0 /* page */,
							pack (o.headToTceqCycles),
							3'h0 /* padding */,
							pack (o.tceqToTcerCycles)
						};
					end
					tagged Pipeline2 .w: begin
						responsePayload = {
							3'h1 /* page */,
							pack (w.tcerToMemqCycles),
							3'h0 /* padding */,
							pack (w.memqToMemrCycles)
						};
					end
					tagged Pipeline3 .t: begin
						responsePayload = {
							3'h2 /* page */,
							pack (t.memrToCuCycles),
							3'h0 /* padding */,
							pack (t.cuToOutCycles)
						};
					end
					tagged Memories .m: begin
						responsePayload = {
							3'h3 /* page */,
							pack (m.numTceRequests),
							3'h0 /* padding */,
							pack (m.numMemoryRequests)
						};
					end
					tagged FrameRate .f: begin
						responsePayload = {
							3'h4 /* page */,
							pack (f.numCycles),
							3'h0 /* padding */,
							pack (f.numFrames)
						};
					end
				endcase
			end
			tagged ControlStatistics: begin
				opcode = 12;
				responsePayload = unpack (0);
			end
			default: begin
				Action y = $error ("Unknown payload type in response: %x", r);
				opcode = 0;
				responsePayload = unpack (0);
			end
		endcase

		responseHeader[7:4] = pack (opcode);

		return { responseHeader, responsePayload };
	endfunction: pack

	function CompositorResponse unpack (Bit#(96) i);
		CompositorResponse retval;

		retval.seqNum = unpack (i[75:72]);
		retval.status = unpack (i[67:64]);

		case (i[71:68])
			4'h0: retval.payload = tagged Noop;
			4'h1: retval.payload = tagged AllocateCfb;
			4'h2: retval.payload = tagged FreeCfb;
			4'h3: retval.payload = tagged UpdateCfb;
			4'h4: retval.payload = tagged SwapCfbs;
			4'h5: retval.payload = tagged GetConfiguration { configuration: CompositorConfiguration {
				xResolution: unpack (i[27:16]),
				yResolution: unpack (i[10:0])
			}};
			4'h6: retval.payload = tagged SetConfiguration;
			4'h9: retval.payload = tagged UpdateTileCacheEntry;
			4'hA: retval.payload = tagged GetParameters {
				page: unpack (i[63:61]),
				parameters: case (i[63:61])
					3'h0: tagged Monitor {
						xResolutionNative: unpack (i[59:48]),
						yResolutionNative: unpack (i[42:32]),
						refreshRate: unpack (i[30:24]),
						ppi: unpack (i[17:8]),
						subpixel: unpack (i[2:0])
					};
					3'h1: tagged Compositor {
						xResolutionMax: unpack (i[59:48]),
						yResolutionMax: unpack (i[42:32]),
						zResolutionMax: unpack (i[27:16]),
						tileSize: unpack (i[10:8]),
						pixelFormats: unpack (i[7:0])
					};
					3'h2: tagged Manufacturer {
						revisionId: unpack (i[39:32]),
						vendorId: unpack (i[31:16]),
						deviceId: unpack (i[15:0])
					};
					default: tagged Monitor {
						/* Error. */
						xResolutionNative: 0,
						yResolutionNative: 0,
						refreshRate: 0,
						ppi: 0,
						subpixel: UNKNOWN
					};
				endcase
			};
			4'hB: retval.payload = tagged GetStatistics {
				page: unpack (i[63:61]),
				statistics: case (i[63:61])
					3'h0: tagged Pipeline1 {
						headToTceqCycles: unpack (i[60:32]),
						tceqToTcerCycles: unpack (i[28:0])
					};
					3'h1: tagged Pipeline2 {
						tcerToMemqCycles: unpack (i[60:32]),
						memqToMemrCycles: unpack (i[28:0])
					};
					3'h2: tagged Pipeline3 {
						memrToCuCycles: unpack (i[60:32]),
						cuToOutCycles: unpack (i[28:0])
					};
					3'h3: tagged Memories {
						numTceRequests: unpack (i[60:32]),
						numMemoryRequests: unpack (i[28:0])
					};
					3'h4: tagged FrameRate {
						numCycles: unpack (i[60:32]),
						numFrames: unpack (i[28:0])
					};
					default: tagged FrameRate {
						/* Error. */
						numCycles: 0,
						numFrames: 0
					};
				endcase
			};
			4'hC: retval.payload = tagged ControlStatistics;
			default: begin
				Action y = $error ("Unknown payload type in response: %x", i);
				retval.payload = tagged Noop;
			end
		endcase

		return retval;
	endfunction: unpack
endinstance: Bits

/**
 * Implementation of the CompositorPhyInnerIfc interface. This implementation
 * handles command and response FIFOs, and interrupt emission and clearing.
 *
 * Interrupt behaviour: interrupts are triggered by the response to a fenced
 * command being enqueued. The interrupt output is kept high until the response
 * which triggered it is explicitly dequeued by software. If another fenced
 * command's response is enqueued before the interrupt line is reset, the
 * interrupt line is only reset once the latter command's response is dequeued.
 *
 * Commands are enqueued by writing the command payload to (32-bit) addresses 1
 * and 2, then the command header to address 0. The command is then executed.
 * The response command and payload will be available in addresses 3, 4 and 5
 * from the next clock cycle and will persist until address 3 is written to, at
 * which point the response from the next-executed command will be returned in
 * addresses 3, 4, 5. All commands and responses have sequence numbers.
 */
module mkCompositorPhyInner (CompositorPhyInnerIfc);
	Reg#(Bit#(64)) params <- mkReg (?);
	FIFOF#(CompositorCommand) commandBuffer <- mkDFIFOF (?);
	FIFOF#(Tuple2#(Bool, CompositorResponse)) responseBuffer <- mkDFIFOF (?);

	CompositorIfc compositor <- mkCompositor ();

	FIFO#(PerifReq) controlInBuffer <- mkFIFO ();
	FIFO#(PerifResp) controlOutBuffer <- mkFIFO ();

	/* Interrupt output line. This is taken high until explicitly
	 * acknowledged by software by dequeuing the command response which triggered the interrupt.
	 * The interruptOutCount counts the number of unacknowledged interrupts,
	 * and its width was arbitrarily chosen (with a lower bound of 1 so that
	 * it can count all entries in responseBuffer). */
	PulseWire emitInterrupt <- mkPulseWire ();
	PulseWire resetInterrupt <- mkPulseWire ();
	Reg#(UInt#(2)) interruptOutCount <- mkReg (0);

	/* Handle an incoming read/write request on the command interface. */
	(* fire_when_enabled *)
	rule handleCommandRequest;
		let req = controlInBuffer.first;
		controlInBuffer.deq ();
		PerifResp resp = 64'hdeaddeaddeaddead;
		UInt#(20) dword = unpack (req.offset[22:3]);

		debugCompositor ($display ("handleCommandRequest: %s of offset: %0d (dword: %0d), data: 0x%0h", req.read ? "read" : "write",
		                           req.offset, dword, req.data));

		case (tuple2 (dword, req.read))
			/* Doubleword 0 is the command header. */
			tuple2 (0, False): begin
				/* Schedule the command to be run. Ensure this won't block, since we want to return a response on the Avalon bus
				 * immediately. This will only block in the case that the command buffer is full, so we can afford to drop the
				 * command then. (We don't have much alternative, since we can't raise a bus exception.)
				 * TODO: Could we raise an interrupt? */
				let commandBits = { req.data[31:0], params };
				CompositorCommand command = unpack (commandBits);

				if (commandBuffer.notFull ()) begin
					debugCompositor ($display ("handleCommandRequest: enqueuing command 0x%0h: ", commandBits, fshow (command)));
					commandBuffer.enq (command);
				end
			end
			tuple2 (0, True):
				/* Write-only. */
				resp = 0;
			/* Doubleword 1 is the command payload. */
			tuple2 (1, False):
				params <= req.data;
			tuple2 (1, True):
				resp = params;
			/* Doubleword 2 is the response header. */
			tuple2 (2, False):
				/* Take any write to the response buffer to be an acknowledgement of the response. */
				if (responseBuffer.notEmpty ()) begin
					debugCompositor ($display ("handleCommandRequest: acknowledging response and dequeuing"));

					/* Was the response fenced? */
					if (tpl_1 (responseBuffer.first))
						resetInterrupt.send ();

					responseBuffer.deq ();
				end
			tuple2 (2, True):
				if (responseBuffer.notEmpty ()) begin
					let response = tpl_2 (responseBuffer.first);

					debugCompositor ($display ("handleCommandRequest: returning response header 0x%0h",
					                           pack (response)[95:64]));
					resp = { 32'h00000000, pack (response)[95:64] };
				end else begin
					$display ("Warning: Compositor returning 0 response due to empty responseBuffer.");
					resp = 0;
				end
			/* Doubleword 3 is the response payload. */
			tuple2 (3, False):
				begin /* Read-only. */ end
			tuple2 (3, True):
				if (responseBuffer.notEmpty ()) begin
					let response = tpl_2 (responseBuffer.first);

					debugCompositor ($display ("handleCommandRequest: returning response payload 0x%0h",
					                           pack (response)[63:0]));
					resp = pack (response)[63:0];
				end else begin
					$display ("Warning: Compositor returning 0 response due to empty responseBuffer.");
					resp = 0;
				end
			/* All other words return the default value given above. */
		endcase

		/* Note: We should only return a response for reads. */
		if (req.read) begin
			debugCompositor ($display ("handleCommandRequest: returning response 0x%0h", resp));
			controlOutBuffer.enq (resp);
		end
	endrule

	/* Pop a command off the command FIFO and run it. */
	(* fire_when_enabled *)
	rule runCommand (commandBuffer.notEmpty ());
		let command = commandBuffer.first;
		commandBuffer.deq ();
		CompositorResponse response;

		debugCompositor ($display ("runCommand: running ", fshow (command)));

		response.seqNum = command.seqNum;
		response.status = FAILURE;
		response.payload = ?;

		case (command.payload) matches
			tagged Noop .p: begin
				/* Do nothing. */
				response.status = SUCCESS;
				response.payload = tagged Noop;
			end
			tagged AllocateCfb .p: begin
				if (p.width == 0 || p.height == 0 ||
				    p.width > fromInteger (valueOf (MaxXTiles)) ||
				    p.height > fromInteger (valueOf (MaxYTiles))) begin
					/* Allocations must be non-zero-sized and also within the maximum resolution.
					 * It is up to the kernel to ensure that allocations don't overlap. */
					response.status = FAILURE;
				end else begin
					/* TODO: This should store the CFB metadata. */
					response.status = SUCCESS;
					response.payload = tagged AllocateCfb;
				end
			end
			tagged FreeCfb .p: begin
				/* TODO: This should free the CFB metadata. */
				response.status = SUCCESS;
				response.payload = tagged FreeCfb;
			end
			tagged UpdateCfb .p: begin
				/* TODO: This should update the CFB metadata and recalculate the relevant tile cache entries. */
				response.status = SUCCESS;
				response.payload = tagged UpdateCfb;
			end
			tagged SwapCfbs .p: begin
				/* TODO */
				response.status = SUCCESS;
				response.payload = tagged SwapCfbs;
			end
			tagged GetConfiguration .p: begin
				/* Get the configuration. */
				response.status = SUCCESS;
				response.payload = tagged GetConfiguration { configuration: compositor.configuration };
			end
			tagged SetConfiguration .p: begin
				/* Set the configuration. */
				if (p.configuration.xResolution > fromInteger (valueOf (MaxXResolution)) ||
				    p.configuration.yResolution > fromInteger (valueOf (MaxYResolution))) begin
					/* Throw an exception if the requested resolution is too big. */
					response.status = FAILURE;
				end else begin
					compositor.configuration <= p.configuration;

					response.status = SUCCESS;
					response.payload = tagged SetConfiguration;
				end
			end
			tagged UpdateTileCacheEntry .p: begin
				/* Update a tile cache entry in the compositor's controller. This is a temporary command which will be eliminated once
				 * the functionality to do this in hardware (derived from the CFB metadata) is implemented. Accordingly, it has no
				 * error checking or polish. */
				compositor.updateTileCacheEntry (p.layer, p.address, p.entry);
				response.status = SUCCESS;
				response.payload = tagged UpdateTileCacheEntry;
			end
			tagged GetParameters .p: begin
				case (p.page) matches
					MONITOR: begin
						response.status = SUCCESS;
						response.payload = tagged GetParameters {
							page: MONITOR,
							parameters: tagged Monitor {
								xResolutionNative: 800, /* TODO */
								yResolutionNative: 480, /* TODO */
								refreshRate: 60, /* TODO */
								ppi: 96, /* TODO */
								subpixel: NONE /* TODO */
							}
						};
					end
					COMPOSITOR: begin
						response.status = SUCCESS;
						response.payload = tagged GetParameters {
							page: COMPOSITOR,
							parameters: tagged Compositor {
								xResolutionMax: 2560, /* TODO */
								yResolutionMax: 1600, /* TODO */
								zResolutionMax: 2560, /* TODO */
								tileSize: fromInteger (valueOf (TLog#(TileSize))),
								pixelFormats: B8G8R8A8 /* TODO */
							}
						};
					end
					MANUFACTURER: begin
						response.status = SUCCESS;
						response.payload = tagged GetParameters {
							page: MANUFACTURER,
							parameters: tagged Manufacturer {
								revisionId: 1, /* TODO */
								vendorId: 0, /* TODO */
								deviceId: 0 /* TODO */
							}
						};
					end
					default: /* Invalid page */ begin
						response.status = FAILURE;
					end
				endcase
			end
			tagged GetStatistics .p: begin
				let stats = compositor.getStatistics ();

				case (p.page) matches
					PIPELINE1: begin
						response.status = SUCCESS;
						response.payload = tagged GetStatistics {
							page: PIPELINE1,
							statistics: tagged Pipeline1 {
								headToTceqCycles: stats.headToTceqCycles,
								tceqToTcerCycles: stats.tceqToTcerCycles
							}
						};
					end
					PIPELINE2: begin
						response.status = SUCCESS;
						response.payload = tagged GetStatistics {
							page: PIPELINE2,
							statistics: tagged Pipeline2 {
								tcerToMemqCycles: stats.tcerToMemqCycles,
								memqToMemrCycles: stats.memqToMemrCycles
							}
						};
					end
					PIPELINE3: begin
						response.status = SUCCESS;
						response.payload = tagged GetStatistics {
							page: PIPELINE3,
							statistics: tagged Pipeline3 {
								memrToCuCycles: stats.memrToCuCycles,
								cuToOutCycles: stats.cuToOutCycles
							}
						};
					end
					MEMORIES: begin
						response.status = SUCCESS;
						response.payload = tagged GetStatistics {
							page: MEMORIES,
							statistics: tagged Memories {
								numTceRequests: stats.numTceRequests,
								numMemoryRequests: stats.numMemoryRequests
							}
						};
					end
					FRAME_RATE: begin
						response.status = SUCCESS;
						response.payload = tagged GetStatistics {
							page: FRAME_RATE,
							statistics: tagged FrameRate {
								numCycles: stats.numCycles,
								numFrames: stats.numFrames
							}
						};
					end
					default: /* Invalid page */ begin
						response.status = FAILURE;
					end
				endcase
			end
			tagged ControlStatistics .p: begin
				if (p.reset) begin
					compositor.resetStatistics ();
				end
				if (p.isPaused) begin
					compositor.pauseStatistics ();
				end else begin
					compositor.unpauseStatistics ();
				end

				response.status = SUCCESS;
				response.payload = tagged ControlStatistics;
			end
		endcase

		/* Return the response. If the response buffer is full, there isn't much we can do.
		 * TODO: Could we raise an interrupt?
		 * TODO: Consider fences. */
		if (responseBuffer.notFull ()) begin
			debugCompositor ($display ("runCommand: enqueuing response 0x%0h", response));
			responseBuffer.enq (tuple2 (command.fence, response));

			if (command.fence) begin
				/* Emit an interrupt for the fence. We don't need to care about waiting for previous commands to complete at the moment,
				 * since we don't support out of order execution.
				 * This increment should never overflow unless responseBuffer overflows. */
				emitInterrupt.send ();
			end
		end
	endrule: runCommand

	/* Interrupt output. */
	(* fire_when_enabled, no_implicit_conditions *)
	rule trackUnacknowledgedInterrupts;
		if (emitInterrupt && !resetInterrupt)
			interruptOutCount <= interruptOutCount + 1;
		else if (!emitInterrupt && resetInterrupt)
			interruptOutCount <= interruptOutCount - 1;
	endrule: trackUnacknowledgedInterrupts

	method Bit#(1) getIrqs ();
		return (interruptOutCount == 0) ? 1'b0 : 1'b1;
	endmethod: getIrqs

	/* Connect up interfaces. */
	interface Server regs;
		interface Put request = toPut (controlInBuffer);
		interface Get response = toGet (controlOutBuffer);
	endinterface: regs

	interface extMemory = compositor.extMemory;
	interface pixelsOut = compositor.pixelsOut;
endmodule

/**
 * Implementation of the CompositorPhyIfc interface. This implementation
 * connects the compositor up to the Avalon and Bluebus buses for its memory
 * master and control slave connections, respectively.
 *
 * This has been tested at clocking up to 100MHz. Quartus indicates its Fmax is
 * around 114MHz at low optimisation levels. Originally, it was planned to clock
 * the compositor at 200MHz, and some work was done towards this end. However,
 * there were too many over-long combinatorial logic chains to be able to close
 * timing. The following need to be done before 200MHz timing can be closed:
 *  • CompositorMemoryRequest generates some long logic chains for its
 *    outputRequest rule.
 *  • MemoryLatency in compositor-parameters.bsv needs adjusting.
 *  • Clock domain crossing logic needs adding in TopAvalonPhy.bsv.
 *  • Qsys clock for the Compositor and AvalonSampler needs changing to 200MHz.
 *  • CompositorTceResponse generates some long arithmetic logic chains.
 *  • CompositorTceResponse generates some obscene Verilog for its
 *    countZerosLSB() call (although the synthesiser may optimise this away).
 */
`ifdef CHERI_COMPOSITOR
(* synthesize *)
module mkCompositorPhy (CompositorPhyIfc);
	CompositorPhyInnerIfc compositor <- mkCompositorPhyInner ();

	/* Connect up the control registers. */
	interface Peripheral regs;
		interface regs = compositor.regs;
		method getIrqs = compositor.getIrqs;
	endinterface: regs

	/* Connect up the memory interface. */
	interface Client extMemory;
		interface Get request;
			method ActionValue#(MemAccessPacketT#(27)) get ();
				let req <- compositor.extMemory.request.get ();
				MemAccessPacketT#(27) avalonReq = MemAccessPacketT {
					rw: tagged MemRead req.burstLength,
					addr: unpack (zeroExtend (req.sliceAddr)),
					data: 0
				};

				return avalonReq;
			endmethod: get
		endinterface: request

		interface Put response;
			method Action put (AvalonBurstWordT response);
				compositor.extMemory.response.put (unpack (pack (response)));
			endmethod: put
		endinterface: response
	endinterface: extMemory

	/* Connect up the pixel stream. */
	interface Get pixelsOut;
		method ActionValue#(PacketDataT#(RgbPixel)) get ();
			let packet <- compositor.pixelsOut.get ();
			PacketDataT#(RgbPixel) avalonPacket = PacketDataT {
				d: packet.pixel,
				sop: packet.isStartOfFrame,
				eop: packet.isEndOfFrame
			};

			return avalonPacket;
		endmethod: get
	endinterface: pixelsOut
endmodule: mkCompositorPhy
`endif /* CHERI_COMPOSITOR */

/**
 * Dummy implementation of the CompositorPhyIfc interface. This implementation
 * accepts all requests without blocking and returns dummy responses. It's
 * intended to be used as a drop-in replacement for mkCompositorPhy() for when
 * CHERI is to be built without the compositor enabled. This saves FPGA
 * resources.
 *
 * Unfortunately, it has to have the same name as the normal mkCompositorPhy,
 * otherwise a differently-named Verilog file is generated, and the Quartus
 * files which reference it have to be conditionalised on whether the compositor
 * is enabled; which defies the point of having this dummy module.
 */
`ifndef CHERI_COMPOSITOR
(* synthesize *)
module mkCompositorPhy (CompositorPhyIfc);
	Reg#(UInt#(2)) regsCounter <- mkReg (0);

	/* Control registers. */
	interface Peripheral regs;
		interface Server regs;
			interface Put request;
				method Action put (PerifReq req);
					regsCounter <= regsCounter + 1;
				endmethod: put
			endinterface: request

			interface Get response;
				method ActionValue#(PerifResp) get ()
						if (regsCounter > 0);
					regsCounter <= regsCounter - 1;
					/* "disabled" */
					return 64'hd15ab1edd15ab1ed;
				endmethod: get
			endinterface: response
		endinterface: regs

		method Bit#(1) getIrqs ();
			return 0;
		endmethod: getIrqs
	endinterface: regs

	/* External memory interface. */
	interface Client extMemory;
		interface Get request;
			method ActionValue#(MemAccessPacketT#(27)) get ()
					if (False);
				return unpack (0);
			endmethod: get
		endinterface: request

		interface Put response;
			method Action put (AvalonBurstWordT response);
				noAction;
			endmethod: put
		endinterface: response
	endinterface: extMemory

	/* Connect up the pixel stream. */
	interface Get pixelsOut;
		method ActionValue#(PacketDataT#(RgbPixel)) get ();
			return unpack (0);
		endmethod: get
	endinterface: pixelsOut
endmodule: mkCompositorPhy
`endif /* !CHERI_COMPOSITOR */

endpackage: CompositorPhy
