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

package CompositorMemoryRequest;

import CompositorUtils::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import SpecialFIFOs::*;
import Vector::*;

/**
 * Interface for the MEMQ stage of the compositor pipeline. This takes control
 * data from the TCER stage and converts it into memory requests, emitting one
 * request per cycle. It also processes the control data to give control inputs
 * for the MEMR stage, instructing it on how to rotate and combine the pixel
 * data returned from memory to form the next slice for composition.
 *
 * The emittingRequest method returns True iff the module is outputting a
 * request to memory.
 */
interface CompositorMemoryRequestIfc;
	interface Get#(CompositorMemoryRequest) extMemoryRequests;

	method Action enq (CompositorMemoryRequestInputPacket in);
	method Action deq ();
	method CompositorMemoryRequestOutputPacket first ();
	method Action clear ();

	method Action reset ();

	(* always_ready, always_enabled *)
	method Bool emittingRequest ();
endinterface: CompositorMemoryRequestIfc

/**
 * Input packet to the CompositorMemoryRequest pipeline stage. This contains
 * control data coordinating memory requests for pixels to be composited to form
 * the next slice to be rendered.
 *
 * This is intended to map directly to CompositorTceResponseOutputPacket.
 */
typedef struct {
	CUControlData controlData;
} CompositorMemoryRequestInputPacket deriving (Bits);

/**
 * Output packet from the CompositorMemoryRequest pipeline stage. This contains
 * control data coordinating rotation and combination of pixel data returned
 * from memory.
 *
 * requestMade is true if a memory request was made for this data and a response
 * should be expected from memory. If false, a response should not be expected.
 * xPadding gives the number of pixels of rotation to apply to the pixel data,
 * corresponding to the slice-modulus X offset of the CFB containing this layer.
 * lhPixelSource and rhPixelSource give the sources of pixels to be combined to
 * form the slice. After combination, the slice will be rotated (by xPadding
 * pixels) and passed to the CU stage.
 *
 * useBackground and isFinalOp are passed directly through from the TCER stage
 * to the CU stage.
 * useBackground is true if the bottom layer in the composition operation should
 * be the background colour, rather than the results of the previous
 * composition.
 * isFinalOp is true if the results of composition will be the final output
 * slice; i.e. if the composition's top layer is the top-most layer for this
 * slice and the result should be outputted to the screen.
 *
 * This is intended to map directly to CompositorMemoryResponseInputPacket.
 */
typedef struct {
	Bool requestMade;

	UInt#(TLog#(SliceSize)) xPadding;
	CompositorPixelSource lhPixelSource;
	CompositorPixelSource rhPixelSource;

	/* Pass-through. */
	Bool useBackground;
	Bool isFinalOp;
} CompositorMemoryRequestOutputPacket deriving (Bits);

/* Allow CompositorMemoryRequestOutputPackets to be formatted for debug output (only). */
instance FShow#(CompositorMemoryRequestOutputPacket);
	function Fmt fshow (CompositorMemoryRequestOutputPacket packet);
		return $format ("CompositorMemoryRequestOutputPacket { requestMade: %b, xPadding: %0d, lhPixelSource: %b, rhPixelSource: %b, useBackground: %b, isFinalOp: %b }",
		                packet.requestMade, packet.xPadding, packet.lhPixelSource, packet.rhPixelSource, packet.useBackground, packet.isFinalOp);
	endfunction: fshow
endinstance: FShow

/**
 * Implementation of the CompositorMemoryRequestIfc interface. For each slice
 * (each CompositorMemoryRequestInputPacket) the module stores the slice's
 * control data in a local register and dequeues the input packet. It then
 * updates the control data register once per cycle, working from the
 * bottom-most layer of the slice upwards until it reaches the top-most layer,
 * at which point it moves on to the next input packet/slice.
 *
 * For each layer, the module calculates the address of the slice's pixel data
 * in memory for that layer, and calculates the LH and RH pixel sources and X
 * offset for if the CFB contributing that pixel data is non-slice-aligned. If
 * pixel data needs to be requested, a memory request is enqueued to
 * memoryRequests. In any case, output control data is enqueued to
 * outputRequests for consumption by the MEMR stage.
 *
 * TODO: Add support for burst requests. That would entail emitting a burst
 * request on extMemoryRequests in parallel with a normal pipeline emission on
 * outputRequests; then to emit further pipeline emissions for the tail of the
 * burst on outputRequests *but not on extMemoryRequests*.
 */
module mkCompositorMemoryRequest (CompositorMemoryRequestIfc);
	/* DMA interface to DRAM. outputRequests stores the CU operations which
	 * triggered each request, for use with the response. */
	FIFO#(CompositorMemoryRequest) memoryRequests <- mkFIFO ();

	/* Output packets in the pipeline. One per cycle, so *at least* one per
	 * memory request. */
	FIFOF#(CompositorMemoryRequestOutputPacket) outputRequests <- mkSizedFIFOF (valueOf (MemoryLatency));

	/* Input packets in the pipeline. The packet currently having memory
	 * requests made for it is stored in currentControlData.
	 * inputControlData is only dequeued once all processing on the head
	 * element is finished and currentControlData is ready to be set to the
	 * next element in the FIFO. */
	FIFO#(CUControlData) inputControlData <- mkBypassFIFO ();
	Reg#(Maybe#(CUControlData)) currentControlData <- mkReg (tagged Invalid);

	/* Whether a request is being emitted this cycle. */
	Wire#(Bool) isEmittingRequest <- mkDWire (False);

	/**
	 * Calculate the address of a slice's pixel data in memory, given the
	 * TileCacheEntry which describes the client frame buffer (CFB)
	 * containing that slice, and the slice's position relative to the
	 * top-left of the screen. This first calculates the position of the CFB
	 * in slices relative to the top-left of the screen, then transforms the
	 * slice position to be relative to this CFB position; then converts the
	 * relative slice position to a memory address (in slices). The
	 * calculation is resolution independent.
	 */
	function SliceAddress tileCacheEntryToSliceAddress (TileCacheEntry entry, SlicePosition slicePosition);
		/* Calculate the (cached) CFB's position in terms of slices relative to the top-left of the screen. */
		UInt#(TLog#(TDiv#(MaxXResolution, SliceSize))) cfbXOffset = truncate (entry.x / fromInteger (valueOf (SliceSize)));
		let cfbYOffset = entry.y;

		/* Transform the slice position to be relative to the top-left of the CFB. */
		let sliceXOffset = slicePosition.xPos - zeroExtend (cfbXOffset);
		let sliceYOffset = slicePosition.yPos - zeroExtend (cfbYOffset);

		/* Build the slice address in slices (32 byte aligned). */
		return pack (zeroExtend (entry.allocatedTilesBase) * fromInteger (valueOf (TileSize) * valueOf (TileSize) / valueOf (SliceSize)) +
		             zeroExtend (sliceYOffset) * zeroExtend (entry.width) * fromInteger (valueOf (TileSize) / valueOf (SliceSize)) +
		             zeroExtend (sliceXOffset));
	endfunction: tileCacheEntryToSliceAddress

	/**
	 * Calculate whether the given slice lies entirely outside the given tile.
	 */
	function Bool sliceDisjointFromTile (TileCacheEntry entry, SlicePosition slicePosition);
		return slicePosition.yPos < entry.y ||
		       slicePosition.yPos >= entry.y + zeroExtend (entry.height) * fromInteger (valueOf (TileSize)) ||
		       zeroExtend (slicePosition.xPos) * fromInteger (valueOf (SliceSize)) + fromInteger (valueOf (SliceSize) - 1) < entry.x ||
		       zeroExtend (slicePosition.xPos) * fromInteger (valueOf (SliceSize)) >=
		           entry.x + zeroExtend (entry.width) * fromInteger (valueOf (TileSize));
	endfunction: sliceDisjointFromTile

	/* Update currentControlData for a new layer, potentially emitting a memory request. */
	(* fire_when_enabled *)
	rule outputRequest;
		debugController ($display ("CompositorMemoryRequest.outputRequest: control data: ", fshow (currentControlData)));

		CUControlData newControlData;

		if (fromMaybe (unpack (0), currentControlData).nextLayer == 0 || !isValid (currentControlData)) begin
			/* We're either at the top-most layer, or are initialising from invalid control data.
			 * In the former case we've finished this slice; move on to the next one in the output pixel stream.
			 * In the latter case, load up some valid control data (from inputControlData) and return it. */
			newControlData = inputControlData.first;
			debugController ($display ("CompositorMemoryRequest.outputRequest: dequeued ", fshow (newControlData)));
		end else begin
			/* Update the control data for this CU. *
			 * There's another layer in this slice. */
			newControlData = fromMaybe (unpack (0), currentControlData);
			let newNextLayer = newControlData.nextLayer - 1;
			newControlData.nextLayer = newNextLayer;
			newControlData.isFirstLayer = False;
			debugController ($display ("CompositorMemoryRequest.outputRequest: decremented existing nextLayer to %0d", newNextLayer));
		end

		/* If this is the last layer of the slice, dequeue the control data. */
		if (newControlData.nextLayer == 0) begin
			inputControlData.deq ();
		end

		currentControlData <= tagged Valid newControlData;

		/* Only schedule an operation if this slice is visible; it might not be visible due to the CFB having a non-tile offset. */
		let layerData = newControlData.layers[newControlData.nextLayer];

		debugController ($display ("CompositorMemoryRequest.outputRequest: using tile cache entry: ",
		                           fshow (layerData)));

		/* Build the CU operation from the control data.
		 *
		 * isSliceDisjoint is set when a CFB has an offset which is larger than one slice,
		 * but smaller than a tile. The order of layers calculated in
		 * CompositorTceResponse treats the CFB's slice as transparent, even if the CFB
		 * itself is entirely opaque. Consequently, we must skip it here.
		 *
		 * Padding is applied by rotating the slice after loading it from memory, so a
		 * single offset can be used to specify padding at the front or rear of the slice. */
		let isFirstSliceOfRow = (newControlData.slicePosition.xPos == truncate (layerData.x / fromInteger (valueOf (SliceSize))));
		let isFinalSliceOfRow = (newControlData.slicePosition.xPos ==
			truncate ((layerData.x + zeroExtend (layerData.width) * fromInteger (valueOf (TileSize))) / fromInteger (valueOf (SliceSize))));
		let isSliceDisjoint = sliceDisjointFromTile (layerData, newControlData.slicePosition);

		let offset = (isSliceDisjoint) ? 0 : truncate (layerData.x % fromInteger (valueOf (SliceSize)));
		let sliceAddr = (isFinalSliceOfRow || isSliceDisjoint) ? tagged Invalid : tagged Valid tileCacheEntryToSliceAddress (layerData, newControlData.slicePosition);
		let lhPixelSource = (isFinalSliceOfRow || isSliceDisjoint) ? SOURCE_TRANSPARENT : SOURCE_MEMORY;
		let rhPixelSource = (isFirstSliceOfRow || isSliceDisjoint) ? SOURCE_TRANSPARENT : SOURCE_PREVIOUS;

		let outputPacket = CompositorMemoryRequestOutputPacket {
			requestMade: isValid (sliceAddr),
			xPadding: offset,
			useBackground: newControlData.isFirstLayer,
			isFinalOp: (newControlData.nextLayer == 0),
			lhPixelSource: lhPixelSource,
			rhPixelSource: rhPixelSource
		};

		debugController ($display ("CompositorMemoryRequest.outputRequest: enqueueing ", fshow (outputPacket)));
		outputRequests.enq (outputPacket);

		if (isValid (sliceAddr)) begin
			/* If the address is invalid, skip the request since we have the data cached from the previous slice in this tile. */

			CompositorMemoryRequest req = CompositorMemoryRequest {
				burstLength: 1,
				sliceAddr: fromMaybe (?, sliceAddr)
			};

			debugCompositor ($display ("CompositorMemoryRequest.outputRequest: requesting ", fshow (req), " for operation ", fshow (outputPacket)));
			memoryRequests.enq (req);

			isEmittingRequest <= True;
		end
	endrule: outputRequest

	/* Enqueue a new input packet. Processing may not start on it immediately. */
	method Action enq (CompositorMemoryRequestInputPacket in);
		debugController ($display ("CompositorMemoryRequest.enq: control data: ", fshow (in.controlData)));
		inputControlData.enq (in.controlData);
	endmethod: enq

	/* Reset the pipeline stage. */
	method Action reset ();
		inputControlData.clear ();
		currentControlData <= tagged Invalid;
		outputRequests.clear ();
	endmethod: reset

	/* Whether a request is being emitted to memory this cycle. */
	method Bool emittingRequest ();
		return isEmittingRequest;
	endmethod: emittingRequest

	/* DMA interface to memory, acting as an Avalon master. */
	interface Get extMemoryRequests = toGet (memoryRequests);

	/* FIFO pipeline interface. */
	method Action deq = outputRequests.deq;
	method CompositorMemoryRequestOutputPacket first = outputRequests.first;
	method Action clear = outputRequests.clear;
endmodule: mkCompositorMemoryRequest

endpackage: CompositorMemoryRequest
