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

package CompositorUnit;

import CompositorUtils::*;
import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;

/**
 * Interface for a two-layer alpha compositor unit. It has a single slice of stored state (the ‘bottom layer’) and takes a top layer slice as input
 * (where a ‘slice’ is a linear vector of pixels of fixed length SliceSize each). One slice is layered on top of the other and the alpha composition
 * of the two is calculated as a third slice of the same length, SliceSize. The bottom slice is always opaque, which allows the composition
 * operation to be optimised, but imposes the limitation that layers must always be composited from the bottom upwards, and that infinite stacks of
 * non-opaque layers are not allowed.
 *
 * This pipeline stage is guaranteed to output a result every clock cycle (assuming isFinalOp is set in the input packet). It does not
 * guarantee that a given composition operation will take a single cycle. (However, this is currently the case.)
 */
interface CompositorUnitIfc;
	method Action enq (CompositorUnitInputPacket in);
	method Action deq ();
	method CompositorUnitOutputPacket first ();
	method Action clear ();

	method Action reset ();
endinterface: CompositorUnitIfc

/**
 * Input packet to the CompositorUnit pipeline stage. This contains the RGBA top slice of pixels to be composited with the stored
 * composition state, plus two bits of control metadata.
 *
 * useBackground determines whether to use the fixed background colour as the bottom slice, or whether to use the stored
 * composition state.
 * isFinalOp determines whether to enqueue the result slice to the output FIFO.
 *
 * This is intended to map directly to CompositorMemoryResponseOutputPacket.
 */
typedef struct {
	RgbaSlice topSlice;
	Bool useBackground;
	Bool isFinalOp;
} CompositorUnitInputPacket deriving (Bits);

/**
 * Output packet from the CompositorUnit pipeline stage. It currently contains a single RGB output slice, which is ready to display
 * on the screen, and in a typical pipeline will be the next slice of pixels in a traditional raster scan pattern.
 *
 * This is intended to map directly to CompositorOutputInputPacket.
 */
typedef struct {
	RgbSlice outputSlice;
} CompositorUnitOutputPacket deriving (Bits);

/**
 * Implementation of the CompositorUnitIfc interface, intended to be a single stage in a compositing pipeline. It implements alpha
 * compositing by parallel computation on each of the SliceSize pixels. Each pixel is blended with its counterpart in the other slice
 * using the Porter--Duff formula. The core of the implementation is a single-cycle multiply--accumulator and stored composition
 * state which is updated with each new input. The composition state can effectively be cleared by an input packet with useBackground
 * set high, which will ignore the saved state when performing its composition operation.
 *
 * The background colour will be replicated across all SliceSize pixels in the output, and will be used as the bottom layer of
 * composition exactly when useBackground is set in the input packet.
 *
 * Results are queued to the stage's output FIFO exactly when isFinalOp is set in the input packet. Consequently, this stage can output
 * packets at rates equal to or less than its input rate, depending how often isFinalOp is set. It is guaranteed that in-progress
 * composition state will not be pushed onto the output FIFO.
 */
module mkCompositorUnit (ReadOnly#(RgbPixel) backgroundColour, CompositorUnitIfc ifc);
	FIFO#(CompositorUnitOutputPacket) outputQueue <- mkFIFO ();
	Reg#(RgbSlice) bottomSlice <- mkRegU ();

	/* Porter--Duff formula for a single component of two stacked pixels.
	 * The bottom pixel is opaque (i.e. 1.0), simplifying the formula. The
	 * synthesised version is further simplified by using non-saturating
	 * addition, since the calculation is guaranteed not to overflow due to
	 * using pre-multiplied colour components. */
	function PixelComponent alphaCompositeComponent (PixelComponentPM topComponent, PixelComponent topAlpha, PixelComponent bottomComponent);
		return pixelComponentPMtoNonPM (topComponent + pixelComponentNonPMtoPM (bottomComponent * (1.0 - topAlpha)));
	endfunction: alphaCompositeComponent

	/* Porter--Duff formula for all components of two stacked pixels. */
	function RgbPixel alphaCompositePixel (RgbaPixel topPixel, RgbPixel bottomPixel);
		return RgbPixel {
			red: alphaCompositeComponent (topPixel.red, topPixel.alpha, bottomPixel.red),
			green: alphaCompositeComponent (topPixel.green, topPixel.alpha, bottomPixel.green),
			blue: alphaCompositeComponent (topPixel.blue, topPixel.alpha, bottomPixel.blue)
		};
	endfunction: alphaCompositePixel

	/* Start a compositor operation, buffering topSlice and bottomSlice in one clock cycle and overwriting the buffered result
	 * of any previous compositor operation. */
	method Action enq (CompositorUnitInputPacket in);
		let oldBottomSlice = in.useBackground ? replicate (backgroundColour) : bottomSlice;
		let newBottomSlice = zipWith (alphaCompositePixel, in.topSlice, oldBottomSlice);

		debugUnit ($display ("CompositorUnit.enq: ", fshow (in.topSlice), " over ", fshow (oldBottomSlice)));

		if (!in.isFinalOp) begin
			bottomSlice <= newBottomSlice;
		end else begin
			outputQueue.enq (CompositorUnitOutputPacket {
				outputSlice: newBottomSlice
			});
		end
	endmethod: enq

	/**
	 * Reset the pipeline stage's state.
	 */
	method Action reset ();
		outputQueue.clear ();
	endmethod: reset

	/* FIFO output interface. */
	method deq = outputQueue.deq;
	method first = outputQueue.first;
	method clear = outputQueue.clear;
endmodule: mkCompositorUnit

endpackage: CompositorUnit
