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

package CompositorTceRequest;

import BRAM::*;
import CompositorUtils::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;

`include "compositor-parameters.bsv"

/**
 * Interface for the TCEQ stage of the compositor pipeline. This takes the
 * coordinates of an output region as input, and generates a stream of requests
 * to the tile caches for tile cache entries relevant to the output region.
 *
 * An output region is a region of the screen which needs to be redrawn. In
 * graphics terminology, it's also known as a refresh area, invalidation area,
 * or redraw area. It could be the entire screen (to draw a whole frame) or a
 * small area of the screen (e.g. where the cursor is, if it's just moved).
 *
 * The emittingRequest method returns True iff the module is outputting a
 * request to the tile caches.
 */
interface CompositorTceRequestIfc;
	method Action enq (CompositorTceRequestInputPacket in);
	method Action deq ();
	method CompositorTceRequestOutputPacket first ();
	method Action clear ();

	method Action reset ();

	(* always_ready, always_enabled *)
	method Bool emittingRequest ();
endinterface: CompositorTceRequestIfc

/**
 * Input packet to the CompositorTceRequest pipeline stage. This contains
 * coordinates of the output region to be drawn.
 *
 * drawRegion is the output region to be drawn, specified in slice relative to
 * the top-left corner of the screen.
 *
 * This is the first input to the compositor pipeline.
 */
typedef struct {
	SliceRegion drawRegion;
} CompositorTceRequestInputPacket deriving (Bits);

/**
 * Output packet from the CompositorTceRequest pipeline stage. This contains the
 * position of the slice to be rendered next; the slice for which requests to
 * the tile caches have just been sent, and hence for which tile cache entries
 * will be returned next in order.
 *
 * This is intended to map directly to CompositorTceResponseInputPacket.
 */
typedef struct {
	SlicePosition slicePosition;
} CompositorTceRequestOutputPacket deriving (Bits);

/**
 * Implementation of the CompositorTceRequestIfc interface. This implementation
 * allows a short queue of drawing regions to be used, which will all be
 * rendered in FIFO order.
 *
 * The tile caches are exposed as a Put interface, so that only requests to them
 * may be emitted by the module. It is up to the next module up in the hierarchy
 * to connect the same tile cache BRAMs to both the CompositorTceRequest and
 * CompositorTceResponse pipeline stages.
 */
module mkCompositorTceRequest (Vector#(MaxLayers, Put#(BRAMRequest#(TileCacheEntryAddress, TileCacheEntry))) tceRequests, CompositorTceRequestIfc ifc);
	/* Coordinates of the next slice to start being composited, given in numbers of slices (not pixels). */
	Reg#(SlicePosition) currentSlicePosition <- mkRegU ();
	Reg#(Bool) isIdle <- mkReg (True);

	/* FIFO of regions to draw. */
	FIFOF#(SliceRegion) drawRegions <- mkBypassFIFOF ();

	/* FIFO to the next pipeline stage. */
	FIFO#(CompositorTceRequestOutputPacket) outputRequests <- mkFIFO ();

	/* Whether a request is being emitted this cycle. */
	Wire#(Bool) isEmittingRequest <- mkDWire (False);

	/**
	 * Calculate a TileCacheEntryAddress from a slice's position. This works out which tile contains the given slice, then calculates the cache
	 * address for that tile's TileCacheEntry. The calculation is resolution independent; if we're running at a non-maximum resolution, tile cache
	 * entries on the bottom-right edge of the screen will go unused and there may be gaps in the utilised addressing of tile cache entries.
	 */
	function TileCacheEntryAddress slicePositionToTileCacheEntryAddress (SlicePosition pos);
		/* First, convert the slice position to a tile position. */
		UInt#(TLog#(MaxXTiles)) tileXPos = truncate (pos.xPos / fromInteger (valueOf (TileSize) / valueOf (SliceSize)));
		UInt#(TLog#(MaxYTiles)) tileYPos = truncate (pos.yPos / fromInteger (valueOf (TileSize)));

		/* Then convert the tile position to an address. Tiles are addressed left-to-right, top-to-bottom, with address 0 being
		 * the top-left tile. The unit of addressing is a whole tile, so address 1 is the tile after that of address 0 (and not
		 * some offset within its cache entry). */
		return pack (zeroExtend (tileYPos) * fromInteger (valueOf (MaxXTiles)) + zeroExtend (tileXPos));
	endfunction: slicePositionToTileCacheEntryAddress

	/* Reset the currentSlicePosition to the top-left corner of the next region to draw, if
	 * the drawRegions FIFO is non-empty and the stage is otherwise idle. */
	(* fire_when_enabled *)
	rule startFrame (isIdle && drawRegions.notEmpty ());
		currentSlicePosition <= drawRegions.first.topLeftPos;
		isIdle <= False;
	endrule: startFrame

	/* Advance the currentSlicePosition and emit requests to each of the tile caches (one per
	 * layer) for the relevant tile cache entries. */
	(* fire_when_enabled *)
	rule emitRequest (!isIdle && drawRegions.notEmpty ());
		let currentRegion = drawRegions.first;

		debugController ($display ("CompositorTceRequest.emitRequest: current slice position ", fshow (currentSlicePosition), " with region: ", fshow (currentRegion)));

		for (Integer i = 0; i < valueOf (MaxLayers); i = i + 1) begin
			let addr = slicePositionToTileCacheEntryAddress (currentSlicePosition);
			debugController ($display ("CompositorTceRequest.enq: requesting tile cache entry %0d for layer %0d", addr, i));

			tceRequests[i].put (BRAMRequest {
				write: False,
				responseOnWrite: False,
				address: addr,
				datain: ? /* ignored for reads */
			});
		end

		outputRequests.enq (CompositorTceRequestOutputPacket {
			slicePosition: currentSlicePosition
		});

		isEmittingRequest <= True;

		/* Update the next slice to be composited, raster scanning through the currentRegion. */
		let newCurrentSlicePosition = currentSlicePosition;

		if (currentSlicePosition == currentRegion.bottomRightPos) begin
			/* Finished drawing the region. */
			drawRegions.deq ();
			isIdle <= True;

			/* Allow the mux logic for newCurrentSlicePosition to be optimised. */
			newCurrentSlicePosition.xPos = ?;
			newCurrentSlicePosition.yPos = ?;
		end else if (currentSlicePosition.xPos == currentRegion.bottomRightPos.xPos) begin
			newCurrentSlicePosition.xPos = currentRegion.topLeftPos.xPos;
			newCurrentSlicePosition.yPos = currentSlicePosition.yPos + 1;
		end else begin
			newCurrentSlicePosition.xPos = currentSlicePosition.xPos + 1;
		end

		currentSlicePosition <= newCurrentSlicePosition;
	endrule: emitRequest

	/* Enqueue a request to draw another output region. The region should be non-empty. */
	method Action enq (CompositorTceRequestInputPacket in);
		drawRegions.enq (in.drawRegion);
	endmethod: enq

	/* Reset the pipeline stage. */
	method Action reset ();
		/* No need to set currentSlicePosition because it'll be overwritten when we start a new frame anyway. */
		drawRegions.clear ();
		outputRequests.clear ();
		isIdle <= True;
	endmethod: reset

	/* Whether a request is being emitted this cycle. */
	method Bool emittingRequest ();
		return isEmittingRequest;
	endmethod: emittingRequest

	/* FIFO pipeline interface. */
	method Action deq = outputRequests.deq;
	method CompositorTceRequestOutputPacket first = outputRequests.first;
	method Action clear = outputRequests.clear;
endmodule: mkCompositorTceRequest

endpackage: CompositorTceRequest
