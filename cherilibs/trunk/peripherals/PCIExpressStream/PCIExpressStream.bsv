/*-
 * Copyright (c) 2014 Alex Horsman
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

import Vector::*;
import GetPut::*;
import ClientServer::*;
import ConfigReg::*;
import FIFOF::*;
import MEM::*;

import AvalonMM::*;
import AvalonST::*;


typedef Bit#(8) Byte;
typedef Bit#(64) PCIWord;

typedef Bit#(16) PCIByteAddr;
typedef Bit#(13) PCIWordAddr;
typedef Bit#(3)  PCIOffset;

function PCIOffset       pciOffset    (PCIByteAddr addr) = addr[2:0];
function PCIWordAddr     pciWordAddr  (PCIByteAddr addr) = addr[15:3];
function Vector#(8,Bool) pciOffsetMask(PCIByteAddr addr) = unpack(1<<pciOffset(addr));

typedef enum {
  PCIStreamHead,
  PCIStreamTail
} PCIStreamCtrl deriving(Eq, Bits, FShow);


interface PCIStreamIn;
  interface AvalonSourceExt#(Byte) aso;
  interface AvalonSlaveExt#(PCIWord,PCIStreamCtrl,0,0) avs_ctrl;
  interface AvalonSlaveExt#(PCIWord,PCIWordAddr,0,1) avs_buf;
endinterface

(* synthesize, reset_prefix = "csi_reset_n", clock_prefix = "csi_clk" *)
module mkPCIStreamIn(PCIStreamIn);

  Reg#(PCIByteAddr) head <- mkConfigReg(0);
  Reg#(PCIByteAddr) tail <- mkConfigReg(0);

  MemBE#(PCIWordAddr,Vector#(8,Byte)) mem <- mkMemBE;

  AvalonSource#(Byte) source <- mkAvalonSource;
  AvalonSlave#(PCIWord,PCIStreamCtrl,0,0) controlSlave <- mkAvalonSlave;
  AvalonSlave#(PCIWord,PCIWordAddr,0,1) bufferSlave <- mkAvalonSlave;

  Reg#(Bool) init <- mkReg(True);

  rule firstReq(init);
    mem.read.put(0);
    init <= False;
  endrule

  rule pushStream(!init && tail != head);
    Vector#(8,Byte) data <- mem.read.get();
    mem.read.put(pciWordAddr(head + 1));
    source.send.put(data[pciOffset(head)]);
    head <= head + 1;
  endrule

  rule getControlRequest;
    let req <- controlSlave.client.request.get();
    case (req) matches
      tagged AvalonRead { address: PCIStreamHead } : begin
        controlSlave.client.response.put(zeroExtend(head));
      end
      tagged AvalonRead { address: PCIStreamTail } : begin
        controlSlave.client.response.put(zeroExtend(tail));
      end
      tagged AvalonWrite { address: PCIStreamTail, writedata: .data } : begin
        tail <= truncate(data);
      end
    endcase
  endrule

  rule getBufferRequest;
    let req <- bufferSlave.client.request.get();
    case (req) matches
      tagged AvalonRead {} : begin
        bufferSlave.client.response.put(?);
      end
      tagged AvalonWrite { address: .addr, writedata: .data, byteenable: .be } : begin
        mem.write(addr,unpack(data),toChunks(be));
      end
    endcase
  endrule

  interface aso = source.aso;
  interface avs_ctrl = controlSlave.avs;
  interface avs_buf = bufferSlave.avs;

endmodule


interface PCIStreamOut;
  interface AvalonSinkExt#(Byte) asi;
  interface AvalonSlaveExt#(PCIWord,PCIStreamCtrl,0,0) avs_ctrl;
  interface AvalonSlaveExt#(PCIWord,PCIWordAddr,0,0) avs_buf;
endinterface

(* synthesize, reset_prefix = "csi_reset_n", clock_prefix = "csi_clk" *)
module mkPCIStreamOut(PCIStreamOut);

  Reg#(PCIByteAddr) head <- mkConfigReg(0);
  Reg#(PCIByteAddr) tail <- mkConfigReg(0);

  MemBE#(PCIWordAddr,Vector#(8,Byte)) mem <- mkMemBE;

  Reg#(Vector#(8,Byte)) writeBuffer <- mkRegU;

  AvalonSink#(Byte) sink <- mkAvalonSink;
  AvalonSlave#(PCIWord,PCIStreamCtrl,0,0) controlSlave <- mkAvalonSlave;
  AvalonSlave#(PCIWord,PCIWordAddr,0,0) bufferSlave <- mkAvalonSlave;

  rule pullStream(tail + 1 != head);
    Vector#(8,Byte) dataVec = newVector;
    dataVec[pciOffset(tail)] <- sink.receive.get();
    mem.write(pciWordAddr(tail),dataVec,pciOffsetMask(tail));
    writeBuffer <= dataVec;
    tail <= tail + 1;
  endrule

  rule getControlRequest;
    let req <- controlSlave.client.request.get();
    case (req) matches
      tagged AvalonRead { address: PCIStreamHead } : begin
        controlSlave.client.response.put(zeroExtend(head));
      end
      tagged AvalonRead { address: PCIStreamTail } : begin
        controlSlave.client.response.put(zeroExtend(tail));
      end
      tagged AvalonWrite { address: PCIStreamHead, writedata: .data } : begin
        head <= truncate(unpack(data));
      end
    endcase
  endrule

  rule getBufferRequest;
    let req <- bufferSlave.client.request.get();
    case (req) matches
      tagged AvalonRead { address: .addr } : begin
        mem.read.put(addr);
      end
    endcase
  endrule

  rule getBufferResponse;
    let resp <- mem.read.get();
    bufferSlave.client.response.put(pack(resp));
  endrule

  interface asi = sink.asi;
  interface avs_ctrl = controlSlave.avs;
  interface avs_buf = bufferSlave.avs;

endmodule
