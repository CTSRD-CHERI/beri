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
*
*/

import Vector::*;

import MasterSlave::*;

typedef Bit#(TLog#(entries)) ReorderToken#(numeric type entries);

// This is conceptually identical to the Bluespec "CompletionBuffer" type.
// However, this uses in and out FIFOFs, and doesn't incure additional latency.
// Obviously, the cost of this is long combinatorial paths. Additonally, the
// ReorderToken is held directly in the response. This is to support transaction
// ids.
interface ReorderBuffer#(numeric type entries, type elementType);
    interface CheckedGet#(ReorderToken#(entries)) reserve;
    interface CheckedPut#(elementType) complete;
    interface CheckedGet#(elementType) drain;
endinterface

typeclass Reorderable#(type elementType, numeric type entries)
        dependencies (elementType determines entries);
    function ReorderToken#(entries) extractToken(elementType element);
endtypeclass

module mkReorderBuffer
        (ReorderBuffer#(entries, elementType))
        provisos (
            Reorderable#(elementType, typeEntries),
            Add#(entries, _, typeEntries),
            Bits#(elementType, a),
            Add#(a__, TLog#(entries), TLog#(typeEntries)), // from bsc
            Add#(b__, TLog#(entries), TLog#(TAdd#(entries, 1)))
        );

    Reg#(ReorderToken#(entries)) nextToken <- mkReg(0);
    Reg#(ReorderToken#(entries)) nextToReturn <- mkReg(0);

    Vector#(entries, Reg#(Bool)) allocated <- replicateM(mkReg(False));
    Vector#(entries, Reg#(Maybe#(elementType))) buffer <-
        replicateM(mkReg(tagged Invalid));

    RWire#(elementType) newEntry <- mkRWire();
    Wire#(Bool) tokenAllocated <- mkDWire(False);
    Wire#(Bool) wasDequeued <- mkDWire(False);

    function tokenAfter(token);
        ReorderToken#(entries) candidate = token + 1;
        Bit#(TLog#(TAdd#(entries, 1))) limit = fromInteger(valueOf(entries));
        if (candidate == truncate(limit))
            return 0;
        else
            return candidate;
    endfunction

    function tokenAvailable();
        return !allocated[nextToken];
    endfunction

    function entryAvailable();
        // Either the next value to return is in the buffer, or it's just been
        // given to us.
        if (isValid(buffer[nextToReturn]))
            return True;
        else if (newEntry.wget() matches tagged Valid .entry)
            return truncate(extractToken(entry)) == nextToReturn;
        else
            return False;
    endfunction

    function nextEntry();
        case (buffer[nextToReturn]) matches
            tagged Valid .storedEntry:
                return storedEntry;
            tagged Invalid:
                case (newEntry.wget()) matches
                    tagged Valid .forwardedEntry:
                        return forwardedEntry;
                endcase
        endcase
    endfunction

    /*rule printState;*/
        /*$display("%t: nextToken: %d; nextToReturn: %d", $time, nextToken,*/
            /*nextToReturn);*/
    /*endrule*/

    (* no_implicit_conditions, fire_when_enabled *)
    rule updateBuffer;
        // If the element was getueued, we want to invalidate its entry in the
        // buffer.
        if (tokenAllocated) begin
            allocated[nextToken] <= True;
            nextToken <= tokenAfter(nextToken);
        end

        if (wasDequeued) begin
            // Will be old value of nextToken, as needed.
            // Condition means "didn't reallocate the last token immediately."
            if ( !(tokenAllocated && (nextToken == nextToReturn))) begin
                allocated[nextToReturn] <= False;
            end
            buffer[nextToReturn] <= tagged Invalid;
            nextToReturn <= tokenAfter(nextToReturn);
        end

        // If the element was not forwarded, we want to store it into memory.

        case (newEntry.wget()) matches
            tagged Valid .entry: begin
                ReorderToken#(entries) token = truncate(extractToken(entry));
                if (!wasDequeued || (token != nextToReturn))
                    buffer[token] <= tagged Valid entry;
            end
        endcase
    endrule

    interface CheckedGet reserve;
        method canGet = tokenAvailable;

        method ReorderToken#(entries) peek if (tokenAvailable());
            return nextToken;
        endmethod

        method ActionValue#(ReorderToken#(entries)) get() if (tokenAvailable());
            tokenAllocated <= True;
            return nextToken;
        endmethod
    endinterface

    interface CheckedPut complete;
        method Bool canPut();
            return True; // You can always complete a value because you had to
            // reserve a slot for it earlier on.
        endmethod

        method put = newEntry.wset;
    endinterface

    interface CheckedGet drain;
        method canGet = entryAvailable;

        method elementType peek() if (entryAvailable());
            return nextEntry();
        endmethod

        method ActionValue#(elementType) get() if (entryAvailable());
            wasDequeued <= True;
            return nextEntry();
        endmethod
    endinterface
endmodule
