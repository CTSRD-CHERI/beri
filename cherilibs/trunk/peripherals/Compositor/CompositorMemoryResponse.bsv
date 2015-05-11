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

package CompositorMemoryResponse;

import CompositorUtils::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import SpecialFIFOs::*;
import Vector::*;

/**
 * Interface for the MEMR stage of the compositor pipeline. This takes control
 * data describing pixel data requested from memory as input, plus the pixel
 * data itself, then processes the pixel data to produce a slice of pixels which
 * are ready for composition in the CU stage.
 *
 * Processing involves retrieving two vectors (LH and RH) of pixel data from
 * different sources, combining a specified number of pixels from each to form
 * an 8-pixel slice, then rotating that slice so that all the LH pixels are on
 * the right-hand side, and all the RH pixels are on the left-hand side.
 *
 * Pixels can come from three sources: pixel data from memory (via
 * extMemoryResponses); previous pixel data from memory (stored locally in the
 * module); or a constant vector of transparent pixels.
 */
interface CompositorMemoryResponseIfc;
	interface Put#(RgbaSlice) extMemoryResponses;

	method Action enq (CompositorMemoryResponseInputPacket in);
	method Action deq ();
	method CompositorMemoryResponseOutputPacket first ();
	method Action clear ();

	method Action reset ();
endinterface: CompositorMemoryResponseIfc

/**
 * Input packet to the CompositorMemoryResponse pipeline stage. This contains
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
 * This is intended to map directly to CompositorMemoryRequestOutputPacket.
 */
typedef struct {
	Bool requestMade;

	UInt#(TLog#(SliceSize)) xPadding;
	CompositorPixelSource lhPixelSource;
	CompositorPixelSource rhPixelSource;

	/* Pass-through. */
	Bool useBackground;
	Bool isFinalOp;
} CompositorMemoryResponseInputPacket deriving (Bits);

/* Allow CompositorMemoryResponseInputPackets to be formatted for debug output (only). */
instance FShow#(CompositorMemoryResponseInputPacket);
	function Fmt fshow (CompositorMemoryResponseInputPacket packet);
		return $format ("CompositorMemoryResponseInputPacket { requestMade: %b, xPadding: %0d, lhPixelSource: %b, rhPixelSource: %b, useBackground: %b, isFinalOp: %b }",
		                packet.requestMade, packet.xPadding, packet.lhPixelSource, packet.rhPixelSource, packet.useBackground, packet.isFinalOp);
	endfunction: fshow
endinstance: FShow

/**
 * Output packet from the CompositorMemoryResponse pipeline stage. This contains
 * a slice of pixels which are ready for composition as the upper slice to be
 * passed into the CU stage. It also contains some control data for the CU
 * stage.
 *
 * useBackground is true if the bottom layer in the composition operation should
 * be the background colour, rather than the results of the previous
 * composition.
 * isFinalOp is true if the results of composition will be the final output
 * slice; i.e. if the composition's top layer is the top-most layer for this
 * slice and the result should be outputted to the screen.
 *
 * This is intended to map directly to CompositorUnitInputPacket.
 */
typedef struct {
	RgbaSlice topSlice;

	/* Pass-through. */
	Bool useBackground;
	Bool isFinalOp;
} CompositorMemoryResponseOutputPacket deriving (Bits);

/**
 * Implementation of the CompositorMemoryResponseIfc interface. This
 * implementation combines pixels from two sources to produce a vector of pixels
 * which is then rotated to form the stage's output.
 *
 * For example, given xPadding = 3, lhPixels = 12345678 and rhPixels = ABCDEFGH,
 * this module will output:
 *     combinedPixels = rotateBy (combinePixels (lhPixels, rhPixels, 3), 3)
 *                    = rotateBy (12345FGH, 3)
 *                    = FGH12345
 * and given xPadding = 2, lhPixels = 12345678 and rhPixels = * (transparent),
 * it will output:
 *     combinedPixels = rotateBy (combinePixels (lhPixels, rhPixels, 2), 2)
 *                    = rotateBy (123456**, 2)
 *                    = **123456
 * Finally, for xPadding = 0, lhPixels = 12345678 and rhPixels = ABCDEFGH, the
 * module will output:
 *     combinedPixels = rotateBy (combinePixels (lhPixels, rhPixels, 0), 0)
 *                    = rotateBy (12345678, 0)
 *                    = 12345678
 * (i.e. xPadding = 0 will always return lhPixels untransformed).
 *
 * This has been carefully implemented to use one mux per pixel (in
 * combinePixels, choosing between lhPixels and rhPixels), plus one 8-pixel
 * rotater.
 *
 * The pipeline stage supports ignoring memory responses when coming out of
 * reset (the reset() method). By default it will ignore memory responses for
 * the first 3 cycles after reset. This is hard-coded and fairly arbitrarily
 * chosen so that it works with the observed memory latency and pipeline fill
 * levels. It probably should be re-written at some point.
 */
module mkCompositorMemoryResponse (CompositorMemoryResponseIfc);
	/* Response interface for DMA from DRAM. Expect to receive one response
	 * per cycle when operating at maximum resolution. */
	FIFOF#(RgbaSlice) memoryResponses <- mkSizedBypassFIFOF (valueOf (MemoryLatency));

	/* Stored copy of the previous slice retrieved from memory, to allow it
	 * to be combined with the current response in the case that a CFB is
	 * offset and each slice requires contributions of pixels from two
	 * 32-byte aligned input slices in memory. */
	/* TODO: Shouldn't there be one of these for every layer? */
	Reg#(RgbaSlice) previousMemoryResponse <- mkRegU ();

	/* Output slices and metadata. */
	FIFO#(CompositorMemoryResponseOutputPacket) outputResponses <- mkFIFO ();

	/* Remaining number of cycles to ignore incoming memory responses for after reset. */
	Reg#(UInt#(TLog#(TAdd#(SliceSize, 1)))) ignoreMemoryResponses <- mkReg (0);

	/* Generator function for a vector of pixels formed from the head (SliceSize - xPadding) pixels of the left-hand vector of pixels
	 * and the tail xPadding pixels of the right-hand vector of pixels.
	 * See: CompositorMemoryResponse.enq.
	 *
	 * e.g.
	 * Given xPadding = 3, lhPixels = 12345678, rhPixels = ABCDEFGH,
	 * this is used to generate combinedPixels = rotateBy (12345FGH, 3) = FGH12345
	 * Given xPadding = 0, lhPixels = 12345678, rhPixels = ABCDEFGH,
	 * this is used to generate combinedPixels = rotateBy (12345678, 0) = 12345678
	 */
	function RgbaPixel combinePixels (UInt#(TLog#(SliceSize)) xPadding, Vector#(SliceSize, RgbaPixel) lhPixels, Vector#(SliceSize, RgbaPixel) rhPixels, Integer i);
		let useRh = (fromInteger (valueOf (SliceSize) - 1 - i) < xPadding);
		let pixelVector = useRh ? rhPixels : lhPixels;
		return pixelVector[fromInteger (i)];
	endfunction: combinePixels

	/* Ignore memory responses if we've just reset the compositor. */
	rule ignoreMemoryResponse (ignoreMemoryResponses > 0);
		debugCompositor ($display ("CompositorMemoryResponse.ignoreMemoryResponse"));
		if (memoryResponses.notEmpty ())
			memoryResponses.deq ();
		ignoreMemoryResponses <= ignoreMemoryResponses - 1;
	endrule: ignoreMemoryResponse

	/* Handle a response from memory and start the associated CU operation. This has to handle rotating the slice of pixels retrieved from
	 * memory, so that slices which are part of a CFB with a non-slice-sized offset can be rendered while still performing slice-aligned
	 * memory accesses.
	 *
	 * Four cases can occur:
	 *  LH = memory, RH = transparent: first slice of a CFB
	 *  LH = memory, RH = previous: interior slices of a CFB
	 *  LH = transparent, RH = previous: final slice of a CFB
	 *  LH = transparent, RH = transparent: slice preceding or following a CFB
	 */
	method Action enq (CompositorMemoryResponseInputPacket in) if (ignoreMemoryResponses == 0);
		RgbaSlice lhPixels;
		RgbaSlice rhPixels;

		/* Optimised muxing of pixel sources to set the lhPixels and rhPixels.
		 * This is possible because [l|r]hPixels = unpack (0) in the transparent case.
		 *
		 * The following code is equivalent to:
		 *     case (in.lhPixelSource)
		 *     SOURCE_MEMORY: begin
		 *         lhPixels = memoryResponses.first;
		 *         memoryResponses.deq ();
		 *     end
		 *     SOURCE_TRANSPARENT: begin
		 *         lhPixels = replicate (RgbaPixel { red: 0, green: 0, blue: 0, alpha: 0 });
		 *     end
		 *     default: begin
		 *         lhPixels = ?;
		 *     end
		 * endcase
		 *
		 * Similarly for the rhPixels case, except using previousMemoryResponse and SOURCE_PREVIOUS
		 * rather than memoryResponses and SOURCE_MEMORY. */

		/* Left-hand vector of pixels. memoryResponses.first must be examined conditionally
		 * to avoid affecting the method's implicit preconditions. */
		RgbaSlice memoryResponse = ?;
		if (in.lhPixelSource == SOURCE_MEMORY) begin
			memoryResponse = memoryResponses.first;
			memoryResponses.deq ();
		end

		lhPixels = unpack (pack (memoryResponse) &
		                   pack (replicate (in.lhPixelSource == SOURCE_MEMORY)));

		/* Right-hand vector of pixels. */
		rhPixels = unpack (pack (previousMemoryResponse) &
		                   pack (replicate (in.rhPixelSource == SOURCE_PREVIOUS)));

		debugCompositor ($display ("CompositorMemoryResponse.enq: operation ", fshow (in), " got LH pixels ", fshow (lhPixels), " and RH pixels ", fshow (rhPixels)));

		/* Combine the two vectors of pixels as described in combinePixels. */
		let combinedPixels = rotateBy (genWith (combinePixels (in.xPadding, lhPixels, rhPixels)), in.xPadding);

		/* Forward the shifted slice to the next pipeline stage and update state. */
		if (in.xPadding != 0 && in.requestMade) begin
			previousMemoryResponse <= lhPixels;
		end

		outputResponses.enq (CompositorMemoryResponseOutputPacket {
			topSlice: combinedPixels,
			useBackground: in.useBackground,
			isFinalOp: in.isFinalOp
		});
	endmethod: enq

	/* Reset the pipeline stage. */
	method Action reset ();
		ignoreMemoryResponses <= 3; /* ignore memory responses for 3 cycles to clear the queue */
		memoryResponses.clear ();
		outputResponses.clear ();
	endmethod: reset

	/* DMA interface to memory, acting as an Avalon master. */
	interface Put extMemoryResponses = toPut (memoryResponses);

	/* FIFO pipeline interface. */
	method Action deq = outputResponses.deq;
	method CompositorMemoryResponseOutputPacket first = outputResponses.first;
	method Action clear = outputResponses.clear;
endmodule: mkCompositorMemoryResponse

endpackage: CompositorMemoryResponse
