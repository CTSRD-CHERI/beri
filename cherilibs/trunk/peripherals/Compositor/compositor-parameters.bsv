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

/**
 * Main configuration. These parameters should be changeable without causing
 * problems in simulation, but may cause synthesis to fail (e.g. by using too
 * much area or no longer meeting timing. The current values have been chosen
 * partly as the design objectives, and partly as the maximum attainable under
 * the expected clock speed (200MHz).
 */

/**
 * Maximum number of layers of CFBs which may be rendered on a single output
 * tile. Any layers below the top MaxLayers (in the Z ordering) will not be
 * rendered, being replaced by the background colour. In practice, this means
 * that no more than 7 non-opaque CFBs can ever be composited on each other,
 * which should be plenty.
 *
 * This was chosen subject to the clock speed: the maximum possible number of
 * layers so that the compositor can still finish compositing one slice (of size
 * SliceSize) per clock cycle.
 */
typedef 7 MaxLayers;

/**
 * Maximum horizontal output resolution in pixels. This was chosen as a design
 * objective, as it's at the limit of current monitor resolutions. Instead of
 * increasing this, it's expected that the compositor will (eventually) be
 * extended to support multiple monitors.
 */
typedef 2560 MaxXResolution;

/**
 * Maximum vertical output resolution in pixels. See MaxXResolution for an
 * explanation.
 */
typedef 1600 MaxYResolution;

/**
 * Maximum output refresh rate in Hertz. This was chosen as a design objective,
 * as it's a standard refresh rate, the default for many LCD monitors. It's
 * above the refresh rate discernible by the human eye (~30Hz).
 */
typedef 60 MaxRefreshRate;

/**
 * Fixed width and height of a tile in pixels. Tiles are always square. This was
 * chosen for convenience: it's expected that few graphical objects produced by
 * software will be smaller than 32×32 pixels. Conversely, using tiles as big as
 * 32×32 pixels vastly reduces the number of tiles per frame, which limits the
 * amount of metadata the compositor needs to hold and process.
 *
 * This was vaguely chosen to correlate with the burst size supported by DRAM,
 * though the compositor should continue to work if it's changed. Note that it's
 * effectively part of the compositor's ABI, so the kernel driver would need
 * corresponding changes.
 */
typedef 32 TileSize;

/**
 * Size of a slice in pixels. A slice is a 1D vector of pixels, and is the unit
 * of output of the compositor. This was maximised subject to the hardware
 * constraint on reasonable bus width: each pixel is 32 bits (four 8-bit
 * components), and the maximum reasonable bus width is 256 bits before corners
 * consume unreasonable amounts of chip area. 256 bits also happens to be the
 * width of the DRAM data bus at 200MHz.
 *
 * Changing this will have severe repercussions, and will probably break
 * everything.
 */
typedef 8 SliceSize;

/**
 * Latency of an individual memory request in compositor clock cycles. This is
 * used to determine buffer sizes for memory requests and responses, and as such
 * only affects flow control in the compositor. An assumption is made that the
 * memory is pipelined such that it can accept one request and return one
 * response per compositor cycle.
 */
typedef 32 MemoryLatency;

/**
 * Size of the compositor memory, in bytes. This is what's afforded us by a
 * small cut-out region of the main DRAM, since we can't currently use a
 * separate DRAM stick.
 */
typedef 268435456 MemorySize;
