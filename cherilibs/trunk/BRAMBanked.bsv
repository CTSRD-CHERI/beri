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
 *

BRAMBanked
==========

This library provides modules for creating wide BRAMs out of multiple smaller
ones. This can be useful to ensure that these BRAMs are correctly inferred by
the Verilog compiler.

******************************************************************************/

package BRAMBanked;

import BRAM::*;
import BRAMCore::*;
import Vector::*;

//TODO: Experiment with different values.
typedef 64 ChunkSize;
typedef Bit#(ChunkSize) ChunkT;

//Takes module with a BRAM_PORT interface and creates a bank of them to
//implement a wider BRAM_PORT interface.
//Although this module takes two arguments, this is a workaround for a
//limitation in Bluespec's type system, and the two arguments should always be
//identical.
module mkBRAMBanked1#(
    module#(BRAM_PORT#(addrT,ChunkT)) bramChunk,
    module#(BRAM_PORT#(addrT,Bit#(remWidth))) bramRem)
    (BRAM_PORT#(addrT,dataT))
provisos(
    Bits#(addrT,addrWidth),
    Bits#(dataT,dataWidth),
    Div#(dataWidth,ChunkSize,n),
    Add#(TMul#(n,ChunkSize),remWidth,dataWidth)
);

    Vector#(n,BRAM_PORT#(addrT,ChunkT)) bankChunks <- replicateM(bramChunk);
    BRAM_PORT#(addrT,Bit#(remWidth)) bankRem <- bramRem;

    method Action put(Bool write, addrT addr, dataT data);
        Tuple2#(Vector#(n,ChunkT),Bit#(remWidth))
            { chunks, rem } = unpack(pack(data));
        function Action bankPut(BRAM_PORT#(addrT,ChunkT) b, ChunkT d) =
            b.put(write,addr,d);
        zipWithM_(bankPut,bankChunks,chunks);
        bankRem.put(write,addr,rem);
    endmethod

    method dataT read();
        function ChunkT bankRead(BRAM_PORT#(addrT,ChunkT) b) =
            b.read();
        let chunks = pack(map(bankRead,bankChunks));
        let rem = bankRem.read();
        return unpack({ chunks, rem });
    endmethod

endmodule

//Takes module with a BRAM_DUAL_PORT interface and creates a bank of them to
//implement a wider BRAM_DUAL_PORT interface.
//Although this module takes two arguments, this is a workaround for a
//limitation in Bluespec's type system, and the two arguments should always be
//identical.
module mkBRAMBanked2#(
    module#(BRAM_DUAL_PORT#(addrT,ChunkT)) bramChunk,
    module#(BRAM_DUAL_PORT#(addrT,Bit#(remWidth))) bramRem)
    (BRAM_DUAL_PORT#(addrT,dataT))
provisos(
    Bits#(addrT,addrWidth),
    Bits#(dataT,dataWidth),
    Div#(dataWidth,ChunkSize,n),
    Add#(TMul#(n,ChunkSize),remWidth,dataWidth)
);

    Vector#(n,BRAM_DUAL_PORT#(addrT,ChunkT)) bankChunks <- replicateM(bramChunk);
    BRAM_DUAL_PORT#(addrT,Bit#(remWidth)) bankRem <- bramRem;

    interface BRAM_PORT a;
        method Action put(Bool write, addrT addr, dataT data);
            Tuple2#(Vector#(n,ChunkT),Bit#(remWidth))
                { chunks, rem } = unpack(pack(data));
            function Action bankPut(BRAM_DUAL_PORT#(addrT,ChunkT) b,ChunkT d) =
                b.a.put(write,addr,d);
            zipWithM_(bankPut,bankChunks,chunks);
            bankRem.a.put(write,addr,rem);
        endmethod
        method dataT read();
            function ChunkT bankRead(BRAM_DUAL_PORT#(addrT,ChunkT) b) =
                b.a.read();
            let chunks = pack(map(bankRead,bankChunks));
            let rem = bankRem.a.read();
            return unpack({ chunks, rem });
        endmethod
    endinterface

    interface BRAM_PORT b;
        method Action put(Bool write, addrT addr, dataT data);
            Tuple2#(Vector#(n,ChunkT),Bit#(remWidth))
                { chunks, rem } = unpack(pack(data));
            function Action bankPut(BRAM_DUAL_PORT#(addrT,ChunkT) b,ChunkT d) =
                b.b.put(write,addr,d);
            zipWithM_(bankPut,bankChunks,chunks);
            bankRem.b.put(write,addr,rem);
        endmethod
        method dataT read();
            function ChunkT bankRead(BRAM_DUAL_PORT#(addrT,ChunkT) b) =
                b.b.read();
            let chunks = pack(map(bankRead,bankChunks));
            let rem = bankRem.b.read();
            return unpack({ chunks, rem });
        endmethod
    endinterface

endmodule


module mkBRAMBanked1BE#(
    module#(BRAM_PORT_BE#(addrT,ChunkT,8)) bramChunk,
    module#(BRAM_PORT_BE#(addrT,Bit#(remWidth),remBytes)) bramRem)
    (BRAM_PORT_BE#(addrT,dataT,dataBytes))
provisos(
    Bits#(addrT,addrWidth),
    Bits#(dataT,dataWidth),
    Div#(dataWidth,ChunkSize,n),
    Add#(TMul#(n,ChunkSize),remWidth,dataWidth),
    Mul#(remBytes,8,remWidth),
    Mul#(dataBytes,8,dataWidth),
    Add#(TMul#(n,8),remBytes,dataBytes)
);

    Vector#(n,BRAM_PORT_BE#(addrT,ChunkT,8)) bankChunks <- replicateM(bramChunk);
    BRAM_PORT_BE#(addrT,Bit#(remWidth),remBytes) bankRem <- bramRem;

    method Action put(Bit#(dataBytes) byteEnable, addrT addr, dataT data);
        Tuple2#(Vector#(n,ChunkT),Bit#(remWidth))
            { chunks, rem } = unpack(pack(data));
        Tuple2#(Vector#(n,Bit#(8)),Bit#(remBytes))
            { chunksBE, remBE } = unpack(pack(byteEnable));
        function Action bankPut(BRAM_PORT_BE#(addrT,ChunkT,8) b, Bit#(8) be, ChunkT d) =
            b.put(be,addr,d);
        let _ <- zipWith3M(bankPut,bankChunks,chunksBE,chunks);
        bankRem.put(remBE,addr,rem);
    endmethod

    method dataT read();
        function ChunkT bankRead(BRAM_PORT_BE#(addrT,ChunkT,8) b) =
            b.read();
        let chunks = pack(map(bankRead,bankChunks));
        let rem = bankRem.read();
        return unpack({ chunks, rem });
    endmethod

endmodule


module mkBRAMBanked2BE#(
    module#(BRAM_DUAL_PORT_BE#(addrT,ChunkT,8)) bramChunk,
    module#(BRAM_DUAL_PORT_BE#(addrT,Bit#(remWidth),remBytes)) bramRem)
    (BRAM_DUAL_PORT_BE#(addrT,dataT,dataBytes))
provisos(
    Bits#(addrT,addrWidth),
    Bits#(dataT,dataWidth),
    Div#(dataWidth,ChunkSize,n),
    Add#(TMul#(n,ChunkSize),remWidth,dataWidth),
    Mul#(remBytes,8,remWidth),
    Mul#(dataBytes,8,dataWidth),
    Add#(TMul#(n,8),remBytes,dataBytes)
);

    Vector#(n,BRAM_DUAL_PORT_BE#(addrT,ChunkT,8)) bankChunks <- replicateM(bramChunk);
    BRAM_DUAL_PORT_BE#(addrT,Bit#(remWidth),remBytes) bankRem <- bramRem;

    interface BRAM_PORT_BE a;
        method Action put(Bit#(dataBytes) byteEnable, addrT addr, dataT data);
            Tuple2#(Vector#(n,ChunkT),Bit#(remWidth))
                { chunks, rem } = unpack(pack(data));
            Tuple2#(Vector#(n,Bit#(8)),Bit#(remBytes))
                { chunksBE, remBE } = unpack(pack(byteEnable));
            function Action bankPut(
                BRAM_DUAL_PORT_BE#(addrT,ChunkT,8) b,
                Bit#(8) be,
                ChunkT d
            ) = b.a.put(be,addr,d);
            let _ <- zipWith3M(bankPut,bankChunks,chunksBE,chunks);
            bankRem.a.put(remBE,addr,rem);
        endmethod
        method dataT read();
            function ChunkT bankRead(BRAM_DUAL_PORT_BE#(addrT,ChunkT,8) b) =
                b.a.read();
            let chunks = pack(map(bankRead,bankChunks));
            let rem = bankRem.a.read();
            return unpack({ chunks, rem });
        endmethod
    endinterface

    interface BRAM_PORT_BE b;
        method Action put(Bit#(dataBytes) byteEnable, addrT addr, dataT data);
            Tuple2#(Vector#(n,ChunkT),Bit#(remWidth))
                { chunks, rem } = unpack(pack(data));
            Tuple2#(Vector#(n,Bit#(8)),Bit#(remBytes))
                { chunksBE, remBE } = unpack(pack(byteEnable));
            function Action bankPut(
                BRAM_DUAL_PORT_BE#(addrT,ChunkT,8) b,
                Bit#(8) be,
                ChunkT d
            ) = b.b.put(be,addr,d);
            let _ <- zipWith3M(bankPut,bankChunks,chunksBE,chunks);
            bankRem.b.put(remBE,addr,rem);
        endmethod
        method dataT read();
            function ChunkT bankRead(BRAM_DUAL_PORT_BE#(addrT,ChunkT,8) b) =
                b.b.read();
            let chunks = pack(map(bankRead,bankChunks));
            let rem = bankRem.b.read();
            return unpack({ chunks, rem });
        endmethod
    endinterface

endmodule


endpackage
