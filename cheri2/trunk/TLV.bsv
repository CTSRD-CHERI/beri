/*-
 * Copyright (c) 2011-2014 SRI International
 * Copyright (c) 2013 Robert M. Norton
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
 * Description: Parametric Type-Length-Value system
 *
 ******************************************************************************/

import Debug::*;

import Vector::*;
import ClientServer::*;
import GetPut::*;
import FIFO::*;
import FShow::*;

typedef struct {
  Vector#(tsz, Bit#(8)) tlvType;
  Vector#(lsz, Bit#(8)) tlvLength;
  Vector#(dsz, Bit#(8)) tlvData;
} TLV#(numeric type tsz, numeric type lsz, numeric type dsz) deriving (Eq, Bits, FShow);


function TLV#(t,l,d) makeTLV(Bit#(t8) tv, Bit#(l8) lv, Bit#(d8) dv) provisos(Mul#(t,8,t8), Mul#(l,8,l8), Mul#(d,8,d8));
  return TLV{tlvType: unpack(tv), tlvLength: unpack(lv), tlvData: unpack(dv)};
endfunction

typeclass TLVConvert#(type a, numeric type tsz, numeric type lsz, numeric type dsz)
  dependencies (a determines (tsz,lsz,dsz));

  function TLV#(tsz,lsz,dsz)   toTLV(a x);
  function a fromTLV(TLV#(tsz,lsz,dsz) x);
endtypeclass

interface TLVMarshaller#(numeric type t, numeric type l, numeric type d);
  interface Server#(Bit#(8), Bit#(8))            byteStream;
  interface Client#(TLV#(t,l,d), TLV#(t,l,d)) messageStream;
endinterface

module mkTLVMarshaller(TLVMarshaller#(t,l,d)) provisos (Add#(a__, TMul#(l, 8), 64));
  Bit#(64)   tCnt = fromInteger(valueOf(t));
  Bit#(64)  tlCnt = fromInteger(valueOf(t) + valueOf(l));
  Bit#(64) tldCnt = fromInteger(valueOf(t) + valueOf(l) + valueOf(d));

  `ifdef BLUESIM
  FIFO#(TLV#(t,l,d))     toMessageQ <- mkSizedFIFO(8192);
	`else
  FIFO#(TLV#(t,l,d))     toMessageQ <- mkSizedFIFO(32);
	`endif

  Reg#(Bit#(64))           toCnt <- mkReg(0);
  Reg#(Vector#(t,Bit#(8)))   toType <- mkRegU();
  Reg#(Vector#(l,Bit#(8))) toLength <- mkRegU();
  Reg#(Vector#(d,Bit#(8)))   toData <- mkReg(replicate(0));

  FIFO#(TLV#(t,l,d))                          fromMessageQ <- mkFIFO();
  Reg#(Bit#(64))                                   fromCnt <- mkReg(0);
  Reg#(Vector#(TAdd#(TAdd#(t,l),d), Bit#(8)))    fromMessage <- mkRegU;

  interface Server byteStream;
	interface Put request;
	  method Action put(Bit#(8) x);
        //$display("DEBUG DBG: got 0x%h", x, "(%d, %d, %d, 0x%h",toCnt, toType, toLength, pack(toData), ")");
        let newToType = Invalid;
        let newToLength = Invalid;
		let newToData = Invalid;
		if (toCnt < tCnt)// parsing type
		  newToType = Valid (Vector::shiftInAt0(toType, x));
	    else if (toCnt < tlCnt) // parsing length
		  newToLength = Valid (Vector::shiftInAt0(toLength, x));
		else //XXX ndave update before rotate
          newToData = Valid (Vector::update(Vector::rotate(toData), pack(toLength) - 1, x));


		let tlv = TLV{tlvType:   fromMaybe(toType, newToType),
					  tlvLength: fromMaybe(toLength, newToLength),
					  tlvData:   fromMaybe(toData, newToData)};

		//handle count and send result
		let maxCount = tlCnt + zeroExtend(pack(fromMaybe(toLength, newToLength)));
		if (toCnt + 1 == maxCount) // end of packet
		  begin
			toCnt <= 0;
			debug2("tlv", $display("DEBUG DBG: Message From CHERICTL ", fshow(tlv)));
			toMessageQ.enq(tlv);
			newToData = Valid (replicate(0));
		  end
        else
		  begin
			toCnt <= toCnt + 1;
			//$display("DEBUG DBG: got 0x%h ", x, fshow(tlv));
		  end

		function b maybe(b def, function b f(a x), Maybe#(a) mx);
		  case (mx) matches
			tagged Valid .x: return f(x);
			tagged Invalid:  return def;
		  endcase
		endfunction

        //write maybe values into registers
        maybe(noAction, toType._write,   newToType);
        maybe(noAction, toLength._write, newToLength);
        maybe(noAction, toData._write,   newToData);
	  endmethod
	endinterface
	interface Get response;
		method ActionValue#(Bit#(8)) get();
			if (fromCnt == 0)
				begin
					let newFromMessage = fromMessageQ.first();
 					debug2("tlv", $display("DEBUG DBG: Message from DEBUGUNT ", fshow(newFromMessage)));
					fromMessageQ.deq();
					fromCnt <= zeroExtend(pack(newFromMessage.tlvLength)) + tlCnt - 1;
					Vector#(TAdd#(TAdd#(t,l),d), Bit#(8)) vNewFromMessage = Vector::append(Vector::append(newFromMessage.tlvType,
					                                                                                      newFromMessage.tlvLength),
                                                                                                          newFromMessage.tlvData);
				    fromMessage <= shiftOutFrom0(0, vNewFromMessage, 1); // shift in a 0

				    //$display("DEBUG DBG: sending 0x%h vNewFromMesssage", vNewFromMessage[0], fshow(vNewFromMessage));
					return vNewFromMessage[0];
				end
				else
				  begin
					fromCnt <= fromCnt - 1;
					let rv = fromMessage[0];
					fromMessage <= shiftOutFrom0(0, fromMessage, 1);
				    //$display("DEBUG DBG: sending 0x%h", rv);
					return rv;
				  end


	  endmethod
	endinterface
  endinterface

  interface Client messageStream = fifosToClient(toMessageQ, fromMessageQ);

endmodule

interface ByteMarshaller#(type a);
  interface Server#(Bit#(8), Bit#(8)) byteStream;
  interface Client#(a, a) messageStream;
endinterface

module mkTLVByteMarshaller(ByteMarshaller#(a)) provisos (TLVConvert#(a,t,l,d), Add#(a__, TMul#(l, 8), 64));

  TLVMarshaller#(t,l,d) tlvMarshaller <- mkTLVMarshaller();

  interface Server byteStream = tlvMarshaller.byteStream;
  interface Client messageStream;
	interface Get request;
      method ActionValue#(a) get() = liftM(fromTLV, tlvMarshaller.messageStream.request.get());
    endinterface
	interface Put response;
      method Action put(a x);
        let rv = toTLV(x);
		//$display("Sending MESSAGE to CHERICTL: ", fshow(rv));
        tlvMarshaller.messageStream.response.put(rv);
      endmethod
	endinterface
  endinterface
endmodule
