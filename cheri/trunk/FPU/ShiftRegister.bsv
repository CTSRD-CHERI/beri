/*-
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Colin Rothwell as part of his final year
 * undergraduate project.
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
import Vector::*;

interface ShiftRegister#(numeric type length, type td);
    method Action setHead(td head);
    method td getTail();
endinterface

module mkDefaultShiftRegister#(parameter td def)(ShiftRegister#(length, td))
    provisos(Bits#(td, _));

    Wire#(td) headValue <- mkDWire(def);
    Vector#(length, Reg#(td)) registers <- replicateM(mkReg(def));

    rule placeHead;
        registers[0] <= headValue;
    endrule

    (* fire_when_enabled, no_implicit_conditions *)
    rule advanceRegister;
        for (Integer k = 0; k < valueOf(length) - 1; k = k + 1) begin
            registers[k + 1] <= registers[k];
        end
    endrule

    method Action setHead(td head);
        headValue <= head;
    endmethod

    method td getTail();
        return registers[valueOf(length) - 1];
    endmethod
endmodule

module mkShiftRegister(ShiftRegister#(length, td))
    provisos(Bits#(td, _));

    ShiftRegister#(length, td) sr <- mkDefaultShiftRegister(unpack(0));
    method setHead = sr.setHead;
    method getTail = sr.getTail;
endmodule
