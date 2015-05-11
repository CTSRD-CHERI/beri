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

package CompositorOutput;

import CompositorUtils::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import SpecialFIFOs::*;

/**
 * Interface for the OUT stage of the compositor pipeline. This takes a RGB
 * slice of pixels from the CU stage and outputs them as Avalon-style packets,
 * one by one. It tracks the start and end of a frame, given the current output
 * resolution, and sets the control data in the output packets accordingly.
 *
 * If an underflow occurs (because the pipeline can't keep up with the pixel
 * clock), the OUT stage will not output extra pixels, but will print a warning
 * if running under simulation.
 *
 * If the compositor is disabled (because the output resolution is set to 0 in
 * either dimension), the OUT stage will output black pixels.
 *
 * TODO: Shouldn't this be clocked at the pixel clock rate? Or the pipeline's
 * going to be horrendously slow.
 *
 * The current configuration is exposed as a ReadOnly interface, so that the
 * resolution can be read by the module.
 *
 * TODO: What happens if the configuration is changed mid-frame?
 *
 * The endOfFrame method returns True iff the module is outputting the last
 * pixel of a frame this cycle.
 */
interface CompositorOutputIfc;
	method Action enq (CompositorOutputInputPacket in);
	(* always_ready *)
	interface Get#(CompositorOutputPacket) pixelsOut; /* Avalon stream for outputted pixels */

	method Action reset ();

	(* always_ready, always_enabled *)
	method Bool endOfFrame ();
endinterface: CompositorOutputIfc

/**
 * Input packet to the CompositorOutput pipeline stage. This contains a single
 * RGB output slice, which is ready to display on the screen, and in a typical
 * pipeline will be the next slice of pixels in a traditional raster scan
 * pattern.
 *
 * This is intended to map directly to CompositorUnitOutputPacket.
 */
typedef struct {
	RgbSlice outputSlice;
} CompositorOutputInputPacket deriving (Bits);

/**
 * Implementation of the CompositorOutputIfc interface. This implementation
 * stores slices from the OUT stage in the currentSlice input FIFO, dequeuing
 * from the FIFO after outputting the final pixel from the head slice.
 *
 * The module waits for the pipeline to fill up on initialisation and after
 * reset, outputting black pixels until the first output slice is produced by
 * the OUT stage.
 *
 * If the configuration specifies a zero resolution in either dimension, black
 * pixels are outputted.
 */
module mkCompositorOutput (ReadOnly#(CompositorConfiguration) configuration, CompositorOutputIfc ifc);
	/* This is a bypass FIFO to fit with the pipeline-wide structure of
	 * inputting to a bypass FIFO and outputting on a normal FIFO. It's two
	 * elements long to allow the next slice to be enqueued while still
	 * processing the current one. */
	FIFOF#(RgbSlice) currentSlice <- mkSizedBypassFIFOF (2);

	Reg#(UInt#(TLog#(MaxXResolution))) currentOutputPixelX <- mkReg (0); /* 0: first pixel (top-left) in the frame */
	Reg#(UInt#(TLog#(MaxYResolution))) currentOutputPixelY <- mkReg (0);

	/* Output pixel stream. It's two elements long to allow the next pixel
	 * to be enqueued while still waiting to output the current one (so that
	 * it will be ready the clock cycle after the current one is dequeued).
	 */
	FIFOF#(CompositorOutputPacket) outgoingPixels <- mkUGSizedFIFOF (2);

	/* Track whether the pipeline is still initialising. stillInitialising is set to false
	 * once the first output slice is received from the OUT stage. */
	Reg#(Bool) stillInitialising <- mkReg (True);
	PulseWire clearStillInitialising <- mkPulseWire ();
	PulseWire resetStillInitialising <- mkPulseWire ();

	/* Is this the last pixel? */
	Wire#(Bool) isEndOfFrame <- mkDWire (False);

	/* Return whether output is configured to be enabled. Output is disabled if either dimension of the resolution is 0. */
	function Bool isOutputEnabled (CompositorConfiguration configuration);
		return (configuration.xResolution != 0 && configuration.yResolution != 0);
	endfunction: isOutputEnabled

	/* Finish initialisation as soon as the first output slice is ready. */
	(* fire_when_enabled, no_implicit_conditions *)
	rule setStillInitialising;
		if (resetStillInitialising) begin
			stillInitialising <= True;
		end else if (stillInitialising && clearStillInitialising) begin
			debugController ($display ("finishInitialisation"));
			stillInitialising <= False;
		end
	endrule: setStillInitialising

	/* Output a single pixel to the output stream. */
	(* fire_when_enabled *)
	rule outputPixelEnabled (isOutputEnabled (configuration) && outgoingPixels.notFull ());
		clearStillInitialising.send ();

		/* Work out some coordinates. This is a little tricky because we have to handle the case where the X resolution is not a multiple of
		 * n, and hence we end up only using a few pixels from the final slice of a row. */
		let currentSlicePosition = currentOutputPixelX % fromInteger (valueOf (SliceSize));

		/* Grab the current output pixel from the current output slice. */
		let out = currentSlice.first[currentSlicePosition];

		debugCompositor ($display ("outputPixel: handling output pixel %0dx%0d (last output pixel is %0dx%0d): ",
		                           currentOutputPixelX, currentOutputPixelY,
		                           configuration.xResolution, configuration.yResolution,
		                           fshow (out)));

		/* Work out frame metadata. */
		let startingFrame = (currentOutputPixelX == 0 && currentOutputPixelY == 0);
		let finishingSlice = (((currentOutputPixelX + 1) % fromInteger (valueOf (SliceSize))) == 0);
		let finishingRow = ((currentOutputPixelX + 1) == configuration.xResolution);
		let finishingFrame = (finishingRow && (currentOutputPixelY + 1 == configuration.yResolution));

		isEndOfFrame <= finishingFrame;

		/* Move to the next output pixel or slice, but only if that slice is ready. */
		let nextOutputPixelX = currentOutputPixelX;
		let nextOutputPixelY = currentOutputPixelY;

		/* Move to the next output pixel, slice or row. */
		if (finishingFrame) begin
			nextOutputPixelX = 0;
			nextOutputPixelY = 0;
			currentSlice.deq ();
		end else if (finishingRow) begin
			nextOutputPixelX = 0;
			nextOutputPixelY = nextOutputPixelY + 1;
			currentSlice.deq ();
		end else if (finishingSlice) begin
			nextOutputPixelX = nextOutputPixelX + 1;
			currentSlice.deq ();
		end else begin
			nextOutputPixelX = nextOutputPixelX + 1;
`ifdef CHERI_COMPOSITOR_NO_OUTPUT
			/* See comment below. */
			currentSlice.deq ();
`endif
		end

		/* Save state. */
		currentOutputPixelX <= nextOutputPixelX;
		currentOutputPixelY <= nextOutputPixelY;

		/* Output a flit containing a single pixel. Set the sop field
		 * high iff we're starting a new frame and the eop field high
		 * iff we're finishing a frame. This allows the stream sink to
		 * sort out porches and sync signals.
		 *
		 * Allow the output pixel stream to be left disconnected for
		 * performance measurement purposes; flow control on the output
		 * (deliberately) affects the whole compositor pipeline, so it's
		 * impossible to measure the pipeline's maximum performance
		 * unless connected to an infeasibly large screen, because this
		 * pipeline stage slows the pipeline down by a factor of
		 * SliceSize. If CHERI_COMPOSITOR_NO_OUTPUT is defined,
		 * outgoingPixels won’t be used, and hence slices will be
		 * dequeued from the pipeline at the compositor clock rate. */
`ifndef CHERI_COMPOSITOR_NO_OUTPUT
		outgoingPixels.enq (CompositorOutputPacket {
			pixel: out,
			isStartOfFrame: startingFrame,
			isEndOfFrame: finishingFrame
		});
`endif
	endrule: outputPixelEnabled

	/* Enqueue an output slice of pixels from the OUT stage. */
	method Action enq (CompositorOutputInputPacket in);
		debugCompositor ($display ("CompositorOutput.enq: finished compositing: ", fshow (in.outputSlice)));
		currentSlice.enq (in.outputSlice);
	endmethod: enq

	/* Reset the pipeline stage. */
	method Action reset ();
		currentSlice.clear ();
		currentOutputPixelX <= 0;
		currentOutputPixelY <= 0;
		outgoingPixels.clear ();
		resetStillInitialising.send ();
	endmethod: reset

	/* Is this the last pixel of the frame? */
	method Bool endOfFrame ();
		return isEndOfFrame;
	endmethod: endOfFrame

	/* Pixel stream output to the HDMI module or analogue transceiver.
	 * Note: This should be always_ready; if outgoingPixels is empty, it will output a
	 * black pixel instead. */
	interface Get pixelsOut;
		method ActionValue#(CompositorOutputPacket) get ();
			CompositorOutputPacket packet;

			if (outgoingPixels.notEmpty ()) begin
				/* Output the next pixel in FIFO order. */
				packet = outgoingPixels.first;
				outgoingPixels.deq ();
			end else begin
				/* Output a single constant pixel when the compositor is disabled.
				 * If the next output pixel isn't ready, potentially emit a warning. */
				packet = CompositorOutputPacket {
					pixel: RgbPixel { red: 0, green: 0, blue: 0 }, /* black pixel */
					isStartOfFrame: False,
					isEndOfFrame: False
				};

				let notWarn <- $test$plusargs ("disable-compositor-underflow-warnings");
				if (isOutputEnabled (configuration) && !stillInitialising && !notWarn) begin
					Bool useColour <- $test$plusargs ("term-colour");
					if (useColour)
						$warning ("\033[0;31mUnderflow in output pixel stream!\033[0m Compositor's output is not valid yet (for output pixel %0dx%0d of %0dx%0d).",
						          currentOutputPixelX, currentOutputPixelY,
						          configuration.xResolution, configuration.yResolution);
					else
						$warning ("Underflow in output pixel stream! Compositor's output is not valid yet (for output pixel %0dx%0d of %0dx%0d).",
						          currentOutputPixelX, currentOutputPixelY,
						          configuration.xResolution, configuration.yResolution);
				end
			end

			return packet;
		endmethod: get
	endinterface: pixelsOut
endmodule: mkCompositorOutput

endpackage: CompositorOutput
