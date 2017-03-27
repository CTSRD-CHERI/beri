/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2014 Jonathan Woodruff
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Robert N. M. Watson
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

import MIPS::*;
import GetPut::*;
import Memory::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import ClientServer::*;
`ifdef CAP
  import CapCop::*;
  `define CAPTOP 4
  `define USECAP 1
`elsif CAP128
  import CapCop128::*;
  `define CAPTOP 3
  `define USECAP 1
`elsif CAP64
  import CapCop64::*;
  `define CAPTOP 2
  `define USECAP 1
`endif

`ifdef MEM128
  `define LINETOP 3
  `define LINETOPPLUS1 4
`elsif MEM64
  `define LINETOP 2
  `define LINETOPPLUS1 3
`else
  `define LINETOP 4
  `define LINETOPPLUS1 5
`endif

module mkMemAccess#(
  DataMemory m
  `ifdef USECAP
    , CapCopIfc capCop
  `endif
)(PipeStageIfc);

  FIFO#(ControlTokenT) outQ <- mkFIFO;

  method Action enq(ControlTokenT er);
    ControlTokenT mi = er;
     
    Bool cap = False;
    `ifdef USECAP
      CoProResponse capResp <- capCop.getAddress();
      if (mi.exception == None) begin
        mi.exception = capResp.exception;
      end
      if (er.inst matches tagged Coprocessor .ci &&& er.memSize==CapWord) cap = True;
    `endif

    Bool scResult = True;
    if (er.test == SC) begin
      scResult = (er.opB[0] == 1'b1);
    end
    Bit#(64) addr = er.opA;
    
    //Exception handling for unaligned accesses 
    //(exception when crossing cache line boundaries)
    `ifdef UNALIGNEDMEMORY
      Bit#(6) unalignCheck = zeroExtend(addr[`LINETOP:0]);
      unalignCheck = unalignCheck + (case (er.memSize)
                DoubleWord: return 7;
                Word:       return 3;
                HalfWord:   return 1;
                Byte:       return 0;
                default:     return 0;
              endcase);
      `ifdef USECAP
        if (er.memSize == CapWord && addr[`CAPTOP:0] != 0) unalignCheck[`LINETOPPLUS1] = 1;
      `endif
      
      if (mi.exception == None && unalignCheck[`LINETOPPLUS1] == 1) begin
        mi.exception = (case(er.mem)
                          Read: return DADEL;
                          Write: return DADES;
                          default: return None;
                        endcase);
      end
    `else
      if (mi.exception == None &&
          case (er.memSize)
            `ifdef USECAP
              CapWord:    return addr[`CAPTOP:0] != 0;
            `endif
            DoubleWord: return addr[2:0] != 3'b0;
            Word:       return addr[1:0] != 2'b0;
            HalfWord:   return addr[0] != 1'b0;
            Byte:       return False;
          endcase) begin
        mi.exception = (case(er.mem)
                          Read: return DADEL;
                          Write: return DADES;
                          default: return None;
                        endcase);
      end
    `endif
    if (mi.exception == None && ((addr[57:40] ^ addr[58:41]) != 18'b0)) begin
      mi.exception = (case(er.mem)
                        Read: return DADEL;
                        Write: return DADES;
                        default: return None;
                      endcase);
    end
    
    Bool storeConditional = False;
    if (er.mem == Write) begin
      debug($display("Put in Write"));
      if (scResult) begin
        if (er.test == SC) begin
          debug($display("MemAccess Store Conditional Attempt"));
          `ifndef MICRO
            `ifdef MULTI
              storeConditional = True;
            `endif 
          `endif
        end
        else begin
          debug($display("MemAccess Write Complete"));
        end
      end else mi.mem = None;
    end
    m.startMem(mi.mem, addr, er.cop, er.storeData, er.memSize, er.test==LL, cap, er.id, er.epoch, er.fromDebug, storeConditional);
    `ifdef USECAP
      // For arithmetic capability instructions that produce a late result...
      if (er.alu == Cap && er.mem == None && er.pendingWrite) mi.opA = capResp.data;
      else if (er.branch != Never && er.pendingWrite) mi.opB = capResp.data;
    `endif
    outQ.enq(mi);
  endmethod
 
  method first = outQ.first;
  method deq   = outQ.deq;
  method clear = noAction; // XXX This method should never be called.

endmodule
