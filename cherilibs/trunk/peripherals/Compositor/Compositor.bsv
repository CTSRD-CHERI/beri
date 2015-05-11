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

package Compositor;

import BRAM::*;
import ClientServer::*;
import CompositorMemoryRequest::*;
import CompositorMemoryResponse::*;
import CompositorOutput::*;
import CompositorTceRequest::*;
import CompositorTceResponse::*;
import CompositorUnit::*;
import CompositorUtils::*;
import Connectable::*;
import FIFO::*;
import GetPut::*;
import Vector::*;

/**
 * Interface for the compositor. This is an abstract interface which needs to be
 * connected through an adapter to provide any meaningful physical interfaces.
 *
 * backgroundColour allows the RGB colour used as the bottom-most layer in all
 * slice compositing operations to be set.
 *
 * TODO: What happens if backgroundColour is changed part-way through a frame?
 *
 * configuration allows the compositor's configuration data (e.g. resolution) to
 * be read and written. The configuration.put() method provides a convenient way
 * of setting initial state. It must be called at startup, before any other
 * method in the compositor is called, to set the initial output resolution and
 * reset the compositor's state. The compositor is idle if either dimension of
 * its resolution is set to 0.
 *
 * extMemory is a bus master connection to DRAM (either to main memory, or to a
 * private graphics DRAM, as decided by the SOC designer).
 *
 * pixelsOut is a stream interface providing output packets, each containing a
 * single output pixel and some frame metadata. Pixels are outputted in a raster
 * scan pattern (left to right, top to bottom).
 *
 * pauseCompositing() allows the compositor to be paused after it finishes
 * rendering the current frame. This is intended for debugging.
 *
 * getStatistics() returns the values of the sample counters for various
 * compositor variables, which have been counting since they were last reset.
 * resetStatistics() resets these counters to 0. pauseStatistics() and
 * unpauseStatistics() allow incrementing of the counters to be paused or
 * unpaused so that they can be read and reset atomically (for example). It is
 * permitted to call getStatistics() or resetStatistics() while the counters are
 * paused.
 *
 * Statistics collection is only enabled if CHERI_COMPOSITOR_STATISTICS is
 * defined. Otherwise, all statistics will always return 0.
 *
 * updateTileCacheEntry() allows the parent module to write directly into the
 * compositor's tile cache BRAM. This is a hack, and should be removed once the
 * compositor has hardware support for managing its tile cache.
 */
interface CompositorIfc;
	interface Put#(RgbPixel) backgroundColour;
	interface Reg#(CompositorConfiguration) configuration;
	interface Client#(CompositorMemoryRequest, RgbaSlice) extMemory; /* Avalon bus master connection for DMA */
	(* always_ready *)
	interface Get#(CompositorOutputPacket) pixelsOut; /* Avalon stream for outputted pixels */

	method Action pauseCompositing ();

	(* always_ready *)
	method CompositorStatistics getStatistics ();
	(* always_ready *)
	method Action resetStatistics ();
	(* always_ready *)
	method Action pauseStatistics ();
	(* always_ready *)
	method Action unpauseStatistics ();

	/* TODO: Remove this once it's implemented in hardware. */
	method Action updateTileCacheEntry (UInt#(TLog#(MaxLayers)) layer, TileCacheEntryAddress address, TileCacheEntry entry);
endinterface: CompositorIfc

/**
 * Power/Activity state of the compositor.
 *
 * POWER_OFF: Everything turned off. No compositing, no state and no output.
 * UNINITIALISED: Powered on, but no compositing is taking place and state is uninitialised.
 * IDLE: Powered on, no compositing is taking place but pixel output is operational and state is consistent.
 * COMPOSITING: Powered on, actively compositing tiles and operating pixel output.
 */
typedef enum {
	POWER_OFF,
	UNINITIALISED,
	IDLE,
	COMPOSITING
} CompositorState deriving (Bits, Eq);

/**
 * Sample counters for various measurements in the compositor. All counters give
 * the relevant value since they were last reset, counting only throughout the
 * period they've been enabled for since then.
 *
 * numCycles: Number of clock cycles the counters have been enabled since the
 * last reset.
 * headToTceqCycles: Number of packets transmitted into the TCEQ pipeline stage.
 * tceqToTcerCycles: Number of packets transmitted from the TCEQ to TCER stage.
 * tcerToMemqCycles: Number of packets transmitted from the TCER to MEMQ stage.
 * memqToMemrCycles: Number of packets transmitted from the MEMQ to MEMR stage.
 * memrToCuCycles: Number of packets transmitted from the MEMR to CU stage.
 * cuToOutCycles: Number of packets transmitted from the CU to OUT stage.
 * numTceRequests: Number of requests sent to one of the tile caches.
 * numMemoryRequests: Number of requests sent to external memory.
 * numFrames: Number of complete frames rendered.
 */
typedef struct {
	UInt#(29) numCycles;
	UInt#(29) headToTceqCycles;
	UInt#(29) tceqToTcerCycles;
	UInt#(29) tcerToMemqCycles;
	UInt#(29) memqToMemrCycles;
	UInt#(29) memrToCuCycles;
	UInt#(29) cuToOutCycles;
	UInt#(29) numTceRequests;
	UInt#(29) numMemoryRequests;
	UInt#(29) numFrames;
} CompositorStatistics deriving (Bits);

/**
 * Implementation of the CompositorIfc interface. This implementation will
 * schedule the entire screen to be redrawn as fast as possible (with no refresh
 * rate limiting or smoothing) for as long as the compositor is enabled.
 */
module mkCompositor (CompositorIfc);
	Reg#(RgbPixel) currentBackgroundColour <- mkReg (RgbPixel { red: 0, green: 0, blue: 0 });

	Reg#(CompositorConfiguration) currentConfiguration <- mkReg (CompositorConfiguration {
		xResolution: 0,
		yResolution: 0
	});

	Reg#(CompositorState) currentState <- mkReg (UNINITIALISED);
	PulseWire currentStateToIdle <- mkPulseWire ();
	PulseWire currentStateToCompositing <- mkPulseWire ();

	/* Tile cache store. */
	BRAM_Configure tileCacheCfg = defaultValue;
	/* Index 0 is the highest layer. */
	Vector#(MaxLayers, BRAM2Port#(TileCacheEntryAddress, TileCacheEntry)) tileCaches <- replicateM (mkBRAM2Server (tileCacheCfg));

	/* TODO: Remove this */
	Reg#(Bool) needToPokeTileCache <- mkReg (False);

	/* New configuration; this is needed so the action of setting the configuration can be moved into a rule. */
	RWire#(CompositorConfiguration) newConfiguration <- mkRWire ();

`ifdef CHERI_COMPOSITOR_STATISTICS
	/* Statistical sampling state. */
	Reg#(Bool) samplingEnabled <- mkReg (False);
	PulseWire enableSampling <- mkPulseWire ();
	PulseWire disableSampling <- mkPulseWire ();
	PulseWire resetSamples <- mkPulseWire ();

	SampleCounterIfc#(29) numCycles <- mkSampleCounter (regToReadOnly (samplingEnabled));
	SampleCounterIfc#(29) headToTceqCycles <- mkSampleCounter (regToReadOnly (samplingEnabled));
	SampleCounterIfc#(29) tceqToTcerCycles <- mkSampleCounter (regToReadOnly (samplingEnabled));
	SampleCounterIfc#(29) tcerToMemqCycles <- mkSampleCounter (regToReadOnly (samplingEnabled));
	SampleCounterIfc#(29) memqToMemrCycles <- mkSampleCounter (regToReadOnly (samplingEnabled));
	SampleCounterIfc#(29) memrToCuCycles <- mkSampleCounter (regToReadOnly (samplingEnabled));
	SampleCounterIfc#(29) cuToOutCycles <- mkSampleCounter (regToReadOnly (samplingEnabled));

	SampleCounterIfc#(29) numTceRequests <- mkSampleCounter (regToReadOnly (samplingEnabled));
	SampleCounterIfc#(29) numMemoryRequests <- mkSampleCounter (regToReadOnly (samplingEnabled));
	SampleCounterIfc#(29) numFrames <- mkSampleCounter (regToReadOnly (samplingEnabled));
`endif /* CHERI_COMPOSITOR_STATISTICS */

	/* Functions for use with map() to extract request/response interfaces
	 * from port A of a BRAM. bramPortARequest returns a wrapper for the
	 * request interface so that the compositor's statistics can be
	 * updated. */
	function Put#(BRAMRequest#(a, b)) bramPortARequest (BRAM2Port#(a, b) bram);
		return bram.portA.request;
	endfunction: bramPortARequest

	function Get#(b) bramPortAResponse (BRAM2Port#(a, b) bram);
		return bram.portA.response;
	endfunction: bramPortAResponse

	/* Pipeline modules. */
	CompositorTceRequestIfc compositorTceRequest <- mkCompositorTceRequest (map (bramPortARequest, tileCaches));
	CompositorTceResponseIfc compositorTceResponse <- mkCompositorTceResponse (map (bramPortAResponse, tileCaches));
	CompositorMemoryRequestIfc compositorMemoryRequest <- mkCompositorMemoryRequest ();
	CompositorMemoryResponseIfc compositorMemoryResponse <- mkCompositorMemoryResponse ();
	CompositorUnitIfc compositorUnit <- mkCompositorUnit (regToReadOnly (currentBackgroundColour));
	CompositorOutputIfc compositorOutput <- mkCompositorOutput (regToReadOnly (currentConfiguration));

`ifdef CHERI_COMPOSITOR_STATISTICS
	/* Rules for incrementing/resetting sample counters. */
	(* fire_when_enabled, no_implicit_conditions *)
	rule countCycles;
		numCycles.inc ();
	endrule: countCycles

	(* fire_when_enabled, no_implicit_conditions *)
	rule countFrames (compositorOutput.endOfFrame ());
		numFrames.inc ();
	endrule: countFrames

	(* fire_when_enabled, no_implicit_conditions *)
	rule countTceRequests (compositorTceRequest.emittingRequest ());
		numTceRequests.inc ();
	endrule: countTceRequests

	(* fire_when_enabled, no_implicit_conditions *)
	rule countMemoryRequests (compositorMemoryRequest.emittingRequest ());
		numMemoryRequests.inc ();
	endrule: countMemoryRequests

	(* fire_when_enabled, no_implicit_conditions *)
	rule resetSampleCounters (resetSamples);
		numCycles.reset ();
		headToTceqCycles.reset ();
		tceqToTcerCycles.reset ();
		tcerToMemqCycles.reset ();
		memqToMemrCycles.reset ();
		memrToCuCycles.reset ();
		cuToOutCycles.reset ();
		numTceRequests.reset ();
		numMemoryRequests.reset ();
		numFrames.reset ();
	endrule: resetSampleCounters

	(* fire_when_enabled, no_implicit_conditions *)
	rule pauseSampleCounters (disableSampling && !enableSampling);
		samplingEnabled <= False;
	endrule: pauseSampleCounters

	(* fire_when_enabled, no_implicit_conditions *)
	rule unpauseSampleCounters (enableSampling && !disableSampling);
		samplingEnabled <= True;
	endrule: unpauseSampleCounters
`endif /* CHERI_COMPOSITOR_STATISTICS */

	/* Control input to the head of the pipeline.
	 * Enqueue frame drawing requests for as long as the compositor is enabled.
	 *
	 * TODO: Might want to implement refresh rate limiting/smoothing. */
	(* fire_when_enabled *)
	rule headOfPipeline (currentState == COMPOSITING);
		debugCompositor ($display ("%05t: → TCEQ", $time));
`ifdef CHERI_COMPOSITOR_STATISTICS
		headToTceqCycles.inc ();
`endif /* CHERI_COMPOSITOR_STATISTICS */

		compositorTceRequest.enq (CompositorTceRequestInputPacket {
			drawRegion: SliceRegion {
				topLeftPos: SlicePosition {
					xPos: 0,
					yPos: 0
				},
				bottomRightPos: SlicePosition {
					xPos: truncate ((currentConfiguration.xResolution + fromInteger (valueOf (SliceSize) - 1)) / fromInteger (valueOf (SliceSize)) - 1),
					yPos: currentConfiguration.yResolution - 1
				}
			}
		});
	endrule: headOfPipeline

	/* Connect up the pipeline. */
	(* fire_when_enabled *)
	rule connectTceRequestAndTceResponse;
		debugCompositor ($display ("%05t: TCEQ → TCER", $time));
`ifdef CHERI_COMPOSITOR_STATISTICS
		tceqToTcerCycles.inc ();
`endif /* CHERI_COMPOSITOR_STATISTICS */

		let packet = compositorTceRequest.first;
		compositorTceRequest.deq ();
		compositorTceResponse.enq (unpack (pack (packet)));
	endrule: connectTceRequestAndTceResponse

	(* fire_when_enabled *)
	rule connectTceResponseAndMemoryRequest;
		debugCompositor ($display ("%05t: TCER → MEMQ", $time));
`ifdef CHERI_COMPOSITOR_STATISTICS
		tcerToMemqCycles.inc ();
`endif /* CHERI_COMPOSITOR_STATISTICS */

		let packet = compositorTceResponse.first;
		compositorTceResponse.deq ();
		compositorMemoryRequest.enq (unpack (pack (packet)));
	endrule: connectTceResponseAndMemoryRequest

	(* fire_when_enabled *)
	rule connectMemoryRequestAndMemoryResponse;
		debugCompositor ($display ("%05t: MEMQ → MEMR", $time));
`ifdef CHERI_COMPOSITOR_STATISTICS
		memqToMemrCycles.inc ();
`endif /* CHERI_COMPOSITOR_STATISTICS */

		let packet = compositorMemoryRequest.first;
		compositorMemoryRequest.deq ();
		compositorMemoryResponse.enq (unpack (pack (packet)));
	endrule: connectMemoryRequestAndMemoryResponse

	(* fire_when_enabled *)
	rule connectMemoryResponseAndUnit;
		debugCompositor ($display ("%05t: MEMR → CU", $time));
`ifdef CHERI_COMPOSITOR_STATISTICS
		memrToCuCycles.inc ();
`endif /* CHERI_COMPOSITOR_STATISTICS */

		let packet = compositorMemoryResponse.first;
		compositorMemoryResponse.deq ();
		compositorUnit.enq (unpack (pack (packet)));
	endrule: connectMemoryResponseAndUnit

	(* fire_when_enabled *)
	rule connectUnitAndOutput;
		debugCompositor ($display ("%05t: CU → OUT", $time));
`ifdef CHERI_COMPOSITOR_STATISTICS
		cuToOutCycles.inc ();
`endif /* CHERI_COMPOSITOR_STATISTICS */

		let packet = compositorUnit.first;
		compositorUnit.deq ();
		compositorOutput.enq (unpack (pack (packet)));
	endrule: connectUnitAndOutput

	/* TODO: remove me */
	rule pokeTileCache (currentState != POWER_OFF && needToPokeTileCache && !isValid (newConfiguration.wget ()));
		debugCompositor ($display ("pokeTileCache"));

		/* Inform the compositor that the tile cache has been updated. */
		if (currentConfiguration.xResolution != 0 && currentConfiguration.yResolution != 0)
			currentStateToCompositing.send ();

		needToPokeTileCache <= False;
	endrule: pokeTileCache

	/* Set the compositor's configuration and reset state around it. */
	rule setConfiguration (isValid (newConfiguration.wget ()));
		let configuration = fromMaybe (?, newConfiguration.wget ());
		debugCompositor ($display ("setConfiguration: ", fshow (configuration)));

		/* Change the power state, so that all compositing stops. */
		currentStateToIdle.send ();
		currentConfiguration <= configuration;

		/* Clear the pipeline stages. */
		compositorTceRequest.reset ();
		compositorTceResponse.reset ();
		compositorMemoryRequest.reset ();
		compositorMemoryResponse.reset ();
		compositorUnit.reset ();
		compositorOutput.reset ();

		needToPokeTileCache <= True;
	endrule: setConfiguration

	/* Update currentState, resolving conflicts from different rules. */
	(* fire_when_enabled, no_implicit_conditions *)
	rule updateCurrentState;
		if (currentStateToCompositing) begin
			currentState <= COMPOSITING;
		end else if (currentStateToIdle) begin
			currentState <= IDLE;
		end
	endrule: updateCurrentState

	/**
	 * Pause compositing if it's currently ongoing. This will prevent further frames from being rendered, but will
	 * finish rendering the current frame. This method is mostly useful for unit testing, where frames need to be
	 * outputted one at a time.
	 */
	method Action pauseCompositing () if (currentState == COMPOSITING);
		debugCompositor ($display ("pauseCompositing"));
		currentStateToIdle.send ();
	endmethod: pauseCompositing

	/* Return statistics for the compositor. If statistics collection is
	 * disabled, always return 0. */
	method CompositorStatistics getStatistics ();
`ifdef CHERI_COMPOSITOR_STATISTICS
		return CompositorStatistics {
			numCycles: numCycles,
			headToTceqCycles: headToTceqCycles,
			tceqToTcerCycles: tceqToTcerCycles,
			tcerToMemqCycles: tcerToMemqCycles,
			memqToMemrCycles: memqToMemrCycles,
			memrToCuCycles: memrToCuCycles,
			cuToOutCycles: cuToOutCycles,
			numTceRequests: numTceRequests,
			numMemoryRequests: numMemoryRequests,
			numFrames: numFrames
		};
`else /* if !CHERI_COMPOSITOR_STATISTICS */
		return CompositorStatistics {
			numCycles: 0,
			headToTceqCycles: 0,
			tceqToTcerCycles: 0,
			tcerToMemqCycles: 0,
			memqToMemrCycles: 0,
			memrToCuCycles: 0,
			cuToOutCycles: 0,
			numTceRequests: 0,
			numMemoryRequests: 0,
			numFrames: 0
		};
`endif /* !CHERI_COMPOSITOR_STATISTICS */
	endmethod: getStatistics

	/* Reset the sample counters for compositor statistics. */
	method Action resetStatistics ();
`ifdef CHERI_COMPOSITOR_STATISTICS
		resetSamples.send ();
`endif /* CHERI_COMPOSITOR_STATISTICS */
	endmethod: resetStatistics

	/* Pause gathering of compositor statistics. */
	method Action pauseStatistics ();
`ifdef CHERI_COMPOSITOR_STATISTICS
		disableSampling.send ();
`endif /* CHERI_COMPOSITOR_STATISTICS */
	endmethod: pauseStatistics

	/* Un-pause gathering of compositor statistics. */
	method Action unpauseStatistics ();
`ifdef CHERI_COMPOSITOR_STATISTICS
		enableSampling.send ();
`endif /* CHERI_COMPOSITOR_STATISTICS */
	endmethod: unpauseStatistics

	/* TODO: Remove this once it's implemented in hardware. */
	method Action updateTileCacheEntry (UInt#(TLog#(MaxLayers)) layer, TileCacheEntryAddress address, TileCacheEntry entry) if (currentState != POWER_OFF);
		tileCaches[layer].portB.request.put (BRAMRequest {
			write: True,
			responseOnWrite: False,
			address: address,
			datain: entry
		});
	endmethod: updateTileCacheEntry

	/* Allow updating the background colour, but not reading it back. */
	interface Put backgroundColour;
		method Action put (RgbPixel colour);
			currentBackgroundColour <= colour;
		endmethod: put
	endinterface: backgroundColour

	/* Similarly, allow updating the configuration, but not reading it back.
	 * This is required at start up, and will reset the compositor's state
	 * (but not the contents of external memory). */
	interface Reg configuration;
		method CompositorConfiguration _read ();
			return currentConfiguration;
		endmethod: _read

		method Action _write (CompositorConfiguration configuration);
			newConfiguration.wset (configuration);
		endmethod: _write
	endinterface: configuration

	/* DMA interface to memory, acting as an Avalon master. */
	interface Client extMemory;
		interface Get request = compositorMemoryRequest.extMemoryRequests;
		interface Put response = compositorMemoryResponse.extMemoryResponses;
	endinterface: extMemory

	/* Pixel stream output to the HDMI module or analogue transceiver. */
	interface Get pixelsOut = compositorOutput.pixelsOut;
endmodule: mkCompositor

/**
 * Interface for a statistical sample counter. This is a non-decreasing,
 * unsigned counter of the given counterWidth (in bits). All of its methods are
 * always ready.
 *
 * inc() increments the counter by 1.
 * reset() resets the counter to 0.
 * _read() gets the counter's current value.
 *
 * If reset() and inc() are called on the same cycle, reset() will override
 * inc() and the counter will be reset to 0.
 *
 * If inc() and _read() are called on the same cycle, the _read() will happen
 * first, so the old value of the counter will be returned. Similarly if reset()
 * and _read() are called on the same cycle, the old value will be returned.
 */
interface SampleCounterIfc#(numeric type counterWidth);
	(* always_ready *)
	method Action inc ();
	(* always_ready *)
	method Action reset ();
	(* always_ready *)
	method UInt#(counterWidth) _read ();
endinterface: SampleCounterIfc

/**
 * Implementation of the SampleCounterIfc interface. This takes a counterEnabled
 * boolean value as input, and only increments the counter when it is True. The
 * value of counterEnabled does not affect flow control in the module: inc() is
 * still always ready (but will have no effect if called while counterEnabled is
 * False).
 */
module mkSampleCounter (ReadOnly#(Bool) counterEnabled, SampleCounterIfc#(counterWidth) ifc);
	PulseWire incCounter <- mkPulseWire ();
	PulseWire resetCounter <- mkPulseWire ();
	Reg#(UInt#(counterWidth)) counterValue <- mkReg (0);

	(* fire_when_enabled, no_implicit_conditions *)
	rule updateCounter;
		if (resetCounter)
			counterValue <= 0;
		else if (incCounter && counterEnabled)
			counterValue <= counterValue + 1;
	endrule: updateCounter

	method Action inc ();
		incCounter.send ();
	endmethod: inc

	method Action reset ();
		resetCounter.send ();
	endmethod: reset

	method UInt#(counterWidth) _read ();
		return counterValue;
	endmethod: _read
endmodule: mkSampleCounter

endpackage: Compositor
