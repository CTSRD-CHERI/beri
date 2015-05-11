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

package AvalonSampler;

import Avalon2ClientServer::*;
import AvalonBurstMasterWordAddressed::*;
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import GetPut::*;
import Vector::*;

/**
 * Avalon pipelined slave interface. This complements AvalonPipelinedMasterIfc.
 * It is word addressed, and data is inputted in full-length bursts. It does not
 * support byte enables.
 *
 * Signal names are chosen to match what Qsys expects; so don’t change them.
 */
(* always_ready, always_enabled *)
interface AvalonPipelinedSlaveIfc#(numeric type word_address_width);
	method Action s0(UInt#(word_address_width) address,
	                 AvalonBurstWordT writedata, Bool read,
	                 Bool write, BurstLength burstcount);
	method AvalonBurstWordT s0_readdata;
	method Bool s0_readdatavalid;
	method Bool s0_waitrequest;
endinterface

/**
 * Interface for a small peripheral which samples traffic on an Avalon memory
 * bus. (It could be used to sample other buses, but is primarily aimed at
 * memory buses, and hence this documentation will refer to memory buses
 * exclusively.)
 *
 * Traffic on the memory bus passes through the peripheral (just using wiring;
 * no latency is added) from the slave interface, avs, to the master interface,
 * avm. Each request received at the slave increments either the read or write
 * request counter. Each response received at the master increments a counter in
 * a histogram of request–response latencies. The logic to calculate latencies
 * assumes that responses are received in the same order as the requests were
 * (FIFO order).
 *
 * ‘Latency’ is defined as the time between a request arriving at avs, and its
 * associated response arriving at avm.
 *
 * Statistics and control data are exposed on a third interface; the Avalon
 * slave, samples. The following registers are exposed (using byte addressing):
 *  • 0: Control register, R/W:
 *     - Bit 0 indicates counter overflow (read-only), indicating the counters
 *       have overflowed at least once if set.
 *     - Bit 1 indicates counter pause state (read–write), pausing counters when
 *       set.
 *     - Bit 2 resets counters when set (write-only).
 *  • 4: # read requests, R: Number of read requests on the memory bus since the
 *    counters were last reset.
 *  • 8: # write requests, R: Number of write requests on the memory bus since
 *    the counters were last reset.
 *  • 12: # read bursts, R: Number of packets requested by burst requests with a
 *    burst count greater than 1.
 *  • 16: # write bursts, R: Number of packets written by burst requests with a
 *    burst count greater than 1.
 *  • 28: latency histogram configuration, R:
 *     - Bits [7:0] are unused.
 *     - Bits [15:8] give the number of latency histogram bins.
 *     - Bits [23:16] give the upper bound (in clock cycles) of the latency
 *       bins.
 *     - Bits [31:24] give the lower bound (in clock cycles) of the latency
 *       bins.
 *    Hence a configuration { 0, 8, 5 } means the latency histogram has
 *    bins: [0, 2), [2, 4), [4, 6), [6, 8), [8, ∞).
 *  • 64: latency histogram bin 0, R: Number of request–response pairs which had
 *    a latency (in clock cycles) falling in this bin. If this bin’s index is
 *    equal to or greater than the number of bins exposed in the configuration,
 *    its value is undefined.
 *  • 68: latency histogram bin 1, R.
 *  • …
 *  • 124: latency histogram bin 15, R.
 *
 * The control interface allows sample data to be read off the peripheral
 * atomically. For example, using the following sequence of reads/writes:
 *  1. Write (1 << 1) to register 0. (Pause sampling.)
 *  2. Read bit 0 from register 0; read registers 4, 8 and 28; read suitable
 *     registers from 64–124. (Read out the sample data.)
 *  3. Write ((1 << 2) | (0 << 1)) to register 0. (Reset counters and unpause
 *     sampling.)
 *
 * Sub-interface names are chosen to match what Qsys expects; so don’t change
 * them.
 *
 * FIXME: hasOverflowed is currently unimplemented.
 * FIXME: It appears that AvalonSampler can cause some weirdness in Qsys memory
 *        maps, depending on where it’s placed in the map. This seems to be due
 *        to the address bus width it uses, but hasn’t been investigated
 *        further.
 */
interface AvalonSamplerIfc#(numeric type memory_word_address_width,
                            numeric type control_word_address_width);
	/* Memory pass-through interfaces. */
	interface AvalonPipelinedSlaveIfc#(memory_word_address_width) avs;
	interface AvalonPipelinedMasterIfc#(memory_word_address_width) avm;

	/* Samples slave interface. */
	interface AvalonSlaveIfc#(control_word_address_width) samples;
endinterface: AvalonSamplerIfc

/* Latency bin configuration. */
typedef 16 NumLatencyBins;
typedef 0 LatencyBinLowerBound; /* inclusive */
typedef 32 LatencyBinUpperBound; /* exclusive */

/**
 * Implementation of the AvalonSamplerIfc interface. This uses 32-bit addressing
 * for the memory bus, and 5-bit addressing for the control slave interface.
 *
 * See the documentation for AvalonSamplerIfc for more details.
 */
module mkAvalonSampler (AvalonSamplerIfc#(32, 5));
	/* Request data. */
	Wire#(UInt#(32)) requestAddress <- mkDWire (0);
	Wire#(AvalonBurstWordT) requestWriteData <- mkDWire (0);
	Wire#(Bool) requestRead <- mkDWire (False);
	Wire#(Bool) requestWrite <- mkDWire (False);
	Wire#(BurstLength) requestBurstCount <- mkDWire (0);

	/* Response data. */
	Wire#(AvalonBurstWordT) responseReadData <- mkDWire (0);
	Wire#(Bool) responseReadDataValid <- mkDWire (False);
	Wire#(Bool) responseWaitRequest <- mkDWire (False);

	/* Various wires for incrementing/resetting counters. */
	PulseWire resetCounters <- mkPulseWire ();
	PulseWire pauseCounters <- mkPulseWire ();
	PulseWire unpauseCounters <- mkPulseWire ();
	PulseWire readRequest <- mkPulseWire ();
	PulseWire writeRequest <- mkPulseWire ();
	Wire#(BurstLength) readBurstCount <- mkDWire (0);
	Wire#(BurstLength) writeBurstCount <- mkDWire (0);
	Wire#(Maybe#(UInt#(TLog#(TSub#(NumLatencyBins, 1))))) incLatencyBinIndex <- mkDWire (tagged Invalid);

	/* The number of read/write requests seen on the memory bus. The
	 * register sizes were chosen to accommodate one increment per cycle for
	 * at least 5 minutes of uptime before potentially overflowing. */
	Reg#(UInt#(32)) numReadRequests <- mkReg (0);
	Reg#(UInt#(32)) numWriteRequests <- mkReg (0); /* == numResponses */
	Reg#(UInt#(32)) numReadBursts <- mkReg (0);
	Reg#(UInt#(32)) numWriteBursts <- mkReg (0);

	/* Track the pending requests. Each request enqueues the current clock
	 * counter onto the FIFO, so its latency can be calculated when the
	 * response is received and the counter is dequeued from the FIFO.
	 *
	 * The clock counter is only 8 bits because we expect all latencies to
	 * be on the order of 20 cycles. Accordingly, the FIFO needs to be as
	 * long as the maximum expected latency. */
	Reg#(UInt#(8)) clockCounter <- mkReg (0);
	FIFOF#(UInt#(8)) pendingRequests <- mkUGSizedFIFOF (30);

	/* Latency sample bin counters. Count the number of read
	 * request/response latencies which fit in each bin. Bin i handles the
	 * range [2i, 2i + 2). */
	Vector#(NumLatencyBins, Reg#(UInt#(32))) latencyBins <- replicateM (mkReg (0));

	/* Whether the sample counters have overflowed at least once since last
	 * being reset. */
	Reg#(Bool) hasOverflowed <- mkReg (False);

	/* Whether counting is currently paused. */
	Reg#(Bool) isPaused <- mkReg (False);

	/* Adapter for the Avalon control register interface. */
	AvalonSlave2ClientIfc#(5) controlAdapter <- mkAvalonSlave2Client ();

	/* Convert a latency (in cycles) into an index into the latencyBins
	 * vector. Latencies higher than the latencyBinUpperBound are always
	 * assigned to the top-most bin. Similarly for the lower bound and the
	 * bottom-most bin. This assumes the bins have a uniform step. */
	function UInt#(TLog#(NumLatencyBins)) convertLatencyToBinIndex (UInt#(8) latency);
		let binRange = valueOf (LatencyBinUpperBound) - valueOf (LatencyBinLowerBound);
		let binStep = binRange / valueOf (NumLatencyBins);
		let limitedLatency = min (max (latency, fromInteger (valueOf (LatencyBinLowerBound))),
		                          fromInteger (valueOf (LatencyBinUpperBound) - 1 /* right-open bound */));
		return truncate (limitedLatency / fromInteger (binStep) -
		                 fromInteger (valueOf (LatencyBinLowerBound) / binStep));
	endfunction: convertLatencyToBinIndex

	/* Clock counter. If this overflows at most once between a request and
	 * response, the difference between them (when interpreted as an
	 * unsigned integer) is still correct. If this overflows more than once,
	 * it won't be. */
	(* fire_when_enabled, no_implicit_conditions *)
	rule incClockCounter;
		if (resetCounters)
			clockCounter <= 0;
		else if (!isPaused)
			clockCounter <= clockCounter + 1;
	endrule: incClockCounter

	/* Various rules to increment/reset counters. */
	(* fire_when_enabled, no_implicit_conditions *)
	rule incNumReadRequests;
		if (resetCounters)
			numReadRequests <= 0;
		else if (readRequest)
			numReadRequests <= numReadRequests + 1;
	endrule: incNumReadRequests

	(* fire_when_enabled, no_implicit_conditions *)
	rule incNumWriteRequests;
		if (resetCounters)
			numWriteRequests <= 0;
		else if (writeRequest)
			numWriteRequests <= numWriteRequests + 1;
	endrule: incNumWriteRequests

	(* fire_when_enabled, no_implicit_conditions *)
	rule incNumReadBursts;
		if (resetCounters)
			numReadBursts <= 0;
		else
			numReadBursts <= numReadBursts + zeroExtend (readBurstCount);
	endrule: incNumReadBursts

	(* fire_when_enabled, no_implicit_conditions *)
	rule incNumWriteBursts;
		if (resetCounters)
			numWriteBursts <= 0;
		else
			numWriteBursts <= numWriteBursts + zeroExtend (writeBurstCount);
	endrule: incNumWriteBursts

	(* fire_when_enabled, no_implicit_conditions *)
	rule incLatencyBins;
		if (resetCounters) begin
			writeVReg (latencyBins, replicate (0));
		end else if (isValid (incLatencyBinIndex)) begin
			let bin = fromMaybe (?, incLatencyBinIndex);
			latencyBins[bin] <= latencyBins[bin] + 1;
		end
	endrule: incLatencyBins

	(* fire_when_enabled, no_implicit_conditions *)
	rule pause;
		if (unpauseCounters)
			isPaused <= False;
		else if (pauseCounters)
			isPaused <= True;
	endrule: pause

	/* Handle reads/writes to/from the control registers on the second
	 * Avalon slave interface. */
	rule handleCommand;
		let req <- controlAdapter.client.request.get ();

		/* Handle register reads. */
		Bit#(32) response = ?;

		case (tuple2 (req.rw, pack (req.addr))) matches
			{ MemRead, 0 }: begin
				/* Control register:
				 * { padding, isPaused, hasOverflowed } */
				response = { 30'h0,
				             pack (isPaused),
				             pack (hasOverflowed) };
			end
			{ MemWrite, 0 }: begin
				/* Control register: isPaused and reset are
				 * writeable. */
				if (pack (req.data)[1] == 1'b1)
					pauseCounters.send ();
				else
					unpauseCounters.send ();

				if (pack (req.data)[2] == 1'b1) begin
					/* Reset the counters. */
					resetCounters.send ();
					hasOverflowed <= False;
					pendingRequests.clear ();
				end
			end
			{ MemRead, 1 }: begin
				/* numReadRequests. */
				response = pack (numReadRequests);
			end
			{ MemRead, 2 }: begin
				/* numWriteRequests. */
				response = pack (numWriteRequests);
			end
			{ MemRead, 3 }: begin
				/* numReadBursts. */
				response = pack (numReadBursts);
			end
			{ MemRead, 4 }: begin
				/* numWriteBursts. */
				response = pack (numWriteBursts);
			end
			{ MemRead, 7 }: begin
				/* Latency bin configuration:
				 * { padding, number of bins, upper bin bound,
				 *   lower bin bound } */
				UInt#(8) nob = fromInteger (valueOf (NumLatencyBins));
				UInt#(8) ubb = fromInteger (valueOf (LatencyBinUpperBound));
				UInt#(8) lbb = fromInteger (valueOf (LatencyBinLowerBound));

				response = { 8'h00, pack (nob), pack (ubb), pack (lbb) };
			end
			{ MemRead, 5'b_1_???? }: begin /* registers [16, 32) */
				/* Latency bin. */
				UInt#(4) bin = unpack (pack (req.addr)[3:0]);
				response = pack (latencyBins[bin]);
			end
			default: begin
				/* Error response. Ignore writes. */
				response = 32'h00000000;
			end
		endcase

		/* Enqueue the response. */
		if (req.rw == MemRead)
			controlAdapter.client.response.put (tagged Valid unpack (response));
		else
			controlAdapter.client.response.put (tagged Invalid);
	endrule: handleCommand

	/* Memory pass-through slave interface. */
	interface AvalonPipelinedSlaveIfc avs;
		method Action s0 (UInt#(32) address, AvalonBurstWordT writedata,
		                  Bool read, Bool write,
		                  BurstLength burstcount);
			/* Store the request. */
			requestAddress <= address;
			requestWriteData <= writedata;
			requestRead <= read;
			requestWrite <= write;
			requestBurstCount <= burstcount;

			/* Increment samples. */
			let incrementRead = read && !isPaused;
			let incrementWrite = write && !isPaused;

			if (incrementRead)
				readRequest.send ();
			if (incrementWrite)
				writeRequest.send ();

			if (incrementRead && burstcount > 1)
				readBurstCount <= burstcount;
			if (incrementWrite && burstcount > 1)
				writeBurstCount <= burstcount;

			/* Track the latency of this request. */
			if (incrementRead && pendingRequests.notFull ())
				pendingRequests.enq (clockCounter);
			else if (incrementRead)
				$warning ("pendingRequests full.");
		endmethod: s0

		method AvalonBurstWordT s0_readdata;
			return responseReadData;
		endmethod: s0_readdata

		method Bool s0_readdatavalid;
			return responseReadDataValid;
		endmethod: s0_readdatavalid

		method Bool s0_waitrequest;
			return responseWaitRequest;
		endmethod: s0_waitrequest
	endinterface: avs

	/* Memory pass-through master interface. */
	interface AvalonPipelinedMasterIfc avm;
		method Action m0 (AvalonBurstWordT readdata, Bool readdatavalid,
		                  Bool waitrequest);
			/* Store the response. */
			responseReadData <= readdata;
			responseReadDataValid <= readdatavalid;
			responseWaitRequest <= waitrequest;

			/* Calculate the request/response latency, and put it in
			 * the right bin. */
			let storeLatency = readdatavalid && !isPaused;

			if (storeLatency && pendingRequests.notEmpty ()) begin
				let startCounter = pendingRequests.first;
				pendingRequests.deq ();

				let latency = clockCounter - startCounter;
				let bin = convertLatencyToBinIndex (latency);

				incLatencyBinIndex <= tagged Valid bin;
			end else if (storeLatency) begin
				/* pendingRequests can be empty if we forwarded
				 * some requests, then reset the statistics, and
				 * later received the responses. Ignore these
				 * responses, since they’re effectively from
				 * before the reset. */
				$warning ("pendingRequests empty.");
			end
		endmethod: m0

		method AvalonBurstWordT m0_writedata;
			return requestWriteData;
		endmethod: m0_writedata

		method UInt#(32) m0_address;
			return requestAddress;
		endmethod: m0_address

		method Bool m0_read;
			return requestRead;
		endmethod: m0_read

		method Bool m0_write;
			return requestWrite;
		endmethod: m0_write

		method BurstLength m0_burstcount;
			return requestBurstCount;
		endmethod: m0_burstcount
	endinterface: avm

	/* Slave interface exposing the samples in registers. */
	interface samples = controlAdapter.avs;
endmodule: mkAvalonSampler

endpackage: AvalonSampler
