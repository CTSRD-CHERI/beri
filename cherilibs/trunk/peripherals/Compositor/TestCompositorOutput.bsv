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

package TestCompositorOutput;

import CompositorOutput::*;
import CompositorUtils::*;
import GetPut::*;
import StmtFSM::*;
import TestUtils::*;
import Vector::*;

(* synthesize *)
module mkTestCompositorOutput ();
	Reg#(CompositorConfiguration) configuration <- mkReg (CompositorConfiguration { xResolution: 0, yResolution: 0 });
	CompositorOutputIfc compositorOutput <- mkCompositorOutput (regToReadOnly (configuration));

	Wire#(Maybe#(CompositorOutputPacket)) currentOutput <- mkDWire (tagged Invalid);

	/* Temporary registers for loops. */
	Reg#(UInt#(32)) i <- mkReg (0);

	/* Assert that a valid pixel (not black) was outputted this cycle. */
	function assertOutputPixel ();
		action
			if (!isValid (currentOutput) ||
			    fromMaybe (?, currentOutput).pixel != RgbPixel { red: 0, green: 255, blue: 0 }) begin
				let theTime <- $time;
				failTest ($format ("%05t: expected pixel", theTime));
			end else begin
				$display ("%05t: clock", $time);
			end
		endaction
	endfunction: assertOutputPixel

	/* Pull output from the output module as fast as it will provide them. */
	(* fire_when_enabled *)
	rule grabPixel;
		let packet <- compositorOutput.pixelsOut.get ();
		currentOutput <= tagged Valid packet;
	endrule: grabPixel

	/* Pump slices into the output module as fast as it will accept them. */
	(* fire_when_enabled *)
	rule feedCompositor;
		compositorOutput.enq (CompositorOutputInputPacket {
			outputSlice: replicate (RgbPixel { red: 0, green: 255, blue: 0 })
		});
	endrule: feedCompositor

	Stmt testSeq = seq
		seq
			/* Check that the module outputs every cycle.
			 * Give it 1 cycle to get started after setting the configuration. */
			startTest ("Outputs every cycle");

			configuration <= CompositorConfiguration {
				xResolution: 32,
				yResolution: 32
			};
			delay (1);

			/* Check that a pixel is outputted every cycle for at least two slices. */
			loopEveryCycleNoSetup (i, 18, assertOutputPixel ());

			finishTest ();
		endseq
	endseq;
	mkAutoFSM (testSeq);
endmodule: mkTestCompositorOutput

endpackage: TestCompositorOutput
