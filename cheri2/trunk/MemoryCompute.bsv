/*-
 * Copyright (c) 2011-2012 SRI International
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2014 Alexandre Joannou
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
 *
 ******************************************************************************
 *
 * Authors: 
 *   Nirav Dave <ndave@csl.sri.com>
 * 
 ******************************************************************************
 *
 * Description: Logic to convert High-level Ops into memory subsystem ops
 * 
 ******************************************************************************/

import Vector::*;
import FShow::*;

import Debug::*;
import MIPS::*;
import CHERITypes::*;
import MemTypes::*;
import DefaultValue::*;
import Assert::*;

interface MemoryCompute;		
  method ActionValue#(Tuple3#(MemRespData,Exception,VirtualMemRequest))
                                  calcMEMReq(MemOperation op, Value addr, Value val);
  method ActionValue#(Value) handleMEMResp(Value old, CheriMemResponse resp, MemRespData memRespData);
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkMemoryCompute(MemoryCompute);
  method calcMEMReq    = calcMEMReqFN;
  method handleMEMResp = handleMEMRespFN;
endmodule

//  Unaligned Loads... Send mask of correct amount, get response, shift respons to align, then apply simple mask
//  unaligned stores ..Send mask of correct amount, and shift input correctly.

function ActionValue#(Tuple3#(MemRespData,Exception,VirtualMemRequest))  calcMEMReqFN(MemOperation op, Value addr, Value val);
  actionvalue
    let                  offset  = addr[2:0];
    // 64-bit word within 256-bit line. Inverted because cache-line is
    // stored reversed due to big endian madness.
    let                  word    = ~addr[4:3];
    //Values associated with both request and response
    MemCmd               memcmd  = ?;
    Bool                 isUnaligned     = False;
    Bool                 negateUnaligned = False;
    //Values associated with constructing the request
    let                  accessSize = SZ_8Byte; // only
    //Values associated with determining the result from the response
    Bit#(3)              shiftR = ?; // amount to right shift result to put it in correct place for result
    CacheOperation      cacheOp = ?;

    case (op.op_memtype) matches
      tagged MEM_LDL:
        begin //keep left side of bits
          memcmd          = Read;
          isUnaligned     = True;
        end
      tagged MEM_SDL:
        begin
          memcmd          = Write;
          isUnaligned     = True;
        end
      tagged MEM_LDR:
        begin //keep left side of bits
          memcmd          = Read;
          isUnaligned     = True;
          negateUnaligned = True;
        end
      tagged MEM_SDR:
        begin
          memcmd          = Write;
          isUnaligned     = True;
          negateUnaligned = True;
        end
      tagged MEM_LWL:
        begin
          memcmd          = Read;
          isUnaligned     = True;
          accessSize      = SZ_4Byte; // result is 4 bytes so signExtend
        end
      tagged MEM_SWL:
        begin
          memcmd          = Write;
          isUnaligned     = True;
          accessSize      = SZ_4Byte; // result is 4 bytes so signExtend
        end
      tagged MEM_LWR: // no shifting just replacement
        begin
          memcmd          = Read;
          isUnaligned     = True;
          negateUnaligned = True;
          accessSize      = SZ_4Byte;
        end
      tagged MEM_SWR:
        begin
          memcmd          = Write;
          isUnaligned     = True;
          negateUnaligned = True;
          accessSize      = SZ_4Byte;
        end
      tagged MEM_LB:
        begin
          memcmd          = Read;
          accessSize      = SZ_1Byte;
        end
      tagged MEM_SB:
        begin
          memcmd          = Write;
          accessSize      = SZ_1Byte;
        end
      tagged MEM_LH:
        begin
          memcmd          = Read;
          accessSize      = SZ_2Byte;
        end
      tagged MEM_SH:
        begin
          memcmd          = Write;
          accessSize      = SZ_2Byte;
        end
      tagged MEM_LW:
        begin
          memcmd          = Read;
          accessSize      = SZ_4Byte;
        end
      tagged MEM_SW:
        begin
          memcmd          = Write;
          accessSize      = SZ_4Byte;
        end
      tagged MEM_LD:
        begin
          memcmd          = Read;
          accessSize      = SZ_8Byte;
        end
      tagged MEM_SD:
        begin
          memcmd          = Write;
          accessSize      = SZ_8Byte;
        end
      tagged MEM_CACHE .cop:
        begin
	  memcmd          = Cache;
          // Which cache operation?
          let inst = case (cop[4:2])
                       0: return CacheInvalidateWriteback;      // Invalidate index in the cache.
                       1: return CacheNop;                      // Load tag is unsupported
                       2: return CacheNop;                      // Store tag is unsupported
                       3: return CacheNop;                      // Not defined.
                       4: return CacheInvalidate;               // Invalidate on a match.  We just invalidate anyway.
                       5: return CacheInvalidateWriteback;      // Writeback and invalidate.
                       6: return CacheWriteback;                // Just writeback.
                       7: return CacheNop;                      // Fetch and Lock.  Not implemented.
                     endcase;
          // Does the operand refer to a cache index, or an address?
          let indexed = case (cop[4:2]) // Which cache operation?
                       0: return True;  // Invalidate index in the cache.
                       1: return True;  // Load tag is unsupported
                       2: return True;  // Store tag is unsupported
                       3: return True;  // Not defined.
                       4: return False; // Invalidate on a match.  We just invalidate anyway.
                       5: return False; // Writeback and invalidate.
                       6: return False; // Just writeback.
                       7: return False; // Fetch and Lock.  Not implemented.
                     endcase;
          cacheOp = CacheOperation {
             inst:  inst,
             indexed: indexed,
             cache: unpack(cop[1:0])
             };
          // prevents address error for unaligned address
          accessSize      = SZ_1Byte;
	end
      default:
        begin
          debug($display("ERROR: Unexpected Memory Op %h", op.op_memtype));
        end
    endcase

    Bit#(4) shiftNumberA = case (accessSize) matches
                             SZ_1Byte: return (4'b0111-zeroExtend(offset))&4'b0111;
                             SZ_2Byte: return (4'b0111-zeroExtend(offset))&4'b0110;
                             SZ_4Byte: return (4'b0111-zeroExtend(offset))&4'b0100;
                             SZ_8Byte: return (4'b0111-zeroExtend(offset))&4'b0000;
                           endcase;
    //unaligned Right (always positive)
    Bit#(4) shiftNumberR = case (accessSize) matches
                             SZ_4Byte: return 4'b0111 - zeroExtend(offset);
                             SZ_8Byte: return 4'b0111 - zeroExtend(offset);
                             default:  return ?;
                           endcase;
    //unaligned Left (often negative)
    Bit#(4) shiftNumberL = case (accessSize) matches
                             SZ_4Byte: return 4'b0100 -(zeroExtend(offset));
                             SZ_8Byte: return -(zeroExtend(offset)); //always left
                             default:  return ?;
                           endcase;
      
    Int#(4) shiftAmount = unpack((isUnaligned)
                                    ? ((negateUnaligned) ? shiftNumberR: shiftNumberL)
                                    : shiftNumberA);
    Int#(8) shiftBitAmount = signExtend(shiftAmount) * 8;
    
    Bit#(8) baseMask  = case (accessSize) matches
                          SZ_1Byte: return 8'h01;
                          SZ_2Byte: return 8'h03;
                          SZ_4Byte: return 8'h0F;
                          SZ_8Byte: return 8'hFF;
                        endcase;
    Bit#(8) byteMask  = (shiftAmount < 0) ? (baseMask >>negate(shiftAmount))
                                          : (baseMask <<       shiftAmount );
    Bit#(8) sizeMask  = (accessSize == SZ_4Byte && isUnaligned) ? ((offset[2] == 0) ? 8'hF0: 8'h0F) : 8'hFF;
    
    Bit#(8) theByteMask = byteMask & sizeMask;

    Bit#(256) storeVal = ((shiftAmount < 0) ? zeroExtend(val) >> negate(shiftBitAmount): zeroExtend(val) << shiftBitAmount) << {word, 6'b0} ;

    let memRespData = MemRespData{
          isMerge:  isUnaligned,
          isSigned: op.op_signed,
          cmd:      memcmd,
          sz:       accessSize,
          byteMask: theByteMask, // ndave: we don't need a mask for aligned loads
          negateUnaligned: negateUnaligned,
          offset:    offset,
          word:      word
      };
    
    // Create a 256-bit mask for the cache line from the word mask. Note that loads of non-power-of-two masks are not
    // supported by AXI so for unaligned loads we just load the whole word containing the bytes of interest.
    Bit#(32) bigMask = (memcmd == Read && isUnaligned ? zeroExtend(sizeMask) : zeroExtend(theByteMask)) << {word, 3'b0};
    
    let isAddrEx = case (accessSize)
                     SZ_1Byte: return !isUnaligned && (addr[2:0] & 3'b000) != 0; // False
                     SZ_2Byte: return !isUnaligned && (addr[2:0] & 3'b001) != 0;
                     SZ_4Byte: return !isUnaligned && (addr[2:0] & 3'b011) != 0;
                     SZ_8Byte: return !isUnaligned && (addr[2:0] & 3'b111) != 0;
                   endcase;

    function BytesPerFlit accessSizeTobpf (AccessSize as);
        case (as)
            SZ_1Byte: return BYTE_1;
            SZ_2Byte: return BYTE_2;
            SZ_4Byte: return BYTE_4;
            SZ_8Byte: return BYTE_8;
            SZ_32Byte: return BYTE_32;
        endcase
    endfunction

    VirtualMemRequest memReq = defaultValue;
    memReq.addr = unpack(pack(addr));
    memReq.masterID = ?;
    memReq.transactionID = ?;
    case (memcmd) matches
        tagged Read : begin
            memReq.operation = tagged Read {
                uncached: ?,
                linked: op.op_isMemLinked,
                noOfFlits: 0,
                bytesPerFlit: accessSizeTobpf(accessSize)
            };
        end
        tagged Write: begin
            memReq.operation = tagged Write {
                uncached: ?,
                conditional: op.op_isMemLinked,
                byteEnable: unpack(bigMask),
                data: Data{
                    `ifdef CAP
                    cap: unpack('h0),
                    `endif
                    data: storeVal
                },
                last: True
            };
        end
        tagged Cache: begin
            memReq.operation = tagged CacheOp cacheOp;
        end
        default     : begin
            dynamicAssert(False, "Unknown Memory Command");
        end
    endcase
    
    let exception = (!isAddrEx) ? Ex_None :
                      ((memRespData.cmd == Write) ? Ex_AddrErrStore: Ex_AddrErrLoad);

    debug(action
            $display("DEBUG: MEMRespData: ", fshow(memRespData));
            $display("DEBUG:      MEMReq: ", fshow(memReq));
            $display("DEBUG:   Exception: ", fshow(exception), " %h %d ", addr, isUnaligned, fshow(accessSize));
          endaction);

    return tuple3(memRespData, exception, memReq);
  endactionvalue
endfunction

function ActionValue#(Value) handleMEMRespFN(Value old, CheriMemResponse resp256, MemRespData memRespData);
  actionvalue

    Vector#(4, Value) words = ?;
    if(resp256.operation matches tagged Read .op) words = unpack(op.data.data);
    else dynamicAssert(False, "Only Read responses are expected");
    let resp = words[memRespData.word];
    
    debug($display("Getting memory response: 0x%h mask:%b addrOffset %h",
                   resp, memRespData.byteMask, memRespData.offset));

    function extend(x) = (memRespData.isSigned) ? signExtend(x) : zeroExtend(x);

    // How far to shift RIGHT
    Bit#(4) shiftNumberA = case (memRespData.sz) matches // Aligned (always positive)
                             SZ_1Byte: return (4'b0111-zeroExtend(memRespData.offset))&4'b0111;
                             SZ_2Byte: return (4'b0111-zeroExtend(memRespData.offset))&4'b0110;
                             SZ_4Byte: return (4'b0111-zeroExtend(memRespData.offset))&4'b0100;
                             SZ_8Byte: return (4'b0111-zeroExtend(memRespData.offset))&4'b0000;
                           endcase;
    Bit#(4) shiftNumberR = 4'b0111 - zeroExtend(memRespData.offset); //unaligned Right (always positive)
    Bit#(4) shiftNumberL = case (memRespData.sz) matches             //unaligned Left  (often negative)
                             SZ_4Byte: return 4'b0100 - zeroExtend(memRespData.offset);
                             SZ_8Byte: return         -(zeroExtend(memRespData.offset));
                             default:  return ?;
                           endcase;
    Int#(4) shiftAmount = unpack((memRespData.isMerge)
                                    ? ((memRespData.negateUnaligned) ? shiftNumberR: shiftNumberL)
                                    : shiftNumberA);
    Bit#(8) byteMask8 = (memRespData.negateUnaligned) ? (8'hFF >> (3'b111 - memRespData.offset)) 
                                                      : (8'hFF << (memRespData.offset));
    Bit#(8) byteMask4 = (memRespData.offset[2] == 1) ? {4'b0, byteMask8[7:4]} : {4'b0, byteMask8[3:0]};
    Bit#(8) byteMask  = (memRespData.sz == SZ_4Byte && memRespData.isMerge) ? byteMask4: byteMask8;

    Int#(8) shiftBitAmount = signExtend(shiftAmount) * 8;
      
    Value newVal = (shiftAmount < 0) ? resp << negate(shiftBitAmount) : resp >> shiftBitAmount;

    function          ife(p,t,f) = (p) ? t : f;
    Vector#(8, Bool)       mask8 = unpack(byteMask);
    Vector#(8, Bit#(8))  oldVals = unpack(old);
    Vector#(8, Bit#(8))  newVals = unpack(newVal);

    // We patch merge Result so we can share byteMask stuff.
    Value           mergeResult = pack(zipWith3(ife, mask8, newVals, oldVals));
      
    debug($display("MERGING @%h => ", memRespData.offset, fshow(shiftAmount), " [o/n/m] = [%h/%h/%b]",
                                      old, newVal, byteMask));
    debug($display("New Value => %h ", mergeResult));

    Value respV = (memRespData.cmd==Write)
       ? resp
       : ((memRespData.isMerge) ? mergeResult : newVal);
    
    //ndave: This approach shares the right shift which means we have a 8-to-1 mux
    //       feeding a 4-to-1 mux. Specializing can make this much less bad, but given
    //       FPGA timings this should still fit in a single cycle.
    Value result = case (memRespData.sz) matches
                     SZ_1Byte: extend(respV[ 7:0]);
                     SZ_2Byte: extend(respV[15:0]);
                     SZ_4Byte: extend(respV[31:0]);
                     SZ_8Byte: extend(respV[63:0]);
                   endcase;
    return result;
  endactionvalue
endfunction
