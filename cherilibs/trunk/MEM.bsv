/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
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

import FIFO    :: *;
import Vector  :: *;
import RegFile :: *;

interface ReadIfc#(type addr, type data);
  method Action              put(addr a);
  method ActionValue#(data)  get();
  method data                peek();
endinterface

interface MEM#(type addr, type data);
  interface ReadIfc#(addr, data) read;
  method Action                  write(addr a, data x);
endinterface

module mkMEM(MEM#(addr, data))
   provisos(Bits#(addr, addr_sz),
            Bounded#(addr),
            Bits#(data, data_sz));

	RegFile#(addr,data) regFile <- mkRegFileWCF(minBound, maxBound); // BRAM
	FIFO#(addr)         readReq <- mkSizedFIFO(4);

	interface ReadIfc read;
    method Action put(addr a) = readReq.enq(a);
    method data peek() = regFile.sub(readReq.first());
    method ActionValue#(data) get();
      readReq.deq();
      return regFile.sub(readReq.first());
    endmethod
  endinterface
  method Action write(addr a, data x) = regFile.upd(a,x);
endmodule


typedef Bit#(8) Byte;

interface MemBEVerbose#(type addr, type data, numeric type data_bytes);
  interface ReadIfc#(addr, data) read;
  method Action write(addr a, data x, Vector#(data_bytes,Bool) be);
endinterface

typedef MemBEVerbose#(addr,data,TDiv#(SizeOf#(data),8)) MemBE#(type addr, type data);

function data fromChunks(Vector#(n,chunk) vec)
provisos(
  Bits#(data,data_sz),
  Bits#(chunk,chunk_sz),
  Mul#(chunk_sz,n,data_sz)
);
  return unpack(truncate(pack(vec)));
endfunction

module mkMemBE(MemBE#(addr, data))
provisos(
  Bits#(addr, addr_sz),
  Bounded#(addr),
  Bits#(data, data_sz),
  Mul#(data_bytes, 8, data_sz),
  Div#(data_sz, 8, data_bytes)
);

  Vector#(data_bytes,RegFile#(addr,Byte))
    regFiles <- replicateM(mkRegFileWCF(minBound, maxBound));
  FIFO#(addr) readReq <- mkSizedFIFO(4);

  function readF(rf) = rf.sub(readReq.first);
  Vector#(data_bytes,Byte) readBytes = map(readF,regFiles);
  data readResult = fromChunks(readBytes);


  method Action write(addr a, data x, Vector#(data_bytes,Bool) be);
    Vector#(data_bytes,Byte) bytes = unpack(pack(x));
    function writeF(rf, b, en) = action
      if (en) begin
        rf.upd(a,b);
      end
    endaction;
    let _ <- zipWith3M(writeF,regFiles,bytes,be);
  endmethod

  interface ReadIfc read;
    method Action put(addr a) = readReq.enq(a);
    method ActionValue#(data) get();
      readReq.deq();
      return readResult;
    endmethod
    method data peek = readResult;
  endinterface
endmodule
