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

package TestCompositorUnit;

import CompositorUnit::*;
import CompositorUtils::*;
import StmtFSM::*;
import TestUtils::*;
import Vector::*;

(* synthesize *)
module mkTestCompositorUnit ();
	Reg#(RgbPixel) backgroundColour <- mkReg (RgbPixel { red: 20, green: 30, blue: 40 });
	CompositorUnitIfc compositorUnit <- mkCompositorUnit (regToReadOnly (backgroundColour));

	Wire#(Maybe#(CompositorUnitOutputPacket)) currentOutput <- mkDWire (tagged Invalid);

	/* Assert that the expected output slice was outputted this cycle. */
	function assertOutputSlice (expectedSlice);
		action
			if (!isValid (currentOutput)) begin
				let theTime <- $time;
				failTest ($format ("%05t: expected output slice", theTime));
			end else if (fromMaybe (?, currentOutput).outputSlice != expectedSlice) begin
				failTest ($format ("expected ", fshow (expectedSlice), ", got ", fshow (fromMaybe (?, currentOutput).outputSlice)));
			end else begin
				$display ("%05t: - expected ", $time, fshow (expectedSlice));
			end
		endaction
	endfunction: assertOutputSlice

	/* Pull output from the CU module as fast as it will provide it. */
	(* fire_when_enabled *)
	rule grabOutputSlice;
		let packet = compositorUnit.first;
		compositorUnit.deq ();
		currentOutput <= tagged Valid packet;
	endrule: grabOutputSlice

	Stmt testSeq = seq
		seq
			/* Check that an opaque top layer covers the background. */
			startTest ("Opaque top layer covers background");
			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 1, green: 2, blue: 3, alpha: 255 }),
				useBackground: True,
				isFinalOp: True
			});
			assertOutputSlice (replicate (RgbPixel { red: 1, green: 2, blue: 3 }));
			finishTest ();
		endseq


		seq
			/* Check that a transparent top layer does not cover the background. */
			startTest ("Transparent top layer does not cover background");
			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 0, green: 0, blue: 0, alpha: 0 }),
				useBackground: True,
				isFinalOp: True
			});
			assertOutputSlice (replicate (backgroundColour));
			finishTest ();
		endseq


		seq
			/* Check that a translucent top layer is composited with the background. */
			startTest ("Translucent top layer composites with background");
			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 123, green: 5, blue: 88, alpha: 160 }),
				useBackground: True,
				isFinalOp: True
			});
			assertOutputSlice (replicate (RgbPixel { red: 130, green: 16, blue: 103 }));
			finishTest ();
		endseq


		seq
			/* Check that several translucent layers are composited with the background. */
			startTest ("Translucent layers composite with background");
			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 123, green: 5, blue: 88, alpha: 160 }),
				useBackground: True,
				isFinalOp: False
			});
			/* Should give (130, 16, 102). */
			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 0, green: 0, blue: 0, alpha: 0 }),
				useBackground: False,
				isFinalOp: False
			});
			/* Should give (130, 16, 102). */
			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 10, green: 10, blue: 10, alpha: 10 }),
				useBackground: False,
				isFinalOp: False
			});
			/* Should give (134, 25, 108). */
			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 5, green: 100, blue: 80, alpha: 120 }),
				useBackground: False,
				isFinalOp: True
			});
			assertOutputSlice (replicate (RgbPixel { red: 76, green: 113, blue: 138 }));
			finishTest ();
		endseq


		seq
			/* Check that resetting clears the output FIFO state. */
			startTest ("Resetting clears composition state");
			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 123, green: 5, blue: 88, alpha: 160 }),
				useBackground: True,
				isFinalOp: True
			});

			compositorUnit.reset ();

			compositorUnit.enq (CompositorUnitInputPacket {
				topSlice: replicate (RgbaPixel { red: 0, green: 0, blue: 0, alpha: 0 }),
				useBackground: True,
				isFinalOp: True
			});

			assertOutputSlice (replicate (backgroundColour));
			finishTest ();
		endseq
	endseq;
	mkAutoFSM (testSeq);
endmodule: mkTestCompositorUnit

endpackage: TestCompositorUnit
