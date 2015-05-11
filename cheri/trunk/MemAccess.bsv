/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 Jonathan Woodruff
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
import CapCop::*;

module mkMemAccess#(
  DataMemory m
  `ifdef CAP
    , CapCopIfc capCop
  `endif
)(PipeStageIfc);

  FIFO#(ControlTokenT) outQ <- mkFIFO;

  method Action enq(ControlTokenT er);
    ControlTokenT mi = er;
     
    Bool cap = False;
    `ifdef CAP
      CoProResponse capResp <- capCop.getAddress();
      if (mi.alu == Cap || mi.mem != None) begin
        if (mi.exception == None) begin
          mi.exception = capResp.exception;
        end
      end
      if (er.inst matches tagged Coprocessor .ci &&& er.memSize==Line) begin
        cap = True;
      end
    `endif

    Bool scResult = True;
    if (er.test == SC) begin
      scResult = (er.opB[0] == 1'b1);
    end
    Bit#(64) addr = er.opA;
    
    if (mi.exception == None &&
        case (er.memSize)
          Line:       return addr[4:0] != 5'b0;
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
    if (mi.exception == None && ((addr[57:40] ^ addr[58:41]) != 18'b0)) begin
      mi.exception = (case(er.mem)
                        Read: return DADEL;
                        Write: return DADES;
                        default: return None;
                      endcase);
    end

    case(er.mem)
      Read: begin
        debug($display("Put in Read"));
        m.startRead(addr, er.memSize, er.test==LL, cap, er.id, er.epoch, er.fromDebug);
      end
      Write: begin
        debug($display("Put in Write"));
        if (scResult || mi.exception != None) begin
          Bool storeConditional = False;
          if (er.test == SC) begin
            debug($display("MemAccess Store Conditional Attempt"));
            `ifdef MULTI
              storeConditional = True;
            `endif 
          end
          else begin
            debug($display("MemAccess Write Complete"));
          end
          m.startWrite(addr, er.storeData, er.memSize, er.id, er.epoch, er.fromDebug, storeConditional);
        end else m.startNull(er.id, er.epoch);
      end
      DCacheOp, ICacheOp: begin
        debug($display("Put in Cache Operation"));
        m.startCacheOp(addr, er.cop, er.id, er.epoch);
      end
      default: begin
        debug($display("Put in Null Cache Operation"));
        m.startNull(er.id, er.epoch);
      end
    endcase
    outQ.enq(mi);
  endmethod
 
  method first = outQ.first;
  method deq   = outQ.deq;

endmodule
