/*-
 * Copyright (c) 2011-2014 SRI International
 * Copyright (c) 2012-2014 Robert Norton
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
 *   Robert Norton <robert.norton@cl.cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: CHERI2 Debugging Commands
 *
 ******************************************************************************/

import Vector::*;

import TLV::*;
import MIPS::*;
import CHERITypes::*;
`ifdef CAP
import CapabilityTypes::*;
`endif
import Library::*;

//=======================================================================
// Debug Commands

typedef enum {Pipe_Paused=0, Pipe_RunningPipelined=1, Pipe_RunningUnpipelined=2, Pipe_Streaming=3} PipelineState deriving(Bits, Eq, FShow);

typedef union tagged {
  void          D_PausePipelineReq;
  PipelineState D_PausePipelineResp;

  void          D_ResumePipelinedReq;
  PipelineState D_ResumePipelinedResp;

  void          D_ResumeUnpipelinedReq;
  PipelineState D_ResumeUnpipelinedResp;

  void          D_ResumeStreamingReq;
  PipelineState D_ResumeStreamingResp;

  Address       D_SetPCReq;
  void          D_SetPCResp;
  void          D_GetPCReq;
  Address       D_GetPCResp;

  Tuple2#(Address,Bit#(8))  D_SetByteReq;
  void                      D_SetByteResp;
  Address                   D_GetByteReq;
  Bit#(8)                   D_GetByteResp;

  Tuple2#(Address,Bit#(16)) D_SetHalfWordReq;
  void                      D_SetHalfWordResp;
  Address                   D_GetHalfWordReq;
  Bit#(16)                  D_GetHalfWordResp;

  Tuple2#(Address,Bit#(32)) D_SetWordReq;
  void                      D_SetWordResp;
  Address                   D_GetWordReq;
  Bit#(32)                  D_GetWordResp;

  Tuple2#(Address,Bit#(64)) D_SetDoubleWordReq;
  void                      D_SetDoubleWordResp;
  Address                   D_GetDoubleWordReq;
  Bit#(64)                  D_GetDoubleWordResp;

  Tuple2#(RegName,Value)    D_SetRegisterReq;
  void                      D_SetRegisterResp;
  RegName                   D_GetRegisterReq;
  Value                     D_GetRegisterResp;

  Tuple2#(CP0RegName,Value) D_SetC0RegisterReq;
  void                      D_SetC0RegisterResp;
  CP0RegName                D_GetC0RegisterReq;
  Value                     D_GetC0RegisterResp;

`ifdef CAP
  Tuple3#(CapRegName,Bool, Capability) D_SetC2RegisterReq; //XXX ndave: do we really want this?
  void                                 D_SetC2RegisterResp;
  CapRegName                           D_GetC2RegisterReq;
  Tuple2#(Bool, Capability)            D_GetC2RegisterResp;
`endif

  void D_ExecuteSingleInstReq;
  void D_ExecuteSingleInstResp;

  Tuple2#(Bit#(2), Address) D_SetBreakPointReq;
  void                      D_SetBreakPointResp;

  //Trace Commands
  void                      D_PopTraceReq;
  Bit#(256)                 D_PopTraceResp;

  Bit#(256)                 D_SetTraceMaskReq;
  void                      D_SetTraceMaskResp;

  Bit#(256)                 D_SetTraceCmpReq;
  void                      D_SetTraceCmpResp;

  Bit#(8)                   D_SetThreadReq;
  void                      D_SetThreadResp;

  Tuple2#(Bit#(2), Address) D_BreakPointFired;
  Bit#(8)                   D_ExceptionOccurred;
} DebugCommand deriving(Bits, Eq, FShow);

function Bool isMemCommandReq(DebugCommand c);
  return case (c) matches
           tagged D_SetByteReq .*:       return True;
           tagged D_GetByteReq .*:       return True;
           tagged D_SetHalfWordReq .*:   return True;
           tagged D_GetHalfWordReq .*:   return True;
           tagged D_SetWordReq .*:       return True;
           tagged D_GetWordReq .*:       return True;
           tagged D_SetDoubleWordReq .*: return True;
           tagged D_GetDoubleWordReq .*: return True;
           default:                      return False;
         endcase;
endfunction

instance TLVConvert#(DebugCommand,1,1,34);
  function TLV#(1,1,34) toTLV(DebugCommand c);
    function TLV#(1,1,34) makeTLV(Bit#(8) tv, value dv) provisos(Mul#(m,8,m8), Add#(m8,xxx,TMul#(8,34)), Bits#(value, m8), Add#(m, yyy, 34));
    return TLV{tlvType: unpack(tv), tlvLength: unpack(fromInteger(valueOf(m))),
               tlvData: Vector::append(unpack(pack(dv)), replicate(?))};
  endfunction

  Bit#(0) unit = ?;

  case (c) matches
    tagged D_PausePipelineReq:         return makeTLV(8'h00, unit);
    tagged D_PausePipelineResp     .s: return makeTLV(8'h01, toByte(s));
    tagged D_ResumePipelinedReq:       return makeTLV(8'h02, unit);
    tagged D_ResumePipelinedResp   .s: return makeTLV(8'h03, toByte(s));
    tagged D_ResumeUnpipelinedReq:     return makeTLV(8'h04, unit);
    tagged D_ResumeUnpipelinedResp .s: return makeTLV(8'h05, toByte(s));

    tagged D_SetPCReq .a:              return makeTLV(8'h06, a);
    tagged D_SetPCResp:                return makeTLV(8'h07, unit);
    tagged D_GetPCReq:                 return makeTLV(8'h08, unit);
    tagged D_GetPCResp .a:             return makeTLV(8'h09, a);

    tagged D_SetByteReq .t:            return makeTLV(8'h0A, t);
    tagged D_SetByteResp:              return makeTLV(8'h0B, unit);
    tagged D_GetByteReq .a:            return makeTLV(8'h0C, a);
    tagged D_GetByteResp .v:           return makeTLV(8'h0D, v);

    tagged D_SetHalfWordReq  .t:       return makeTLV(8'h0E, t);
    tagged D_SetHalfWordResp:          return makeTLV(8'h0F, unit);
    tagged D_GetHalfWordReq  .a:       return makeTLV(8'h10, a);
    tagged D_GetHalfWordResp .v:       return makeTLV(8'h11, v);

    tagged D_SetWordReq .t:            return makeTLV(8'h12, t);
    tagged D_SetWordResp:              return makeTLV(8'h13, unit);
    tagged D_GetWordReq .a:            return makeTLV(8'h14, a);
    tagged D_GetWordResp .v:           return makeTLV(8'h15, v);

    tagged D_SetDoubleWordReq .t:      return makeTLV(8'h16, t);
    tagged D_SetDoubleWordResp:        return makeTLV(8'h17, unit);
    tagged D_GetDoubleWordReq .a:      return makeTLV(8'h18, a);
    tagged D_GetDoubleWordResp .v:     return makeTLV(8'h19, v);

    tagged D_SetRegisterReq .t:        return makeTLV(8'h1A, applyFst(toByte,t));
    tagged D_SetRegisterResp:          return makeTLV(8'h1B, unit);
    tagged D_GetRegisterReq .r:        return makeTLV(8'h1C, toByte(r));
    tagged D_GetRegisterResp .v:       return makeTLV(8'h1D, v);

    tagged D_SetC0RegisterReq .t:    return makeTLV(8'h1E, applyFst(toByte,t));
    tagged D_SetC0RegisterResp:      return makeTLV(8'h1F, unit);
    tagged D_GetC0RegisterReq .r:    return makeTLV(8'h20, toByte(r));
    tagged D_GetC0RegisterResp .v:   return makeTLV(8'h21, v);

    `ifdef CAP
    tagged D_SetC2RegisterReq .tup:
	  begin
	    match {.r,.p,.v} = tup;
            return makeTLV(8'h22, {toByte(r), toByte(p), pack(v)});
	  end
    tagged D_SetC2RegisterResp:           return makeTLV(8'h23, unit);
    tagged D_GetC2RegisterReq .r:         return makeTLV(8'h24, toByte(r));
    tagged D_GetC2RegisterResp .tup:
	  begin
		match {.p,.v} = tup;
		return makeTLV(8'h25, {toByte(p), pack(v)});
	  end
    `endif

    tagged D_ExecuteSingleInstReq:   return makeTLV(8'h26, unit);
    tagged D_ExecuteSingleInstResp:  return makeTLV(8'h27, unit);

    tagged D_SetBreakPointReq .t:    return makeTLV(8'h28, applyFst(toByte, t));
    tagged D_SetBreakPointResp:      return makeTLV(8'h29, unit);

    tagged D_PopTraceReq:            return makeTLV(8'h2A, unit);
    tagged D_PopTraceResp .t:        return makeTLV(8'h2B, pack(t));

    tagged D_SetTraceMaskReq .v:     return makeTLV(8'h2C, v);
    tagged D_SetTraceMaskResp:       return makeTLV(8'h2D, unit);

    tagged D_SetTraceCmpReq .v:     return makeTLV(8'h30, v);
    tagged D_SetTraceCmpResp:       return makeTLV(8'h31, unit);

    tagged D_ResumeStreamingReq:     return makeTLV(8'h32, unit);
    tagged D_ResumeStreamingResp .s: return makeTLV(8'h33, toByte(s));

    tagged D_SetThreadReq .v:       return makeTLV(8'h34, v);
    tagged D_SetThreadResp:         return makeTLV(8'h35, unit);

    tagged D_BreakPointFired .t:     return makeTLV(8'h2E, applyFst(toByte, t));
    tagged D_ExceptionOccurred .e:   return makeTLV(8'h2F, e);

    default: return ?;
    endcase
  endfunction


  function DebugCommand fromTLV(TLV#(1,1,34) tlv);
  function a convert(Vector#(n, Bit#(8)) vx) provisos(Bits#(a, TMul#(k,8)), Add#(xxx,k,n));
    return unpack(pack(Vector::take(vx)));
  endfunction
  function a trimByte(Bit#(8) vx) provisos(Bits#(a, asz), Add#(xxx, asz, 8));
    return unpack(truncate(vx));
  endfunction

  case (pack(tlv.tlvType)) matches
    8'h00: return D_PausePipelineReq;
    8'h01: return D_PausePipelineResp     (trimByte(head(tlv.tlvData)));
    8'h02: return D_ResumePipelinedReq;
    8'h03: return D_ResumePipelinedResp   (trimByte(head(tlv.tlvData)));
    8'h04: return D_ResumeUnpipelinedReq;
    8'h05: return D_ResumeUnpipelinedResp (trimByte(head(tlv.tlvData)));

    8'h06: return D_SetPCReq              (convert(tlv.tlvData));
    8'h07: return D_SetPCResp             (convert(tlv.tlvData));
    8'h08: return D_GetPCReq;
    8'h09: return D_GetPCResp             (convert(tlv.tlvData));

    8'h0A: return D_SetByteReq            (convert(tlv.tlvData));
    8'h0B: return D_SetByteResp;
    8'h0C: return D_GetByteReq            (convert(tlv.tlvData));
    8'h0D: return D_GetByteResp           (convert(tlv.tlvData));

    8'h0E: return D_SetHalfWordReq  (convert(tlv.tlvData));
    8'h0F: return D_SetHalfWordResp (convert(tlv.tlvData));
    8'h10: return D_GetHalfWordReq  (convert(tlv.tlvData));
    8'h11: return D_GetHalfWordResp (convert(tlv.tlvData));

    8'h12: return D_SetWordReq      (convert(tlv.tlvData));
    8'h13: return D_SetWordResp;
    8'h14: return D_GetWordReq      (convert(tlv.tlvData));
    8'h15: return D_GetWordResp     (convert(tlv.tlvData));

    8'h16: return D_SetDoubleWordReq (convert(tlv.tlvData));
    8'h17: return D_SetDoubleWordResp;
    8'h18: return D_GetDoubleWordReq (convert(tlv.tlvData));
    8'h19: return D_GetDoubleWordResp (convert(tlv.tlvData));

    8'h1A: return D_SetRegisterReq (tuple2(truncate(head(tlv.tlvData)), convert(tail(tlv.tlvData))));
    8'h1B: return D_SetRegisterResp;
    8'h1C: return D_GetRegisterReq (trimByte(tlv.tlvData[0]));
    8'h1D: return D_GetRegisterResp (convert(tlv.tlvData));

    8'h1E: return D_SetC0RegisterReq (tuple2(truncate(head(tlv.tlvData)), convert(tail(tlv.tlvData))));
    8'h1F: return D_SetC0RegisterResp;
    8'h20: return D_GetC0RegisterReq (trimByte(head(tlv.tlvData)));
    8'h21: return D_GetC0RegisterResp (convert(tlv.tlvData));

    `ifdef CAP
    8'h22: begin
             let r = trimByte(head     (tlv.tlvData));
	     let p = trimByte(head(tail(tlv.tlvData)));
	     let v = convert(tail(tail(tlv.tlvData)));
             return D_SetC2RegisterReq (tuple3(r,p,v));
		   end
    8'h23: return D_SetC2RegisterResp;
    8'h24: return D_GetC2RegisterReq (trimByte(head(tlv.tlvData)));
    8'h25: begin
	     let p = trimByte(head(tlv.tlvData));
	     let v = convert(tail(tlv.tlvData));
             return D_GetC2RegisterResp (tuple2(p,v));
	   end
    `endif

    8'h26: return D_ExecuteSingleInstReq;
    8'h27: return D_ExecuteSingleInstResp;

    8'h28: return D_SetBreakPointReq (tuple2(trimByte(head(tlv.tlvData)), convert(tail(tlv.tlvData))));
    8'h29: return D_SetBreakPointResp;

    8'h2A: return D_PopTraceReq;
    8'h2B: return D_PopTraceResp (convert(tlv.tlvData));

    8'h2C: return D_SetTraceMaskReq (convert(tlv.tlvData));
    8'h2D: return D_SetTraceMaskResp;

    8'h30: return D_SetTraceCmpReq (convert(tlv.tlvData));
    8'h31: return D_SetTraceCmpResp;

    8'h32: return D_ResumeStreamingReq;
    8'h33: return D_ResumeStreamingResp (trimByte(head(tlv.tlvData)));

    8'h34: return D_SetThreadReq(convert(tlv.tlvData));
    8'h35: return D_SetThreadResp;

    8'h2E: return D_BreakPointFired (tuple2(trimByte(head(tlv.tlvData)), convert(tail(tlv.tlvData))));
    8'h2F: return D_ExceptionOccurred(convert(tlv.tlvData));
    default: return (?);
  endcase
  endfunction
endinstance

(* synthesize, options="-aggressive-conditions" *)
module mkTLVByteMarshaller_DebugCommand(ByteMarshaller#(DebugCommand));
  let _x <- mkTLVByteMarshaller();
  return _x;
endmodule
