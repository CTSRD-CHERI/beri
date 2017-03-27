/*-
 * Copyright (c) 2014 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
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

/*
 * This is designed to count the number of "open" transactions for a particular
 * bus; the number of transactions for which a request has been made, but no
 * response received.
 *
 * It is essentially a register with increment and decrement methods that can be
 * called in the same cycle.
 *
 * A sequence of method calls that would lead to maximumValue being exceeded is
 * forbidden.
 *
 * an attempt to decrement below zero causes an assertion failure.
 */

import Assert::*;
import ConfigReg::*;
import RegFile::*;
import Vector::*;

import TwoWritePortRegFile::*;

interface InflightCounter#(numeric type width);
    method Action increment();
    method Action decrement();
    method UInt#(width) read();
endinterface

module mkInflightCounter#(Integer maximumValue)(InflightCounter#(width));

    let uintMax = fromInteger(maximumValue);

    Reg#(UInt#(width)) counter <- mkReg(0);
    Wire#(Bool) incrementCalled <- mkDWire(False);
    Wire#(Bool) decrementCalled <- mkDWire(False);

    (* no_implicit_conditions, fire_when_enabled *)
    rule updateValue;
        let newValue = counter;
        if (incrementCalled && !decrementCalled)
            newValue = counter + 1;
        else if (!incrementCalled && decrementCalled) begin
            dynamicAssert(counter > 0,
                "Can't decrement InflightCounter below 0");
            newValue = counter - 1;
        end

        counter <= newValue;
        if (counter != newValue)
            $display("%t: InflightCounter was %d, now %d",
                $time, counter, newValue);
    endrule

    method Action increment()
            if (counter < uintMax ||
                (counter == uintMax && decrementCalled));
        incrementCalled._write(True);
    endmethod
    method Action decrement() = decrementCalled._write(True);
    method UInt#(width) read() = counter._read();

endmodule


interface PerThreadInflightCounter#(numeric type threadsT, numeric type widthT);
    method Action increment(UInt#(TLog#(threadsT)) thread);
    method Action decrement(UInt#(TLog#(threadsT)) thread);
    method UInt#(widthT) read(UInt#(TLog#(threadsT)) thread);
endinterface

module mkPerThreadInflightCounter(PerThreadInflightCounter#(threadsT, widthT));

    let highestThread = fromInteger(valueOf(threadsT) - 1);

    Reg#(Bool) initialised <- mkReg(False);
    Reg#(UInt#(TLog#(threadsT))) threadToInitialise <- mkReg(0);

    TwoWritePortRegFile#(UInt#(TLog#(threadsT)), UInt#(widthT)) counters <-
        mkTwoWritePortRegFile(0, highestThread);

    RWire#(UInt#(TLog#(threadsT))) toIncrement <- mkRWire();
    RWire#(UInt#(TLog#(threadsT))) toDecrement <- mkRWire();

    rule initialise (!initialised);
        counters.writeLeft(threadToInitialise, 0);
        if (threadToInitialise == highestThread)
            initialised <= True;
        threadToInitialise <= threadToInitialise + 1;
    endrule

    (* no_implicit_conditions, fire_when_enabled *)
    rule updateCounts (initialised);
        case (toIncrement.wget()) matches
            tagged Valid .increment: begin
                case (toDecrement.wget()) matches
                    tagged Valid .decrement: begin
                        if (increment != decrement) begin
                            /*$display("Incrementing %d from %d", increment,*/
                                /*counters.read(increment));*/
                            /*$display("Decrementing %d from %d", decrement,*/
                                /*counters.read(decrement));*/
                            counters.writeLeft(increment,
                                counters.read(increment) + 1);
                            counters.writeRight(decrement,
                                counters.read(decrement) - 1);
                            dynamicAssert(counters.read(decrement) > 0,
                                "Attempting to decrement beneath 0");
                        end
                    end
                    tagged Invalid: begin
                        /*$display("Incrementing %d from %d", increment,*/
                            /*counters.read(increment));*/
                        counters.writeLeft(increment,
                            counters.read(increment) + 1);
                    end
                endcase
            end
            tagged Invalid: begin
                case (toDecrement.wget()) matches
                    tagged Valid .decrement: begin
                        /*$display("Decrementing %d from %d",*/
                            /*decrement, counters.read(decrement));*/
                        counters.writeRight(decrement,
                            counters.read(decrement) - 1);
                        dynamicAssert(counters.read(decrement) > 0,
                            "Attempting to decrement beneath 0");
                    end
                endcase
            end
        endcase
    endrule

    method increment if (initialised) = toIncrement.wset;
    method decrement if (initialised) = toDecrement.wset;
    method read if (initialised) = counters.read;
endmodule
