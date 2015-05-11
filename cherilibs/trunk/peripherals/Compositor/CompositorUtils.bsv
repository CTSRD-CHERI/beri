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

package CompositorUtils;

import Debug::*;
import Real::*;
import Vector::*;

`include "compositor-parameters.bsv"

/* Derived configuration. */
typedef TDiv#(TMul#(MaxXResolution, MaxYResolution), TMul#(TileSize, TileSize)) TilesPerLayer;
typedef TMul#(TDiv#(MaxXResolution, SliceSize), MaxYResolution) SlicesPerLayer;
typedef TDiv#(MaxXResolution, TileSize) MaxXTiles;
typedef TDiv#(MaxYResolution, TileSize) MaxYTiles;
typedef TDiv#(MemorySize, TMul#(TMul#(TileSize, TileSize), 4)) MaxTiles;
typedef TMul#(TilesPerLayer, MaxLayers) MaxVisibleTiles;
typedef TDiv#(MemorySize, TMul#(SliceSize, 4)) MaxSlices;

/**
 * Fixed-point representation of a single colour component of a pixel. For example, the red value of a single pixel. It's an 8-bit
 * representation mapping [0, 256) to [0.0, 1.0]. The canonical way to think about PixelComponents is as real numbers in the range
 * [0.0, 1.0], where 0.0 represents no contribution from the component, and 1.0 represents a full contribution.
 *
 * PixelComponent implements the following classes:
 *  - Arith: Saturating arithmetic on PixelComponents, with results being clamped to [0.0, 1.0].
 *  - Literal: Construction of PixelComponents from integers in [0, 256).
 *  - RealLiteral: Construction of PixelComponents from reals in [0.0, 1.0].
 *
 * This has to be implemented as a single-member struct so that it's considered a different type from PixelComponentPM.
 */
typedef struct {
	UInt#(8) v;
} PixelComponent deriving (Bits, Eq);

/* Implement saturating fixed point arithmetic for pixel components. */
instance Arith#(PixelComponent);
	/* Addition, clamping to 255. */
	function PixelComponent \+ (PixelComponent x, PixelComponent y);
		return PixelComponent { v: boundedPlus (x.v, y.v) };
	endfunction: \+

	/* Subtraction, clamping to 0. */
	function PixelComponent \- (PixelComponent x, PixelComponent y);
		return PixelComponent { v: boundedMinus (x.v, y.v) };
	endfunction: \-

	/* Multiplication, clamping to 255. Conceptually, this is multiplication of the components in their real form (e.g.
	 * 0.4 * 0.2); so needs to be careful to not multiply by the 255 scaling factor twice.
	 * The DE4 doesn't have a dedicated divider block, so implement division by 255 using the
	 * method given by Blinn, Three Wrongs Make a Right, 1995. */
	function PixelComponent \* (PixelComponent x, PixelComponent y);
		UInt#(17) i = zeroExtend (x.v) * zeroExtend (y.v);
		UInt#(17) r = (i + (i / 256)) / 256;
		return PixelComponent { v: truncate (r) };
	endfunction: \*

	/* Modulus: not supported. */
	function PixelComponent \% (PixelComponent x, PixelComponent y);
		return error ("Modulus of two PixelComponents is not supported.");
	endfunction: \%

	/* Division: not supported. */
	function PixelComponent \/ (PixelComponent x, PixelComponent y);
		return error ("Division of two PixelComponents is not supported.");
	endfunction: \/

	/* Negation: not supported. */
	function PixelComponent negate (PixelComponent x);
		return error ("Negation of PixelComponents is not supported.");
	endfunction: negate
endinstance: Arith

/* Allow PixelComponents to be constructed from integer literals in [0, 255]. */
instance Literal#(PixelComponent);
	/* Construct a PixelComponent from an integer in [0, 256). */
	function PixelComponent fromInteger (Integer i);
		PixelComponent res;
		if (i >= 256)
			res = warning ("Integer " + integerToString (i) + " exceeds bounds for PixelComponent. Clamping to 1.0.", PixelComponent { v: 255 });
		else if (i < 0)
			res = warning ("Integer " + integerToString (i) + " is negative. Clamping to 0.0.", PixelComponent { v: 0 });
		else
			res = PixelComponent { v: fromInteger (i) };

		return res;
	endfunction: fromInteger

	/* Return true iff the given integer is in [0, 256). The pm input is ignored. */
	function Bool inLiteralRange (PixelComponent pm, Integer i);
		return (i >= 0 && i < 256);
	endfunction: inLiteralRange
endinstance: Literal

/* Allow PixelComponents to be constructed from real literals in [0.0, 1.0]. */
instance RealLiteral#(PixelComponent);
	/* Construct a PixelComponent from a real in [0.0, 1.0]. */
	function PixelComponent fromReal (Real x);
		PixelComponent res;
		if (x > 1.0)
			res = warning ("Real " + realToString (x) + " exceeds bounds for PixelComponent. Clamping to 1.0.", PixelComponent { v: 255 });
		else if (x < 0.0)
			res = warning ("Real " + realToString (x) + " is negative. Clamping to 0.0.", PixelComponent { v: 0 });
		else begin
			let xScaled = (x * 255.0);
			res = PixelComponent { v: fromInteger (tpl_1 (splitReal (xScaled))) };
		end

		return res;
	endfunction: fromReal
endinstance: RealLiteral

/* Allow PixelComponents to be formatted for debug output (only). */
instance FShow#(PixelComponent);
	function Fmt fshow (PixelComponent c);
		return $format ("%0d", c);
	endfunction: fshow
endinstance: FShow

/**
 * Convert a pre-multiplied pixel component to a non-pre-multiplied component. This implicitly blends with a black background: i.e.
 * a pre-multiplied component with alpha 0.0 will become the non-pre-multiplied component 0.0.
 */
function PixelComponent pixelComponentPMtoNonPM (PixelComponentPM pm);
	return PixelComponent { v: pm.v };
endfunction: pixelComponentPMtoNonPM

/**
 * Fixed-point representation of a single colour component of a pixel, pre-multiplied by the pixel's alpha component. This is very
 * similar to its non-pre-multiplied counterpart, PixelComponent, and implements the same classes.
 *
 * Storage of the pixel's alpha component is left to higher-level structs (such as RgbaPixel). Note that it doesn't make sense to
 * store an alpha component itself as a PixelComponentPM: alpha components should always be normal PixelComponents.
 *
 * This has to be implemented as a single-member struct so that it's considered a different type from PixelComponent.
 */
typedef struct {
	UInt#(8) v;
} PixelComponentPM deriving (Bits, Eq);

/* Implement saturating fixed point arithmetic for pixel components. */
instance Arith#(PixelComponentPM);
	/* Addition. No saturation logic is needed, since pre-multiplied
	 * components should never overflow (if pre-multiplied correctly). */
	function PixelComponentPM \+ (PixelComponentPM x, PixelComponentPM y);
		return PixelComponentPM { v: x.v + y.v };
	endfunction: \+

	/* Subtraction. No saturation logic is needed, since pre-multiplied
	 * components should never overflow (if pre-multiplied correctly). */
	function PixelComponentPM \- (PixelComponentPM x, PixelComponentPM y);
		return PixelComponentPM { v: x.v - y.v };
	endfunction: \-

	/* Multiplication, clamping to 255. Conceptually, this is multiplication of the components in their real form (e.g.
	 * 0.4 * 0.2); so needs to be careful to not multiply by the 255 scaling factor twice.
	 * The DE4 doesn't have a dedicated divider block, so implement division by 255 using the
	 * method given by Blinn, Three Wrongs Make a Right, 1995. */
	function PixelComponentPM \* (PixelComponentPM x, PixelComponentPM y);
		UInt#(17) i = zeroExtend (x.v) * zeroExtend (y.v) + 128;
		UInt#(17) r = (i + (i / 256)) / 256;
		return PixelComponentPM { v: truncate (r) };
	endfunction: \*

	/* Modulus: not supported. */
	function PixelComponentPM \% (PixelComponentPM x, PixelComponentPM y);
		return error ("Modulus of two PixelComponentPMs is not supported.");
	endfunction: \%

	/* Division: not supported. */
	function PixelComponentPM \/ (PixelComponentPM x, PixelComponentPM y);
		return error ("Division of two PixelComponentPMs is not supported.");
	endfunction: \/

	/* Negation: not supported. */
	function PixelComponentPM negate (PixelComponentPM x);
		return error ("Negation of PixelComponentPMs is not supported.");
	endfunction: negate
endinstance: Arith

/* Allow PixelComponents to be constructed from integer literals in [0, 255]. */
instance Literal#(PixelComponentPM);
	/* Construct a PixelComponentPM from an integer in [0, 256). */
	function PixelComponentPM fromInteger (Integer i);
		return PixelComponentPM { v: fromInteger (i) };
	endfunction: fromInteger

	/* Return true iff the given integer is in [0, 256). The pm input is ignored. */
	function Bool inLiteralRange (PixelComponentPM pm, Integer i);
		return (i >= 0 && i < 256);
	endfunction: inLiteralRange
endinstance: Literal

/* Allow PixelComponents to be constructed from real literals in [0.0, 1.0]. */
instance RealLiteral#(PixelComponentPM);
	/* Construct a PixelComponentPM from a real in [0.0, 1.0]. */
	function PixelComponentPM fromReal (Real x);
		PixelComponentPM res;
		if (x > 1.0)
			res = warning ("Real " + realToString (x) + " exceeds bounds for PixelComponentPM. Clamping to 1.0.", PixelComponentPM { v: 255 });
		else if (x < 0.0)
			res = warning ("Real " + realToString (x) + " is negative. Clamping to 0.0.", PixelComponentPM { v: 0 });
		else begin
			let xScaled = (x * 255.0);
			res = PixelComponentPM { v: fromInteger (tpl_1 (splitReal (xScaled))) };
		end

		return res;
	endfunction: fromReal
endinstance: RealLiteral

/* Allow PixelComponentPMs to be formatted for debug output (only). */
instance FShow#(PixelComponentPM);
	function Fmt fshow (PixelComponentPM c);
		return $format ("%0d*", c);
	endfunction: fshow
endinstance: FShow

/**
 * Convert a non-pre-multiplied pixel component to a pre-multiplied component. This implicitly uses an alpha component of 1.0
 * (fully opaque): i.e. a non-pre-multiplied component with value 0.78 will become the pre-multiplied component 0.78 with an alpha
 * of 1.0.
 */
function PixelComponentPM pixelComponentNonPMtoPM (PixelComponent pix);
	return PixelComponentPM { v: pix.v };
endfunction: pixelComponentNonPMtoPM

/**
 * Representation of a 3-component pixel, with red, green and blue components. No alpha component is present; the pixel implicitly
 * has an alpha component of 1.0.
 *
 * RgbPixel implements the following classes:
 *  - FShow: Debugging representation of RgbPixels as 3-tuples of real numbers in [0.0, 1.0].
 */
typedef struct {
	PixelComponent red;
	PixelComponent green;
	PixelComponent blue;
} RgbPixel deriving (Bits, Eq);

/* Allow RgbPixels to be formatted for debug output (only). */
instance FShow#(RgbPixel);
	function Fmt fshow (RgbPixel pix);
		return $format ("(", fshow (pix.red), ",", fshow (pix.green), ",", fshow (pix.blue), ")");
	endfunction: fshow
endinstance: FShow

/**
 * Representation of a 4-component pixel, with red, green, blue and alpha components. The pixel is stored using pre-multiplied
 * alpha, giving the important invariant that no component's value may exceed that of the alpha component. e.g. A white pixel with
 * alpha component 0.5 will be stored as (0.5, 0.5, 0.5, 0.5). Similarly, a black pixel with alpha component 0.7 will be stored as
 * (0.0, 0.0, 0.0, 0.7).
 *
 * RgbaPixel implements the following classes:
 *  - FShow: Debugging representation of RgbaPixels as 4-tuples of real numbers in [0.0, 1.0]. The pre-multiplied components are
 *           shown with an asterisk (e.g. (0.5*,0.7*,0.1*,0.9)).
 */
typedef struct {
	PixelComponentPM red;
	PixelComponentPM green;
	PixelComponentPM blue;
	PixelComponent alpha;
} RgbaPixel deriving (Bits, Eq);

/* Allow RgbaPixels to be formatted for debug output (only). */
instance FShow#(RgbaPixel);
	function Fmt fshow (RgbaPixel pix);
		return $format ("(", fshow (pix.red), ",", fshow (pix.green), ",", fshow (pix.blue), ",", fshow (pix.alpha), ")");
	endfunction: fshow
endinstance: FShow

/**
 * A linear series of pixels of fixed length, SliceSize (in pixels). Each pixel is stored in RGBA format. Typically SliceSize will be a low power
 * of 2 to allow the screen to be decomposed into a whole number of slices. Slices may not wrap from one line on the screen to the
 * next, and may not overlap.
 */
typedef Vector#(SliceSize, RgbaPixel) RgbaSlice;

/**
 * As RgbaSlice, but the slice as a whole is assumed to be opaque (i.e. each pixel implicitly has an alpha component of 1.0).
 */
typedef Vector#(SliceSize, RgbPixel) RgbSlice;

/**
 * Convert an RGBA pixel to an RGB pixel. This implicitly blends with a black background by dropping the alpha component but
 * keeping other components pre-multiplied. e.g. The RGBA pixel (0.5, 0.1, 0.7, 0.9) becomes (0.5, 0.1, 0.7).
 */
function RgbPixel rgbaToRgb (RgbaPixel pix);
	return RgbPixel {
		red: pixelComponentPMtoNonPM (pix.red),
		green: pixelComponentPMtoNonPM (pix.green),
		blue: pixelComponentPMtoNonPM (pix.blue)
	};
endfunction: rgbaToRgb

/**
 * Convert an RGB pixel to an RGBA pixel. This implicitly uses an alpha component of 1.0 (fully opaque). e.g. The RGB pixel
 * (1.0, 0.5, 0.7) becomes (1.0, 0.5, 0.7, 1.0).
 */
function RgbaPixel rgbToRgba (RgbPixel pix);
	return RgbaPixel {
		red: pixelComponentNonPMtoPM (pix.red),
		green: pixelComponentNonPMtoPM (pix.green),
		blue: pixelComponentNonPMtoPM (pix.blue),
		alpha: 1.0
	};
endfunction: rgbToRgba

/**
 * A complete address for a byte in graphics memory.
 */
typedef Bit#(64) MemoryAddress;

/**
 * Output configuration for the compositor, such as the output resolution (in pixels).
 */
typedef struct {
	UInt#(TLog#(MaxXResolution)) xResolution; /* in pixels */
	UInt#(TLog#(MaxYResolution)) yResolution; /* in pixels */
	/* TODO: Include things like hsync and vsync parameters here? */
} CompositorConfiguration deriving (Bits, Eq);

/* Allow CompositorConfigurations to be formatted for debug output (only). */
instance FShow#(CompositorConfiguration);
	function Fmt fshow (CompositorConfiguration conf);
		return $format ("CompositorConfiguration { xResolution: %0d, yResolution: %0d }",
		                conf.xResolution, conf.yResolution);
	endfunction: fshow
endinstance: FShow

/**
 * Identifier for a client frame buffer (CFB). The unit of addressing is tiles; each CFB must be at least one tile in size.
 */
typedef Bit#(TLog#(MaxTiles)) ClientFrameBufferId;

/**
 * Address of a slice in memory, in slices (32 byte aligned), relative to the start of the compositor's data region in memory.
 * i.e. The first slice has address 0 (which is byte 0), the second slice has address 1 (which is byte 32), etc.
 */
typedef Bit#(TLog#(MaxSlices)) SliceAddress;

/**
 * Position of a slice relative to the entire screen, given in units of slices. For example, the first slice has X coordinate 0, the second has X
 * coordinate 1, etc. Coordinates start at (0, 0) in the top-left corner of the screen, and increase left-to-right, top-to-bottom.
 *
 * n: number of pixels in each slice being composited
 */
typedef struct {
	UInt#(TLog#(TDiv#(MaxXResolution, SliceSize))) xPos;
	UInt#(TLog#(MaxYResolution)) yPos;
} SlicePosition deriving (Bits, Eq);

/* Allow SlicePositions to be formatted for debug output (only). */
instance FShow#(SlicePosition);
	function Fmt fshow (SlicePosition pos);
		return $format ("SlicePosition { xPos: %0d, yPos: %0d }", pos.xPos, pos.yPos);
	endfunction: fshow
endinstance: FShow

/**
 * Rectangular region of an image containing a whole number of slices. It's
 * described in terms of its top-left and bottom-right corners. The bottom-right
 * corner must be greater than or equal to the top-left in both dimensions; if
 * the two corners are equal, the region is a single slice (i.e. the region is
 * inclusive of the row and column of slices with coordinates shared with the
 * bottom-right corner).
 *
 * All coordinates are given in slices from the top-left of the screen.
 */
typedef struct {
	SlicePosition topLeftPos;
	SlicePosition bottomRightPos;
} SliceRegion deriving (Bits);

/* Allow SliceRegions to be formatted for debug output (only). */
instance FShow#(SliceRegion);
	function Fmt fshow (SliceRegion region);
		return $format ("SliceRegion { (%0d, %0d) to (%0d, %0d) }",
		                region.topLeftPos.xPos, region.topLeftPos.yPos,
		                region.bottomRightPos.xPos, region.bottomRightPos.yPos);
	endfunction: fshow
endinstance: FShow

/**
 * Address of a TileCacheEntry in one of the CompositorController's tile caches. The unit of addressing is a TileCacheEntry; so the first entry has
 * address 0, the second has address 1, etc.
 */
typedef Bit#(TLog#(TilesPerLayer)) TileCacheEntryAddress;

/**
 * Cached data about the client frame buffer (CFB) which is projected on a given layer for this output tile. This effectively allows caching of the
 * Z-ordering of CFBs. TileCacheEntrys are stored in per-layer BRAM caches inside the CompositorController, and updated when CFB metadata is updated.
 */
typedef struct {
	Bool isOpaque; /* cached value specifying whether the entire tile is opaque (i.e. all alpha components are 1.0) */
	/* Cached from ClientFrameBuffer. */
	UInt#(TLog#(MaxXResolution)) x; /* offset of the top-left corner of the CFB from the top-left of the screen, in pixels */
	UInt#(TLog#(MaxYResolution)) y;
	UInt#(TLog#(MaxTiles)) allocatedTilesBase; /* address of the first tile of the CFB in memory, in tiles */
	UInt#(TLog#(TDiv#(MaxXResolution, TileSize))) width; /* width of the CFB in terms of tiles */
	UInt#(TLog#(TDiv#(MaxYResolution, TileSize))) height; /* height of the CFB in terms of tiles */
} TileCacheEntry deriving (Bits);

/* Allow TileCacheEntrys to be formatted for debug output (only). */
instance FShow#(TileCacheEntry);
	function Fmt fshow (TileCacheEntry op);
		return $format ("TileCacheEntry { isOpaque: %b, x: %0d, y: %0d, allocatedTilesBase: 0x%h, width: %0d, height: %0d }",
		                op.isOpaque, op.x, op.y, op.allocatedTilesBase, op.width, op.height);
	endfunction: fshow
endinstance: FShow

/**
 * Pixel source for a combination operation in CompositorMemoryResponse. This
 * specifies where one half of the pixel data for the output slice from the
 * CompositorMemoryResponse stage should come from.
 *
 *   SOURCE_MEMORY: The data returned from memory.
 *   SOURCE_TRANSPARENT: A fully transparent slice.
 *   SOURCE_PREVIOUS: The data returned from memory for the previous slice.
 */
typedef enum {
	SOURCE_MEMORY,
	SOURCE_TRANSPARENT,
	SOURCE_PREVIOUS
} CompositorPixelSource deriving (Bits, Eq);

/**
 * Control data passed from the CompositorTceResponse to the
 * CompositorMemoryRequest stage of the pipeline.
 */
typedef struct {
	/* Cache of the TileCacheEntrys for all layers of the current output tile. Index 0 is the top-most layer. */
	Vector#(MaxLayers, TileCacheEntry) layers;
	UInt#(TLog#(MaxLayers)) nextLayer; /* index of the next layer to be composited when building this output slice */
	Bool isFirstLayer; /* if this is true, this is the first layer of this output slice being composited */
	SlicePosition slicePosition; /* position of the slice to composite, relative to the screen, in units of slices */
} CUControlData deriving (Bits);

/* Allow CUControlData to be formatted for debug output (only). */
instance FShow#(CUControlData);
	function Fmt fshow (CUControlData op);
		return $format ("CUControlData { layers: (omitted), nextLayer: %0d, isFirstLayer: %b, slicePosition: ", op.nextLayer, op.isFirstLayer,
		                fshow (op.slicePosition), " }");
	endfunction: fshow
endinstance: FShow

/**
 * Memory request from the compositor to graphics memory. Such a request is
 * always a read, and is always slice-aligned (256-bit aligned).
 *
 * burstLength: The number of consecutive slices to return. Must always be 1 or
 *              greater.
 * sliceAddr: Address of the slice to load, using 256-bit slices as the unit of
 *            addressing, relative to the base of compositor memory.
 */
typedef struct {
	UInt#(4) burstLength;
	SliceAddress sliceAddr;
} CompositorMemoryRequest deriving (Bits);

/* Allow CompositorMemoryRequests to be formatted for debug output (only). */
instance FShow#(CompositorMemoryRequest);
	function Fmt fshow (CompositorMemoryRequest req);
		return $format ("CompositorMemoryRequest { sliceAddr: %0h, burstLength: %0d }", req.sliceAddr, req.burstLength);
	endfunction: fshow
endinstance: FShow

/**
 * Single pixel output from the compositor, ready to be displayed on the
 * monitor.
 *
 * This is intended to map directly to PacketDataT#(RgbPixel).
 *
 * pixel: RGB pixel, using 8 bits per channel.
 * isStartOfFrame: True iff this pixel is the first pixel of a new frame (i.e.
 *                 the top-left pixel).
 * isEndOfFrame: True iff this pixel is the last pixel of a frame (i.e the
 *               bottom-right pixel).
 */
typedef struct {
	RgbPixel pixel;
	Bool isStartOfFrame;
	Bool isEndOfFrame;
} CompositorOutputPacket deriving (Bits, Eq);

/* Allow CompositorOutputPackets to be formatted for debug output (only). */
instance FShow#(CompositorOutputPacket);
	function Fmt fshow (CompositorOutputPacket p);
		return $format ("CompositorOutputPacket { d: ", fshow (p.pixel), ", sop: %b, eop: %b }", p.isStartOfFrame, p.isEndOfFrame);
	endfunction: fshow
endinstance: FShow

/**
 * Print a debug message from a compositor controller instance (if debug messages are enabled).
 *
 * a: action to print the message, fired if debugging is enabled
 */
function Action debugController (Action a);
	action
		debug2 ("compositor-controller", a);
	endaction
endfunction: debugController

/**
 * Print a debug message from the compositor (if debug messages are enabled).
 *
 * a: action to print the message, fired if debugging is enabled
 */
function Action debugCompositor (Action a);
	action
		debug2 ("compositor-compositor", a);
	endaction
endfunction: debugCompositor

/**
 * Print a debug message from a compositor unit instance (if debug messages are enabled).
 *
 * a: action to print the message, fired if debugging is enabled
 */
function Action debugUnit (Action a);
	action
		debug2 ("compositor-unit", a);
	endaction
endfunction: debugUnit

/**
 * Print a debug message from a unit test (if debug messages are enabled).
 *
 * a: action to print the message, fired if debugging is enabled
 */
function Action debugTest (Action a);
	action
		debug2 ("tests", a);
	endaction
endfunction: debugTest

endpackage: CompositorUtils
