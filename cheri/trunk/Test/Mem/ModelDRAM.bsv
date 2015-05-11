/*-
 * Copyright (c) 2015 Matthew Naylor
 * All rights reserved.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
 * project, funded by EPSRC grant EP/K008528/1.
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

import ConfigReg    :: *;
import RegFile      :: *;
import Vector       :: *;
import FIFO         :: *;
import FIFOF        :: *;
import MasterSlave  :: *;
import MemTypes     :: *;
import RegFileAssoc :: *;
import RegFileHash  :: *;

interface ModelDRAM#(numeric type addrWidth);
  interface Slave#(CheriMemRequest, CheriMemResponse) slave;
endinterface

module mkModelDRAMGeneric#
         ( Integer maxOutstandingReqs         // Max outstanding requests
         , Integer latency                    // Latency (cycles)
         , RegFile# (Bit#(addrWidth)
                   , Bit#(256)
                   ) ram                      // For storage
         )
         (ModelDRAM#(addrWidth))
         provisos (Add#(a, addrWidth, 35));

  // Slave interface
  FIFOF#(CheriMemRequest)  preReqFifo <- mkSizedFIFOF(maxOutstandingReqs);
  FIFOF#(CheriMemResponse) respFifo   <- mkFIFOF;

  // Internal request FIFO contains requests and a flag which denotes
  // the last read request in a burst read.
  FIFOF#(Tuple2#(CheriMemRequest, Bool))  reqFifo <- mkFIFOF;

  // Latency-introducing response FIFO
  FIFOF#(Maybe#(CheriMemResponse)) preRespFifo <- mkSizedFIFOF(latency);

  // Storage implemented as a register file
  //RegFile#(Bit#(addrWidth), Bit#(256)) ram <- mkRegFileFull;

  // State for burst writes
  Reg#(Maybe#(Bit#(35))) burstWriteAddr <- mkConfigReg(tagged Invalid);

  // State for burst reads
  Reg#(UInt#(TLog#(MaxNoOfFlits))) burstReadCount <- mkConfigReg(0);
 
  // State for initialisation
  Reg#(Bool)     init      <- mkConfigReg(False);

  // Unroll burst read requests
  rule unrollBurstReads (!init);
    // Extract request
    let req  = preReqFifo.first;
    let addr = pack(req.addr)[39:5];

    // Update address to account for bursts
    req.addr = unpack({addr + zeroExtend(pack(burstReadCount)), 5'b00000});

    // Only dequeue read request if burst read finished
    Bool last = False;
    if (req.operation matches tagged Read .readOp)
      begin
        if (readOp.noOfFlits == burstReadCount)
          begin
            last = True;
            burstReadCount <= 0;
            preReqFifo.deq;
          end
        else 
          burstReadCount <= burstReadCount+1;
      end
    else
      preReqFifo.deq;

    // Forward request to next stage
    reqFifo.enq(tuple2(req, last));
  endrule

  (* preempts = "produceResponses,introduceLatency" *)
  // Produce responses
  rule produceResponses (!init);
    // Extract request
    let req  = tpl_1(reqFifo.first);
    let last = tpl_2(reqFifo.first);
    let addr = pack(req.addr)[39:5];
    reqFifo.deq;

    // Data lookup
    let data = ram.sub(truncate(addr));
   
    // Prepare response
    CheriMemResponse resp;
    Bool validResponse = False;
    resp.operation     = ?;
    resp.masterID      = req.masterID;
    resp.transactionID = req.transactionID;
    resp.error         = NoError;

    case (req.operation) matches
      // Cache operation ======================================================
      tagged CacheOp .cacheOp:
        begin
          $display("WARNING: cache operation reached DRAM");
        end
      
      // Write ================================================================
      tagged Write .writeOp:
        begin
          // Handle burst writes
          if (writeOp.last)
            burstWriteAddr <= tagged Invalid;
          else if (burstWriteAddr matches tagged Valid .a)
            begin
              burstWriteAddr <= tagged Valid (a+1);
              addr = a+1;
            end
          else
            burstWriteAddr <= tagged Valid addr;

          // Perform write
          Vector#(32, Bit#(8)) bytes    = unpack(zeroExtend(data));
          Vector#(32, Bit#(8)) newBytes = unpack(writeOp.data.data);
          for (Integer i = 0; i < 32; i=i+1)
            if (writeOp.byteEnable[i])
              bytes[i] = newBytes[i];
          ram.upd(truncate(addr), pack(bytes));
         
          // Produce response
          resp.operation = tagged Write;
          validResponse = writeOp.last;
        end

      // Read =================================================================
      tagged Read .readOp:
        begin
          // Produce response
          Data#(256) d = Data {data: data};
          resp.operation = tagged Read {data: d, last: last};
          validResponse  = True;
        end
    endcase

    // Respond
    preRespFifo.enq(validResponse ? tagged Valid resp : tagged Invalid);
  endrule
  
  // Introduce latency by keeping pre-response FIFO full
  // (This rule can only fire if previous one does not)
  rule introduceLatency;
    preRespFifo.enq(tagged Invalid);
  endrule

  // Final responses
  rule produceFinalResponses (!init);
    let resp = preRespFifo.first;
    if (resp matches tagged Valid .r) respFifo.enq(r);
    preRespFifo.deq;
  endrule

  // Initialise until pre-response FIFO is full
  rule initialise (init && !preRespFifo.notFull);
    init <= False;
  endrule

  // Slave interface
  interface Slave slave;
    interface request  = toCheckedPut(preReqFifo);
    interface response = toCheckedGet(respFifo);
  endinterface

endmodule

// Version using a standard register file
module mkModelDRAM#
         ( Integer maxOutstandingReqs         // Max outstanding requests
         , Integer latency                    // Latency (cycles)
         )
         (ModelDRAM#(addrWidth))
         provisos (Add#(a, addrWidth, 35));
  RegFile#(Bit#(addrWidth), Bit#(256)) ram <- mkRegFileFull;
  let dram <- mkModelDRAMGeneric(maxOutstandingReqs, latency, ram);
  interface Slave slave = dram.slave;
endmodule

// Version using an associative register file.  Must be small, but has
// the advantage of being efficiently resettable to a predefined state.
module mkModelDRAMAssoc#
         ( Integer maxOutstandingReqs         // Max outstanding requests
         , Integer latency                    // Latency (cycles)
         )
         (ModelDRAM#(addrWidth))
         provisos (Add#(a, addrWidth, 35));
  RegFile#(Bit#(addrWidth), Bit#(256)) ram <- mkRegFileAssoc;
  let dram <- mkModelDRAMGeneric(maxOutstandingReqs, latency, ram);
  interface Slave slave = dram.slave;
endmodule

// Version using hash table implemented in C
module mkModelDRAMHash#
         ( Integer maxOutstandingReqs         // Max outstanding requests
         , Integer latency                    // Latency (cycles)
         )
         (ModelDRAM#(35));
  RegFile#(Bit#(35), Bit#(256)) ram <- mkRegFileHash(8192);
  let dram <- mkModelDRAMGeneric(maxOutstandingReqs, latency, ram);
  interface Slave slave = dram.slave;
endmodule

