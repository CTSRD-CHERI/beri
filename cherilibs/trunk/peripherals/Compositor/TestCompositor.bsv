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

package TestCompositor;

import Avalon2ClientServer::*;
import AvalonBurstMaster::*;
import AvalonStreaming::*;
import ClientServer::*;
import Compositor::*;
import CompositorUtils::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import SpecialFIFOs::*;
import StmtFSM::*;
import TestUtils::*;
import Vector::*;

(* synthesize *)
module mkTestCompositor ();
	/* A normal compositor. */
	CompositorIfc compositor <- mkCompositor ();

	/* The pixels most recently outputted by the compositor. We expect this to be at worst 8 times faster than the memory requests. */
	FIFO#(CompositorOutputPacket) outputtedPixels <- mkBypassFIFO ();

	/* Responses to expected memory requests. This must be unguarded to avoid stalling handling memory requests on it. */
	FIFOF#(Tuple2#(SliceAddress, RgbaSlice)) expectedMemoryRequests <- mkUGSizedFIFOF (1000 /* manually selected to match the tests below */);

	/* Avalon bus master reply logic. */
	Reg#(Bit#(8)) masterAddrBits <- mkReg (0);
	Reg#(UInt#(4)) masterBurstCount <- mkReg (0);
	FIFO#(RgbaSlice) memoryResponses <- mkFIFO ();

	/* Temporary registers for loops. */
	Reg#(UInt#(32)) i <- mkRegU ();
	Reg#(UInt#(32)) j <- mkRegU ();
	Reg#(UInt#(32)) k <- mkRegU ();
	Reg#(UInt#(32)) l <- mkRegU ();
	Reg#(File) fh <- mkRegU ();

	(* fire_when_enabled *)
	rule printOutputPixels;
		let packet <- compositor.pixelsOut.get ();
		outputtedPixels.enq (packet);

		debugTest ($display ("%05t: > PIX: data = %0h, isStartOfFrame = %b, isEndOfFrame = %b", $time, packet.pixel, packet.isStartOfFrame, packet.isEndOfFrame));
	endrule: printOutputPixels

	(* fire_when_enabled *)
	rule handleAvalonRequest;
		let actualRequest <- compositor.extMemory.request.get ();

		Bit#(8) addrBits = pack (truncate (actualRequest.sliceAddr >> 5)) << 6;
		UInt#(4) bc = actualRequest.burstLength;

		/* Check if the memory request was expected. */
		if (!expectedMemoryRequests.notEmpty) begin
			failTest ($format ("did not expect memory request ", fshow (actualRequest)));
		end else begin
			let expectedRequestResponse = expectedMemoryRequests.first;
			let expectedAddress = tpl_1 (expectedRequestResponse);
			let expectedResponse = tpl_2 (expectedRequestResponse);
			expectedMemoryRequests.deq ();
			let expectedRequest = CompositorMemoryRequest { burstLength: 1, sliceAddr: expectedAddress };

			/* Check if the memory request is what was expected. We can't just compare the MemAccessPacketTs, since the data may not match (for
			 * reads this doesn't matter). */
			if (actualRequest.burstLength != expectedRequest.burstLength || actualRequest.sliceAddr != expectedRequest.sliceAddr) begin
				failTest ($format ("expected memory request ", fshow (expectedRequest), ", got ", fshow (actualRequest)));
			end else begin
				/* Success! The request was expected. */
				masterBurstCount <= bc;
				masterAddrBits <= addrBits;
				memoryResponses.enq (expectedResponse);

				debugTest ($display ("%05t: > MEM: address: 0x%0h", $time, actualRequest.sliceAddr));
			end
		end
	endrule: handleAvalonRequest

	(* fire_when_enabled *)
	rule generateAvalonResponse (masterBurstCount > 0);
		if (masterBurstCount > 0) begin
			RgbaSlice returnedData = memoryResponses.first;
			memoryResponses.deq ();
			compositor.extMemory.response.put (returnedData);

			masterAddrBits <= masterAddrBits + 8;
			masterBurstCount <= masterBurstCount - 1;

			debugTest ($display ("%05t: < MEM: data: %0h", $time, returnedData));
		end
	endrule: generateAvalonResponse

	function assertNextOutputPixelEquals (expectedPacket);
		return action
			let actualPacket = outputtedPixels.first;
			outputtedPixels.deq ();

			assertEqual (actualPacket, expectedPacket);
		endaction;
	endfunction: assertNextOutputPixelEquals

	/* Wait (at most 100 cycles) for an output frame to start, discarding all intervenining black output pixels. */
	function Stmt waitForFrameStart ();
		return seq
			i <= 0;
			while (i < 100 && /* cycle limit */
			       outputtedPixels.first == CompositorOutputPacket { pixel: RgbPixel { red: 0, green: 0, blue: 0 }, isStartOfFrame: False, isEndOfFrame: False }) seq
				outputtedPixels.deq ();
				i <= i + 1;
			endseq
		endseq;
	endfunction: waitForFrameStart

	function Stmt resetCompositor (xResolution, yResolution);
		return seq
			compositor.configuration <= CompositorConfiguration { xResolution: xResolution, yResolution: yResolution };
			if (xResolution != 0 && yResolution != 0) seq
				delay (1); /* wait for the compositor to schedule the first frame to be drawn */
				compositor.pauseCompositing (); /* prevent further frames from being drawn */
			endseq
		endseq;
	endfunction: resetCompositor

	/* Reset the expected memory requests and output pixels FIFOs. Disable the compositor. */
	function Stmt resetHarness ();
		return seq
			resetCompositor (0, 0);
			outputtedPixels.clear ();
			expectedMemoryRequests.clear ();
		endseq;
	endfunction: resetHarness

	/* Layer 0 is the top-most layer. */
	function Action updateTileCacheEntry (layer, address, entry);
		return action
			compositor.updateTileCacheEntry (layer, address, entry);
		endaction;
	endfunction: updateTileCacheEntry

	/* Note: The unit of addressing is a 32-byte word, not a single byte. Handily, a 32-byte word is exactly one slice. */
	function Action expectMemoryRequest (UInt#(32) address, Vector#(8, RgbaPixel) response);
		return action
			expectedMemoryRequests.enq (tuple2 (pack (truncate (address)), unpack (pack (response))));
		endaction;
	endfunction: expectMemoryRequest

	function Action assertNoMemoryRequestsRemaining ();
		return action
			if (expectedMemoryRequests.notEmpty)
				failTest ($format ("expected memory request ", fshow (expectedMemoryRequests.first)));
		endaction;
	endfunction: assertNoMemoryRequestsRemaining

	/* Output a single frame in PPM format: http://en.wikipedia.org/wiki/Portable_Gray_Map. */
	function Stmt saveFrame (filename, xResolution, yResolution);
		return seq
			action
				let fhd <- $fopen (filename, "wb");
				fh <= fhd;
			endaction

			/* PPM header. */
			$fwrite (fh, "P3\n");
			$fwrite (fh, "%0d %0d\n", xResolution, yResolution);
			$fwrite (fh, "255\n");

			if (fh == InvalidFile) seq
				failTest ($format ("couldn't open output file '%s'", filename));
			endseq else seq
				/* Check we're at the start of a frame. */
				if (!outputtedPixels.first.isStartOfFrame)
					failTest ($format ("not at the start of a frame: ", fshow (outputtedPixels.first)));

				i <= 0; /* horizontal position counter */

				for (j <= 0; j < xResolution * yResolution; j <= j + 1) seq
					action
						/* End of a row? */
						if (i == xResolution) begin
							$fwrite (fh, "\n");
							i <= 1;
						end else begin
							i <= i + 1;
						end

						let pix = outputtedPixels.first.pixel;
						outputtedPixels.deq ();
						$fwrite (fh, "%0d %0d %0d  ", pix.red, pix.green, pix.blue);
					endaction
				endseq

				/* Check we outputted the right number of pixels (assume the next frame starts immediately after the current one). */
				if (!outputtedPixels.first.isStartOfFrame)
					failTest ($format ("not reached the end of the frame: ", fshow (outputtedPixels.first)));
			endseq

			$fclose (fh);
		endseq;
	endfunction: saveFrame

	/* Build the base address of tiles in a CFB, given the CFB's layer and size (number of tiles forming the entire CFB).
	 * The address is returned in tiles. */
	function UInt#(TLog#(MaxTiles)) buildTilesBaseAddress (layer, cfbSize);
		return truncate (layer * cfbSize);
	endfunction: buildTilesBaseAddress

	Stmt testSeq = seq
		/* Check that an uninitialised compositor outputs only black pixels, with isStartOfFrame == isEndOfFrame == True. */
		seq
			startTest ("Uninitialised compositor outputs black");

			/* Check for an arbitrary number of pixels. */
			loopEveryCycle (i, 10,
				assertNextOutputPixelEquals (CompositorOutputPacket { pixel: RgbPixel { red: 0, green: 0, blue: 0 }, isStartOfFrame: False, isEndOfFrame: False }));

			finishTest ();
		endseq


		/* Check that a compositor initialised to 0-resolution outputs only black pixels. */
		seq
			startTest ("0-initialised compositor outputs black");
			resetCompositor (0, 0);

			/* Check for an arbitrary number of pixels. */
			loopEveryCycle (i, 10,
				assertNextOutputPixelEquals (CompositorOutputPacket { pixel: RgbPixel { red: 0, green: 0, blue: 0 }, isStartOfFrame: False, isEndOfFrame: False }));

			finishTest ();
		endseq


		/* Check that rendering a single tile (resolution: 32 by 32 pixels) is correct. */
		seq
			startTest ("Single tile rendering");

			/* Update the tile cache. */
			for (i <= 0; i < 7; i <= i + 1)
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 0,
				                      TileCacheEntry { isOpaque: True, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 1),
				                                       width: 1, height: 1 });

			/* Set up the expected memory requests. These should be all the slices for one tile only. */
			for (i <= 0; i < 32 * 32 / 8; i <= i + 1) /* slices */
				expectMemoryRequest (truncate (i), replicate (RgbaPixel { red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0 }));

			/* Go! */
			resetCompositor (32, 32);

			/* Verify the whole frame. */
			waitForFrameStart ();

			loopEveryCycle2D (i, 32, j, 32,
				assertNextOutputPixelEquals (CompositorOutputPacket {
					pixel: RgbPixel { red: 1.0, green: 0.3, blue: 0.5 },
					isStartOfFrame: (i == 0 && j == 0),
					isEndOfFrame: (i == 31 && j == 31)
				}));

			finishTest ();
			resetHarness ();
		endseq


		/* Check that rendering part of a single tile (resolution: 17 by 5 pixels) is correct. */
		seq
			startTest ("Partial single tile rendering");

			/* Update the tile cache. */
			for (i <= 0; i < 7; i <= i + 1)
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 0,
				                      TileCacheEntry { isOpaque: True, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 1),
				                                       width: 1, height: 1 });

			/* Set up the expected memory requests. These should be three out of four slices for each of the first five rows of one tile
			 * only. */
			for (i <= 0; i < 5; i <= i + 1) seq /* rows */
				expectMemoryRequest (truncate (i) * 4,
				                     replicate (RgbaPixel { red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0 }));
				expectMemoryRequest (truncate (i) * 4 + 1,
				                     replicate (RgbaPixel { red: 0.0, green: 0.3, blue: 0.5, alpha: 1.0 }));
				expectMemoryRequest (truncate (i) * 4 + 2,
				                     replicate (RgbaPixel { red: 1.0, green: 0.0, blue: 0.2, alpha: 1.0 }));
			endseq

			/* Go! */
			resetCompositor (17, 5);

			/* Verify the whole frame. */
			waitForFrameStart ();

			loopEveryCycle2D (i, 17, j, 5,
				assertNextOutputPixelEquals (CompositorOutputPacket {
					pixel:
						(i < 8) ? RgbPixel { red: 1.0, green: 0.3, blue: 0.5 } : /* left-most slice */
						(i < 16) ? RgbPixel { red: 0.0, green: 0.3, blue: 0.5 } : /* middle slice */
						RgbPixel { red: 1.0, green: 0.0, blue: 0.2 }, /* right-most slice */
					isStartOfFrame: (i == 0 && j == 0),
					isEndOfFrame: (i == 16 && j == 4)
				}));

			finishTest ();
			resetHarness ();
		endseq


		/* Check that rendering multiple tiles (resolution: 64 by 32 pixels) is correct, with the tiles coming from different CFBs. */
		seq
			startTest ("Multiple tile rendering from different CFBs");

			/* Update the tile cache. */
			for (i <= 0; i < 7; i <= i + 1) seq
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 0,
				                      TileCacheEntry { isOpaque: True, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 1),
				                                       width: 1, height: 1 /* first CFB */ });
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 1,
				                      TileCacheEntry { isOpaque: True, x: 32, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i + 7, 1),
				                                       width: 1, height: 1 /* second CFB */ });
			endseq

			/* Set up the expected memory requests. These should be all the slices for the top layers of both tiles, interleaved by row. */
			for (j <= 0; j < 32; j <= j + 1) seq /* rows */
				/* First tile. */
				for (i <= 0; i < 32 / 8; i <= i + 1) /* slices */
					expectMemoryRequest (truncate (i) + truncate (j) * 4,
					                     replicate (RgbaPixel { red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0 }));

				/* Second tile. */
				for (i <= 0; i < 32 / 8; i <= i + 1) /* slices */
					expectMemoryRequest (truncate (i) + truncate (j) * 4 + 7 * fromInteger (valueOf (TileSize) * valueOf (TileSize)) / 8,
					                     replicate (RgbaPixel { red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0 }));
			endseq

			/* Go! */
			resetCompositor (64, 32);

			/* Verify the whole frame. */
			waitForFrameStart ();

			loopEveryCycle2D (i, 64, j, 32,
				assertNextOutputPixelEquals (CompositorOutputPacket {
					pixel:
						(i < 32) ? RgbPixel { red: 1.0, green: 0.0, blue: 0.0 } : /* left tile */
						RgbPixel { red: 0.0, green: 0.0, blue: 1.0 }, /* right tile */
					isStartOfFrame: (i == 0 && j == 0),
					isEndOfFrame: (i == 63 && j == 31)
				}));

			finishTest ();
			resetHarness ();
		endseq


		/* Check that rendering multiple tiles (resolution: 61 by 33 pixels) is correct, with the tiles coming from the same CFB. */
		seq
			startTest ("Multiple tile rendering from the same CFB");

			/* Update the tile cache. */
			for (i <= 0; i < 7; i <= i + 1) seq
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 0,
				                      TileCacheEntry { isOpaque: True, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 4),
				                                       width: 2, height: 2 });
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 1,
				                      TileCacheEntry { isOpaque: True, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 4),
				                                       width: 2, height: 2 });
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 80,
				                      TileCacheEntry { isOpaque: True, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 4),
				                                       width: 2, height: 2 });
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 81,
				                      TileCacheEntry { isOpaque: True, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 4),
				                                       width: 2, height: 2 });
			endseq

			/* Set up the expected memory requests. These should be all the slices for the top layers of all four tiles, interleaved by
			 * row. */
			for (j <= 0; j < 33; j <= j + 1) seq /* rows */
				/* First tile. */
				if (j < 32)
					for (i <= 0; i < 32 / 8; i <= i + 1) /* slices */
						expectMemoryRequest (truncate (i) + truncate (j) * 4,
						                     replicate (RgbaPixel { red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0 }));
				/* Third tile. */
				else
					for (i <= 0; i < 32 / 8; i <= i + 1) /* slices */
						expectMemoryRequest (truncate (i) + truncate (j - 32) * 4 + 2 * fromInteger (valueOf (TileSize) * valueOf (TileSize)) / 8,
						                     replicate (RgbaPixel { red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0 }));

				/* Second tile. */
				if (j < 32)
					for (i <= 0; i < 32 / 8; i <= i + 1) /* slices */
						expectMemoryRequest (truncate (i) + truncate (j) * 4 + 1 * fromInteger (valueOf (TileSize) * valueOf (TileSize)) / 8,
						                     replicate (RgbaPixel { red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0 }));
				/* Fourth tile. */
				else
					for (i <= 0; i < 32 / 8; i <= i + 1) /* slices */
						expectMemoryRequest (truncate (i) + truncate (j - 32) * 4 + 3 * fromInteger (valueOf (TileSize) * valueOf (TileSize)) / 8,
						                     replicate (RgbaPixel { red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0 }));
			endseq

			/* Go! */
			resetCompositor (61, 33);

			/* Verify the whole frame. */
			waitForFrameStart ();

			loopEveryCycle2D (i, 61, j, 33,
				assertNextOutputPixelEquals (CompositorOutputPacket {
					pixel:
						(i < 32 && j < 32) ? RgbPixel { red: 1.0, green: 0.0, blue: 0.0 } : /* top-left tile */
						(i >= 32 && j < 32) ? RgbPixel { red: 0.0, green: 0.0, blue: 1.0 } : /* top-right tile */
						(i < 32 && j >= 32) ? RgbPixel { red: 0.0, green: 1.0, blue: 0.0 } : /* bottom-left tile */
						RgbPixel { red: 1.0, green: 0.0, blue: 1.0 }, /* bottom-right tile */
					isStartOfFrame: (i == 0 && j == 0),
					isEndOfFrame: (i == 60 && j == 32)
				}));

			finishTest ();
			resetHarness ();
		endseq


		/* Check that rendering a single transparent tile onto the background colour works. */
		seq
			startTest ("Single transparent tile rendering");

			/* Update the tile cache. */
			for (i <= 0; i < 7; i <= i + 1)
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 0,
				                      TileCacheEntry { isOpaque: False, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 1),
				                                       width: 1, height: 1 });

			/* Set up the expected memory requests. These should be all the slices for all layers of one output tile only, interleaved by
			 * layer then by slice. */
			for (j <= 0; j < 32; j <= j + 1) /* rows */
				for (i <= 0; i < 32 / 8; i <= i + 1) /* slices */
					for (l <= 6; l < 7; l <= l - 1) /* layers */
						expectMemoryRequest (truncate (i) +
						                     truncate (j) * fromInteger (valueOf (TileSize)) / 8 +
						                     truncate (l) * fromInteger (valueOf (TileSize) * valueOf (TileSize)) / 8,
						                     replicate (RgbaPixel { red: 0.0, green: 0.1, blue: 0.1, alpha: 0.1 }));

			/* Go! */
			compositor.backgroundColour.put (RgbPixel { red: 0.5, green: 0.5, blue: 0.0 });
			resetCompositor (32, 32);

			/* Verify the whole frame. */
			waitForFrameStart ();

			loopEveryCycle2D (i, 32, j, 32,
				assertNextOutputPixelEquals (CompositorOutputPacket {
					pixel: RgbPixel { red: 0.244, green: 0.757, blue: 0.514 },
					isStartOfFrame: (i == 0 && j == 0),
					isEndOfFrame: (i == 31 && j == 31)
				}));

			finishTest ();
			resetHarness ();
		endseq


		/* Check that rendering a single tile then resetting the resolution to 0 causes a single-pixel black frame to be outputted. */
		seq
			startTest ("0-reset compositor outputs black");

			/* Update the tile cache. */
			for (i <= 0; i < 7; i <= i + 1)
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 0,
				                      TileCacheEntry { isOpaque: True, x: 0, y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 1),
				                                       width: 1, height: 1 });

			/* Set up the expected memory requests. These should be all the slices for one tile only. */
			for (i <= 0; i < 32 * 32 / 8; i <= i + 1) /* slices */
				expectMemoryRequest (truncate (i), replicate (RgbaPixel { red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0 }));

			/* Go! */
			resetCompositor (32, 32);

			/* Verify the whole frame. */
			waitForFrameStart ();

			loopEveryCycle2D (i, 32, j, 32,
				assertNextOutputPixelEquals (CompositorOutputPacket {
					pixel: RgbPixel { red: 1.0, green: 0.3, blue: 0.5 },
					isStartOfFrame: (i == 0 && j == 0),
					isEndOfFrame: (i == 31 && j == 31)
				}));

			/* Set the resolution to 0 and forget any pixels outputted from the next frame (before we set the resolution). */
			compositor.configuration <= CompositorConfiguration { xResolution: 0, yResolution: 0 };
			outputtedPixels.clear ();

			/* Verify that black pixels are outputted. */
			for (i <= 0; i < 10; i <= i + 1) /* arbitrary */
				assertNextOutputPixelEquals (CompositorOutputPacket { pixel: RgbPixel { red: 0, green: 0, blue: 0 }, isStartOfFrame: False, isEndOfFrame: False });

			finishTest ();
			resetHarness ();
		endseq


		/* Check that rendering a single tile (resolution: 32 by 32 pixels) at a non-tile-size offset is correct. */
		seq
			startTest ("Single tile rendering at non-tile offset");

			/* Update the tile cache. The top layer is the offset tile. Lower layers are a background fill. */
			for (i <= 0; i < 7; i <= i + 1) seq
				l <= (i == 0) ? 10 : 0; /* offset */

				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 0,
				                      TileCacheEntry { isOpaque: True, x: truncate (l), y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 1),
				                                       width: (i == 0) ? 1 : 2, height: 1 });
				updateTileCacheEntry (/* layer */ truncate (i), /* tile */ 1,
				                      TileCacheEntry { isOpaque: True, x: truncate (l), y: 0,
				                                       allocatedTilesBase: buildTilesBaseAddress (i, 1),
				                                       width: (i == 0) ? 1 : 2, height: 1 });
			endseq

			/* Set up the expected memory requests. These should be all the slices for one tile only. */
			for (j <= 0; j < 3; j <= j + 1) seq /* rows */
				/* We expect requests in the following order (1 is first; columns correspond to slices; rows correspond to layers, top first):
				 *     3 4 5 6 *
				 *   1 2       7 8 9
				 *   _ _ _ _ _ _ _ _
				 *
				 * Expect two requests from the second layer first, to handle the gap caused by the offset of the first layer. */
				expectMemoryRequest (truncate (fromInteger (valueOf (TileSize) * valueOf (TileSize) / 8) + j * 32 / 8),
				                     replicate (RgbaPixel { red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0 }));
				expectMemoryRequest (truncate (fromInteger (valueOf (TileSize) * valueOf (TileSize) / 8) + j * 32 / 8 + 1),
				                     replicate (RgbaPixel { red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0 }));

				/* Now expect memory requests from the first layer. */
				expectMemoryRequest (truncate (j * 32 / 8),
				                     replicate (RgbaPixel { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }));
				expectMemoryRequest (truncate (j * 32 / 8 + 1),
				                     replicate (RgbaPixel { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }));
				expectMemoryRequest (truncate (j * 32 / 8 + 2),
				                     replicate (RgbaPixel { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }));
				expectMemoryRequest (truncate (j * 32 / 8 + 3),
				                     replicate (RgbaPixel { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }));

				/* Three requests from the second layer for the right-hand gap. */
				expectMemoryRequest (truncate (fromInteger (valueOf (TileSize) * valueOf (TileSize) / 8 * 2) + j * 32 / 8 + 1),
				                     replicate (RgbaPixel { red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0 }));
				expectMemoryRequest (truncate (fromInteger (valueOf (TileSize) * valueOf (TileSize) / 8 * 2) + j * 32 / 8 + 2),
				                     replicate (RgbaPixel { red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0 }));
				expectMemoryRequest (truncate (fromInteger (valueOf (TileSize) * valueOf (TileSize) / 8 * 2) + j * 32 / 8 + 3),
				                     replicate (RgbaPixel { red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0 }));
			endseq

			/* Go! */
			resetCompositor (64, 3);

			/* Verify the whole frame. */
			waitForFrameStart ();

			loopEveryCycle2D (i, 64, j, 3,
				assertNextOutputPixelEquals (CompositorOutputPacket {
					pixel:
						(i < 10 || i >= 42) ? RgbPixel { red: 1.0, green: 0.3, blue: 0.5 } :
						                      RgbPixel { red: 1.0, green: 1.0, blue: 1.0 },
					isStartOfFrame: (j == 0 && i == 0),
					isEndOfFrame: (j == 2 && i == 63)
				}));

			finishTest ();
			resetHarness ();
		endseq
	endseq;
	mkAutoFSM (testSeq);
endmodule: mkTestCompositor

endpackage: TestCompositor
