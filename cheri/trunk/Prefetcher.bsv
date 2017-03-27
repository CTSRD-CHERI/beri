/*-
 * Copyright (c) 2015 Alexandre Joannou
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

import MIPS::*;
import MemTypes::*;
import Debug::*;
import Assert::*;
import FIFOF::*;
import MasterSlave::*;
`ifdef CAP
  import CapCop :: *;
  `define USECAP
`elsif CAP128
  import CapCop128 :: *;
  `define USECAP
`elsif CAP64
  import CapCop64 :: *;
  `define USECAP
`endif

interface PrefetcherIfc;
    (* always_ready *)
    method ActionValue#(Tuple2#(TlbRequest,CacheRequestDataT)) getPftchReq;
    method Action spyCacheReq (CacheRequestDataT req);
    method Action spyCacheRsp (CacheResponseDataT rsp);
endinterface

CacheOperation dcachePrefetch = CacheOperation {
    inst: CachePrefetch,
    cache: DCache,
    indexed: ?
};

CacheOperation l2Prefetch = CacheOperation {
    inst: CachePrefetch,
    cache: L2,
    indexed: ?
};

CacheRequestDataT defaultCacheReq = CacheRequestDataT {
    cop: dcachePrefetch,
    byteEnable: ?,
    memSize: ?,
    data: ?,
    `ifdef USECAP
    capability: ?,
    `endif
    instId: ?,
    epoch: ?,
    tr: ?
};

TlbRequest defaultTlbReq = TlbRequest {
    addr: ?,
    write: False,
    ll: False,
    exception: None,
    fromDebug: False,
    instId: ?
};

CacheRequestDataT nopCacheReq = CacheRequestDataT{
    `ifdef USECAP
    capability: False,
    `endif
    cop: CacheOperation{inst: CacheNop, indexed: False, cache: DCache},
    byteEnable: ?,
    memSize: ?,
    data: ?,
    instId: ?,
    epoch: ?,
    tr: ?
};

TlbRequest nopTlbReq = TlbRequest{
    addr: ?,
    write: False,
    ll: False,
    exception: DTLBL, // XXX This is here for a reason (apparently, lets the kernel boot). Either way, I was told to keep it there, but I have no clue why it's not "None"
    fromDebug: False,
    instId: ?
};

module mkSimplePrefetcher#(CacheOperation cop) (PrefetcherIfc);
    FIFOF#(Tuple2#(TlbRequest,CacheRequestDataT)) reqs <- mkUGFIFOF();
    method ActionValue#(Tuple2#(TlbRequest,CacheRequestDataT)) getPftchReq();
        Tuple2#(TlbRequest,CacheRequestDataT) ret = tuple2(nopTlbReq, nopCacheReq);
        if (reqs.notEmpty()) begin
            reqs.deq();
            ret = reqs.first();
        end
        debug2("SimplePrefetch", $display("<time %0t, SimplePrefetch> get Request ", $time, fshow(ret)));
        return ret;
    endmethod
    method Action spyCacheReq (CacheRequestDataT req);
        debug2("SimplePrefetch", $display("<time %0t, SimplePrefetch> spy req ", $time, fshow(req)));
        // prepare cache request
        CacheRequestDataT cacheReq = defaultCacheReq;
        cacheReq.cop = cop;
        // prepare tlb request
        TlbRequest tlbReq = defaultTlbReq;
        CheriPhyAddr tmp = unpack(req.tr.addr);
        tlbReq.addr = {tmp.lineNumber + 1, 0};
        // enqueue the requests
        if (reqs.notFull) reqs.enq(tuple2(tlbReq, cacheReq));
    endmethod
endmodule

`ifdef USECAP
module mkCapPrefetcher#(CacheOperation cop) (PrefetcherIfc);
    // XXX Assumption : a response flit can contain exactly one capability
    // XXX Vector#(Reg#(Maybe(Address)), capPerFlit) and rotate if more
    FIFOF#(Tuple2#(TlbRequest,CacheRequestDataT)) reqs <- mkUGFIFOF();
    method ActionValue#(Tuple2#(TlbRequest,CacheRequestDataT)) getPftchReq();
        Tuple2#(TlbRequest,CacheRequestDataT) ret = tuple2(nopTlbReq, nopCacheReq);
        if (reqs.notEmpty()) begin
            reqs.deq();
            ret = reqs.first();
        end
        debug2("CapPrefetch", $display("<time %0t, CapPrefetch> get Request ", $time, fshow(ret)));
        return ret;
    endmethod
    method Action spyCacheRsp (CacheResponseDataT rsp);
        debug2("CapPrefetch", $display("<time %0t, CapPrefetch> enq response", $time));
        if (rsp.data matches tagged Line .c &&& rsp.capability) begin
            debug2("CapPrefetch", $display("<time %0t, CapPrefetch> got capability", $time));
            // prepare cache request
            CacheRequestDataT cacheReq = defaultCacheReq;
            cacheReq.cop = cop;
            // prepare tlb request
            TlbRequest tlbReq = defaultTlbReq;
            Capability cap = unpack(zeroExtend(c));
            cap.isCapability = True;
            `ifdef CAP
            tlbReq.addr = getOffset(cap);
            `else ifdef CAP128
            tlbReq.addr = getPointer(cap);
            `else ifdef CAP64
            tlbReq.addr = getPointer(cap);
            `endif
            // enqueue the requests
            if (reqs.notFull) reqs.enq(tuple2(tlbReq, cacheReq));
        end
    endmethod
endmodule
`endif
