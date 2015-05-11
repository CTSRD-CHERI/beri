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

package TestCompositorMemoryRequest;

import CompositorMemoryRequest::*;
import CompositorUtils::*;
import GetPut::*;
import StmtFSM::*;
import TestUtils::*;
import Vector::*;

(* synthesize *)
module mkTestCompositorMemoryRequest ();
	CompositorMemoryRequestIfc compositorMemoryRequest <- mkCompositorMemoryRequest ();

	Wire#(Maybe#(CompositorMemoryRequestOutputPacket)) currentOutput <- mkDWire (tagged Invalid);
	Wire#(Maybe#(CompositorMemoryRequest)) currentRequest <- mkDWire (tagged Invalid);

	/* Temporary registers for loops. */
	Reg#(UInt#(32)) i <- mkReg (0);

	/* Assert that a valid packet and request were outputted this cycle. */
	function assertOutputPacket ();
		action
			if (!isValid (currentOutput)) begin
				let theTime <- $time;
				failTest ($format ("%05t: expected packet", theTime));
			end else if (!isValid (currentRequest)) begin
				let theTime <- $time;
				failTest ($format ("%05t: expected memory request", theTime));
			end else begin
				$display ("%05t: clock", $time);
			end
		endaction
	endfunction: assertOutputPacket

	/* Pull output from the MEMQ module as fast as it will provide it. */
	(* fire_when_enabled *)
	rule grabOutputPacket;
		let packet = compositorMemoryRequest.first;
		compositorMemoryRequest.deq ();
		currentOutput <= tagged Valid packet;
	endrule: grabOutputPacket

	/* Pull memory requests from the MEMQ module as fast as it will provide them. */
	(* fire_when_enabled *)
	rule grabOutputRequest;
		let request <- compositorMemoryRequest.extMemoryRequests.get ();
		currentRequest <= tagged Valid request;
	endrule: grabOutputRequest

	/* Pump input into the MEMQ module as fast as it will accept it. */
	(* fire_when_enabled *)
	rule feedInputPacket;
		compositorMemoryRequest.enq (CompositorMemoryRequestInputPacket {
			controlData: CUControlData {
				layers: replicate (TileCacheEntry {
					isOpaque: False,
					x: 0,
					y: 0,
					allocatedTilesBase: 0,
					width: 3,
					height: 3
				}),
				nextLayer: fromInteger (valueOf (MaxLayers) - 1),
				isFirstLayer: True,
				slicePosition: SlicePosition { xPos: 0, yPos: 0 }
			}
		});
	endrule: feedInputPacket

	Stmt testSeq = seq
		seq
			/* Check that the module outputs every cycle. */
			startTest ("Outputs every cycle");

			/* Check that a packet is outputted every cycle for at least one frame. */
			loopEveryCycleNoSetup (i, 12, assertOutputPacket ());

			finishTest ();
		endseq
	endseq;
	mkAutoFSM (testSeq);
endmodule: mkTestCompositorMemoryRequest

endpackage: TestCompositorMemoryRequest
