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

package TestCompositorTceRequest;

import BRAM::*;
import CompositorTceRequest::*;
import CompositorUtils::*;
import GetPut::*;
import StmtFSM::*;
import TestUtils::*;
import Vector::*;

(* synthesize *)
module mkTestCompositorTceRequest ();
	/* Tile cache store. */
	BRAM_Configure tileCacheCfg = defaultValue;
	/* Index 0 is the highest layer. */
	Vector#(MaxLayers, BRAM2Port#(TileCacheEntryAddress, TileCacheEntry)) tileCaches <- replicateM (mkBRAM2Server (tileCacheCfg));

	/* Functions for use with map() to extract request/response interfaces from port A of a BRAM. */
	function Put#(BRAMRequest#(a, b)) bramPortARequest (BRAM2Port#(a, b) bram);
		return bram.portA.request;
	endfunction: bramPortARequest

	function Get#(b) bramPortAResponse (BRAM2Port#(a, b) bram);
		return bram.portA.response;
	endfunction: bramPortAResponse

	CompositorTceRequestIfc compositorTceRequest <- mkCompositorTceRequest (map (bramPortARequest, tileCaches));

	Wire#(Maybe#(CompositorTceRequestOutputPacket)) currentOutput <- mkDWire (tagged Invalid);

	/* Temporary registers for loops. */
	Reg#(UInt#(32)) i <- mkReg (0);

	/* Assert that a valid packet was outputted this cycle. */
	function assertOutputPacket ();
		action
			if (!isValid (currentOutput)) begin
				let theTime <- $time;
				failTest ($format ("%05t: expected packet", theTime));
			end else begin
				$display ("%05t: clock", $time);
			end
		endaction
	endfunction: assertOutputPacket

	/* Pull output from the TCEQ module as fast as it will provide it. */
	(* fire_when_enabled *)
	rule grabOutputPacket;
		let packet = compositorTceRequest.first;
		compositorTceRequest.deq ();
		currentOutput <= tagged Valid packet;
	endrule: grabOutputPacket

	/* Pull responses out of the BRAMs (and discard them). */
	(* fire_when_enabled *)
	rule grabBramResponses;
		for (Integer i = 0; i < valueOf (MaxLayers); i = i + 1) begin
			let ignore <- tileCaches[i].portA.response.get ();
		end
	endrule: grabBramResponses

	/* Pump input into the TCEQ module as fast as it will accept it. */
	(* fire_when_enabled *)
	rule feedInputPacket;
		compositorTceRequest.enq (CompositorTceRequestInputPacket {
			drawRegion: SliceRegion {
				topLeftPos: SlicePosition { xPos: 0, yPos: 0 },
				bottomRightPos: SlicePosition { xPos: 3, yPos: 1 }
			}
		});
	endrule: feedInputPacket

	Stmt testSeq = seq
		seq
			/* Check that the module outputs every cycle. */
			startTest ("Outputs every cycle");

			/* Check that a packet is outputted every cycle for at least one frame. */
			loopEveryCycleNoSetup (i, 8, assertOutputPacket ());
			i <= 0; /* give a cycle's delay for the start of the new frame */
			loopEveryCycleNoSetup (i, 4, assertOutputPacket ());

			finishTest ();
		endseq
	endseq;
	mkAutoFSM (testSeq);
endmodule: mkTestCompositorTceRequest

endpackage: TestCompositorTceRequest
