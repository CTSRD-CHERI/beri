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

package CompositorTceResponse;

import BRAM::*;
import CompositorUtils::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;

`include "compositor-parameters.bsv"

/**
 * Interface for the TCER stage of the compositor pipeline. This takes pairs of
 * a slice position and tile cache entries for that slice as input, and outputs
 * control data coordinating memory requests for pixels to be composited to form
 * that slice. The control data is calculated to provide addresses for the pixel
 * data of each layer in the slice, starting with the top-most opaque layer and
 * proceeding by increasing Z coordinate.
 */
interface CompositorTceResponseIfc;
	method Action enq (CompositorTceResponseInputPacket in);
	method Action deq ();
	method CompositorTceResponseOutputPacket first ();
	method Action clear ();

	method Action reset ();
endinterface: CompositorTceResponseIfc

/**
 * Input packet to the CompositorTceResponse pipeline stage. This contains the
 * position of the slice to be rendered next; the slice for which requests to
 * the tile caches have just been sent, and hence for which tile cache entries
 * will be returned next in order.
 *
 * This is intended to map directly to CompositorTceRequestOutputPacket.
 */
typedef struct {
	SlicePosition slicePosition;
} CompositorTceResponseInputPacket deriving (Bits);

/**
 * Output packet from the CompositorTceResponse pipeline stage. This contains
 * control data coordinating memory requests for pixels to be composited to form
 * the next slice to be rendered.
 *
 * This is intended to map directly to CompositorMemoryRequestInputPacket.
 */
typedef struct {
	CUControlData controlData;
} CompositorTceResponseOutputPacket deriving (Bits);

/**
 * Implementation of the CompositorTceResponseIfc interface. This implementation
 * determines which of the layers in the slice are opaque (according to their
 * cached isOpaque bits, plus some calculations about whether the CFB for that
 * layer is offset far enough to make a slice transparent), and sets the
 * nextLayer to be rendered accordingly.
 *
 * The bottom-most layer ((MaxLayers - 1)th layer) of a slice is always treated
 * as opaque, even if it isn't actually, so that composition can complete in a
 * bounded time, by limiting the number of layers composited to form a single
 * slice to MaxLayers.
 *
 * The pipeline stage supports ignoring memory responses when coming out of
 * reset (the reset() method). By default it will ignore memory responses for
 * the first 3 cycles after reset. This is hard-coded and fairly arbitrarily
 * chosen so that it works with the observed memory latency and pipeline fill
 * levels. It probably should be re-written at some point.
 *
 * The tile caches are exposed as a Get interface, so that only responses from
 * them may be grabbed by the module. It is up to the next module up in the
 * hierarchy to connect the same tile cache BRAMs to both the
 * CompositorTceRequest and CompositorTceResponse pipeline stages.
 */
module mkCompositorTceResponse (Vector#(MaxLayers, Get#(TileCacheEntry)) tceResponses, CompositorTceResponseIfc ifc);
	/* Output packets in the pipeline. */
	FIFO#(CompositorTceResponseOutputPacket) outputResponses <- mkFIFO ();

	/* Remaining number of cycles to ignore incoming TCE responses for after reset. */
	Reg#(UInt#(TLog#(TAdd#(SliceSize, 1)))) ignoreTceResponses <- mkReg (0);

	/* Calculate whether the given slice should be treated as opaque on a given layer.
	 * This takes in the slice's position, plus the TileCacheEntry for that slice on a
	 * given layer. */
	function Bool sliceIsOpaqueForLayer (SlicePosition slicePosition, TileCacheEntry entry);
		let isSliceAligned = (entry.x % fromInteger (valueOf (SliceSize)) == 0);
		let spansCurrentSliceX =
			entry.x <= zeroExtend (slicePosition.xPos) * fromInteger (valueOf (SliceSize)) &&
			entry.x + zeroExtend (entry.width) * fromInteger (valueOf (TileSize)) >
				zeroExtend (slicePosition.xPos) * fromInteger (valueOf (SliceSize)) + fromInteger (valueOf (SliceSize) - 1);
		let spansCurrentSliceY =
			entry.y <= slicePosition.yPos &&
			entry.y + zeroExtend (entry.height) * fromInteger (valueOf (TileSize)) >
				zeroExtend (slicePosition.yPos);
		let spansCurrentSlice = spansCurrentSliceX && spansCurrentSliceY;

		return entry.isOpaque && (isSliceAligned || spansCurrentSlice);
	endfunction: sliceIsOpaqueForLayer

	/* Ignore TCE responses if we've just reset the compositor. */
	rule ignoreTceResponse (ignoreTceResponses > 0);
		debugCompositor ($display ("CompositorTceResponse.ignoreTceResponse"));
		for (Integer i = 0; i < valueOf (MaxLayers); i = i + 1) begin
			let dummy <- tceResponses[i].get ();
		end
		ignoreTceResponses <= ignoreTceResponses - 1;
	endrule: ignoreTceResponse

	/* Continue decrementing the ignoreTceResponses counter to 0 even if there aren't
	 * any responses to ignore in a clock cycle. */
	(* descending_urgency = "ignoreTceResponse, ignoreNoTceResponse" *)
	rule ignoreNoTceResponse (ignoreTceResponses > 0);
		ignoreTceResponses <= ignoreTceResponses - 1;
	endrule: ignoreNoTceResponse

	/* Process a slice position and its tile cache entries, and generate control data for that slice. */
	method Action enq (CompositorTceResponseInputPacket in) if (ignoreTceResponses == 0);
		/* Read the responses from the tile cache entry caches. */
		Vector#(MaxLayers, TileCacheEntry) tileCacheEntries = newVector ();

		for (Integer i = 0; i < valueOf (MaxLayers); i = i + 1) begin
			tileCacheEntries[i] <- tceResponses[i].get ();
			debugController ($display ("CompositorTceResponse.enq: got response ", fshow (tileCacheEntries[i]), " for layer %0d", i));
		end

		let slicePosition = in.slicePosition;

		/* Calculate the index of the first layer to composite. This should be the index
		 * of the top-most opaque layer; equivalently the lowest index of any opaque layer.
		 *
		 * Always treat the bottom-most layer as opaque, since if no other layers are opaque, the bottom-most
		 * layer will always have to be composited (regardless of whether it's transparent or opaque).
		 * If an otherwise opaque layer has a non-slice-sized offset, it will end up being mixed with
		 * transparent pixels on its edges, so must be counted as non-opaque.
		 *
		 * nextLayer should be in [0, MaxLayers - 1]. */
		Vector#(MaxLayers, Bool) sliceIsOpaque = map (sliceIsOpaqueForLayer (slicePosition), tileCacheEntries);
		sliceIsOpaque[valueOf (MaxLayers) - 1] = True; /* see note above */

		UInt#(TLog#(MaxLayers)) nextLayer = countZerosLSB (pack (sliceIsOpaque));

		/* Create and enqueue the control data, ready to be used to composite the slice. */
		let controlData = CUControlData {
			layers: tileCacheEntries,
			nextLayer: nextLayer,
			isFirstLayer: True,
			slicePosition: slicePosition
		};

		debugController ($display ("CompositorTceResponse.enq: enqueueing ", fshow (controlData)));
		outputResponses.enq (CompositorTceResponseOutputPacket {
			controlData: controlData
		});
	endmethod: enq

	/* Reset the pipeline stage. */
	method Action reset ();
		ignoreTceResponses <= 3; /* ignore TCE responses for 3 cycles to clear the queue */
		outputResponses.clear ();
	endmethod: reset

	/* FIFO pipeline interface. */
	method Action deq = outputResponses.deq;
	method CompositorTceResponseOutputPacket first = outputResponses.first;
	method Action clear = outputResponses.clear;
endmodule: mkCompositorTceResponse

endpackage: CompositorTceResponse
