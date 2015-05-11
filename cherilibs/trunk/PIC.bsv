/*-
 * Copyright (c) 2012-2013 Robert M. Norton
 * Copyright (c) 2013 Philip Withnall
 * Copyright (c) 2013 Bjoern A. Zeeb
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
 *
 ******************************************************************************
 *
 * Authors:
 *   Robert Norton <rmn30@cam.ac.uk>
 *
 ******************************************************************************
 *
 * Description: Memory mapped peripheral for controlling the mapping of incoming
 * interrupts to local MIPS interrupts.
 *
 ******************************************************************************/

import FIFO::*;
import SpecialFIFOs::*;
import Vector::*;
import ClientServer::*;
import GetPut::*;
import Assert::*;

import Library::*;
import Debug::*;
import Peripheral::*;

// Numbering for MIPS interrupts
typedef enum {
// Corresponding to IP bits in Cause register
   MIPS_IRQ_IP2 = 0,
   MIPS_IRQ_IP3 = 1,
   MIPS_IRQ_IP4 = 2,
   MIPS_IRQ_IP5 = 3,
   MIPS_IRQ_IP6 = 4,
   MIPS_IRQ_IP7 = 5, // ORed with timer
 // XXX rmn30 these two aren't supported yet
   MIPS_IRQ_NMI = 6, // non-maskable
   MIPS_IRQ_DBG = 7  // debug
} MIPS_IRQ deriving(Bits,Eq,FShow);

typedef struct {
   tid      thread;
   MIPS_IRQ    irq;
} LocalIRQID#(type tid) deriving(FShow,Bits,Eq);

interface IRQMapper#(numeric type inputs, type tid);
  method Action  putExtIrqs(Bit#(inputs) irqs);
  method Bit#(8) getMIPSIrqs(tid id);
endinterface

interface PIC#(numeric type inputs, type tid);
  interface IRQMapper#(inputs, tid) irqMapper;
  interface Peripheral#(0)          regs;
endinterface

// Offset (in bytes) of the control registers.
`define PIC_CONFIG_BASE  23'h0000
`define PIC_IP_READ_BASE 23'h2000
`define PIC_IP_SET_BASE  23'h2080
`define PIC_IP_CLR_BASE  23'h2100

`define NUM_HARD_IRQS 64
`define NUM_SOFT_IRQS 64
`define TOT_IRQS (`NUM_HARD_IRQS+`NUM_SOFT_IRQS)

module mkPIC(PIC#(`NUM_HARD_IRQS, tid)) provisos(Bits#(tid, tsz),Add#(a__,tsz,23),Eq#(tid));
  // Functions to provide a backwards compatible initial value
  // for configuration of first 5 interrupts

  module mkMaskReg#(Integer irq)(Reg#(Bool));
    let x <- mkReg(irq < 5);
    return x;
  endmodule

  module mkMapReg#(Integer irq)(Reg#(LocalIRQID#(tid)));
    let x <- mkReg(LocalIRQID{thread: unpack(0), irq: (irq < 5) ? unpack(fromInteger(irq)) : unpack(0)});
    return x;
  endmodule

  Vector#(128, Reg#(Bool))         ip <- replicateM(mkReg(False));
  Vector#(128, Reg#(Bool))       mask <- genWithM(mkMaskReg);
  Vector#(128, Reg#(LocalIRQID#(tid))) maps <- genWithM(mkMapReg);
  // NUM_HARD_IRQS hard irqs plus NUM_SOFT_IRQS wires stuck at zero
  Vector#(128, Wire#(Bool))  hardIrqs <- replicateM(mkDWire(False));
  let                         picFifo <- mkPipelineFIFO;


  function Bool sourceVal(Reg#(Bool) ip, Reg#(Bool) maskReg, Wire#(Bool) w)
     = (ip || w) && maskReg;

  let maskedIrqs = zipWith3(sourceVal, ip, mask, hardIrqs);

  function Bool irqStatus(LocalIRQID#(tid) irq);
    function Bool isIRQ(Bool mask, Reg#(LocalIRQID#(tid)) x)= mask && (x._read == irq);

    let matched = Vector::zipWith(isIRQ, maskedIrqs, maps);

    return Vector::any(id, matched);
  endfunction

  function Bit#(8) doMapping(tid t);
    function map1(i);
      return irqStatus(LocalIRQID{thread:t, irq: unpack(fromInteger(i))});
    endfunction
    Vector#(8, Bool) mapped = Vector::genWith(map1);
    return pack(mapped);
  endfunction

  interface IRQMapper irqMapper;
    method Action putExtIrqs(Bit#(n) newIrqs);
      for(Integer i = 0; i < `NUM_HARD_IRQS; i = i+1)
        hardIrqs[i] <= unpack(newIrqs[i]);
    endmethod

    method Bit#(8) getMIPSIrqs(tid t);
      return doMapping(t);
    endmethod
  endinterface

  interface Peripheral regs;
    interface Server regs;
      interface Put request;
        method Action put(PerifReq r);
          let response = 64'hebadbadbadbadbad;
          let offset   = r.offset;
          debug2("pic", $display("PIC: req ", fshow(r)));
          if (offset < `PIC_IP_READ_BASE)
            begin
              // Config Regs
              if (offset[12:10] == 0) // we only support 128 sources
                begin
                  let irqNo = offset[9:3];
                  if (r.read)
                    begin
                      let en    = mask[irqNo];
                      let map   = maps[irqNo];
                      response  = {32'b0,pack(en),zeroExtend(pack(map.thread)), 5'b0, pack(map.irq)};
                      end
                  else
                    begin
                      mask[irqNo] <= unpack(r.data[31]);
                      maps[irqNo] <= LocalIRQID{thread: unpack(truncate(r.data[30:8])), irq:unpack(r.data[2:0])};
                    end
                end
              else
                dynamicAssert(False, "Only 128 PIC Sources Supported");
            end
          else if (offset < `PIC_IP_SET_BASE && r.read)
            begin
              // IP Read, we only support the first 128 (16 bytes) yet, return 0 for the rest.
              if (offset < (`PIC_IP_READ_BASE + 16))
                response = offset[3]==1 ? pack(maskedIrqs)[127:64] : pack(maskedIrqs)[63:0];
              else
                response = 64'h0000000000000000;
            end
          else if (offset < `PIC_IP_CLR_BASE && !r.read)
            begin
              // IP Set
              Vector#(64, Reg#(Bool)) ips = offset[3] == 1 ? takeAt(64,ip) : take(ip);
              writeVReg(ips, unpack(pack(readVReg(ips))|r.data));
            end
          else if (offset < (`PIC_IP_CLR_BASE + 128) && !r.read)
            begin
              // IP Clear
              Vector#(64, Reg#(Bool)) ips = offset[3] == 1 ? takeAt(64,ip) : take(ip);
              writeVReg(ips, unpack(pack(readVReg(ips)) & ~r.data));
            end
          if(r.read)
            picFifo.enq(response);
        endmethod
      endinterface
      interface Get response;
        method ActionValue#(PerifResp) get;
          let r <- popFIFO(picFifo);
          debug2("pic", $display("PIC: response 0x%x", r));
          return r;
        endmethod
      endinterface //Get
    endinterface //Server

    method Bit#(0) getIrqs();
      return 0;
    endmethod: getIrqs
  endinterface //Peripheral
endmodule
