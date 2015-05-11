/*-
 * Copyright (c) 2015 Colin Rothwell
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
 * A register file with two write ports.
 *
 * Uses two register files, and keeps track of which has the most recent value.
 * This is probably not the most efficient way of doing this: a replacement with
 * a verilog module is probably a good idea if a file of signficant size is used
 * in the design.
 *
 */

import ConfigReg::*;
import RegFile::*;
import Vector::*;

interface TwoWritePortRegFile#(type indexT, type dataT);
    method Action writeLeft(indexT index, dataT data);
    method Action writeRight(indexT index, dataT data);
    method dataT read(indexT index);
endinterface

module mkTwoWritePortRegFile
        #(indexT low, indexT high)
        (TwoWritePortRegFile#(indexT, dataT))
        provisos (
            Bits#(indexT, indexSizeT),
            Bits#(dataT, a__), // BSC
            PrimIndex#(indexT, b__),
            FShow#(dataT)
        );
    // If the write to the left file is most recent, signalLeft is updated to
    // match signalRight.
    // If write to the right file is most recent, it updates the relevant entry
    // in singalRight to mismatch that in signalLeft.

    RegFile#(indexT, dataT) fileLeft <- mkRegFileWCF(low, high);
    RegFile#(indexT, dataT) fileRight <- mkRegFileWCF(low, high);

    // These are potentially overly large: hopefully they'll be optimised
    // correctly. It should be possibly to do this with a register of vector,
    // which might be more efficient, but would require complicated bit masking
    // and a variable shift. It shouldn't but, it seems to according to
    // Bluespec.
    Vector#(TExp#(indexSizeT), Reg#(Bool)) signalLeft <- replicateM(mkConfigRegU);
    Vector#(TExp#(indexSizeT), Reg#(Bool)) signalRight <- replicateM(mkConfigRegU);

    method Action writeLeft(indexT index, dataT data);
        fileLeft.upd(index, data);
        signalLeft[index] <= signalRight[index];
    endmethod

    method Action writeRight(indexT index, dataT data);
        fileRight.upd(index, data);
        signalRight[index] <= !signalLeft[index];
    endmethod

    method dataT read(indexT index);
        if (signalLeft[index] == signalRight[index])
            return fileLeft.sub(index);
        else
            return fileRight.sub(index);
    endmethod
endmodule
