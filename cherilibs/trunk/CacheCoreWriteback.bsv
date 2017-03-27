/*-
 * Copyright (c) 2015 Jonathan Woodruff
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
 
import Debug::*;
import MemTypes::*;
import DefaultValue::*;
import Assert::*;
import FIFO::*;
import FIFOF::*;
import Vector::*;
import ConfigReg::*;
import CacheCoreTypes::*;

module mkCacheCoreWriteback#(Bit#(16) cacheId, 
                    WhichCache whichCache)
                   (CacheCoreWriteback#(ways, keyBits, tagBits))
    provisos (
      Bits#(CheriPhyAddr, paddr_size),
      Bits#(CacheCoreTypes::CacheAddress#(keyBits, tagBits), paddr_size)
    );
                   
  FIFOF#(AddrTagWay#(ways, keyBits, tagBits))                writebacks <- mkUGFIFOF1;
  Reg#(Bank)                                         writebackWriteBank <- mkConfigReg(0);
  
  method Action put(AddrTagWay#(ways, keyBits, tagBits) atw);
    writebacks.enq(atw);
  endmethod
  method Bool canPut = writebacks.notFull;
  
  method ActionValue#(FetchToken#(ways, keyBits, tagBits)) get;
    FetchToken#(ways, keyBits, tagBits) ft = defaultValue;
    AddrTagWay#(ways, keyBits, tagBits) evict = writebacks.first;
    evict.addr.bank = writebackWriteBank;
    ft.command = Writeback;
    ft.dataKey.way = evict.way; // The rest of the data key is set to fields of addr.
    ft.addr = unpack(pack(evict.addr));
    ft.fresh = False;
    ft.req = defaultValue;
    ft.req.addr = unpack(pack(ft.addr));
    debug2("CacheCore", $display("<time %0t, cache %0d, CacheCore> Started Writeback, evict write bank: %x ", $time, cacheId, writebackWriteBank, fshow(evict)));
    ft.last = (writebackWriteBank == 3); // Signal the last eviction frame to the lookup stage.
    Bank nextFetch = writebackWriteBank + 1;
    if (writebackWriteBank == 3) begin
      writebacks.deq();
      writebackWriteBank <= 0;
    end else writebackWriteBank <= nextFetch;
    return ft;
  endmethod
  method Bool canGet = writebacks.notEmpty;
  
endmodule
