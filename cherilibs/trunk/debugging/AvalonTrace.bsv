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

package AvalonTrace;

import Base::*;

import Avalon::*;


module mkAvalonTrace#(
    AvalonMaster#(dataT,addressT,burstSize) master)(Put#(dataT))
provisos(
    Bits#(dataT,dataWidth),
    Bits#(addressT,addressWidth),
    Literal#(addressT),
    Arith#(addressT),
    Eq#(addressT)
);
    Reg#(addressT) addr <- mkReg(0);

    method Action put(x);
        let next = addr + 1;
        if (next != 0) begin
            master.write(addr,x);
            addr <= next;
        end
    endmethod

endmodule


endpackage
