/*-
 * Copyright (c) 2012-2013 Robert M. Norton
 * All rights reserved.
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
 ******************************************************************************
 *
 * Authors: 
 *   Robert Norton <rmn30@cam.ac.uk>
 * 
 ******************************************************************************
 *
 * Description: Generic cache infrastructure.
 * 
 ******************************************************************************/

import MIPS::*;
import CHERITypes::*;
import Bram::*;
import Library::*;

import ConfigReg::*;
import Debug::*;
import FIFO::*;
import SpecialFIFOs::*;

/**
 * Interface for a cache. Similar to a server interface but without the verbiage...
 */
interface CacheIfc#(type requestT, type responseT);
  method Action                  req(requestT request);
  method ActionValue#(responseT) resp();
  method Action                  invalidate(requestT request);
endinterface

module mkSimpleDirectMappedCache#(
   function indexT    getIndex(requestT req),
   function tagT      getTag(requestT req),
   function Bool      isCacheable(requestT req, responseT resp),
   function dataT     getData(responseT resp),
   function responseT toResp(dataT data),
   CacheIfc#(requestT, responseT) nextLevel
   )(CacheIfc#(requestT, responseT)) provisos
   (Bounded#(indexT), Eq#(indexT), Bits#(indexT, indexSz), Arith#(indexT),
    Bits#(tagT, tagSz), Eq#(tagT), 
    Bits#(dataT, dataSz),
    Bits#(requestT, requestSz),
    Bits#(responseT, responseSz));
  function initialTag(idx)                        =  tuple3(False, ?, ?);
  let initBram                                    <- mkInitialisedBramNoWriteForward(initialTag);
  Bram#(indexT, Tuple3#(Bool, tagT, dataT)) cache =  initBram.bram;
  let initialised                                 =  initBram.isInitialised;
  
  let reqQ     <- mkFIFO;
  let missQ    <- mkFIFO;
  `ifndef VERIFY2
  let hitBP    <- mkBypassFIFO;
  `else
  let hitBP    <- mkSizedFIFO(1);	
  `endif
  let missBP   <- mkFIFO;
  let invalidateQ <- mkFIFO;
     
  rule middleBit;
    match {.valid, .cacheTag, .data} <- cache.readResp;
    let request  <- popFIFO(reqQ);
    let tag       = getTag(request);
    let cacheHit  = valid && tag == cacheTag;
    hitBP.enq(tuple2(cacheHit, toResp(data)));
    if (!cacheHit)
      begin
        nextLevel.req(request);
        missQ.enq(request);
      end
  endrule

  rule doInvalidate;
    let idx <- popFIFO(invalidateQ);
    cache.write(idx, tuple3(False, ?, ?));
  endrule
  
  rule fillMiss;
    let request  <- popFIFO(missQ);
    let response <- nextLevel.resp();
    if (isCacheable(request, response))
      cache.write(getIndex(request), tuple3(True, getTag(request), getData(response)));
    missBP.enq(response);
  endrule
  
  method Action req(requestT request) if (initialised);
    let index = getIndex(request);
    reqQ.enq(request);
    cache.readReq(index);
  endmethod
     
  method ActionValue#(responseT) resp if (initialised);
    match{.hit, .response} <- popFIFO(hitBP);
    let r <- hit ? toAV(response) : popFIFO(missBP);
    return r;
  endmethod
     
  method Action invalidate(requestT request) if (initialised);
    invalidateQ.enq(getIndex(request));
  endmethod
     
//  (* preempts = "invalidate, resp" *)
endmodule
