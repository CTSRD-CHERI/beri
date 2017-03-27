/*-
 * Copyright (c) 2013 Alex Horsman
 * All rights reserved.
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

package DynamicBits;


import List::*;


typedef List#(Bit#(1)) DynamicBits;

function DynamicBits toDynamic (dataT x)
provisos (Bits#(dataT,dataWidth));
    if (valueof(dataWidth) == 0) begin
        return Nil;
    end else begin
        return Cons {
            _1: pack(x)[0],
            _2: toDynamic(Bit#(TSub#(dataWidth,1))'(truncateLSB(pack(x))))
        };
    end
endfunction


function dataT fromDynamic(DynamicBits dyn)
provisos(Bits#(dataT,dataWidth));
    if (valueof(dataWidth) == 0) begin
        return ?;
    end else begin
        case (dyn) matches
            tagged Nil :
                return error("Not enough dynamic bits.");
            tagged Cons { _1: .x, _2: .xs } :
                return unpack(
                    { Bit#(TSub#(dataWidth,1))'(fromDynamic(xs)), x }
                );
        endcase
    end
endfunction


endpackage
