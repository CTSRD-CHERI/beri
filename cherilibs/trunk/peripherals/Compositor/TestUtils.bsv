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

import StmtFSM::*;

/**
 * Begin a unit test with the given testName. This will output an appropriate message to the console.
 */
function Action startTest (String testName);
	action
		Bool useColour <- $test$plusargs ("term-colour");
		if (useColour)
			$display ("\033[0;32mTEST\033[0m: ", testName, "…");
		else
			$display ("TEST: ", testName, "…");
	endaction
endfunction: startTest

/**
 * Finish the current unit test (as started using startTest()), marking it as successful. This will output an appropriate message to the console.
 */
function Action finishTest ();
	action
		Bool useColour <- $test$plusargs ("term-colour");
		if (useColour)
			$display ("\033[0;32mPASS\033[0m\n");
		else
			$display ("PASS\n");
	endaction
endfunction: finishTest

/**
 * Finish the current unit test (as started using startTest()), marking it as failed. This will output the given failure message to the console and
 * stop the simulation.
 */
function Action failTest (Fmt message);
	action
		Bool useColour <- $test$plusargs ("term-colour");
		if (useColour)
			$display ("\033[0;31mFAIL\033[0m: ", message);
		else
			$display ("FAIL: ", message);
		$finish (1);
	endaction
endfunction: failTest

/**
 * Version of loopEveryCycle which doesn't initialise the counter to 0, expecting the
 * caller to do this instead. This means it can guarantee to execute loopBody for the
 * first time on the first cycle it's called, rather than the second.
 */
function Stmt loopEveryCycleNoSetup (Reg#(UInt#(32)) counter, UInt#(32) count, Action loopBody);
	return seq
		while (counter < count) action
			loopBody ();
			counter <= counter + 1;
		endaction
	endseq;
endfunction: loopEveryCycleNoSetup

/**
 * Wrapper for a StmtFSM while loop which ensures the given loopBody is executed every
 * cycle for exactly count cycles. This is necessary because Bluespec's StmtFSM for loops
 * take 2 cycles per iteration.
 *
 * The register passed as counter must not be written to in loopBody, but may be read.
 */
function Stmt loopEveryCycle (Reg#(UInt#(32)) counter, UInt#(32) count, Action loopBody);
	return seq
		counter <= 0;
		loopEveryCycleNoSetup (counter, count, loopBody);
	endseq;
endfunction: loopEveryCycle

/**
 * Version of loopEveryCycle which operates in two dimensions, using two separate loop
 * counters. This ensures that the loopBody is executed every cycle, even when the xCounter
 * rolls over.
 *
 * xCounter is incremented every cycle; yCounter is incremented every time xCounter rolls
 * over.
 */
function Stmt loopEveryCycle2D (Reg#(UInt#(32)) xCounter, UInt#(32) xCount,
                                Reg#(UInt#(32)) yCounter, UInt#(32) yCount, Action loopBody);
	return seq
		action
			xCounter <= 0;
			yCounter <= 0;
		endaction

		while (xCounter < xCount && yCounter < yCount) action
			loopBody ();

			if (xCounter == xCount - 1) begin
				xCounter <= 0;
				yCounter <= yCounter + 1;
			end else begin
				xCounter <= xCounter + 1;
			end
		endaction
	endseq;
endfunction: loopEveryCycle2D

/**
 * Assert that two values are equal. If they are, the assertion succeeds and a
 * status message is printed. If they are not, the assertion fails, an error
 * message is printed, and the current test fails.
 *
 * Both actual and expected must be of the same type, which must implement Eq
 * and FShow.
 */
function Action assertEqual (a_type actual, a_type expected) provisos (Eq#(a_type), FShow#(a_type));
	return action
		if (actual != expected) begin
			let theTime <- $time;
			failTest ($format ("%05t: expected ", theTime, fshow (expected), ", got ", fshow (actual)));
		end else begin
			$display (" - %05t: expected ", $time, fshow (expected));
		end
	endaction;
endfunction: assertEqual
